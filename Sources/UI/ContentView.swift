import SwiftUI
import Sensors

struct ContentView: View {
    /// Which screen the window shows. Owned by the app so the menu bar menu can
    /// switch to one before the window is even open.
    @Binding var selection: WindowTab

    var body: some View {
        TabView(selection: $selection) {
            GraphsView()
                .tabItem { Label(WindowTab.temperatures.title, systemImage: WindowTab.temperatures.icon) }
                .tag(WindowTab.temperatures)
            FansView()
                .tabItem { Label(WindowTab.fans.title, systemImage: WindowTab.fans.icon) }
                .tag(WindowTab.fans)
            SettingsView()
                .tabItem { Label(WindowTab.settings.title, systemImage: WindowTab.settings.icon) }
                .tag(WindowTab.settings)
        }
        .frame(minWidth: UI.Layout.windowMinWidth, minHeight: UI.Layout.windowMinHeight)
    }
}
