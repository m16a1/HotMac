import Testing
@testable import Sensors

/// The keys that are read but never reported: per-block GPU fabric extremes, and
/// the derived "Virtual Memory Summary" summaries.
@Suite("Exclusions")
struct ExclusionTests {
    @Test(arguments: ["Tf05", "Tf06", "Tf15", "Tf16", "Tf45", "Tf46"])
    func gpuFabricExtremesAreExcluded(_ key: String) {
        #expect(SensorCatalog.aggregateTempKeys.contains(key))
    }

    @Test(arguments: ["Tp00", "Tp0O", "TCMb", "Tg5q"])
    func realSensorsAreNotAggregates(_ key: String) {
        #expect(!SensorCatalog.aggregateTempKeys.contains(key))
    }

    @Test(arguments: ["TVMX", "TVmS", "TVms"])
    func derivedSummariesAreExcluded(_ key: String) {
        #expect(SensorCatalog.derivedTempKeys.contains(key))
        #expect(SensorCatalog.excludedTempKeys.contains(key))
    }

    @Test(arguments: ["Tp00", "TCMb", "TVD0", "TVMR", "Tg5q"])
    func realSensorsAreNotDerived(_ key: String) {
        #expect(!SensorCatalog.derivedTempKeys.contains(key))
        #expect(!SensorCatalog.excludedTempKeys.contains(key))
    }

    @Test func theExcludedSetCoversBothClasses() {
        #expect(
            SensorCatalog.excludedTempKeys
                == SensorCatalog.aggregateTempKeys.union(SensorCatalog.derivedTempKeys)
        )
    }
}
