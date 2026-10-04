import Foundation

/// One GPU client's share of the device over the last sampling interval.
///
/// The driver reports a running total per client, not a percentage, so a share is
/// derived from two counter samples and never read directly. It also carries the
/// name the driver recorded, which matters because the kernel will not describe
/// another user's process to us: the driver's name is the only one such a process
/// has, and it is what gives that process a row in the table at all.
public struct GPUShare: Identifiable, Equatable, Sendable {
    /// The process identifier. The kernel reuses a pid, so a share is only
    /// meaningful for the tick that measured it.
    public let pid: Int32
    /// The process's name as the driver recorded it, which the kernel truncates.
    public let name: String
    /// GPU time used over the interval, as a percentage of the whole device.
    public let gpuPercent: Double

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, gpuPercent: Double) {
        self.pid = pid
        self.name = name
        self.gpuPercent = gpuPercent
    }
}

extension GPUShare {
    /// Every GPU client's share for this tick, one entry per process.
    ///
    /// A process holding a client and submitting nothing is kept, reading 0%: the
    /// table shows it as measured and idle, which is not the same as the dash a
    /// process with no client at all gets.
    public static func readings(
        previous: [GPUClientCounters],
        current: [GPUClientCounters],
        elapsed: TimeInterval
    ) -> [GPUShare] {
        current.map { counter in
            GPUShare(
                pid: counter.pid,
                name: counter.name,
                gpuPercent: counter.percentage(previous: previous, elapsed: elapsed)
            )
        }
    }
}
