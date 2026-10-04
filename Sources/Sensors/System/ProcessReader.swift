import Darwin
import Foundation

/// Reads every running process straight from libproc: its name, cumulative CPU
/// time, and resident memory.
///
/// This is the host boundary for the process table. `proc_listallpids` and
/// `proc_pidinfo` only mean anything on a running macOS host, so this file lives
/// in `System/` and is excluded from the coverage report; the pure
/// `ProcessCounters` turns what it returns into readings.
enum ProcessReader {
    /// Buffer size for `proc_name`, which libproc documents as
    /// `PROC_PIDPATHINFO_MAXSIZE` (4 * MAXPATHLEN). The kernel truncates longer
    /// names rather than failing, so this needs no length check.
    private static let nameBufferSize = 4 * 1024

    /// CPU time is reported in mach absolute time units. The host's timebase
    /// converts them and never changes, so it is read once.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// One counter entry per process the kernel will report to us, in the order
    /// the kernel lists them. A process whose task info or name cannot be read
    /// is skipped, which is what a process owned by another user looks like.
    static func read() -> [ProcessCounters] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }

        // A little headroom: processes can appear between the two calls, and a
        // buffer that is exactly the old count would silently drop them.
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 16)
        let listed = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard listed > 0 else { return [] }

        return pids.prefix(Int(listed)).compactMap { pid in
            guard pid > 0 else { return nil }
            return counters(for: pid)
        }
    }

    private static func counters(for pid: pid_t) -> ProcessCounters? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }

        var name = [CChar](repeating: 0, count: nameBufferSize)
        guard proc_name(pid, &name, UInt32(nameBufferSize)) > 0 else { return nil }

        let ticks = Double(info.pti_total_user + info.pti_total_system)
        let nanoseconds = ticks * Double(timebase.numer) / Double(timebase.denom)
        return ProcessCounters(
            pid: pid,
            name: String(cString: name),
            cpuSeconds: nanoseconds / 1_000_000_000,
            memoryBytes: UInt64(info.pti_resident_size)
        )
    }
}
