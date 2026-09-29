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
        // A virtual family that is not floor-clamped; it would rank as the
        // hottest sensor if the ranking did not skip virtual keys.
        "TVD0": floatEntry(52.0),
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

    @Test func virtualReadingsAreNotRanked() {
        #expect(!snapshot.hottest.contains { $0.key == "TVD0" })
    }

    /// The virtual block keeps its chart group even though it is not ranked, so
    /// the graphs still show it.
    @Test func aVirtualFamilyIsStillAveragedIntoItsGroup() {
        #expect(group("Virtual die")?.average == 52.0)
    }

    /// The whole virtual block is charted, one line per family, and the
    /// floor-clamped summary stays out of the average of the family it belongs
    /// to: `TVMR` is the memory rail, `TVMX` the clamped summary.
    @Test func theVirtualBlockIsChartedWithoutTheSummaries() {
        let table: TemperatureTable = [
            "TVMR": floatEntry(20.0),
            "TVMX": floatEntry(61.0),
            "TVS0": floatEntry(40.0),
            "TVS2": floatEntry(44.0),
            "TVA0": floatEntry(27.0),
            "TN00": floatEntry(34.0),
        ]
        let snapshot = SensorCatalog.snapshot(brand: "Apple M5 Max", table: table)
        let virtualMemory = snapshot.groups.first { $0.name == "Virtual memory" }

        #expect(virtualMemory?.average == 20.0)
        #expect(virtualMemory?.count == 1)
        #expect(snapshot.groups.first { $0.name == "Virtual sensors" }?.average == 42.0)
        #expect(snapshot.groups.first { $0.name == "Virtual ambient" }?.average == 27.0)
        #expect(snapshot.groups.first { $0.name == "SoC package" }?.average == 34.0)
        // Charting them must not put them back into the ranking.
        #expect(!snapshot.hottest.contains { $0.key.hasPrefix("TV") })
    }

    @Test func theHighestMatchesTheTopRealSensor() {
        #expect(snapshot.highest == 47.0)
    }

    /// More plausible keys than the cap, so the list size is pinned rather than
    /// merely bounded: a one-sided assertion cannot see a smaller cap.
    @Test func theHottestListKeepsOnlyTheTopFive() {
        var crowded: TemperatureTable = [:]
        for index in 0..<8 {
            crowded["Tq0\(index)"] = floatEntry(40.0 + Float(index))
        }

        let capped = SensorCatalog.snapshot(brand: "Apple M5 Max", table: crowded)

        #expect(capped.hottest.map(\.value) == [47.0, 46.0, 45.0, 44.0, 43.0])
    }

    /// The band is inclusive at both ends: a sensor sitting exactly on it is a
    /// reading, not noise. Counted from the edge, either bound could be moved.
    @Test func readingsOnTheBandEdgesCount() {
        let edges = SensorCatalog.snapshot(brand: "Apple M5 Max", table: [
            "Tp00": floatEntry(5.0),
            "Tp04": floatEntry(120.0),
        ])

        #expect(edges.hottest.map(\.key) == ["Tp04", "Tp00"])
        #expect(edges.highest == 120.0)
    }

    @Test func readingsJustOutsideTheBandAreDropped() {
        let outside = SensorCatalog.snapshot(brand: "Apple M5 Max", table: [
            "Tp00": floatEntry(4.99),
            "Tp04": floatEntry(120.01),
        ])

        #expect(outside.hottest.isEmpty)
        #expect(outside.highest == nil)
        #expect(outside.groups.isEmpty)
    }
}
