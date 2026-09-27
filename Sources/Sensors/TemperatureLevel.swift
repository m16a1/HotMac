import Foundation

/// How hot a reading is, banded so the menu bar can flag a machine running hot
/// without inventing thresholds of its own.
///
/// The bands partition the plausible range: everything below `warmThreshold` is
/// `normal`, which is what a machine at rest reads and what deserves no
/// emphasis. The boundaries come from the measured behaviour of the M5 Max,
/// which idles near 45-50 °C, reaches the high 80s under saturated GPU load,
/// and passes 100 °C under a sustained local-LLM run.
public enum TemperatureLevel: Equatable {
    case normal
    case warm
    case hot
    case critical

    /// The temperature each band starts at, in °C.
    public static let warmThreshold = 60.0
    public static let hotThreshold = 80.0
    public static let criticalThreshold = 95.0

    public static func level(for celsius: Double) -> TemperatureLevel {
        switch celsius {
        case ..<warmThreshold: .normal
        case ..<hotThreshold: .warm
        case ..<criticalThreshold: .hot
        default: .critical
        }
    }
}
