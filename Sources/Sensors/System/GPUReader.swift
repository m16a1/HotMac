import Foundation
import IOKit

/// Reads the GPU's own utilization figure from the accelerator in the IORegistry.
///
/// This is the host boundary for the device-wide GPU figure. The accelerator
/// publishes a `PerformanceStatistics` dictionary; this walks the matching
/// services and hands the first usable one to the pure `GPUUtilization`. The
/// per-process half is a different property of a different object, read by
/// `GPUClientReader`; the two agree, because the per-process totals partition
/// this figure. The file lives in `System/` and is excluded from the coverage
/// report.
enum GPUReader {
    static func read() -> GPUUtilization? {
        // IOServiceGetMatchingServices consumes the matching dictionary.
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = statistics(for: service),
               let utilization = GPUUtilization.from(statistics: statistics) {
                IOObjectRelease(service)
                return utilization
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private static func statistics(for service: io_service_t) -> [String: Any]? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return property.takeRetainedValue() as? [String: Any]
    }
}
