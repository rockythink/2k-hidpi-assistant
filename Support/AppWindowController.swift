import AppKit
import SwiftUI

enum AppWindowController {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("cc.ss-data.hidpibuddy.main")

    static func showMainWindow(openNewWindow: @escaping () -> Void) {
        let existingWindows = mainWindows
        if let window = existingWindows.first {
            existingWindows.dropFirst().forEach { $0.close() }
            focus(window)
            return
        }

        openNewWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = mainWindows.first {
                focus(window)
            }
        }
    }

    static func tagMainWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.identifier = mainWindowIdentifier
        configureMainWindow(window)
    }

    private static func configureMainWindow(_ window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
    }

    private static var mainWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.identifier == mainWindowIdentifier && !window.isReleasedWhenClosed
        }
    }

    private static func focus(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MainWindowTagger: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            AppWindowController.tagMainWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            AppWindowController.tagMainWindow(nsView.window)
        }
    }
}
