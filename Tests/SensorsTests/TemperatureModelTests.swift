import Foundation
import Testing
@testable import Sensors

/// Sampling, what is published, and how failures and the timer are handled.
///
/// Serialized because every case here drives `UserDefaults.standard`, which the
/// model reads its stored sampling period from, and because two cases construct
/// a model that starts its timer immediately.
@Suite("Temperature model", .serialized)
struct TemperatureModelTests {
    private let table: TemperatureTable = [
        "Tp00": floatEntry(45.0),
        "Tg0a": floatEntry(41.0),
    ]

    private func model() -> TemperatureModel {
        let transport = FakeSMCTransport(order: Array(table.keys), table: table)
        return testModel(makeSMC: { SMC(transport: transport) })
    }

    @Test func nothingIsPublishedBeforeSampling() {
        let model = model()
        #expect(model.snapshot == nil)
        #expect(model.seriesNames.isEmpty)
        #expect(model.menuBarTitle == "--°")
    }

    @Test func aSampleIsPublished() {
        let model = model()
        model.sample()

        #expect(model.snapshot != nil)
        #expect(model.history.count == 1)
        #expect(model.lastUpdate != nil)
        #expect(model.errorMessage == nil)
        #expect(model.snapshot?.highest == 45.0)
        #expect(model.menuBarTitle == "45°")
    }

    @Test func theSeriesAreTheGroupsPlusTheHotspot() {
        let model = model()
        model.sample()

        #expect(model.seriesNames.contains(SensorCatalog.cpuOverallGroupName))
        #expect(model.seriesNames.last == SensorCatalog.hottestSeriesName)
    }

    @Test func theConnectionIsReusedAcrossTicks() {
        let transport = FakeSMCTransport(order: Array(table.keys), table: table)
        let model = testModel(makeSMC: { SMC(transport: transport) })
        model.sample()
        let callsAfterFirstTick = transport.requests.count

        model.sample()
        #expect(transport.closeCount == 0)
        #expect(transport.requests.count > callsAfterFirstTick)
        #expect(model.history.count == 2)
        #expect(model.history.last?.values[SensorCatalog.hottestSeriesName] == 45.0)
    }

    @Test func historyCanBeCleared() {
        let model = model()
        model.sample()

        model.clearHistory()
        #expect(model.history.isEmpty)
    }

    @Test func aConnectionFailureIsReported() {
        let failing = testModel()
        failing.sample()

        #expect(failing.errorMessage?.contains("no AppleSMC service") == true)
        #expect(failing.snapshot == nil)
    }

    @Test func aMetadataFailureIsReported() {
        let metering = testModel(makeSMC: { SMC(transport: ThrowingTransport()) })
        metering.sample()

        #expect(metering.errorMessage?.contains("kernel said no") == true)
    }

    /// An empty table is a machine with nothing to report, not a failure.
    @Test func anEmptyTablePublishesNothingAndIsNotAnError() {
        let unreadable = testModel(makeSMC: {
            SMC(transport: FakeSMCTransport(
                order: ["Tp00"],
                table: ["Tp00": floatEntry(45.0)],
                unreadableKeys: ["Tp00"]
            ))
        })
        unreadable.sample()

        #expect(unreadable.snapshot == nil)
        #expect(unreadable.errorMessage == nil)
    }

    /// A failed tick drops the connection, so the next one reconnects.
    @Test func aRecoveringReaderClearsTheError() {
        var reconnects = false
        let recovering = testModel(makeSMC: {
            guard reconnects else { throw SMC.SMCError.serviceNotFound }
            return SMC(transport: FakeSMCTransport(
                order: ["Tp00"],
                table: ["Tp00": floatEntry(48.0)]
            ))
        })

        recovering.sample()
        #expect(recovering.errorMessage != nil)

        reconnects = true
        recovering.sample()
        #expect(recovering.errorMessage == nil)
        #expect(recovering.snapshot?.highest == 48.0)
    }

    @Test func aStoredPeriodIsRestored() {
        withStoredRefreshPeriod(5.0) {
            #expect(testModel().refreshPeriod == 5.0)
        }
    }

    @Test func aNonNumericStoredPeriodIsIgnored() {
        withStoredRefreshPeriod("nonsense") {
            #expect(testModel().refreshPeriod == TemperatureModel.defaultRefreshPeriod)
        }
    }

    @Test func aNonPositiveStoredPeriodIsIgnored() {
        withStoredRefreshPeriod(-1.0) {
            #expect(testModel().refreshPeriod == TemperatureModel.defaultRefreshPeriod)
        }
    }

    @Test func aChangedPeriodIsAppliedAndPersisted() {
        withStoredRefreshPeriod(nil) {
            let timed = testModel()
            timed.start()
            timed.start()

            timed.refreshPeriod = 1.0
            #expect(timed.refreshPeriod == 1.0)
            #expect(UserDefaults.standard.object(forKey: storedRefreshPeriodKey) as? Double == 1.0)

            timed.stop()
            timed.stop()
            #expect(timed.refreshPeriod == 1.0)
        }
    }

    /// `startImmediately` defaults to true, so constructing this way exercises
    /// the timer path. The timer only ever runs the fake SMC, and the period
    /// this runs at is the default, so nothing has been sampled by the assert.
    @Test func aModelCanStartAtConstruction() {
        let transport = FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])
        let autostart = testModel(startImmediately: true, makeSMC: { SMC(transport: transport) })
        autostart.stop()

        #expect(autostart.history.isEmpty)
    }

    @Test func historyIsCapped() {
        let transport = FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])
        let trimming = testModel(makeSMC: { SMC(transport: transport) })
        trimming.stop()

        for _ in 0..<(TemperatureModel.maxHistory + 1) {
            trimming.sample()
        }
        #expect(trimming.history.count == TemperatureModel.maxHistory)
    }

    #if DEBUG
    @Test func previewDataShowsRoundedDegrees() {
        let model = testModel()
        model.loadPreviewData()

        #expect(model.menuBarTitle == "76°")
    }
    #endif
}
