import Testing
@testable import Sensors

/// Which chip the app thinks it is running on, and what it does when it cannot
/// tell.
@Suite("Chip identity")
struct ChipTests {
    @Test func aMissingSysctlReadingFallsBack() {
        #expect(SensorCatalog.chipBrand(fromSysctl: nil) == SensorCatalog.unknownChipName)
    }

    @Test func aReadingIsUsedAsGiven() {
        #expect(SensorCatalog.chipBrand(fromSysctl: "Apple M5 Max") == "Apple M5 Max")
    }

    @Test func theUnknownChipLabel() {
        #expect(SensorCatalog.unknownChipName == "unknown chip")
    }

    /// The host read itself. `machdep.cpu.brand_string` exists on every macOS
    /// release, so on the one platform this suite can link on, it must resolve.
    @Test func theHostBrandStringIsRead() {
        #expect(SensorCatalog.systemChipBrand() != SensorCatalog.unknownChipName)
    }

    @Test(arguments: [("Apple M5 Max", "M5"), ("Apple M1", "M1"), ("Apple A18 Pro", "A18")])
    func familyIsTheGenerationalPrefix(_ brand: String, _ family: String) {
        #expect(SensorCatalog.chipFamily(brand) == family)
    }

    @Test func anUnknownBrandHasNoFamily() {
        #expect(SensorCatalog.chipFamily("Intel(R) Core(TM) i7") == nil)
    }
}
