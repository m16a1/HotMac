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
        static let selectedSeriesKey = "selectedSeries"
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
        let processes: [ProcessReading]
        let gpuUtilization: GPUUtilization?
    }

    @Published public private(set) var snapshot: TemperatureSnapshot? {
        didSet { seedSelectionIfNeeded() }
    }
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
    /// The busiest processes, busiest first. Empty until the first reading,
    /// which has no earlier counters to compute a rate from.
    @Published public private(set) var processes: [ProcessReading] = []
    /// How busy the whole GPU is. Nil until the first reading, and on a machine
    /// whose accelerator publishes no such figure.
    @Published public private(set) var gpuUtilization: GPUUtilization?
    @Published public var refreshPeriod: Double = TemperatureModel.defaultRefreshPeriod {
        didSet { persistPeriod(); restartTimer() }
    }
    /// How many samples the graph keeps. Lowering it drops the surplus at once.
    @Published public var historyLimit: Int = TemperatureModel.defaultHistoryLimit {
        didSet { persistHistoryLimit(); trimHistory() }
    }

    /// The series the Temperatures graph shows, persisted so the choice
    /// survives a relaunch. Empty until the first reading seeds the defaults.
    @Published public var selectedSeries: Set<String> = [] {
        didSet { persistSelectedSeries() }
    }

    /// Whether the Processes screen is on screen. The CPU fallback runs only
    /// while it is, because it costs a subprocess and nothing else reads those
    /// figures. The view writes it on the main queue and the sampling queue reads
    /// it, so it is guarded rather than published: nothing redraws when it
    /// changes.
    public var processesVisible: Bool {
        get {
            visibilityLock.lock()
            defer { visibilityLock.unlock() }
            return isProcessesVisible
        }
        set {
            visibilityLock.lock()
            defer { visibilityLock.unlock() }
            isProcessesVisible = newValue
        }
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

    /// Reads every process's counters for this tick. Injectable so tests do not
    /// depend on what the host happens to be running.
    private let readProcesses: () -> [ProcessCounters]

    /// Reads the GPU's utilization for this tick. Injectable so tests do not
    /// depend on the host's GPU.
    private let readGPU: () -> GPUUtilization?

    /// Reads every process's cumulative GPU time for this tick, one entry per GPU
    /// client. Injectable so tests do not depend on what the host is rendering.
    private let readGPUClientCounters: () -> [GPUClientCounters]

    /// Reads the CPU and memory `ps` reports for the processes the kernel will
    /// not describe, given the pids that need them. Injectable so tests do not
    /// spawn anything.
    private let readFallbackUsage: ([Int32]) -> [Int32: ProcessUsage]

    /// Hands work back to the main thread. Injectable so tests can stay
    /// synchronous instead of spinning a run loop.
    private let deliver: (@escaping () -> Void) -> Void

    private var timer: DispatchSourceTimer?
    private var session: SMCSession?
    private var started = false
    /// Guards `isProcessesVisible`, which the main queue writes and the sampling
    /// queue reads.
    private let visibilityLock = NSLock()
    private var isProcessesVisible = false
    /// Whether the graph's series have been decided: restored from storage, or
    /// seeded from the first reading.
    private var seededSelection = false

    /// The previous tick's process counters and when they were taken, so the
    /// next tick can turn the host's running CPU totals into a rate. Nil until
    /// the first tick.
    private var previousProcessCounters: [ProcessCounters] = []
    private var previousProcessTime: Date?

    /// The previous tick's GPU totals, folded one per process. Both counter
    /// families are sampled in the same tick, so they share a timestamp, and
    /// their shares are formed over the same interval.
    private var previousGPUCounters: [GPUClientCounters] = []

    /// Dependencies are required rather than defaulted so that this class
    /// contains no production wiring of its own; `TemperatureModel.live()`
    /// supplies the real ones. Internal because `SMC` is an implementation
    /// detail: the app composes through `live()`.
    init(
        startImmediately: Bool = true,
        brand: String,
        makeSMC: @escaping () throws -> SMC,
        readThrottleState: @escaping () -> ThrottleState,
        readProcesses: @escaping () -> [ProcessCounters],
        readGPU: @escaping () -> GPUUtilization?,
        readGPUClientCounters: @escaping () -> [GPUClientCounters],
        readFallbackUsage: @escaping ([Int32]) -> [Int32: ProcessUsage],
        deliver: @escaping (@escaping () -> Void) -> Void
    ) {
        self.makeSMC = makeSMC
        self.readThrottleState = readThrottleState
        self.readProcesses = readProcesses
        self.readGPU = readGPU
        self.readGPUClientCounters = readGPUClientCounters
        self.readFallbackUsage = readFallbackUsage
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
        if let stored = UserDefaults.standard.stringArray(forKey: Storage.selectedSeriesKey) {
            selectedSeries = Set(stored)
            seededSelection = true
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
        fans: [FanReading],
        processes: [ProcessReading],
        gpuUtilization: GPUUtilization?
    ) {
        self.history = history
        self.fanHistory = fanHistory
        self.lastUpdate = history.last?.time
        self.snapshot = snapshot
        self.throttleState = throttleState
        self.fans = fans
        self.processes = processes
        self.gpuUtilization = gpuUtilization
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
        snapshot?.groups.map(\.name) ?? []
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

    private func persistSelectedSeries() {
        UserDefaults.standard.set(
            Array(selectedSeries).sorted(), forKey: Storage.selectedSeriesKey
        )
    }

    /// Give the graph its starting series the first time a reading arrives,
    /// unless a stored choice was restored or the chip reports no groups.
    private func seedSelectionIfNeeded() {
        guard !seededSelection, !seriesNames.isEmpty else { return }
        seededSelection = true
        selectedSeries = SensorCatalog.defaultSeries(from: seriesNames)
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

        let now = Date()
        let snapshot = SensorCatalog.snapshot(brand: brand, table: table)
        let fans = SensorCatalog.fanReadings(from: active.readFans())
        var values: [String: Double] = [:]
        for group in snapshot.groups { values[group.name] = group.average }

        let counters = readProcesses()
        let elapsed = previousProcessTime.map { now.timeIntervalSince($0) } ?? 0
        // One fold and one interval for both halves: the GPU clients are read in
        // this same tick, so their totals are as old as the process counters'.
        let gpuCounters = GPUClientCounters.merged(readGPUClientCounters())
        let gpuShares = GPUShare.readings(
            previous: previousGPUCounters,
            current: gpuCounters,
            elapsed: elapsed
        )
        // The rows the kernel would not describe have no figures of their own.
        // `ps` is the only unprivileged source for them, so it is asked only for
        // those pids, and only while the screen that shows them is on screen.
        let undescribed = ProcessCounters.undescribed(counters, gpuShares: gpuShares)
        let processes = ProcessCounters.readings(
            previous: previousProcessCounters,
            current: counters,
            elapsed: elapsed,
            gpuShares: gpuShares,
            fallback: processesVisible ? readFallbackUsage(undescribed.map(\.pid)) : [:]
        )
        previousProcessCounters = counters
        previousGPUCounters = gpuCounters
        previousProcessTime = now

        return Tick(
            snapshot: snapshot,
            point: HistoryPoint(time: now, values: values),
            throttleState: readThrottleState(),
            fans: fans,
            processes: processes,
            gpuUtilization: readGPU()
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
                    fans: tick.fans,
                    processes: tick.processes,
                    gpuUtilization: tick.gpuUtilization
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
        fans: [FanReading],
        processes: [ProcessReading],
        gpuUtilization: GPUUtilization?
    ) {
        self.snapshot = snapshot
        self.throttleState = throttleState
        self.fans = fans
        self.processes = processes
        self.gpuUtilization = gpuUtilization
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
