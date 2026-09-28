import Testing
@testable import Sensors

/// Turning a table of fan speed keys into readings.
@Suite("Fan readings")
struct FanTests {
    @Test func eachFanBecomesOneReadingInNumberOrder() {
        let table: TemperatureTable = [
            "F1Ac": floatEntry(1467.0),
            "F1Mn": floatEntry(1350.0),
            "F1Mx": floatEntry(5777.0),
            "F0Ac": floatEntry(1350.0),
            "F0Mn": floatEntry(1350.0),
            "F0Mx": floatEntry(5349.0),
        ]

        let fans = SensorCatalog.fanReadings(from: table)

        #expect(fans.map(\.id) == [0, 1])
        #expect(fans.map(\.current) == [1350.0, 1467.0])
        #expect(fans.map(\.minimum) == [1350.0, 1350.0])
        #expect(fans.map(\.maximum) == [5349.0, 5777.0])
    }

    /// A fan with only thresholds is not a fan: there is no speed to report.
    @Test func aFanWithNoCurrentSpeedIsLeftOut() {
        let table: TemperatureTable = [
            "Tp00": floatEntry(45.0),
            "F0Mn": floatEntry(1350.0),
        ]

        #expect(SensorCatalog.fanReadings(from: table).isEmpty)
    }

    /// A fan is reported on its current speed alone; the range is optional.
    @Test func aMissingRangeReadsAsZero() {
        let table: TemperatureTable = ["F0Ac": floatEntry(1350.0)]

        let fan = SensorCatalog.fanReadings(from: table).first

        #expect(fan?.current == 1350.0)
        #expect(fan?.minimum == 0)
        #expect(fan?.maximum == 0)
    }

    /// A stopped fan is a reading of zero, not a missing fan.
    @Test func aStoppedFanIsStillAFan() {
        let table: TemperatureTable = [
            "F0Ac": floatEntry(0.0),
            "F0Mn": floatEntry(1350.0),
            "F0Mx": floatEntry(5349.0),
        ]

        #expect(SensorCatalog.fanReadings(from: table).first?.current == 0)
    }

    @Test func onlyTheSpeedKeysAreRead() {
        #expect(SensorCatalog.isFanKey("F0Ac"))
        #expect(SensorCatalog.isFanKey("F0Mn"))
        #expect(SensorCatalog.isFanKey("F0Mx"))
        #expect(!SensorCatalog.isFanKey("F0Tg"))
        #expect(!SensorCatalog.isFanKey("F0ID"))
        #expect(!SensorCatalog.isFanKey("Tp00"))
        #expect(!SensorCatalog.isFanKey("FAc"))
        #expect(!SensorCatalog.isFanKey("F0Acx"))
    }

    @Test func theFanNumberComesFromTheKey() {
        #expect(SensorCatalog.fanIndex(of: "F0Ac") == 0)
        #expect(SensorCatalog.fanIndex(of: "F3Mx") == 3)
        #expect(SensorCatalog.fanIndex(of: "FAAc") == nil)
        #expect(SensorCatalog.fanIndex(of: "F") == nil)
        #expect(SensorCatalog.fanIndex(of: "Tp00") == nil)
    }

    /// A negative speed is a decode artifact, not a fan running backwards.
    @Test func aNegativeSpeedIsNotAFan() {
        let table: TemperatureTable = ["F0Ac": ("i16", Wire.int16(-100), true)]

        #expect(SensorCatalog.fanReadings(from: table).isEmpty)
    }

    /// Neither is a speed above what any fan can turn at.
    @Test func anImpossibleSpeedIsNotAFan() {
        let table: TemperatureTable = ["F0Ac": floatEntry(30_000.0)]

        #expect(SensorCatalog.fanReadings(from: table).isEmpty)
    }

    @Test func anUndecodableSpeedIsNotAFan() {
        let table: TemperatureTable = ["F0Ac": ("hex_", [0, 0, 0, 0], true)]

        #expect(SensorCatalog.fanReadings(from: table).isEmpty)
    }
}
