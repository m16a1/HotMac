import Foundation

/// The host's `sysctl` interface, kept out of the pure catalog.
///
/// This and `IOKitTransport.swift` are the only files in the Sensors layer that
/// consult the host OS: a directory is this project's marker for the boundary
/// that cannot be exercised in-process, and `test.py` excludes it from the
/// coverage report. Everything else in the layer must be fully covered.
extension SensorCatalog {
    /// The sysctl holding the CPU marketing name, for example "Apple M5 Max".
    private static let brandStringKey = "machdep.cpu.brand_string"

    /// The CPU brand string as the host reports it, or the unknown-chip label.
    public static func systemChipBrand() -> String {
        chipBrand(fromSysctl: sysctlString(brandStringKey))
    }

    /// Read a sysctl string.
    ///
    /// The buffer is pre-sized rather than grown with a second probe: a value
    /// longer than `maxLength` is reported as absent, which is acceptable for
    /// the brand string and avoids an error path that no host can produce.
    static func sysctlString(_ name: String, maxLength: Int = 256) -> String? {
        var buffer = [CChar](repeating: 0, count: maxLength)
        var size = maxLength
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
