import SwiftUI

/// Constants shared by more than one view.
///
/// View-specific values stay in that view so they sit next to their use; only
/// what is genuinely shared lives here.
enum UI {
    enum Layout {
        static let windowMinWidth: CGFloat = 700
        static let windowMinHeight: CGFloat = 480
        static let windowDefaultWidth: CGFloat = 760
        static let windowDefaultHeight: CGFloat = 520
        static let panelPadding: CGFloat = 12
    }

    enum Text {
        /// Placeholder shown before the first reading arrives.
        static let noValue = "—"
        static let temperatureFormat = "%.1f °C"
        static let temperatureAxisLabel = "°C"
        static let rpmFormat = "%.0f RPM"
        static let rpmRangeFormat = "%.0f–%.0f RPM"
        static let rpmAxisLabel = "RPM"
        static let percentFormat = "%.1f%%"
        static let megabyteFormat = "%.0f MB"
        static let gigabyteFormat = "%.2f GB"
        /// Memory at or above this many bytes reads in gigabytes.
        static let gigabyteThreshold: UInt64 = 1_073_741_824
        /// A megabyte in bytes, for the memory formatter.
        static let bytesPerMegabyte: Double = 1_048_576
    }

    /// One decimal of °C, or the placeholder when there is no reading yet.
    static func temperature(_ value: Double?) -> String {
        value.map { String(format: Text.temperatureFormat, $0) } ?? Text.noValue
    }

    /// A whole number of revolutions per minute, e.g. `2150 RPM`.
    static func rpm(_ value: Double) -> String {
        String(format: Text.rpmFormat, value)
    }

    /// A fan's speed range, e.g. `1350–5349 RPM`.
    static func rpmRange(_ low: Double, _ high: Double) -> String {
        String(format: Text.rpmRangeFormat, low, high)
    }

    /// A CPU share, e.g. `41.2%`. Kept at one decimal however large the value
    /// grows, so a process using several cores still lines up in the table.
    static func percent(_ value: Double) -> String {
        String(format: Text.percentFormat, value)
    }

    /// Resident memory at a glance: megabytes below a gigabyte, gigabytes above,
    /// so a small process and a huge one are both readable at a glance.
    static func memory(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / Text.bytesPerMegabyte
        guard bytes >= Text.gigabyteThreshold else {
            return String(format: Text.megabyteFormat, megabytes)
        }
        return String(format: Text.gigabyteFormat, megabytes / 1024)
    }
}
