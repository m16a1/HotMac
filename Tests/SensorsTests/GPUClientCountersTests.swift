import Foundation
import Testing
@testable import Sensors

/// Reading the driver's per-process GPU totals: the strings it names them with,
/// the nanoseconds it counts in, and the shares two samples make.
@Suite("GPU client counters")
struct GPUClientCountersTests {
    private func counter(_ pid: Int32, name: String = "p", gpu: Double) -> GPUClientCounters {
        GPUClientCounters(pid: pid, name: name, gpuSeconds: gpu)
    }

    /// The driver records the owning process as `pid <n>, <name>`, with the name
    /// truncated to what fits.
    @Test func theOwnerIsParsedOutOfTheDriversString() {
        let owner = GPUClientCounters.owner(fromCreator: "pid 170, WindowServer")

        #expect(owner?.pid == 170)
        #expect(owner?.name == "WindowServer")
    }

    /// The kernel truncates long names, so a short one is all there is.
    @Test func aTruncatedNameIsKeptAsItIs() {
        let owner = GPUClientCounters.owner(fromCreator: "pid 418, iconservicesagen")

        #expect(owner?.pid == 418)
        #expect(owner?.name == "iconservicesagen")
    }

    /// A string that names no process would be attributed to a guess, so it is
    /// dropped instead. Each case is a shape the driver does not produce.
    @Test(arguments: [
        "WindowServer",              // no pid at all
        "pid 170 WindowServer",      // no comma
        "pid x, WindowServer",       // the pid is not a number
        "pid 170, ",                 // no name
        "pid 170,    ",              // a name that is only spaces
        "xpid 170, WindowServer",    // a different prefix
        "pid 170,",                  // the comma and nothing after it
    ])
    func anUnattributableClientIsDropped(creator: String) {
        #expect(GPUClientCounters.owner(fromCreator: creator) == nil)
    }

    /// One client holds one entry per API it submitted through, and its total is
    /// their sum. Swapping the key or adding the entries wrongly would show up
    /// here.
    @Test func theClientTotalIsTheSumOfItsUsageEntries() {
        let usage: [[String: Any]] = [
            ["API": "Metal", "accumulatedGPUTime": UInt64(1_500_000_000)],
            ["API": "Metal", "accumulatedGPUTime": UInt64(500_000_000)],
        ]

        #expect(GPUClientCounters.gpuSeconds(fromAppUsage: usage) == 2.0)
    }

    /// An entry whose figure is missing or not a number contributes nothing,
    /// rather than making the whole client unreadable.
    @Test func anUnreadableEntryContributesNothing() {
        let usage: [[String: Any]] = [
            ["API": "Metal"],
            ["API": "Metal", "accumulatedGPUTime": "nonsense"],
            ["API": "Metal", "accumulatedGPUTime": UInt64(2_000_000_000)],
        ]

        #expect(GPUClientCounters.gpuSeconds(fromAppUsage: usage) == 2.0)
    }

    /// A client that has submitted nothing is a measured zero, not a failure.
    @Test func aClientWithNoUsageIsZero() {
        #expect(GPUClientCounters.gpuSeconds(fromAppUsage: []) == 0)
    }

    /// A process can open several clients, and its GPU time is their sum: reading
    /// only the first would under-report exactly the busiest processes.
    @Test func aProcesssClientsAreSummed() {
        let merged = GPUClientCounters.merged([
            counter(170, name: "WindowServer", gpu: 2),
            counter(42, gpu: 1),
            counter(170, name: "WindowServer", gpu: 3),
        ])

        #expect(merged.map(\.pid) == [170, 42])
        #expect(merged.map(\.gpuSeconds) == [5, 1])
        #expect(merged.map(\.name) == ["WindowServer", "p"])
    }

    /// A share is the GPU time used over the interval, as a percentage of the
    /// whole device: the totals partition the GPU, so half a second of it in one
    /// second of wall time is half the device.
    @Test func aShareIsTheTimeUsedOverTheInterval() {
        let share = counter(1, gpu: 10.5).percentage(previous: [counter(1, gpu: 10)], elapsed: 1)

        #expect(share == 50.0)
    }

    /// The device can be fully busy from several processes at once, and each
    /// reads its own part of it.
    @Test func sharesAreIndependentOfEachOther() {
        let previous = [counter(1, gpu: 0), counter(2, gpu: 0)]

        #expect(counter(1, gpu: 0.3).percentage(previous: previous, elapsed: 1) == 30.0)
        #expect(counter(2, gpu: 0.7).percentage(previous: previous, elapsed: 1) == 70.0)
    }

    /// The baseline is the same process's earlier total, matched by pid: reading
    /// another process's would invent usage out of nothing.
    @Test func theBaselineIsTheSameProcess() {
        let share = counter(2, gpu: 0).percentage(previous: [counter(1, gpu: 500)], elapsed: 1)

        #expect(share == 0)
    }

    /// A process seen for the first time has no baseline, so it reads as 0%
    /// rather than as its whole lifetime of GPU time.
    @Test func aProcessWithNoEarlierCounterReadsAsZero() {
        let share = counter(1, gpu: 500).percentage(previous: [], elapsed: 1)

        #expect(share == 0)
    }

    /// With no time between the snapshots there is no rate to form.
    @Test func aNonPositiveIntervalYieldsNoRate() {
        let share = counter(1, gpu: 1).percentage(previous: [counter(1, gpu: 0)], elapsed: 0)

        #expect(share == 0)
    }

    /// A pid reused by a process that has used less GPU makes the total appear to
    /// go backwards; that is a stale baseline, not negative usage.
    @Test func aCounterThatGoesBackwardsClampsToZero() {
        let share = counter(1, gpu: 4).percentage(previous: [counter(1, gpu: 10)], elapsed: 1)

        #expect(share == 0)
    }
}
