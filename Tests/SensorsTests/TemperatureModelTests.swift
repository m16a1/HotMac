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
        "F0Ac": floatEntry(2150.0),
        "F0Mn": floatEntry(1350.0),
        "F0Mx": floatEntry(5349.0),
    ]

    private func model() -> TemperatureModel {
        let transport = FakeSMCTransport(order: Array(table.keys), table: table)
        return testModel(makeSMC: { SMC(transport: transport) })
    }

    @Test func nothingIsPublishedBeforeSampling() {
        let model = model()
        #expect(model.snapshot == nil)
        #expect(model.seriesNames.isEmpty)
        #expect(model.menuBarTitle == "--°C")
        #expect(model.menuBarLevel == nil)
        #expect(model.throttleState == nil)
        #expect(model.fans.isEmpty)
        #expect(model.fanHistory.isEmpty)
        #expect(model.processes.isEmpty)
        #expect(model.gpuUtilization == nil)
    }

    @Test func aSampleIsPublished() {
        let model = model()
        model.sample()

        #expect(model.snapshot != nil)
        #expect(model.history.count == 1)
        #expect(model.lastUpdate != nil)
        #expect(model.errorMessage == nil)
        #expect(model.snapshot?.highest == 45.0)
        #expect(model.menuBarTitle == "45°C")
        #expect(model.menuBarLevel == .normal)
        #expect(model.throttleState == .nominal)
        #expect(model.fans.map(\.current) == [2150.0])
        #expect(model.fans.first?.maximum == 5349.0)
        #expect(model.fanHistory.count == 1)
        #expect(model.fanHistory.first?.speeds[0] == 2150.0)
    }

    /// The processes travel with the reading too: the first sample has no
    /// baseline so its rates are zero, and the next one carries the new
    /// counters. The exact percentage is the pure layer's business.
    @Test func processesArePublishedWithTheReading() {
        var counters = [ProcessCounters(pid: 42, name: "busy", cpuSeconds: 10, memoryBytes: 1_000)]
        let model = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])) },
            readProcesses: { counters }
        )

        model.sample()
        #expect(model.processes.map(\.pid) == [42])
        #expect(model.processes.first?.cpuPercent == 0)
        #expect(model.processes.first?.memoryBytes == 1_000)

        counters = [ProcessCounters(pid: 42, name: "busy", cpuSeconds: 12, memoryBytes: 2_000)]
        model.sample()
        #expect(model.processes.first?.memoryBytes == 2_000)
        #expect(model.processes.first?.cpuPercent ?? -1 >= 0)
    }

    /// The GPU happens to be a whole-device figure, and a machine whose
    /// accelerator reports nothing must not fail the tick.
    @Test func gpuUtilizationIsPublishedWhenTheAcceleratorReportsIt() {
        let busy = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])) },
            readGPU: { GPUUtilization(percent: 36) }
        )
        busy.sample()

        #expect(busy.gpuUtilization?.percent == 36)
    }

    /// A missing GPU figure is not an error, just nothing to show.
    @Test func aMachineWithNoGPUFigureStillPublishes() {
        let quiet = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])) }
        )
        quiet.sample()

        #expect(quiet.snapshot != nil)
        #expect(quiet.gpuUtilization == nil)
    }

    /// A GPU share is derived from two counter samples, so the first tick has
    /// no baseline to form one from and the column reads 0 for one tick. The
    /// interval is real wall time here, so the size of the share is the pure
    /// layer's business.
    @Test func theGPUColumnIsFilledOnceThereIsABaseline() {
        var gpuSeconds = 10.0
        let model = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])) },
            readProcesses: { [ProcessCounters(pid: 42, name: "busy", cpuSeconds: 1, memoryBytes: 1_000)] },
            readGPUClientCounters: { [GPUClientCounters(pid: 42, name: "busy", gpuSeconds: gpuSeconds)] }
        )

        model.sample()
        #expect(model.processes.first?.gpuPercent == 0)

        Thread.sleep(forTimeInterval: 0.01)
        gpuSeconds += 0.5
        model.sample()

        #expect((model.processes.first?.gpuPercent ?? -1) > 0)
    }

    /// A process holding a GPU client and using none of it reads 0%.
    @Test func aGPUClientThatUsesNothingReadsZero() {
        let counters = [GPUClientCounters(pid: 42, name: "quiet", gpuSeconds: 10)]
        let model = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])) },
            readProcesses: { [ProcessCounters(pid: 42, name: "quiet", cpuSeconds: 1, memoryBytes: 1_000)] },
            readGPUClientCounters: { counters }
        )

        model.sample()
        Thread.sleep(forTimeInterval: 0.01)
        model.sample()

        #expect(model.processes.first?.gpuPercent == 0)
    }

    /// A process that has never reached the GPU reads 0%: holding no GPU client
    /// is using none of the device, so the GPU column has no dash.
    @Test func aProcessWithNoGPUClientReadsZero() {
        var cpuSeconds = 1.0
        let model = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])) },
            readProcesses: { [ProcessCounters(pid: 42, name: "quiet", cpuSeconds: cpuSeconds, memoryBytes: 1_000)] }
        )

        model.sample()
        Thread.sleep(forTimeInterval: 0.01)
        cpuSeconds += 0.5
        model.sample()

        #expect(model.processes.first?.cpuPercent ?? -1 > 0)
        #expect(model.processes.first?.gpuPercent == 0)
    }

    /// The CPU and memory fallback runs only while the Processes screen is on
    /// screen, and it is asked only about the processes the kernel would not
    /// describe.
    @Test func theFallbackRunsForTheHiddenRowsWhileVisible() {
        var gpuSeconds = 5.0
        var asked: [[Int32]] = []
        let usage = ProcessUsage(cpuPercent: 31.5, memoryBytes: 277_544_960)
        let model = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])) },
            readProcesses: { [ProcessCounters(pid: 42, name: "quiet", cpuSeconds: 1, memoryBytes: 1_000)] },
            readGPUClientCounters: { [GPUClientCounters(pid: 170, name: "WindowServer", gpuSeconds: gpuSeconds)] },
            readFallbackUsage: { pids in asked.append(pids); return [170: usage] }
        )

        model.sample()
        Thread.sleep(forTimeInterval: 0.01)
        gpuSeconds += 0.5
        model.sample()

        #expect(asked.isEmpty)

        model.processesVisible = true
        Thread.sleep(forTimeInterval: 0.01)
        gpuSeconds += 0.5
        model.sample()

        #expect(asked == [[170]])
        let windowServer = model.processes.first { $0.pid == 170 }
        #expect(windowServer?.cpuPercent == 31.5)
        #expect(windowServer?.memoryBytes == 277_544_960)
    }

    /// With the Processes screen hidden the fallback is not run at all, so the
    /// row the kernel would not describe keeps its dashes.
    @Test func theFallbackIsNotRunWhileHidden() {
        var gpuSeconds = 5.0
        var called = false
        let model = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])) },
            readProcesses: { [ProcessCounters(pid: 42, name: "quiet", cpuSeconds: 1, memoryBytes: 1_000)] },
            readGPUClientCounters: { [GPUClientCounters(pid: 170, name: "WindowServer", gpuSeconds: gpuSeconds)] },
            readFallbackUsage: { _ in called = true; return [170: ProcessUsage(cpuPercent: 31.5, memoryBytes: 1)] }
        )

        model.sample()
        Thread.sleep(forTimeInterval: 0.01)
        gpuSeconds += 0.5
        model.sample()

        #expect(called == false)
        let windowServer = model.processes.first { $0.pid == 170 }
        #expect(windowServer?.cpuPercent == nil)
        #expect(windowServer?.memoryBytes == nil)
    }

    /// The throttling level travels with the reading, so the UI can show it
    /// without consulting the OS itself.
    @Test func aThrottledHostIsPublished() {
        let throttled = testModel(
            makeSMC: { SMC(transport: FakeSMCTransport(order: ["Tp00"], table: table)) },
            readThrottleState: { .serious }
        )
        throttled.sample()

        #expect(throttled.throttleState == .serious)
    }

    /// A machine with no fans is not an error, just an empty list.
    @Test func aMachineWithNoFansPublishesAnEmptyList() {
        let fanless = testModel(makeSMC: {
            SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)]))
        })
        fanless.sample()

        #expect(fanless.snapshot != nil)
        #expect(fanless.fans.isEmpty)
    }

    /// The band follows the reading, which is what lets the menu bar flag heat.
    @Test func aHotReadingIsBanded() {
        let hot = testModel(makeSMC: {
            SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(88.0)]))
        })
        hot.sample()

        #expect(hot.menuBarTitle == "88°C")
        #expect(hot.menuBarLevel == .hot)
    }

    /// The reading can be gathered and inspected without publishing it.
    @Test func aReadingCanBeGatheredWithoutPublishingIt() throws {
        let model = model()
        let reading = try model.readTick()
        let tick = try #require(reading)

        #expect(tick.snapshot.highest == 45.0)
        #expect(tick.point.values[SensorCatalog.cpuOverallGroupName] == 45.0)
        #expect(tick.throttleState == .nominal)
        #expect(tick.fans.map(\.current) == [2150.0])
        #expect(model.snapshot == nil)
        #expect(model.throttleState == nil)
        #expect(model.fans.isEmpty)
        #expect(model.fanHistory.isEmpty)
        #expect(model.history.isEmpty)
    }

    /// A machine with no temperature keys is not an error, just no reading.
    @Test func nothingToReadYieldsNoTick() throws {
        let empty = testModel(makeSMC: {
            SMC(transport: FakeSMCTransport(order: [], table: [:]))
        })
        let reading = try empty.readTick()

        #expect(reading == nil)
    }

    @Test func theSeriesAreTheGroupAverages() {
        let model = model()
        model.sample()

        #expect(model.seriesNames == model.snapshot?.groups.map(\.name))
        #expect(model.seriesNames.contains(SensorCatalog.cpuOverallGroupName))
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
        #expect(model.history.last?.values[SensorCatalog.cpuOverallGroupName] == 45.0)
    }

    @Test func historyCanBeCleared() {
        let model = model()
        model.sample()
        #expect(!model.fanHistory.isEmpty)

        model.clearHistory()
        #expect(model.history.isEmpty)
        #expect(model.fanHistory.isEmpty)
    }

    @Test func aConnectionFailureIsReported() {
        let failing = testModel()
        failing.sample()

        #expect(failing.errorMessage?.contains("no AppleSMC service") == true)
        #expect(failing.errorMessage?.hasPrefix("SMC connection failed") == true)
        #expect(failing.snapshot == nil)
    }

    @Test func aMetadataFailureIsReported() {
        let metering = testModel(makeSMC: { SMC(transport: ThrowingTransport()) })
        metering.sample()

        #expect(metering.errorMessage?.contains("kernel said no") == true)
        #expect(metering.errorMessage?.hasPrefix("SMC key table failed") == true)
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
        withStoredHistoryLimit(nil) {
            let transport = FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])
            let trimming = testModel(makeSMC: { SMC(transport: transport) })
            trimming.stop()

            for _ in 0..<(TemperatureModel.defaultHistoryLimit + 1) {
                trimming.sample()
            }
            #expect(trimming.history.count == TemperatureModel.defaultHistoryLimit)
            #expect(trimming.fanHistory.count == TemperatureModel.defaultHistoryLimit)
        }
    }

    @Test func loweringTheLimitTrimsTheHistoryAtOnce() {
        withStoredHistoryLimit(nil) {
            let transport = FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(45.0)])
            let model = testModel(makeSMC: { SMC(transport: transport) })
            for _ in 0..<5 {
                model.sample()
            }
            #expect(model.history.count == 5)

            model.historyLimit = 2
            #expect(model.history.count == 2)
            #expect(model.fanHistory.count == 2)
        }
    }

    @Test func aStoredHistoryLimitIsRestored() {
        withStoredHistoryLimit(120) {
            #expect(testModel().historyLimit == 120)
        }
    }

    @Test func aNonNumericStoredHistoryLimitIsIgnored() {
        withStoredHistoryLimit("nonsense") {
            #expect(testModel().historyLimit == TemperatureModel.defaultHistoryLimit)
        }
    }

    @Test func aNonPositiveStoredHistoryLimitIsIgnored() {
        withStoredHistoryLimit(0) {
            #expect(testModel().historyLimit == TemperatureModel.defaultHistoryLimit)
        }
    }

    @Test func aChangedHistoryLimitIsPersisted() {
        withStoredHistoryLimit(nil) {
            let model = testModel()
            model.historyLimit = 300

            #expect(model.historyLimit == 300)
            #expect(UserDefaults.standard.object(forKey: storedHistoryLimitKey) as? Int == 300)
        }
    }

    /// A chosen set of series comes back on the next launch instead of the
    /// defaults, and is never replaced by a later reading.
    @Test func aChosenSelectionIsRestoredAndKept() {
        withStoredSelectedSeries(["Memory", "GPU clusters"]) {
            let model = model()
            #expect(model.selectedSeries == ["Memory", "GPU clusters"])

            model.sample()
            #expect(model.selectedSeries == ["Memory", "GPU clusters"])
        }
    }

    /// With nothing stored, the first reading seeds the default groups this
    /// chip reports.
    @Test func theFirstReadingSeedsTheDefaultSeries() {
        withStoredSelectedSeries(nil) {
            let model = model()
            #expect(model.selectedSeries.isEmpty)

            model.sample()
            #expect(model.selectedSeries == ["CPU overall", "GPU clusters"])
        }
    }

    /// A chip whose keys yield no group has nothing to seed, which is not an
    /// error and must not invent a selection.
    @Test func aChipWithNoGroupsSeedsNothing() {
        withStoredSelectedSeries(nil) {
            let model = testModel(makeSMC: {
                SMC(transport: FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(0.0)]))
            })
            model.sample()

            #expect(model.snapshot != nil)
            #expect(model.selectedSeries.isEmpty)
        }
    }

    /// A reading with nothing to group must not count as the user's choice, or
    /// the graph would stay empty once real readings arrive.
    @Test func aReadingWithNothingToGroupIsNotAChoice() {
        withStoredSelectedSeries(nil) {
            let transport = FakeSMCTransport(order: ["Tp00"], table: ["Tp00": floatEntry(0.0)])
            let model = testModel(makeSMC: { SMC(transport: transport) })

            model.sample()
            #expect(model.selectedSeries.isEmpty)

            transport.table = ["Tp00": floatEntry(45.0)]
            model.sample()
            #expect(model.selectedSeries == ["CPU overall"])
        }
    }

    /// A chip that reports groups, but none of the default ones, seeds the first
    /// few it does report. Four of them, so the fallback count is pinned rather
    /// than merely bounded.
    @Test func aChipWithNoDefaultGroupsSeedsItsFirstGroups() {
        withStoredSelectedSeries(nil) {
            let model = testModel(makeSMC: {
                SMC(transport: FakeSMCTransport(
                    order: ["TCMb", "TCDX", "TVD0", "TUD0"],
                    table: [
                        "TCMb": floatEntry(50.0),
                        "TCDX": floatEntry(51.0),
                        "TVD0": floatEntry(52.0),
                        "TUD0": floatEntry(53.0),
                    ]
                ))
            })
            model.sample()

            #expect(model.selectedSeries == ["CPU die", "CPU die aggregate", "Virtual die"])
        }
    }

    /// The shipped defaults are user-visible (the Settings hints name them), so
    /// pin them by value rather than comparing them with themselves.
    @Test func theShippedDefaultsArePinned() {
        #expect(TemperatureModel.defaultRefreshPeriod == 2.0)
        #expect(TemperatureModel.defaultHistoryLimit == 900)
    }

    /// Toggling a checkbox in the graph writes the set through, so the choice
    /// survives a relaunch.
    @Test func aChangedSelectionIsPersisted() {
        withStoredSelectedSeries(nil) {
            let model = model()
            model.selectedSeries.insert("Memory")
            #expect(UserDefaults.standard.stringArray(forKey: storedSelectedSeriesKey) == ["Memory"])

            model.selectedSeries.remove("Memory")
            #expect(
                UserDefaults.standard.stringArray(forKey: storedSelectedSeriesKey)?.isEmpty == true
            )
        }
    }

    #if DEBUG
    @Test func previewDataShowsRoundedDegrees() {
        withStoredSelectedSeries(nil) {
            let model = testModel()
            model.loadPreviewData()

            #expect(model.menuBarTitle == "76°C")
            #expect(model.throttleState == .nominal)
            #expect(model.fans.count == 2)
            #expect(model.fans.last?.maximum == 5777.0)
            #expect(model.fanHistory.count == PreviewData.sampleCount)
            #expect(model.fanHistory.first?.speeds[1] != nil)
            #expect(model.processes.count == PreviewData.processes.count)
            #expect(model.processes.first?.name == "Google Chrome")
            #expect(model.gpuUtilization?.percent == 36)
            #expect(!model.selectedSeries.isEmpty)
        }
    }
    #endif
}
