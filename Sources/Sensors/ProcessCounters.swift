import Foundation

/// A process's cumulative counters as the host reports them at one instant.
///
/// The host hands out CPU time as a running total, so a percentage needs two
/// samples and the wall time between them; `readings(previous:current:elapsed:)`
/// does that derivation and the ranking. `System/ProcessReader.swift` produces
/// these, one per process it can read.
public struct ProcessCounters: Equatable, Sendable {
    public let pid: Int32
    public let name: String
    /// Cumulative CPU time in seconds, user plus system.
    public let cpuSeconds: Double
    /// Resident memory in bytes.
    public let memoryBytes: UInt64

    public init(pid: Int32, name: String, cpuSeconds: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuSeconds = cpuSeconds
        self.memoryBytes = memoryBytes
    }
}

extension ProcessCounters {
    /// How many processes the table keeps. macOS runs hundreds at once; a
    /// top-like view wants the busiest handful.
    public static let limit = 12

    /// One core fully busy, which is the scale `top` counts on.
    private static let percentScale = 100.0

    /// Turn two counter snapshots into readings, busiest first.
    ///
    /// A process with no earlier counter has no baseline, so its first reading
    /// is 0% rather than its lifetime average. A process that exits between the
    /// snapshots simply disappears. `elapsed` is the wall time between the two
    /// snapshots; when it is not positive no rate can be formed and every
    /// reading is 0%.
    ///
    /// The GPU arrives as its own derived shares, taken over the same interval, so
    /// a row can carry both of its own figures. A process the kernel will not
    /// describe to an unprivileged caller — every process owned by another user,
    /// `WindowServer` among them — is missing from the CPU list entirely, while
    /// the GPU driver still reports its time and its name, so it gets a row of its
    /// own. Its CPU and memory are unknown unless `fallback` carries them: the
    /// caller can supply both from `ps`, the only unprivileged source for them.
    /// Such a row is only worth having when
    /// it is using the GPU: a dash of a row per idle GPU client would bury the
    /// table.
    public static func readings(
        previous: [ProcessCounters],
        current: [ProcessCounters],
        elapsed: TimeInterval,
        gpuShares: [GPUShare] = [],
        fallback: [Int32: ProcessUsage] = [:]
    ) -> [ProcessReading] {
        var baselines: [Int32: Double] = [:]
        for counter in previous {
            baselines[counter.pid] = counter.cpuSeconds
        }
        var shares: [Int32: GPUShare] = [:]
        for share in gpuShares {
            shares[share.pid] = share
        }

        var readings = current.map { sample in
            ProcessReading(
                pid: sample.pid,
                name: sample.name,
                cpuPercent: rate(of: sample, baselines: baselines, elapsed: elapsed),
                memoryBytes: sample.memoryBytes,
                gpuPercent: shares[sample.pid]?.gpuPercent ?? 0
            )
        }

        for share in undescribed(current, gpuShares: gpuShares) {
            let usage = fallback[share.pid]
            readings.append(
                ProcessReading(
                    pid: share.pid,
                    name: share.name,
                    cpuPercent: usage?.cpuPercent,
                    memoryBytes: usage?.memoryBytes,
                    gpuPercent: share.gpuPercent
                )
            )
        }

        // Rank on values that are all present, so the comparator has no missing
        // case to handle: a row the kernel would not describe has no memory to
        // rank on and counts as none.
        let ranked = readings.map { reading in
            (reading: reading, load: load(reading), memory: reading.memoryBytes ?? 0)
        }
        return ranked
            .sorted(by: rank)
            .prefix(limit)
            .map(\.reading)
    }

    /// The GPU clients the kernel will not describe: the rows that have no CPU
    /// figure of their own and so need one from another source. Only the ones
    /// using the GPU are among them, because a hidden client using none of the
    /// device gets no row at all.
    public static func undescribed(
        _ current: [ProcessCounters],
        gpuShares: [GPUShare]
    ) -> [GPUShare] {
        let listed = Set(current.map(\.pid))
        return gpuShares.filter { $0.gpuPercent > 0 && !listed.contains($0.pid) }
    }

    /// CPU time used over the interval, as a share of one core. A process with no
    /// earlier counter has no baseline to measure from, so it reads 0 rather than
    /// as an unknown: the process was described, it just was not measured before.
    private static func rate(
        of sample: ProcessCounters,
        baselines: [Int32: Double],
        elapsed: TimeInterval
    ) -> Double {
        guard elapsed > 0, let baseline = baselines[sample.pid] else { return 0 }
        return max(0, sample.cpuSeconds - baseline) / elapsed * percentScale
    }

    /// A row is placed by whichever of its two shares is the larger, then by the
    /// memory it holds, then by pid, so the order is total and the table does not
    /// shuffle between ticks.
    private static func rank(
        _ lhs: (reading: ProcessReading, load: Double, memory: UInt64),
        _ rhs: (reading: ProcessReading, load: Double, memory: UInt64)
    ) -> Bool {
        if lhs.load != rhs.load { return lhs.load > rhs.load }
        if lhs.memory != rhs.memory { return lhs.memory > rhs.memory }
        return lhs.reading.pid < rhs.reading.pid
    }

    /// The share a row is ranked on: a row is placed by whichever of its two
    /// shares is the larger.
    ///
    /// The two are not the same unit — CPU is a share of one core, GPU a share of
    /// the whole device — so taking the larger is a heuristic rather than a
    /// measurement. It is the one that keeps the table readable: a machine whose
    /// GPU is idle reports no GPU shares at all, so the order is then exactly the
    /// CPU order it has always been, while a process taking a fifth of the GPU is
    /// placed beside the CPU hogs instead of being buried under a dozen idle rows.
    private static func load(_ reading: ProcessReading) -> Double {
        max(reading.cpuPercent ?? 0, reading.gpuPercent)
    }
}
