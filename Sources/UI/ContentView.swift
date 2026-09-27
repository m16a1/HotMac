import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
            GraphsView()
                .tabItem { Label("Graphs", systemImage: "chart.xyaxis.line") }
        }
        .frame(minWidth: 700, minHeight: 480)
    }
}
