import Testing
@testable import Sensors

/// `SensorCatalog.isVirtualGroup`: which chart series are Apple's computed
/// readings rather than thermometers on the hardware, so the Temperatures graph
/// can list the two apart.
@Suite("Series split")
struct SeriesSplitTests {
    @Test func theVirtualDieIsAVirtualGroup() {
        #expect(SensorCatalog.isVirtualGroup("Virtual die"))
    }

    /// Only the prefix groups can be virtual, and the set has to be non-empty:
    /// it is derived from the mapping tables, so a virtual prefix added or
    /// removed there is the only thing that can move it.
    @Test func onlyPrefixGroupsCanBeVirtual() {
        let prefixLabels = Set(SensorCatalog.prefixGroups.map(\.0))
        #expect(SensorCatalog.virtualGroupNames.isSubset(of: prefixLabels))
        #expect(!SensorCatalog.virtualGroupNames.isEmpty)
    }

    @Test(arguments: [
        "CPU overall", "CPU super cores", "CPU die", "CPU die aggregate", "Uncore die",
        "GPU clusters", "Memory", "SoC package", "NAND (SSD)", "SSD controller",
        "Battery", "WiFi / Airport", "Airflow",
    ])
    func hardwareGroupsAreNotVirtual(_ name: String) {
        #expect(!SensorCatalog.isVirtualGroup(name))
    }

    /// An uncurated chip is grouped by prefix, so a label can turn up that no
    /// table names. It is a sensor, not a summary.
    @Test func anUnknownGroupIsNotVirtual() {
        #expect(!SensorCatalog.isVirtualGroup("No such group"))
    }

    /// The families the mapping charts, in the order the sidebar files them:
    /// the die first, then the probes and the rails. Pinned so that adding a
    /// virtual family to the mapping cannot quietly leave it uncharted.
    @Test func everyVirtualFamilyTheMappingChartsIsFileable() {
        #expect(
            SensorCatalog.virtualGroupNames == [
                "Virtual die", "Voltage probes", "Voltage probes (group 1)",
                "Voltage probe mirrors", "Virtual memory", "Virtual sensors",
                "Virtual ambient", "Virtual voltage",
            ]
        )
    }

    /// The split has to line up with what a snapshot actually emits, or the
    /// sidebar would file a real series under Virtual, or the other way round.
    /// One key from a family is enough for its block to appear.
    @Test func theSnapshotGroupsSplitTheWayTheSidebarFilesThem() {
        let table: TemperatureTable = [
            "Tp00": floatEntry(45.0),
            "Tp04": floatEntry(47.0),
            "Tg0a": floatEntry(40.0),
            "TVD0": floatEntry(60.0),
            "TV01": floatEntry(35.0),
            "TV11": floatEntry(35.0),
            "TVN1": floatEntry(35.0),
            "TVMR": floatEntry(30.0),
            "TVS0": floatEntry(40.0),
            "TVA0": floatEntry(27.0),
            "TVV0": floatEntry(50.0),
        ]
        let names = SensorCatalog.snapshot(brand: "Apple M5 Max", table: table).groups.map(\.name)

        #expect(
            names.filter { !SensorCatalog.isVirtualGroup($0) }
                == ["CPU super cores", "CPU overall", "GPU clusters"]
        )
        #expect(
            names.filter(SensorCatalog.isVirtualGroup) == [
                "Virtual die", "Voltage probes", "Voltage probes (group 1)",
                "Voltage probe mirrors", "Virtual memory", "Virtual sensors",
                "Virtual ambient", "Virtual voltage",
            ]
        )
    }
}
