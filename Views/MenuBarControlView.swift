import SwiftUI

struct MenuBarControlView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                VStack(alignment: .leading, spacing: 8) {
                    Label(display.shortName(language: store.language), systemImage: display.isBuiltin ? "macbook" : "display")
                        .font(.subheadline.weight(.medium))

                    Text(display.currentMode?.detailLabel ?? L10n.t("display.modeUnavailable", store.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(display.recommendedHiDPIModes.prefix(3)) { mode in
                        Button {
                            store.applyDisplayMode(mode, for: display.id)
                        } label: {
                            HStack {
                                Text(mode.label)
                                Spacer()
                                Image(systemName: "checkmark.circle")
                            }
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
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 380)
    }
}
