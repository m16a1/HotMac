import SwiftUI
import AppKit
import Sensors

@main
struct HotMacApp: App {
    private enum MainWindow {
        static let id = "main"
        static let title = "HotMac"
    }

    private enum MenuLabels {
        static let showUI = "Show UI"
        static let quit = "Quit"
        static let quitShortcut: KeyEquivalent = "q"
    }

    @StateObject private var model = TemperatureModel.live()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            Button(MenuLabels.showUI) {
                openWindow(id: MainWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button(MenuLabels.quit) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut(MenuLabels.quitShortcut)
        } label: {
            MenuBarBadge(title: model.menuBarTitle, level: model.menuBarLevel)
        }

        Window(MainWindow.title, id: MainWindow.id) {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: UI.Layout.windowDefaultWidth, height: UI.Layout.windowDefaultHeight)
    }
}
