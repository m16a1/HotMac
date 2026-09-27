import Foundation
@testable import Sensors

/// The defaults key `TemperatureModel` restores the sampling period from. It is
/// private in the model, so the suite spells it out: a rename there has to break
/// these tests rather than silently stop covering the restore path.
let storedRefreshPeriodKey = "refreshPeriod"

/// A model with a deterministic brand, a fake SMC, and synchronous delivery.
///
/// Defaults to a client that fails, which is what a model must cope with when
/// there is no AppleSMC service.
func testModel(
    startImmediately: Bool = false,
    makeSMC: @escaping () throws -> SMC = { throw SMC.SMCError.serviceNotFound }
) -> TemperatureModel {
    TemperatureModel(
        startImmediately: startImmediately,
        brand: "Apple M5 Max",
        makeSMC: makeSMC,
        deliver: { $0() }
    )
}

/// Run *body* with the stored sampling period set to *value*, then put the
/// previous value back, so the suite leaves the machine's defaults as it found
/// them.
func withStoredRefreshPeriod(_ value: Any?, _ body: () -> Void) {
    let saved = UserDefaults.standard.object(forKey: storedRefreshPeriodKey)
    defer {
        if let saved {
            UserDefaults.standard.set(saved, forKey: storedRefreshPeriodKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storedRefreshPeriodKey)
        }
    }

    if let value {
        UserDefaults.standard.set(value, forKey: storedRefreshPeriodKey)
    } else {
        UserDefaults.standard.removeObject(forKey: storedRefreshPeriodKey)
    }
    body()
}
