import Foundation
import IOKit

/// Reads every process's cumulative GPU time from the GPU driver's clients in the
/// IORegistry.
///
/// This is the host boundary for per-process GPU time. Every process that has
/// reached the GPU owns one of these objects, and the driver records both the
/// process that opened it and that client's accumulated GPU time. The objects are
/// not registered services, so `IOServiceMatching` cannot find them and the walk
/// has to compare class names the way `ioreg` does. Reading this needs no
/// privileges and no helper process, which is why the app has neither.
///
/// The file lives in `System/` and is excluded from the coverage report; the
/// strings it parses and the nanoseconds it converts are interpreted by the pure
/// `GPUClientCounters`.
enum GPUClientReader {
    /// The driver object that carries the per-process totals.
    private static let className = "AGXDeviceUserClient"
    /// The property naming the process that opened the client.
    private static let creatorKey = "IOUserClientCreator"
    /// The property holding one entry per API the client submitted through.
    private static let usageKey = "AppUsage"

    static func read() -> [GPUClientCounters] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        let options = IOOptionBits(kIORegistryIterateRecursively)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, options, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var counters: [GPUClientCounters] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard isClient(entry), let counter = counter(for: entry) else { continue }
            counters.append(counter)
        }
        return counters
    }

    private static func isClient(_ entry: io_object_t) -> Bool {
        var name = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        guard IOObjectGetClass(entry, &name) == KERN_SUCCESS else { return false }
        return String(cString: name) == className
    }

    /// A client whose owning process cannot be named, or whose usage cannot be
    /// read, is skipped: it cannot be attributed to anything.
    private static func counter(for entry: io_object_t) -> GPUClientCounters? {
        guard let properties = properties(of: entry),
              let creator = properties[creatorKey] as? String,
              let owner = GPUClientCounters.owner(fromCreator: creator),
              let usage = properties[usageKey] as? [[String: Any]]
        else { return nil }
        return GPUClientCounters(
            pid: owner.pid,
            name: owner.name,
            gpuSeconds: GPUClientCounters.gpuSeconds(fromAppUsage: usage)
        )
    }

    private static func properties(of entry: io_object_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS
        else { return nil }
        return unmanaged?.takeRetainedValue() as? [String: Any]
    }
}
