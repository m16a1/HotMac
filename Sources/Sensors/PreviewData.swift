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

    /// A plausible process table: a few recognisable names, busiest first, as
    /// the real ranking would leave them. The last one has no GPU client, so it
    /// reads 0%, the way the real table shows it.
    static let processes: [ProcessReading] = [
        ProcessReading(pid: 812, name: "Google Chrome", cpuPercent: 41.2,
                       memoryBytes: 1_204_000_000, gpuPercent: 8.4),
        ProcessReading(pid: 2331, name: "Xcode", cpuPercent: 28.7,
                       memoryBytes: 2_140_000_000, gpuPercent: 31.6),
        ProcessReading(pid: 188, name: "WindowServer", cpuPercent: 12.4,
                       memoryBytes: 486_000_000, gpuPercent: 44.9),
        ProcessReading(pid: 1337, name: "python3", cpuPercent: 6.1,
                       memoryBytes: 212_000_000, gpuPercent: 0),
    ]

    /// A plausible GPU reading: the machine is clearly doing work, which is the
    /// state the process table alone no longer shows.
    static let gpuUtilization = GPUUtilization(percent: 36)

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
