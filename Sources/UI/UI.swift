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
    }

    /// One decimal of °C, or the placeholder when there is no reading yet.
    static func temperature(_ value: Double?) -> String {
        value.map { String(format: Text.temperatureFormat, $0) } ?? Text.noValue
    }
}
