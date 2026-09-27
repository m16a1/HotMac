#if DEBUG
import Foundation

/// Synthetic waveforms for `TemperatureModel.loadPreviewData()`.
enum PreviewData {
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
