import SwiftUI
import AppKit

@main
struct PixelFitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: DisplayStore

    init() {
        CLIService.runIfNeeded()
        Self.activateExistingInstanceIfNeeded()
        _store = State(initialValue: DisplayStore())
    }

    private static func activateExistingInstanceIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = NSRunningApplication.current.processIdentifier
        let firstInstance = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .min { left, right in
                let leftLaunch = left.launchDate ?? .distantFuture
                let rightLaunch = right.launchDate ?? .distantFuture
                return leftLaunch == rightLaunch
                    ? left.processIdentifier < right.processIdentifier
                    : leftLaunch < rightLaunch
            }
        guard let firstInstance, firstInstance.processIdentifier != currentPID else { return }
        firstInstance.activate(options: [])
        Foundation.exit(0)
    }

    var body: some Scene {
        WindowGroup(L10n.t("app.name", store.language), id: "main") {
            ContentView(store: store)
                .frame(minWidth: 840, minHeight: 640)
                .background(MainWindowTagger())
        }
        .defaultSize(width: 980, height: 720)
        .windowToolbarStyle(.unifiedCompact)
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
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
