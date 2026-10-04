import Foundation
@testable import Sensors

/// The defaults keys `TemperatureModel` restores its settings from. They are
/// private in the model, so the suite spells them out: a rename there has to
/// break these tests rather than silently stop covering the restore paths.
let storedRefreshPeriodKey = "refreshPeriod"
let storedHistoryLimitKey = "historyLimit"
let storedSelectedSeriesKey = "selectedSeries"

/// A model with a deterministic brand, a fake SMC, and synchronous delivery.
///
/// Defaults to a client that fails, which is what a model must cope with when
/// there is no AppleSMC service, to a host that is not throttling, to a host
/// with no processes to report, and to a host whose GPU reports nothing at all.
func testModel(
    startImmediately: Bool = false,
    makeSMC: @escaping () throws -> SMC = { throw SMC.SMCError.serviceNotFound },
    readThrottleState: @escaping () -> ThrottleState = { .nominal },
    readProcesses: @escaping () -> [ProcessCounters] = { [] },
    readGPU: @escaping () -> GPUUtilization? = { nil },
    readGPUClientCounters: @escaping () -> [GPUClientCounters] = { [] },
    readFallbackUsage: @escaping ([Int32]) -> [Int32: ProcessUsage] = { _ in [:] }
) -> TemperatureModel {
    TemperatureModel(
        startImmediately: startImmediately,
        brand: "Apple M5 Max",
        makeSMC: makeSMC,
        readThrottleState: readThrottleState,
        readProcesses: readProcesses,
        readGPU: readGPU,
        readGPUClientCounters: readGPUClientCounters,
        readFallbackUsage: readFallbackUsage,
        deliver: { $0() }
    )
}

/// Run *body* with the default at *key* set to *value*, then put the previous
/// value back, so the suite leaves the machine's defaults as it found them.
func withStoredDefault(_ key: String, _ value: Any?, _ body: () -> Void) {
    let saved = UserDefaults.standard.object(forKey: key)
    defer {
        if let saved {
            UserDefaults.standard.set(saved, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    if let value {
        UserDefaults.standard.set(value, forKey: key)
    } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
    body()
}

func withStoredRefreshPeriod(_ value: Any?, _ body: () -> Void) {
    withStoredDefault(storedRefreshPeriodKey, value, body)
}

func withStoredHistoryLimit(_ value: Any?, _ body: () -> Void) {
    withStoredDefault(storedHistoryLimitKey, value, body)
}

func withStoredSelectedSeries(_ value: Any?, _ body: () -> Void) {
    withStoredDefault(storedSelectedSeriesKey, value, body)
}
