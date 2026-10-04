import Foundation

/// The main window's screens, in the order the tab strip shows them.
///
/// The titles are shared by the tab strip and the menu bar menu, so the two can
/// never drift apart.
enum WindowTab: String, CaseIterable, Identifiable {
    case temperatures
    case processes
    case fans
    case settings

    var id: String { rawValue }

    /// The label on the tab and in the menu bar menu.
    var title: String {
        switch self {
        case .temperatures: "Temperatures"
        case .processes: "Processes"
        case .fans: "Fans"
        case .settings: "Settings"
        }
    }

    /// The SF Symbol shown on the tab.
    var icon: String {
        switch self {
        case .temperatures: "chart.xyaxis.line"
        case .processes: "list.bullet.rectangle"
        case .fans: "fan"
        case .settings: "gearshape"
        }
    }
}
