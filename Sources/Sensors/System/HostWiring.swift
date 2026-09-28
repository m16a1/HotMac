import Foundation

/// The composition root: the one place that decides to talk to the real kernel.
///
/// It lives with the host boundary because it cannot be exercised in-process —
/// constructing it opens an AppleSMC connection — and because keeping it here
/// means `SMC` stays an implementation detail. The app only ever calls
/// `TemperatureModel.live()`.
extension TemperatureModel {
    public static func live() -> TemperatureModel {
        TemperatureModel(
            brand: SensorCatalog.systemChipBrand(),
            makeSMC: { try SMC() },
            readThrottleState: ThrottleState.system,
            deliver: { DispatchQueue.main.async(execute: $0) }
        )
    }
}
