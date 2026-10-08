import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @Bindable var store: DisplayStore
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 300
    @State private var physicalConfigurationRequestID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("app.name", store.language)).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { store.refreshDisplays() } label: {
                    Label(L10n.t("action.refresh", store.language), systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(L10n.t("action.refresh", store.language))
                .disabled(store.isChangingPhysicalConfiguration)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.displays.count > 1 {
                        DisplayArrangementView(displays: store.displays, selectedDisplayID: $store.selectedDisplayID, language: store.language)
                    }
                    if store.isPreparingVirtualHiDPI || store.pendingModeChange != nil || store.virtualSession != nil {
                        ResolutionChangeControls(store: store)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard()
                    }
                    if store.displays.isEmpty {
                        Text(L10n.t("empty.noDisplay", store.language)).foregroundStyle(.secondary)
                    }
                    ForEach(store.displays.indices, id: \.self) { index in
                        displayPanel(store.displays[index], number: index + 1)
                    }

                    if let error = store.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, maximumContentHeight))
            Divider()
            HStack(spacing: 10) {
                Button(L10n.t("menu.openMain", store.language)) {
                    AppWindowController.showMainWindow { openWindow(id: "main") }
                }
                Button { store.openSystemDisplaySettings() } label: { Image(systemName: "gearshape") }
                    .help(L10n.t("hidpi.openSettings", store.language))
                    .accessibilityLabel(L10n.t("hidpi.openSettings", store.language))
                Text(store.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(store.statusMessage)
                Spacer(minLength: 0)
                Button(L10n.t("menu.quit", store.language)) { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(AppTheme.background)
        .tint(AppTheme.accent)
        .physicalHiDPIConfirmation(store: store, requestID: $physicalConfigurationRequestID)
    }

    private var maximumContentHeight: CGFloat {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        return min(500, max(120, (screen?.visibleFrame.height ?? 640) - 110))
    }

    private func displayPanel(_ display: DisplayDevice, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                DisplayGlyph(display: display, number: number)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(display.shortName(language: store.language))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            .help(display.shortName(language: store.language))
                        if display.metadata.isMain {
                            Text(L10n.t("display.main", store.language)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    if let mode = display.currentMode {
                        Text("\(String(mode.width))×\(String(mode.height)) · \(mode.refreshRateLabel)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Text("HiDPI").font(.caption).foregroundStyle(.secondary)
                HiDPIResolutionMenu(store: store, display: display)
                    .controlSize(.small)
            }
            PhysicalHiDPIControls(store: store, display: display) {
                physicalConfigurationRequestID = store.physicalConfigurationRequest?.id
            }
            DisclosureGroup(L10n.t("ui.advanced", store.language)) {
                ExperimentalHiDPIControls(store: store, display: display)
                    .padding(.top, 8)
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}
