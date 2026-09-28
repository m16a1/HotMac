import SwiftUI
import Sensors

struct ContentView: View {
    private enum Tab {
        static let graphsTitle = "Temperatures"
        static let graphsIcon = "chart.xyaxis.line"
        static let fansTitle = "Fans"
        static let fansIcon = "fan"
        static let settingsTitle = "Settings"
        static let settingsIcon = "gearshape"
    }

    var body: some View {
        TabView {
            GraphsView()
                .tabItem { Label(Tab.graphsTitle, systemImage: Tab.graphsIcon) }
            FansView()
                .tabItem { Label(Tab.fansTitle, systemImage: Tab.fansIcon) }
            SettingsView()
                .tabItem { Label(Tab.settingsTitle, systemImage: Tab.settingsIcon) }
        }
        .frame(minWidth: UI.Layout.windowMinWidth, minHeight: UI.Layout.windowMinHeight)
    }
}
