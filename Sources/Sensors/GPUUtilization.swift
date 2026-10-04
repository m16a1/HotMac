import Foundation

/// How busy the GPU is, as a percentage, from the accelerator's own statistics.
///
/// This is the device as a whole. The same driver accounts GPU time per process,
/// which `GPUClientCounters` reads, and those shares add up to this figure: the
/// two are the same measurement at two resolutions, so they can be shown
/// together. `System/GPUReader.swift` reads the accelerator's statistics
/// dictionary; interpreting it is pure and lives here.
public struct GPUUtilization: Equatable, Sendable {
    /// Busy time over the accelerator's last sampling window, 0...100.
    public let percent: Double

    /// Rejects a value outside the percentage range, which is a statistic that
    /// does not mean what this type says it means.
    public init?(percent: Int) {
        guard (0...100).contains(percent) else { return nil }
        self.percent = Double(percent)
    }
}

extension GPUUtilization {
    /// The key the accelerator uses for the whole-device figure in its
    /// `PerformanceStatistics` dictionary.
    static let statisticsKey = "Device Utilization %"

    /// Pull the device utilization out of an accelerator's statistics, or nil
    /// when the key is absent or not a number, as older accelerators report it.
    static func from(statistics: [String: Any]?) -> GPUUtilization? {
        guard let raw = statistics?[statisticsKey] as? Int else { return nil }
        return GPUUtilization(percent: raw)
    }
}
