import Foundation

/// One process's cumulative GPU time as the GPU driver reports it at one instant.
///
/// The driver keeps a running total for each process that has reached the GPU,
/// and unlike CPU time those totals partition the device: the shares of every
/// process add up to the whole GPU's busy time, which is what makes one process's
/// percentage comparable with the whole-device figure. The process's own name
/// comes with it, because the driver records who opened the client.
/// `System/GPUClientReader.swift` produces these, one per client;
/// `percentages(previous:current:elapsed:)` turns two samples into shares.
public struct GPUClientCounters: Equatable, Sendable {
    public let pid: Int32
    /// The process name the kernel recorded when the client was opened. The
    /// kernel truncates it, so a table row that has the process's own name should
    /// show that instead; this is the only name a process outside the table has.
    public let name: String
    /// Cumulative GPU time in seconds since that process opened its client.
    public let gpuSeconds: Double

    public init(pid: Int32, name: String, gpuSeconds: Double) {
        self.pid = pid
        self.name = name
        self.gpuSeconds = gpuSeconds
    }
}

extension GPUClientCounters {
    /// The key inside an `AppUsage` entry that holds the accumulated GPU time.
    static let usageGpuTimeKey = "accumulatedGPUTime"

    /// GPU time is reported in nanoseconds, the unit the driver's clock counts in.
    static let nanosecondsPerSecond = 1_000_000_000.0

    /// A share of the whole device, in percent: the GPU time this client gained
    /// over the interval, divided by the time that passed.
    ///
    /// A client with no earlier counter has no baseline, so its first share is
    /// 0% rather than its whole lifetime of GPU time, and an interval that is not
    /// positive leaves no rate to form, which `top` answers the same way for CPU.
    /// A pid reused by a process that has used less GPU makes the total appear to
    /// go backwards; that is a stale baseline, not negative usage. The baseline is
    /// matched by pid, so another process's total is never read as this one's.
    public func percentage(previous: [GPUClientCounters], elapsed: TimeInterval) -> Double {
        guard elapsed > 0, let baseline = previous.first(where: { $0.pid == pid }) else {
            return 0
        }
        return max(0, gpuSeconds - baseline.gpuSeconds) / elapsed * Self.percentScale
    }

    /// One hundred percent, the scale a share of one GPU is counted on.
    private static let percentScale = 100.0

    /// Fold the clients of one process into a single total.
    ///
    /// The driver keeps one counter per client and a process can open several, so
    /// a process's GPU time is the sum of its clients'. The first name wins: the
    /// clients of one process all carry the same name, truncated the same way.
    public static func merged(_ counters: [GPUClientCounters]) -> [GPUClientCounters] {
        var order: [Int32] = []
        var totals: [Int32: GPUClientCounters] = [:]
        for counter in counters {
            guard let kept = totals[counter.pid] else {
                totals[counter.pid] = counter
                order.append(counter.pid)
                continue
            }
            totals[counter.pid] = GPUClientCounters(
                pid: kept.pid,
                name: kept.name,
                gpuSeconds: kept.gpuSeconds + counter.gpuSeconds
            )
        }
        return order.compactMap { totals[$0] }
    }

    /// The process a client belongs to, read out of the string the driver records
    /// for it, which is spelled `pid 170, WindowServer` with the name truncated.
    ///
    /// A string that does not have that shape names no process, so the client is
    /// dropped rather than attributed to a guess.
    static func owner(fromCreator creator: String) -> (pid: Int32, name: String)? {
        let prefix = "pid "
        guard creator.hasPrefix(prefix) else { return nil }
        let rest = creator.dropFirst(prefix.count)
        guard let comma = rest.firstIndex(of: ","), let pid = Int32(rest[rest.startIndex..<comma])
        else { return nil }
        let name = rest[rest.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return (pid, name)
    }

    /// One client's accumulated GPU time, in seconds, from the array of usage
    /// entries the driver keeps for it: one entry per API it submitted through,
    /// and the client's total is their sum. An empty array is a client that
    /// submitted nothing, which is a measured zero.
    static func gpuSeconds(fromAppUsage usage: [[String: Any]]) -> Double {
        var nanoseconds: UInt64 = 0
        for entry in usage {
            nanoseconds += (entry[usageGpuTimeKey] as? UInt64) ?? 0
        }
        return Double(nanoseconds) / nanosecondsPerSecond
    }
}
