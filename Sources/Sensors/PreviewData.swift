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

    /// A plausible status row: the hot waveform is presented as un-throttled.
    static let throttleState = ThrottleState.nominal

    /// A plausible fan readout: two fans, both above idle, like a machine that
    /// has been working.
    static let fans: [FanReading] = [
        FanReading(index: 0, current: 2150, minimum: 1350, maximum: 5349),
        FanReading(index: 1, current: 2380, minimum: 1350, maximum: 5777),
    ]

    /// A fan's speed at a point in the preview: a slow swing around its
    /// reported current, so the graph has something to draw.
    static func fanSpeed(_ fan: FanReading, inPhase phase: Double) -> Double {
        fan.current * (1 + 0.15 * sin(phase * .pi * 2))
    }

    /// One oscillating series: a sine or cosine of `quarterTurns` half-turns
    /// across the span, added to `offset`. One entry per group the preview
    /// snapshot reports.
    static let waves: [Wave] = [
        Wave(
            name: SensorCatalog.cpuOverallGroupName,
            offset: 42, amplitude: 14, quarterTurns: 2, useCosine: false
        ),
        Wave(name: "GPU clusters", offset: 38, amplitude: 10, quarterTurns: 2, useCosine: true),
        Wave(name: "Memory", offset: 40, amplitude: 6, quarterTurns: 4, useCosine: false),
        Wave(name: "SoC package", offset: 34, amplitude: 3, quarterTurns: 3, useCosine: true),
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
