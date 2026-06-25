import SwiftUI

struct DisplaysView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $store.selectedDisplayID) {
                ForEach(store.displays) { display in
                    DisplayRow(display: display, language: store.language)
                        .tag(display.id)
                }
            }
            .frame(minWidth: 240, idealWidth: 280)
            .listStyle(.sidebar)

            Divider()

            if let display = store.selectedDisplay {
                DisplayDetailView(store: store, display: display)
            } else {
                ContentUnavailableView(L10n.t("empty.noDisplay", store.language), systemImage: "display.trianglebadge.exclamationmark")
            }
        }
        .toolbar {
            Button {
                store.refreshDisplays()
            } label: {
                Label(L10n.t("action.refresh", store.language), systemImage: "arrow.clockwise")
            }
        }
    }
}

private struct DisplayRow: View {
    var display: DisplayDevice
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(display.shortName(language: language), systemImage: display.isBuiltin ? "macbook" : "display")
                .font(.headline)
            Text(display.currentMode?.label ?? "\(Int(display.frame.width)) x \(Int(display.frame.height))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct DisplayDetailView: View {
    @Bindable var store: DisplayStore
    var display: DisplayDevice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                hidpiSettings
                status
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(display.shortName(language: store.language))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(display.shortName(language: store.language))
                    .font(.largeTitle.weight(.semibold))
                Text("\(L10n.t("display.vendor", store.language)) \(display.vendorID) · \(L10n.t("display.model", store.language)) \(display.modelID) · \(L10n.t("display.serial", store.language)) \(display.serialNumber)")
                    .foregroundStyle(.secondary)
                Text(display.currentMode?.label ?? L10n.t("display.modeUnavailable", store.language))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hidpiSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("hidpi.title", store.language))
                .font(.title2.weight(.semibold))

            GeometryReader { proxy in
                if proxy.size.width < 760 {
                    VStack(alignment: .leading, spacing: 18) {
                        diagnosticPanel
                        recommendationPanel
                    }
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        diagnosticPanel
                            .frame(width: min(380, proxy.size.width * 0.38), alignment: .topLeading)

                        recommendationPanel
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(minHeight: 520)
        }
    }

    private var diagnosticPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("hidpi.diagnosis", store.language))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text(L10n.t("display.class", store.language))
                        .foregroundStyle(.secondary)
                    Text(display.displayClass.label(language: store.language))
                        .font(.body.weight(.medium))
                }

                GridRow {
                    Text(L10n.t("display.native", store.language))
                        .foregroundStyle(.secondary)
                    Text(display.nativeMode?.label ?? L10n.t("display.modeUnavailable", store.language))
                }

                GridRow {
                    Text(L10n.t("hidpi.current", store.language))
                        .foregroundStyle(.secondary)
                    Text(display.currentMode?.detailLabel ?? L10n.t("display.modeUnavailable", store.language))
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            Label(
                display.isCurrentHiDPI ? L10n.t("hidpi.currentOn", store.language) : L10n.t("hidpi.currentOff", store.language),
                systemImage: display.isCurrentHiDPI ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(display.isCurrentHiDPI ? .green : .orange)

            Text(L10n.t("hidpi.note", store.language))
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                store.openSystemDisplaySettings()
            } label: {
                Label(L10n.t("hidpi.openSettings", store.language), systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var recommendationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            status
            let hidpiModes = display.availableModes.filter(\.isHiDPI)
            if hidpiModes.isEmpty {
                ContentUnavailableView(L10n.t("hidpi.none", store.language), systemImage: "rectangle.badge.xmark")
                    .frame(maxWidth: 520, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("hidpi.recommended", store.language))
                        .font(.headline)

                    if !display.recommendedHiDPIModes.isEmpty {
                        modeList(display.recommendedHiDPIModes, markFirst: true)
                    } else {
                        Text(L10n.t("hidpi.noRecommendations", store.language))
                            .foregroundStyle(.secondary)
                    }

                    Text(L10n.t("hidpi.available", store.language))
                        .font(.headline)
                        .padding(.top, 8)
                    modeList(hidpiModes, markFirst: false)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func modeList(_ modes: [DisplayMode], markFirst: Bool) -> some View {
        ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(mode.label)
                            .font(.body.weight(.medium))
                        if markFirst && index == 0 {
                            Text(L10n.t("hidpi.best", store.language))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(mode.detailLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.t("hidpi.apply", store.language)) {
                    store.applyDisplayMode(mode, for: display.id)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pending = store.pendingModeChange, pending.displayID == display.id {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(L10n.t("hidpi.pending", store.language)) · \(pending.remainingSeconds)s")
                        .font(.headline)
                    HStack {
                        Button(L10n.t("hidpi.confirm", store.language)) {
                            store.confirmDisplayModeChange()
                        }
                        .buttonStyle(.borderedProminent)
                        Button(L10n.t("hidpi.rollback", store.language), role: .cancel) {
                            store.rollbackDisplayModeChange()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            Text(store.statusMessage)
                .foregroundStyle(.secondary)
            if let error = store.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }
}
