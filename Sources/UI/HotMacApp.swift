import SwiftUI
import AppKit
import Sensors

@main
struct HotMacApp: App {
    private enum MainWindow {
        static let id = "main"
        static let title = "HotMac"
    }

    private enum AboutWindow {
        static let id = "about"
        static let title = "About HotMac"
    }

    private enum MenuLabels {
        static let about = "About HotMac"
        static let quit = "Quit"
        static let quitShortcut: KeyEquivalent = "q"
    }

    @StateObject private var model = TemperatureModel.live()
    @State private var selection: WindowTab = .temperatures
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            ForEach(WindowTab.allCases) { tab in
                Button(tab.title) { show(tab) }
            }
            Divider()
            Button(MenuLabels.about) {
                openWindow(id: AboutWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(MenuLabels.quit) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut(MenuLabels.quitShortcut)
        } label: {
            MenuBarBadge(title: model.menuBarTitle, level: model.menuBarLevel)
        }

        Window(MainWindow.title, id: MainWindow.id) {
            ContentView(selection: $selection)
                .environmentObject(model)
        }
        .defaultSize(width: UI.Layout.windowDefaultWidth, height: UI.Layout.windowDefaultHeight)

        Window(AboutWindow.title, id: AboutWindow.id) {
            AboutView()
        }
        .windowResizability(.contentSize)
    }

    /// Show one screen of the main window, opening the window if it is closed.
    private func show(_ tab: WindowTab) {
        selection = tab
        openWindow(id: MainWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
