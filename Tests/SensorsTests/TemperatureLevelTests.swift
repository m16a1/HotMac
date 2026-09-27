import Testing
@testable import Sensors

/// Which band a reading falls in, and where the boundaries are.
@Suite("Temperature levels")
struct TemperatureLevelTests {
    @Test func aReadingBelowWarmIsNormal() {
        #expect(TemperatureLevel.level(for: 45.0) == .normal)
        #expect(TemperatureLevel.level(for: TemperatureLevel.warmThreshold - 0.1) == .normal)
    }

    @Test func theWarmBandStartsAtItsThreshold() {
        #expect(TemperatureLevel.level(for: TemperatureLevel.warmThreshold) == .warm)
        #expect(TemperatureLevel.level(for: TemperatureLevel.hotThreshold - 0.1) == .warm)
    }

    @Test func theHotBandRunsUpToCritical() {
        #expect(TemperatureLevel.level(for: TemperatureLevel.hotThreshold) == .hot)
        #expect(TemperatureLevel.level(for: TemperatureLevel.criticalThreshold - 0.1) == .hot)
    }

    /// The top band takes anything above it, including the ~108 °C a sustained
    /// local-LLM run reaches.
    @Test func theCriticalBandHasNoCeiling() {
        #expect(TemperatureLevel.level(for: TemperatureLevel.criticalThreshold) == .critical)
        #expect(TemperatureLevel.level(for: 108.0) == .critical)
    }
}
