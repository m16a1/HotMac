import Foundation
import Testing
@testable import Sensors

/// Reading the whole-GPU utilization the accelerator publishes.
@Suite("GPU utilization")
struct GPUUtilizationTests {
    /// The bounds are inclusive, so an idle and a saturated GPU are readings
    /// rather than rejections.
    @Test func aValueInRangeIsAccepted() {
        #expect(GPUUtilization(percent: 0)?.percent == 0)
        #expect(GPUUtilization(percent: 36)?.percent == 36)
        #expect(GPUUtilization(percent: 100)?.percent == 100)
    }

    @Test func aValueOutsideTheRangeIsRejected() {
        #expect(GPUUtilization(percent: -1) == nil)
        #expect(GPUUtilization(percent: 101) == nil)
    }

    /// The device figure is the one this type means; the tiler and renderer
    /// figures alongside it are not.
    @Test func theDeviceUtilizationIsReadFromTheStatistics() {
        let statistics: [String: Any] = [
            "Device Utilization %": 36,
            "Tiler Utilization %": 6,
            "Renderer Utilization %": 34,
        ]

        #expect(GPUUtilization.from(statistics: statistics)?.percent == 36)
    }

    /// Absent, or of a type that is not a number, is no reading rather than a
    /// wrong one.
    @Test func aMissingOrMalformedStatisticYieldsNothing() {
        #expect(GPUUtilization.from(statistics: nil) == nil)
        #expect(GPUUtilization.from(statistics: [:]) == nil)
        #expect(GPUUtilization.from(statistics: ["Device Utilization %": "36"]) == nil)
    }

    /// The key is the accelerator's, so pin it by value rather than against the
    /// symbol it is read from.
    @Test func theStatisticKeyIsPinned() {
        #expect(GPUUtilization.statisticsKey == "Device Utilization %")
    }
}
