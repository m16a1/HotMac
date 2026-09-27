import SwiftUI
import AppKit

@main
struct HotMacApp: App {
    @StateObject private var model = TemperatureModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            Button("Show UI") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Text(model.menuBarTitle)
                .monospacedDigit()
        }

        Window("HotMac", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 760, height: 520)
    }
}
