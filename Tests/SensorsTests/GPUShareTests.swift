import Foundation
import Testing
@testable import Sensors

/// Every GPU client as a share of the device: the derived set the process table
/// joins onto its rows, and the only source of a name for a process the kernel
/// will not describe.
@Suite("GPU shares")
struct GPUShareTests {
    private func counter(_ pid: Int32, name: String = "p", gpu: Double = 0) -> GPUClientCounters {
        GPUClientCounters(pid: pid, name: name, gpuSeconds: gpu)
    }

    /// A share travels with the name the driver recorded for it, so a process
    /// outside the process table can still be named.
    @Test func aShareCarriesThePidNameAndShare() {
        let shares = GPUShare.readings(
            previous: [counter(170, name: "WindowServer")],
            current: [counter(170, name: "WindowServer", gpu: 0.449)],
            elapsed: 1
        )

        #expect(shares.map(\.pid) == [170])
        #expect(shares.map(\.name) == ["WindowServer"])
        #expect(shares.map(\.gpuPercent) == [44.9])
        #expect(shares.map(\.id) == shares.map(\.pid))
    }

    /// Every client gets an entry, one per process, and the order follows the
    /// counters so the table can rely on it.
    @Test func everyClientGetsAnEntry() {
        let shares = GPUShare.readings(
            previous: [counter(1), counter(2)],
            current: [counter(1, gpu: 0.25), counter(2, gpu: 0.5)],
            elapsed: 1
        )

        #expect(shares.map(\.pid) == [1, 2])
        #expect(shares.map(\.gpuPercent) == [25.0, 50.0])
    }

    /// A process that has just opened a client is still listed, reading 0%: the
    /// table shows that as measured and idle rather than as unknown, which is what
    /// a process with no client at all reads.
    @Test func aClientWithNoBaselineIsListedAtZero() {
        let shares = GPUShare.readings(previous: [], current: [counter(7, gpu: 12)], elapsed: 1)

        #expect(shares.map(\.pid) == [7])
        #expect(shares.map(\.gpuPercent) == [0])
    }

    /// Nothing using the GPU is an empty set, not a failure.
    @Test func noClientsGiveAnEmptySet() {
        #expect(GPUShare.readings(previous: [], current: [], elapsed: 1).isEmpty)
    }
}
