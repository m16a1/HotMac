import Testing
@testable import Sensors

/// The band a reading has to land in to be reported, and the keys that are
/// dropped whatever they read.
@Suite("Plausibility")
struct PlausibilityTests {
    private let table: TemperatureTable = [
        "Tp00": floatEntry(45.0),
        // An unpopulated slot reads exactly zero.
        "Tp04": floatEntry(0.0),
        // A per-block GPU fabric extreme, read but never reported.
        "Tf06": floatEntry(88.8125),
        "Tp08": floatEntry(200.0),
        "TVMX": floatEntry(61.0),
        "Tbad": ("hex_", [0x01, 0x02], true),
    ]

    @Test func onlyTheInBandRealSensorSurvives() {
        let keys = ["Tp00", "Tp04", "Tf06", "Tp08", "Tp0C", "Tbad"]
        #expect(SensorCatalog.plausible(table, keys).map(\.key) == ["Tp00"])
    }

    @Test func aMissingKeyYieldsNothing() {
        #expect(SensorCatalog.plausible(table, ["NOPE"]).isEmpty)
    }

    @Test func aDerivedSummaryIsFiltered() {
        #expect(SensorCatalog.plausible(table, ["TVMX"]).isEmpty)
    }
}
