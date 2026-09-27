import Foundation

/// Samples the SMC on a background queue and publishes readings for the UI.
///
/// The SMC connection and the per-key metadata are created once and reused,
/// so each tick is only the value reads (~10 ms of CPU on the M5 Max).
public final class TemperatureModel: ObservableObject {
    /// Sampling period in seconds before the user moves the slider.
    public static let defaultRefreshPeriod: Double = 2.0

    /// UserDefaults key holding the user's sampling period.
    private enum Storage {
        static let refreshPeriodKey = "refreshPeriod"
    }

    private static let queueLabel = "com.hotmac.smc"
    private static let timerLeeway = DispatchTimeInterval.milliseconds(200)
    private static let menuBarPlaceholder = "--°"
    private static let degreeSymbol = "°"

    /// How many samples the graph keeps before the oldest are dropped.
    static let maxHistory = 900

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

    @Published public private(set) var snapshot: TemperatureSnapshot?
    @Published public private(set) var history: [HistoryPoint] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastUpdate: Date?
    @Published public var refreshPeriod: Double = TemperatureModel.defaultRefreshPeriod {
        didSet { persistPeriod(); restartTimer() }
    }

    private let queue = DispatchQueue(label: TemperatureModel.queueLabel, qos: .utility)
    private let brand: String

    /// Creates the SMC connection. Injectable so tests can supply a client
    /// wired to a fake transport instead of the kernel.
    private let makeSMC: () throws -> SMC

    /// Hands work back to the main thread. Injectable so tests can stay
    /// synchronous instead of spinning a run loop.
    private let deliver: (@escaping () -> Void) -> Void

    private var timer: DispatchSourceTimer?
    private var smc: SMC?
    private var meta: [String: SMC.KeyInfo] = [:]
    private var started = false

    /// Dependencies are required rather than defaulted so that this class
    /// contains no production wiring of its own; `TemperatureModel.live()`
    /// supplies the real ones. Internal because `SMC` is an implementation
    /// detail: the app composes through `live()`.
    init(
        startImmediately: Bool = true,
        brand: String,
        makeSMC: @escaping () throws -> SMC,
        deliver: @escaping (@escaping () -> Void) -> Void
    ) {
        self.makeSMC = makeSMC
        self.deliver = deliver
        self.brand = brand
        if let stored = UserDefaults.standard.object(forKey: Storage.refreshPeriodKey) as? Double,
           stored > 0 {
            refreshPeriod = stored
        }
        if startImmediately {
            start()
        }
    }

#if DEBUG
    /// Load a synthetic history so the UI can be rendered without an SMC.
    func loadPreviewData(samples: Int = PreviewData.sampleCount) {
        let now = Date()
        var points: [HistoryPoint] = []
        for index in 0..<samples {
            let time = now.addingTimeInterval(Double(index - samples) * refreshPeriod)
            let phase = Double(index) / Double(samples)
            var values: [String: Double] = [:]
            for wave in PreviewData.waves {
                values[wave.name] = wave.value(inPhase: phase)
            }
            points.append(HistoryPoint(time: time, values: values))
        }
        history = points
        lastUpdate = points.last?.time
        snapshot = TemperatureSnapshot(
            brand: brand,
            groups: PreviewData.waves.dropLast().map {
                GroupReading(
                    name: $0.name,
                    average: PreviewData.groupAverage,
                    minimum: PreviewData.groupMinimum,
                    maximum: PreviewData.groupMaximum,
                    count: PreviewData.groupSensorCount
                )
            },
            hottest: [
                SensorReading(key: PreviewData.hottestKey, value: PreviewData.hottestValue)
            ],
            highest: PreviewData.hottestValue
        )
    }
#endif

    public var menuBarTitle: String {
        guard let highest = snapshot?.highest else { return TemperatureModel.menuBarPlaceholder }
        return "\(Int(highest.rounded()))\(TemperatureModel.degreeSymbol)"
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
    }

    private func persistPeriod() {
        UserDefaults.standard.set(refreshPeriod, forKey: Storage.refreshPeriodKey)
    }

    private func restartTimer() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: refreshPeriod, leeway: TemperatureModel.timerLeeway)
        source.setEventHandler { [weak self] in self?.sample() }
        timer = source
        source.resume()
    }

    /// One sampling tick. Not private so tests can drive it directly rather
    /// than waiting on the timer.
    func sample() {
        do {
            let client: SMC
            if let existing = smc {
                client = existing
            } else {
                let created = try makeSMC()
                meta = try created.collectTemperatureMeta()
                smc = created
                client = created
            }

            var table: [String: (format: String, raw: [UInt8], littleEndian: Bool)] = [:]
            for (key, info) in meta {
                if let raw = try? client.readValue(key, size: info.size) {
                    table[key] = (info.format, raw, info.littleEndian)
                }
            }
            guard !table.isEmpty else { return }

            let snap = SensorCatalog.snapshot(brand: brand, table: table)
            var values: [String: Double] = [:]
            for group in snap.groups { values[group.name] = group.average }
            if let highest = snap.highest {
                values[SensorCatalog.hottestSeriesName] = highest
            }
            let point = HistoryPoint(time: Date(), values: values)
            deliver { [weak self] in
                self?.apply(snapshot: snap, point: point)
            }
        } catch {
            smc = nil
            deliver { [weak self] in
                self?.errorMessage = "\(error)"
            }
        }
    }

    private func apply(snapshot: TemperatureSnapshot, point: HistoryPoint) {
        self.snapshot = snapshot
        self.errorMessage = nil
        self.lastUpdate = point.time
        history.append(point)
        if history.count > TemperatureModel.maxHistory {
            history.removeFirst(history.count - TemperatureModel.maxHistory)
        }
    }
}

#if DEBUG
/// Synthetic waveforms for `TemperatureModel.loadPreviewData()`.
private enum PreviewData {
    static let sampleCount = 150
    static let groupAverage = 45.0
    static let groupMinimum = 40.0
    static let groupMaximum = 50.0
    static let groupSensorCount = 4
    static let hottestKey = "TCMb"
    static let hottestValue = 76.0

    /// One oscillating series: a sine or cosine of `quarterTurns` half-turns
    /// across the span, added to `offset`. The last entry is the "Hottest
    /// sensor" series, which is also the snapshot's top reading.
    static let waves: [Wave] = [
        Wave(
            name: SensorCatalog.cpuOverallGroupName,
            offset: 42, amplitude: 14, quarterTurns: 2, useCosine: false
        ),
        Wave(name: "GPU clusters", offset: 38, amplitude: 10, quarterTurns: 2, useCosine: true),
        Wave(name: "Memory", offset: 40, amplitude: 6, quarterTurns: 4, useCosine: false),
        Wave(name: "SoC package", offset: 34, amplitude: 3, quarterTurns: 3, useCosine: true),
        Wave(
            name: SensorCatalog.hottestSeriesName,
            offset: 58, amplitude: 18, quarterTurns: 2, useCosine: false
        ),
    ]

    struct Wave {
        let name: String
        let offset: Double
        let amplitude: Double
        let quarterTurns: Double
        let useCosine: Bool

        func value(inPhase phase: Double) -> Double {
            let angle = phase * .pi * quarterTurns
            return offset + amplitude * (useCosine ? cos(angle) : sin(angle))
        }
    }
}
#endif
