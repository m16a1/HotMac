import Foundation

/// Samples the SMC on a background queue and publishes readings for the UI.
///
/// The SMC connection and the per-key metadata are created once and reused,
/// so each tick is only the value reads (~10 ms of CPU on the M5 Max).
final class TemperatureModel: ObservableObject {
    struct HistoryPoint: Identifiable {
        let id = UUID()
        let time: Date
        let values: [String: Double]
    }

    @Published private(set) var snapshot: TemperatureSnapshot?
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdate: Date?
    @Published var refreshPeriod: Double = 2.0 {
        didSet { persistPeriod(); restartTimer() }
    }

    private let queue = DispatchQueue(label: "com.hotmac.smc", qos: .utility)
    private let brand: String
    private let maxHistory = 900

    private var timer: DispatchSourceTimer?
    private var smc: SMC?
    private var meta: [String: SMC.KeyInfo] = [:]
    private var started = false

    init(startImmediately: Bool = true) {
        brand = SensorCatalog.chipBrand()
        if let stored = UserDefaults.standard.object(forKey: "refreshPeriod") as? Double, stored > 0 {
            refreshPeriod = stored
        }
        if startImmediately {
            start()
        }
    }

#if DEBUG
    /// Load a synthetic history so the UI can be rendered without an SMC.
    func loadPreviewData(samples: Int = 150) {
        let names = ["CPU overall", "GPU clusters", "Memory", "SoC package", SensorCatalog.hottestSeriesName]
        let now = Date()
        var points: [HistoryPoint] = []
        for index in 0..<samples {
            let time = now.addingTimeInterval(Double(index - samples) * refreshPeriod)
            let phase = Double(index) / Double(samples)
            var values: [String: Double] = [:]
            values["CPU overall"] = 42 + 14 * sin(phase * .pi * 2)
            values["GPU clusters"] = 38 + 10 * cos(phase * .pi * 2)
            values["Memory"] = 40 + 6 * sin(phase * .pi * 4)
            values["SoC package"] = 34 + 3 * cos(phase * .pi * 3)
            values[SensorCatalog.hottestSeriesName] = 58 + 18 * sin(phase * .pi * 2)
            points.append(HistoryPoint(time: time, values: values))
        }
        history = points
        lastUpdate = points.last?.time
        snapshot = TemperatureSnapshot(
            brand: brand,
            groups: names.dropLast().map {
                GroupReading(name: $0, average: 45, minimum: 40, maximum: 50, count: 4)
            },
            hottest: [SensorReading(key: "TCMb", value: 76.0)],
            highest: 76.0
        )
    }
#endif

    var menuBarTitle: String {
        guard let highest = snapshot?.highest else { return "--°" }
        return "\(Int(highest.rounded()))°"
    }

    var seriesNames: [String] {
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

    func clearHistory() {
        history.removeAll()
    }

    private func persistPeriod() {
        UserDefaults.standard.set(refreshPeriod, forKey: "refreshPeriod")
    }

    private func restartTimer() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: refreshPeriod, leeway: .milliseconds(200))
        source.setEventHandler { [weak self] in self?.sample() }
        timer = source
        source.resume()
    }

    private func sample() {
        do {
            if smc == nil {
                let client = try SMC()
                meta = try client.collectTemperatureMeta()
                smc = client
            }
            guard let smc = smc else { return }

            var table: [String: (format: String, raw: [UInt8], littleEndian: Bool)] = [:]
            for (key, info) in meta {
                if let raw = try? smc.readValue(key, size: info.size) {
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
            DispatchQueue.main.async { [weak self] in
                self?.apply(snapshot: snap, point: point)
            }
        } catch {
            smc = nil
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "\(error)"
            }
        }
    }

    private func apply(snapshot: TemperatureSnapshot, point: HistoryPoint) {
        self.snapshot = snapshot
        self.errorMessage = nil
        self.lastUpdate = point.time
        history.append(point)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }
}
