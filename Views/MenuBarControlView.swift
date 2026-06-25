import SwiftUI

struct MenuBarControlView: View {
    @Bindable var store: DisplayStore
    @Environment(\.openWindow) private var openWindow
    @State private var showMoreModes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("app.name", store.language))
                    .font(.headline)
                Spacer()
                Button {
                    store.refreshDisplays()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            ForEach(store.displays) { display in
                VStack(alignment: .leading, spacing: 7) {
                    Label(display.shortName(language: store.language), systemImage: display.isBuiltin ? "macbook" : "display")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    HStack {
                        Text(display.currentMode?.resolutionLabel ?? L10n.t("display.modeUnavailable", store.language))
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text(display.isCurrentHiDPI ? "HiDPI" : "1x")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(display.isCurrentHiDPI ? .green : .secondary)
                    }

                    Text(display.currentMode?.refreshRateLabel ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let bestMode = display.recommendedHiDPIModes.first {
                        Button {
                            store.applyDisplayMode(bestMode, for: display.id)
                        } label: {
                            HStack {
                                Label(bestMode.resolutionLabel, systemImage: "sparkles")
                                Spacer()
                                Text(L10n.t("hidpi.best", store.language))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    let extraModes = Array(display.recommendedHiDPIModes.dropFirst().prefix(3))
                    if !extraModes.isEmpty {
                        DisclosureGroup(isExpanded: $showMoreModes) {
                            ForEach(extraModes) { mode in
                                Button(mode.resolutionLabel) {
                                    store.applyDisplayMode(mode, for: display.id)
                                }
                            }
                        } label: {
                            Text(L10n.t("menu.moreModes", store.language))
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 8)

                if display.id != store.displays.last?.id {
                    Divider()
                }
            }

            Divider()

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label(L10n.t("menu.openMain", store.language), systemImage: "macwindow")
            }

            Button {
                store.openSystemDisplaySettings()
            } label: {
                Label(L10n.t("hidpi.openSettings", store.language), systemImage: "gearshape")
            }

            if let pending = store.pendingModeChange {
                Divider()
                Text("\(L10n.t("hidpi.pending", store.language)) · \(pending.remainingSeconds)s")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    Button(L10n.t("hidpi.confirm", store.language)) {
                        store.confirmDisplayModeChange()
                    }
                    Button(L10n.t("hidpi.rollback", store.language)) {
                        store.rollbackDisplayModeChange()
                    }
                }
            }

            Text(store.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 320)
    }
}
