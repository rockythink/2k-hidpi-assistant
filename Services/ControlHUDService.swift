import AppKit
import SwiftUI

enum ControlHUDKind {
    case brightness
    case contrast
    case volume

    var iconName: String {
        switch self {
        case .brightness:
            "sun.max"
        case .contrast:
            "circle.lefthalf.filled"
        case .volume:
            "speaker.wave.2"
        }
    }

    var trailingIconName: String {
        switch self {
        case .brightness:
            "sun.max.fill"
        case .contrast:
            "circle.lefthalf.filled"
        case .volume:
            "speaker.wave.3.fill"
        }
    }
}

@MainActor
final class ControlHUDService {
    private var panel: NSPanel?
    private var model = ControlHUDModel()
    private var hideWorkItem: DispatchWorkItem?

    func show(kind: ControlHUDKind, value: Double, label: String, position: HUDPosition) {
        let clamped = value.clamped(to: 0...1)
        ensurePanel()
        model.kind = kind
        model.label = label
        model.position = position

        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            model.value = clamped
            model.isVisible = true
        }

        positionPanel()
        panel?.orderFrontRegardless()
        scheduleHide()
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView: ControlHUDView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
        self.panel = panel
    }

    private func positionPanel() {
        guard let panel else { return }
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return }

        let size = NSSize(width: 320, height: 72)
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 28,
            y: visibleFrame.maxY - size.height - 42
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hide()
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: workItem)
    }

    private func hide() {
        withAnimation(.easeOut(duration: 0.18)) {
            model.isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard self?.model.isVisible == false else { return }
            self?.panel?.orderOut(nil)
        }
    }
}

@Observable
private final class ControlHUDModel {
    var kind: ControlHUDKind = .brightness
    var value: Double = 1
    var label = "DisplayBuddy"
    var position: HUDPosition = .lowerCenter
    var isVisible = false
}

private struct ControlHUDView: View {
    @Bindable var model: ControlHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)

            HStack(spacing: 8) {
                Image(systemName: model.kind.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 18)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.30))
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: max(4, proxy.size.width * model.value))
                    }
                }
                .frame(height: 5)

                Image(systemName: model.kind.trailingIconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 300, height: 58)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 6)
        .frame(width: 320, height: 72)
        .opacity(model.isVisible ? 1 : 0)
        .scaleEffect(model.isVisible ? 1 : 0.985)
    }
}
