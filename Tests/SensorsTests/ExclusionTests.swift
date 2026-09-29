import Testing
@testable import Sensors

/// The keys that are read but never ranked as point sensors: per-block GPU
/// fabric extremes, the derived "Virtual Memory Summary" summaries, and the
/// virtual `TV*` families.
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

    @Test(arguments: ["Tp00", "TCMb", "Tg5q"])
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

    @Test(arguments: ["TVD0", "TVDP", "TVMR", "TVS1", "TVV0"])
    func virtualFamiliesAreNotRanked(_ key: String) {
        #expect(!SensorCatalog.isRankablePointSensor(key))
    }

    @Test(arguments: ["Tf06", "TVMX"])
    func aggregatesAndDerivedSummariesAreNotRanked(_ key: String) {
        #expect(!SensorCatalog.isRankablePointSensor(key))
    }

    @Test(arguments: ["Tp00", "TCMb", "Tg5q", "Tm00", "TN00"])
    func realSensorsAreRankable(_ key: String) {
        #expect(SensorCatalog.isRankablePointSensor(key))
    }
}
