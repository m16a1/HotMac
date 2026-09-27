import SwiftUI
import Sensors

struct ContentView: View {
    private enum Tab {
        static let settingsTitle = "Settings"
        static let settingsIcon = "gearshape"
        static let graphsTitle = "Graphs"
        static let graphsIcon = "chart.xyaxis.line"
    }

    var body: some View {
        TabView {
            SettingsView()
                .tabItem { Label(Tab.settingsTitle, systemImage: Tab.settingsIcon) }
            GraphsView()
                .tabItem { Label(Tab.graphsTitle, systemImage: Tab.graphsIcon) }
        }
        .frame(minWidth: UI.Layout.windowMinWidth, minHeight: UI.Layout.windowMinHeight)
    }
}
