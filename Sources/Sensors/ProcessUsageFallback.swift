import Foundation

/// One process's CPU and memory as `ps` reports them.
///
/// This is the shape of the figures for the processes the kernel will not
/// describe to us, which have no counters of their own. It pairs with
/// `ProcessReading`, whose two fields it fills.
public struct ProcessUsage: Equatable, Sendable {
    /// CPU time over the interval, as a percentage of one core.
    public let cpuPercent: Double
    /// Resident memory in bytes.
    public let memoryBytes: UInt64

    public init(cpuPercent: Double, memoryBytes: UInt64) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

/// The per-process CPU and memory `ps` reports, parsed from its output.
///
/// The kernel will not describe another user's process to an unprivileged
/// caller, so the rows for those processes have no figures of their own. The only
/// unprivileged source is `ps`, which is an Apple platform binary carrying the
/// `com.apple.system-task-ports.read` entitlement our ad-hoc signature cannot
/// have. Running it is the host boundary (`System/PSReader.swift`); the parsing is
/// here because it is pure and can be tested without spawning anything.
public enum ProcessUsageFallback {
    /// `ps` reports resident memory in 1024-byte units, the same resident set the
    /// kernel reports for a process it will describe, so the two agree.
    private static let bytesPerResidentUnit: UInt64 = 1024

    /// Parse the `pid cpu rss` lines `ps -o pid=,pcpu=,rss=` prints, one process
    /// per line, into a pid-keyed table. A line that is not exactly three numbers
    /// is skipped, so a stray message on stdout cannot become a reading. A pid
    /// that has exited by the time `ps` runs is simply absent from the table.
    public static func parse(_ output: String) -> [Int32: ProcessUsage] {
        var table: [Int32: ProcessUsage] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 3,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let resident = UInt64(fields[2]) else { continue }
            table[pid] = ProcessUsage(
                cpuPercent: cpu,
                memoryBytes: resident * bytesPerResidentUnit
            )
        }
        return table
    }
}
