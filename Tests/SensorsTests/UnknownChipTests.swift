import Testing
@testable import Sensors

/// What the report does with a chip it does not recognise: no curated CPU list
/// exists, so every `Tp` sensor is grouped together.
@Suite("Unknown chip")
struct UnknownChipTests {
    private let table: TemperatureTable = [
        "Tp00": floatEntry(45.0),
        "Tp04": floatEntry(47.0),
        "Tg0a": floatEntry(40.0),
    ]

    private var snapshot: TemperatureSnapshot {
        SensorCatalog.snapshot(brand: "Intel(R) Core(TM) i7", table: table)
    }

    private func group(_ name: String) -> GroupReading? {
        snapshot.groups.first { $0.name == name }
    }

    @Test func theBrandIsReportedAsGiven() {
        #expect(snapshot.brand == "Intel(R) Core(TM) i7")
    }

    @Test func everyTpSensorBecomesOneGroup() {
        #expect(group(SensorCatalog.cpuFallbackGroupName)?.average == 46.0)
    }

    @Test func thereIsNoCuratedCpuGroup() {
        #expect(!snapshot.groups.map(\.name).contains(SensorCatalog.cpuOverallGroupName))
    }
}
