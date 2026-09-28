import Foundation

/// Samples the SMC on a background queue and publishes readings for the UI.
///
/// The SMC connection and the per-key metadata are created once and reused,
/// so each tick is only the value reads (~10 ms of CPU on the M5 Max).
public final class TemperatureModel: ObservableObject {
    /// Sampling period in seconds before the user moves the slider.
    public static let defaultRefreshPeriod: Double = 2.0

    /// UserDefaults keys holding the user's settings.
    private enum Storage {
        static let refreshPeriodKey = "refreshPeriod"
        static let historyLimitKey = "historyLimit"
    }

    private static let queueLabel = "com.hotmac.smc"
    private static let timerLeeway = DispatchTimeInterval.milliseconds(200)
    private static let celsiusSymbol = "°C"
    private static let menuBarPlaceholder = "--\(TemperatureModel.celsiusSymbol)"

    /// How many samples the graph keeps before the oldest are dropped, before
    /// the user moves the slider.
    public static let defaultHistoryLimit = 900

    public struct HistoryPoint: Identifiable {
        public let id: UUID
        public let time: Date
        public let values: [String: Double]

        init(time: Date, values: [String: Double]) {
            self.id = UUID()
            self.time = time
            self.values = values
        }
    }

    /// One fan sample: every fan's speed at a moment in time.
    public struct FanHistoryPoint: Identifiable {
        public let id: UUID
        public let time: Date
        /// Speed in RPM, keyed by fan number.
        public let speeds: [Int: Double]

        init(time: Date, speeds: [Int: Double]) {
            self.id = UUID()
            self.time = time
            self.speeds = speeds
        }
    }

    /// One completed reading, waiting to be published on the main queue.
    struct Tick {
        let snapshot: TemperatureSnapshot
        let point: HistoryPoint
        let throttleState: ThrottleState
        let fans: [FanReading]
    }

    @Published public private(set) var snapshot: TemperatureSnapshot?
    @Published public private(set) var history: [HistoryPoint] = []
    /// The fans' speed over time, sampled alongside the temperatures and capped
    /// by the same `historyLimit`.
    @Published public private(set) var fanHistory: [FanHistoryPoint] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastUpdate: Date?
    /// How far the OS is throttling the CPU, nil until the first reading.
    @Published public private(set) var throttleState: ThrottleState?
    /// The machine's fans, ordered by number. Empty until the first reading,
    /// and on a machine with none.
    @Published public private(set) var fans: [FanReading] = []
    @Published public var refreshPeriod: Double = TemperatureModel.defaultRefreshPeriod {
        didSet { persistPeriod(); restartTimer() }
    }
    /// How many samples the graph keeps. Lowering it drops the surplus at once.
    @Published public var historyLimit: Int = TemperatureModel.defaultHistoryLimit {
        didSet { persistHistoryLimit(); trimHistory() }
    }

    private let queue = DispatchQueue(label: TemperatureModel.queueLabel, qos: .utility)

    /// The chip brand reported in the snapshot. Internal so the DEBUG preview
    /// file can build a snapshot with it.
    let brand: String

    /// Creates the SMC connection. Injectable so tests can supply a client
    /// wired to a fake transport instead of the kernel.
    private let makeSMC: () throws -> SMC

    /// The OS throttling level for this tick. Injectable so tests do not depend
    /// on what the host happens to be doing.
    private let readThrottleState: () -> ThrottleState

    /// Hands work back to the main thread. Injectable so tests can stay
    /// synchronous instead of spinning a run loop.
    private let deliver: (@escaping () -> Void) -> Void

    private var timer: DispatchSourceTimer?
    private var session: SMCSession?
    private var started = false

    /// Dependencies are required rather than defaulted so that this class
    /// contains no production wiring of its own; `TemperatureModel.live()`
    /// supplies the real ones. Internal because `SMC` is an implementation
    /// detail: the app composes through `live()`.
    init(
        startImmediately: Bool = true,
        brand: String,
        makeSMC: @escaping () throws -> SMC,
        readThrottleState: @escaping () -> ThrottleState,
        deliver: @escaping (@escaping () -> Void) -> Void
    ) {
        self.makeSMC = makeSMC
        self.readThrottleState = readThrottleState
        self.deliver = deliver
        self.brand = brand
        if let stored = UserDefaults.standard.object(forKey: Storage.refreshPeriodKey) as? Double,
           stored > 0 {
            refreshPeriod = stored
        }
        if let stored = UserDefaults.standard.object(forKey: Storage.historyLimitKey) as? Int,
           stored > 0 {
            historyLimit = stored
        }
        if startImmediately {
            start()
        }
    }

#if DEBUG
    /// Replace the published state with synthetic data, for rendering the views
    /// without an SMC. It lives beside the stored properties so the DEBUG-only
    /// preview file does not need access to their setters.
    func adopt(
        history: [HistoryPoint],
        fanHistory: [FanHistoryPoint],
        snapshot: TemperatureSnapshot?,
        throttleState: ThrottleState,
        fans: [FanReading]
    ) {
        self.history = history
        self.fanHistory = fanHistory
        self.lastUpdate = history.last?.time
        self.snapshot = snapshot
        self.throttleState = throttleState
        self.fans = fans
    }
#endif

    public var menuBarTitle: String {
        guard let highest = snapshot?.highest else { return TemperatureModel.menuBarPlaceholder }
        return "\(Int(highest.rounded()))\(TemperatureModel.celsiusSymbol)"
    }

    /// The band the current reading falls in, so the menu bar can emphasize a
    /// hot machine without knowing the thresholds. Nil until a reading arrives.
    public var menuBarLevel: TemperatureLevel? {
        guard let highest = snapshot?.highest else { return nil }
        return TemperatureLevel.level(for: highest)
    }

    public var seriesNames: [String] {
        var names = snapshot?.groups.map(\.name) ?? []
        if snapshot?.highest != nil {
            names.append(SensorCatalog.hottestSeriesName)
        }
        return names
    }

    func start() {
        guard !started else { return }
        started = true
        restartTimer()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        started = false
    }

    public func clearHistory() {
        history.removeAll()
        fanHistory.removeAll()
    }

    private func persistPeriod() {
        UserDefaults.standard.set(refreshPeriod, forKey: Storage.refreshPeriodKey)
    }

    private func persistHistoryLimit() {
        UserDefaults.standard.set(historyLimit, forKey: Storage.historyLimitKey)
    }

    private func restartTimer() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: refreshPeriod, leeway: TemperatureModel.timerLeeway)
        source.setEventHandler { [weak self] in self?.sample() }
        timer = source
        source.resume()
    }

    /// Gather one reading without publishing it: connect if needed, read the
    /// key table, and turn it into a snapshot. Returns nil when the machine
    /// exposes nothing to read, which is not an error.
    ///
    /// Not private so tests can assert on the reading itself rather than on the
    /// published properties it feeds.
    func readTick() throws -> Tick? {
        let active: SMCSession
        if let existing = session {
            active = existing
        } else {
            let created = try SMCSession(connect: makeSMC)
            session = created
            active = created
        }

        let table = active.readTable()
        guard !table.isEmpty else { return nil }

        let snapshot = SensorCatalog.snapshot(brand: brand, table: table)
        let fans = SensorCatalog.fanReadings(from: active.readFans())
        var values: [String: Double] = [:]
        for group in snapshot.groups { values[group.name] = group.average }
        if let highest = snapshot.highest {
            values[SensorCatalog.hottestSeriesName] = highest
        }
        return Tick(
            snapshot: snapshot,
            point: HistoryPoint(time: Date(), values: values),
            throttleState: readThrottleState(),
            fans: fans
        )
    }

    /// One sampling tick. Not private so tests can drive it directly rather
    /// than waiting on the timer.
    func sample() {
        do {
            guard let tick = try readTick() else { return }
            deliver { [weak self] in
                self?.apply(
                    snapshot: tick.snapshot,
                    point: tick.point,
                    throttleState: tick.throttleState,
                    fans: tick.fans
                )
            }
        } catch {
            session = nil
            deliver { [weak self] in
                self?.errorMessage = "\(error)"
            }
        }
    }

    private func apply(
        snapshot: TemperatureSnapshot,
        point: HistoryPoint,
        throttleState: ThrottleState,
        fans: [FanReading]
    ) {
        self.snapshot = snapshot
        self.throttleState = throttleState
        self.fans = fans
        self.errorMessage = nil
        self.lastUpdate = point.time
        history.append(point)
        fanHistory.append(
            FanHistoryPoint(
                time: point.time,
                speeds: Dictionary(uniqueKeysWithValues: fans.map { ($0.index, $0.current) })
            )
        )
        trimHistory()
    }

    /// Drop the oldest samples once a graph holds more than the limit. Runs
    /// both when a sample arrives and when the user lowers the limit. Removing
    /// zero is a no-op, which keeps the two arrays in step without a branch
    /// that could never be taken.
    private func trimHistory() {
        history.removeFirst(max(0, history.count - historyLimit))
        fanHistory.removeFirst(max(0, fanHistory.count - historyLimit))
    }
}
