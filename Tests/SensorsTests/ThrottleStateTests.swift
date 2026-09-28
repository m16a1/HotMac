import Testing
@testable import Sensors

/// Which throttling level each OS reading maps to.
@Suite("Throttle states")
struct ThrottleStateTests {
    /// The raw values are `ProcessInfo.ThermalState`'s, in case order.
    @Test func eachReadingMapsToItsLevel() {
        #expect(ThrottleState(thermalState: 0) == .nominal)
        #expect(ThrottleState(thermalState: 1) == .fair)
        #expect(ThrottleState(thermalState: 2) == .serious)
        #expect(ThrottleState(thermalState: 3) == .critical)
    }

    /// A reading outside the four known levels reads as unconstrained rather
    /// than crashing or inventing a level.
    @Test func anUnknownReadingReadsAsNominal() {
        #expect(ThrottleState(thermalState: 99) == .nominal)
        #expect(ThrottleState(thermalState: -1) == .nominal)
    }
}
