import Testing
@testable import Sensors

/// `SensorCatalog.snapshot`: how sensors are gathered into named groups and
/// ranked for the hottest-sensors list.
@Suite("Snapshot")
struct SnapshotTests {
    private let table: TemperatureTable = [
        "Tp00": floatEntry(45.0),
        "Tp04": floatEntry(47.0),
        "Tp0O": floatEntry(43.0),
        "Tg0a": floatEntry(40.0),
        // Ties with Tg0a, so the ranking's key tie-break is exercised.
        "Tg0b": floatEntry(40.0),
        "Tf06": floatEntry(88.8125),
        "TN00": floatEntry(34.0),
        "TVMX": floatEntry(61.0),
        "TVmS": floatEntry(61.0),
        "TVms": floatEntry(61.0),
        // Out of the plausibility band, and an undecodable format.
        "TCDX": floatEntry(200.0),
        "Tzzz": ("hex_", [0x01, 0x02], true),
    ]

    private var snapshot: TemperatureSnapshot {
        SensorCatalog.snapshot(brand: "Apple M5 Max", table: table)
    }

    private func group(_ name: String) -> GroupReading? {
        snapshot.groups.first { $0.name == name }
    }

    @Test func cpuGroupIsAveraged() {
        #expect(group("CPU super cores")?.average == 46.0)
        #expect(group("CPU super cores")?.count == 2)
    }

    @Test func gpuGroupIsAveraged() {
        #expect(group("GPU clusters")?.average == 40.0)
    }

    @Test func packageGroupIsAveraged() {
        #expect(group("SoC package")?.average == 34.0)
    }

    @Test func aGroupIsIdentifiedByName() {
        #expect(group("CPU super cores")?.id == "CPU super cores")
    }

    @Test func derivedSummariesAreNotRendered() {
        #expect(group("Virtual memory") == nil)
    }

    @Test func theHottestSensorIsTheRealHotspot() {
        #expect(snapshot.hottest.first?.key == "Tp04")
    }

    @Test func unreadableKeysAreNotRanked() {
        #expect(!snapshot.hottest.contains { $0.key == "Tf06" })
        #expect(!snapshot.hottest.contains { $0.key == "TVMX" })
    }

    @Test func theHighestMatchesTheTopRealSensor() {
        #expect(snapshot.highest == 47.0)
    }

    @Test func theHottestListIsCapped() {
        #expect(snapshot.hottest.count <= SensorCatalog.hotspots)
    }
}
