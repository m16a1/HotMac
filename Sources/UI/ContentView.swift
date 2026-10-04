import SwiftUI
import Sensors

struct ContentView: View {
    /// Which screen the window shows. Owned by the app so the menu bar menu can
    /// switch to one before the window is even open.
    @Binding var selection: WindowTab
    @EnvironmentObject var model: TemperatureModel

    var body: some View {
        TabView(selection: $selection) {
            GraphsView()
                .tabItem { Label(WindowTab.temperatures.title, systemImage: WindowTab.temperatures.icon) }
                .tag(WindowTab.temperatures)
            ProcessesView()
                .tabItem { Label(WindowTab.processes.title, systemImage: WindowTab.processes.icon) }
                .tag(WindowTab.processes)
            FansView()
                .tabItem { Label(WindowTab.fans.title, systemImage: WindowTab.fans.icon) }
                .tag(WindowTab.fans)
            SettingsView()
                .tabItem { Label(WindowTab.settings.title, systemImage: WindowTab.settings.icon) }
                .tag(WindowTab.settings)
        }
        .frame(minWidth: UI.Layout.windowMinWidth, minHeight: UI.Layout.windowMinHeight)
        // The Processes screen is the only one that needs the CPU fallback, and it
        // costs a subprocess, so the model runs it only while that screen is up.
        // The tab selection is the app's own state, which makes this exact where
        // the tab strip's appear/disappear is not; `onDisappear` covers the window
        // being closed while the Processes screen was selected.
        .onAppear { model.processesVisible = selection == .processes }
        .onDisappear { model.processesVisible = false }
        .onChange(of: selection) { _, tab in model.processesVisible = tab == .processes }
    }
}
