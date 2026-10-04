import Foundation
import Testing
@testable import Sensors

/// Turning two counter snapshots into a ranked process table.
@Suite("Process readings")
struct ProcessTests {
    /// One process's counters at a moment, with the parts a case does not care
    /// about defaulted so a case states only what it is testing.
    private func process(
        _ pid: Int32,
        name: String = "p",
        cpu: Double,
        memory: UInt64 = 0
    ) -> ProcessCounters {
        ProcessCounters(pid: pid, name: name, cpuSeconds: cpu, memoryBytes: memory)
    }

    /// One process's GPU share for the interval, as the derived set would carry
    /// it. The derivation itself is `GPUShareTests`' business; a case here states
    /// the shares it wants the table to be built from.
    private func gpu(
        _ pid: Int32,
        name: String = "gpu",
        percent: Double
    ) -> GPUShare {
        GPUShare(pid: pid, name: name, gpuPercent: percent)
    }

    /// CPU time used over the interval, as a share of one core.
    @Test func cpuIsTheTimeUsedOverTheInterval() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 10.0)],
            current: [process(1, cpu: 10.5)],
            elapsed: 1
        )

        #expect(readings.map(\.cpuPercent) == [50.0])
    }

    /// A process on several cores reports a multiple of 100, the way `top` does.
    @Test func cpuCanExceedOneHundred() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0)],
            current: [process(1, cpu: 1)],
            elapsed: 0.25
        )

        #expect(readings.map(\.cpuPercent) == [400.0])
    }

    /// A process seen for the first time has no baseline, so it reads as 0%
    /// rather than as its whole lifetime of CPU time.
    @Test func aProcessWithNoEarlierCounterReadsAsZero() {
        let readings = ProcessCounters.readings(
            previous: [],
            current: [process(1, cpu: 10.0)],
            elapsed: 1
        )

        #expect(readings.map(\.cpuPercent) == [0.0])
    }

    /// A new process among known ones does not disturb the others' rates.
    @Test func onlyTheProcessesWithABaselineGetARate() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0)],
            current: [process(1, cpu: 0.5), process(2, cpu: 5.0)],
            elapsed: 1
        )

        #expect(readings.map(\.pid) == [1, 2])
        #expect(readings.map(\.cpuPercent) == [50.0, 0.0])
    }

    /// With no time between the snapshots there is no rate to form.
    @Test func aNonPositiveIntervalYieldsNoRate() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0)],
            current: [process(1, cpu: 1)],
            elapsed: 0
        )

        #expect(readings.map(\.cpuPercent) == [0.0])
    }

    /// A pid reused by a lighter process makes the counter appear to go
    /// backwards; that is a stale baseline, not negative usage.
    @Test func aCounterThatGoesBackwardsClampsToZero() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 10.0)],
            current: [process(1, cpu: 5.0)],
            elapsed: 1
        )

        #expect(readings.map(\.cpuPercent) == [0.0])
    }

    /// Busiest CPU first, then the largest memory, then pid, so equal-looking
    /// rows still have a settled order.
    @Test func readingsAreRankedByCpuThenMemoryThenPid() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0), process(2, cpu: 0),
                       process(3, cpu: 0), process(4, cpu: 0)],
            current: [
                process(1, cpu: 0.5, memory: 10),
                process(2, cpu: 0.5, memory: 20),
                process(3, cpu: 0.1, memory: 5),
                process(4, cpu: 0.5, memory: 10),
            ],
            elapsed: 1
        )

        #expect(readings.map(\.pid) == [2, 1, 4, 3])
    }

    /// The table is a top-N, not the whole process list: the extra rows are
    /// dropped, and the ones kept are exactly the busiest.
    @Test func onlyTheBusiestProcessesAreKept() {
        let total = ProcessCounters.limit + 3
        var previous: [ProcessCounters] = []
        var current: [ProcessCounters] = []
        for pid in 0..<total {
            previous.append(process(Int32(pid), cpu: 0))
            current.append(process(Int32(pid), cpu: Double(pid) + 1))
        }

        let readings = ProcessCounters.readings(
            previous: previous,
            current: current,
            elapsed: 1
        )

        #expect(readings.count == ProcessCounters.limit)
        #expect(readings.first?.pid == Int32(total - 1))
        #expect(readings.last?.pid == Int32(total - ProcessCounters.limit))
    }

    /// The table is user-visible, so pin its size by value rather than against
    /// the symbol it is read from.
    @Test func theTableSizeIsPinned() {
        #expect(ProcessCounters.limit == 12)
    }

    /// Name, memory and identity all travel with the reading.
    @Test func theReadingCarriesNameMemoryAndIdentity() {
        let readings = ProcessCounters.readings(
            previous: [process(7, cpu: 0)],
            current: [process(7, name: "python3", cpu: 0.5, memory: 999)],
            elapsed: 1
        )

        #expect(readings.first?.name == "python3")
        #expect(readings.first?.memoryBytes == 999)
        #expect(readings.map(\.id) == readings.map(\.pid))
    }

    /// The GPU half is joined onto the reading by pid, so a row can show both of
    /// its shares without the view holding two lists.
    @Test func theGPUFigureIsJoinedByPid() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0), process(2, cpu: 0)],
            current: [process(1, cpu: 0.5), process(2, cpu: 0.5)],
            elapsed: 1,
            gpuShares: [gpu(2, percent: 44.9)]
        )

        #expect(readings.map(\.pid) == [1, 2])
        #expect(readings.map(\.gpuPercent) == [0, 44.9])
    }

    /// The GPU column has no dash: a process the driver saw holding a client and
    /// using none of it reads 0%, and so does a process with no GPU client at
    /// all, because holding no client is using none of the device.
    @Test func aProcessWithNoGPUUseReadsAsZero() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0), process(2, cpu: 0)],
            current: [process(1, cpu: 0.5), process(2, cpu: 0.5)],
            elapsed: 1,
            gpuShares: [gpu(1, percent: 0)]
        )

        #expect(readings.map(\.gpuPercent) == [0, 0])
    }

    /// A process the kernel will not describe to an unprivileged caller is absent
    /// from the CPU list — `WindowServer` belongs to another user — but the GPU
    /// driver still names it and reports its GPU time, so it gets a row with only
    /// the share that exists. Without this the GPU column sums to less than the
    /// whole-device figure the Settings screen shows.
    @Test func aProcessTheKernelHidesIsNamedByTheDriver() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0)],
            current: [process(1, cpu: 0.2)],
            elapsed: 1,
            gpuShares: [gpu(170, name: "WindowServer", percent: 30)]
        )

        #expect(readings.map(\.pid) == [170, 1])
        #expect(readings.first?.name == "WindowServer")
        #expect(readings.first?.gpuPercent == 30)
        #expect(readings.first?.cpuPercent == nil)
        #expect(readings.first?.memoryBytes == nil)
    }

    /// The rows that need a CPU figure from another source are exactly the GPU
    /// clients the kernel did not describe, and only the ones using the GPU: a
    /// hidden client using none of the device gets no row to fill.
    @Test func undescribedIsTheGPUUsingHiddenClients() {
        let undescribed = ProcessCounters.undescribed(
            [process(1, cpu: 0)],
            gpuShares: [
                gpu(1, percent: 10),
                gpu(900, name: "runningboardd", percent: 0),
                gpu(170, name: "WindowServer", percent: 30),
            ]
        )

        #expect(undescribed.map(\.pid) == [170])
    }

    /// The CPU and memory `ps` reports fill the row the kernel would not describe.
    @Test func theFallbackFillsTheHiddenRowsFigures() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0)],
            current: [process(1, cpu: 0.2)],
            elapsed: 1,
            gpuShares: [gpu(170, name: "WindowServer", percent: 30)],
            fallback: [170: ProcessUsage(cpuPercent: 31.5, memoryBytes: 277_544_960)]
        )

        #expect(readings.map(\.pid) == [170, 1])
        #expect(readings.first?.cpuPercent == 31.5)
        #expect(readings.first?.memoryBytes == 277_544_960)
    }

    /// An idle GPU client the kernel will not describe has nothing to show but
    /// dashes, so it is left out rather than given a row of them.
    @Test func anIdleHiddenGPUClientGetsNoRow() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0)],
            current: [process(1, cpu: 0.2)],
            elapsed: 1,
            gpuShares: [gpu(900, name: "runningboardd", percent: 0)]
        )

        #expect(readings.map(\.pid) == [1])
    }

    /// A process the kernel describes and the driver knows is one row, not two.
    @Test func aProcessInBothSourcesIsListedOnce() {
        let readings = ProcessCounters.readings(
            previous: [process(9, cpu: 0)],
            current: [process(9, name: "listed", cpu: 0.4)],
            elapsed: 1,
            gpuShares: [gpu(9, name: "driver", percent: 20)]
        )

        #expect(readings.map(\.pid) == [9])
        #expect(readings.first?.name == "listed")
        #expect(readings.first?.gpuPercent == 20)
    }

    /// A process loading the GPU is placed beside the CPU hogs: a fifth of the
    /// device outranks a small CPU share, while a process that is busy on the CPU
    /// still outranks a small GPU share. Neither key alone would do both.
    @Test func aRowIsRankedByWhicheverShareIsLarger() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0), process(2, cpu: 0), process(3, cpu: 0)],
            current: [process(1, cpu: 3.0), process(2, cpu: 0.1), process(3, cpu: 40.0)],
            elapsed: 1,
            gpuShares: [gpu(2, percent: 20), gpu(3, percent: 1)]
        )

        #expect(readings.map(\.pid) == [3, 1, 2])
        #expect(readings.map(\.gpuPercent) == [1.0, 0.0, 20.0])
    }

    /// A row with nothing measured in the interval sorts below the ones that
    /// have something, rather than displacing a measured row.
    @Test func aRowMeasuringNothingSortsLast() {
        let readings = ProcessCounters.readings(
            previous: [process(1, cpu: 0), process(2, cpu: 0)],
            current: [process(1, cpu: 0.3), process(2, cpu: 0)],
            elapsed: 1
        )

        #expect(readings.map(\.pid) == [1, 2])
        #expect(readings.map(\.cpuPercent) == [30.0, 0.0])
    }
}
