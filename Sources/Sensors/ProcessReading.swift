import Foundation

/// One process's share of the machine at a moment in time.
///
/// The Processes screen and the menu bar's process list are ranked lists of
/// these. A reading is derived from two counter samples
/// (`ProcessCounters.readings(previous:current:elapsed:)`), never read directly:
/// the host reports cumulative CPU time, not a percentage or a name.
public struct ProcessReading: Identifiable, Equatable, Sendable {
    /// The process identifier. The kernel reuses a pid after a process exits,
    /// which is why a reading is only meaningful for the tick that took it.
    public let pid: Int32
    /// The process's short name, for example `kernel_task` or `Google Chrome`.
    /// A process the kernel will not describe is named by the GPU driver instead,
    /// which records a name for every GPU client.
    public let name: String
    /// CPU time used over the sampling interval, as a percentage of one core.
    /// A process spread across several cores reports a multiple of 100, which is
    /// how `top` shows it. Nil for a process the kernel would not describe to an
    /// unprivileged caller, which is every process owned by another user, unless
    /// another source supplied a figure: `ps` reports one for exactly those
    /// processes and the model fills it in.
    public let cpuPercent: Double?
    /// Resident memory in bytes, nil for the same reason `cpuPercent` is.
    public let memoryBytes: UInt64?
    /// GPU time over the same interval, as a percentage of the whole device.
    /// Every process carries one: a process the driver never saw holding a GPU
    /// client is using none of the device, so it reads 0.
    public let gpuPercent: Double

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        name: String,
        cpuPercent: Double? = nil,
        memoryBytes: UInt64? = nil,
        gpuPercent: Double
    ) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.gpuPercent = gpuPercent
    }
}
