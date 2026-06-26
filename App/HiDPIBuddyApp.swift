import SwiftUI
import AppKit

@main
struct HiDPIBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: DisplayStore

    init() {
        CLIService.runIfNeeded()
        _store = State(initialValue: DisplayStore())
    }

    var body: some Scene {
        WindowGroup(L10n.t("app.name", store.language), id: "main") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 640)
                .background(MainWindowTagger())
        }
        .commands {
            CommandMenu(L10n.t("menu.displays", store.language)) {
                Button(L10n.t("menu.refresh", store.language)) {
                    store.refreshDisplays()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button(L10n.t("hidpi.openSettings", store.language)) {
                    store.openSystemDisplaySettings()
                }
            }
        }

        MenuBarExtra(L10n.t("app.name", store.language), systemImage: "display") {
            MenuBarControlView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
