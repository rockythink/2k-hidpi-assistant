import SwiftUI

struct DisplaysView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.t("nav.displays", store.language))
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                List(selection: $store.selectedDisplayID) {
                    ForEach(store.displays) { display in
                        DisplayRow(display: display, language: store.language)
                            .tag(display.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 300)

            Divider()

            if let display = store.selectedDisplay {
                DisplayDetailView(store: store, display: display)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(L10n.t("empty.noDisplay", store.language), systemImage: "display.trianglebadge.exclamationmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                systemSettingsSnapshot
                hidpiSettings
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .navigationTitle(display.shortName(language: store.language))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(display.shortName(language: store.language))
                    .font(.largeTitle.weight(.semibold))
                Text(displaySubtitle)
                    .foregroundStyle(.secondary)
                Text(display.currentMode?.label ?? L10n.t("display.modeUnavailable", store.language))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displaySubtitle: String {
        [
            "\(L10n.t("display.vendor", store.language)) \(display.metadata.vendorHex)",
            "\(L10n.t("display.model", store.language)) \(display.metadata.productHex)",
            "\(L10n.t("display.serial", store.language)) \(display.metadata.serialText)"
        ].joined(separator: " · ")
    }

    private var hidpiSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("hidpi.title", store.language))
                .font(.title2.weight(.semibold))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    diagnosticPanel
                        .frame(width: 340, alignment: .topLeading)

                    recommendationPanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    diagnosticPanel
                    recommendationPanel
                }
            }
        }
    }

    private var systemSettingsSnapshot: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.t("systemSettings.title", store.language))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    store.openSystemDisplaySettings()
                } label: {
                    Label(L10n.t("hidpi.openSettings", store.language), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    systemSummaryGrid
                        .frame(width: 340, alignment: .topLeading)
                    systemResolutionList
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    systemSummaryGrid
                    systemResolutionList
                }
            }
        }
    }

    private var systemSummaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Text(L10n.t("display.defaultResolution", store.language))
                    .foregroundStyle(.secondary)
                Text(display.nativeMode?.resolutionLabel ?? L10n.t("display.modeUnavailable", store.language))
                    .font(.body.weight(.medium))
            }

            GridRow {
                Text(L10n.t("display.currentResolution", store.language))
                    .foregroundStyle(.secondary)
                Text(display.currentMode?.resolutionLabel ?? L10n.t("display.modeUnavailable", store.language))
                    .font(.body.weight(.medium))
            }

            GridRow {
                Text(L10n.t("display.refreshRate", store.language))
                    .foregroundStyle(.secondary)
                Text(display.currentMode?.refreshRateLabel ?? "-")
            }

            GridRow {
                Text(L10n.t("display.colorProfile", store.language))
                    .foregroundStyle(.secondary)
                Text(display.metadata.colorSpaceText(language: store.language))
                    .lineLimit(1)
            }

            GridRow {
                Text(L10n.t("display.role", store.language))
                    .foregroundStyle(.secondary)
                Text(displayRoleText)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var systemResolutionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("systemSettings.resolutions", store.language))
                .font(.headline)

            ForEach(display.systemScaledModes) { mode in
                systemResolutionRow(mode)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func systemResolutionRow(_ mode: DisplayMode) -> some View {
        let isNative = display.nativeMode?.width == mode.width && display.nativeMode?.height == mode.height
        let isCurrent = display.currentMode?.width == mode.width && display.currentMode?.height == mode.height

        return HStack(spacing: 10) {
            Text(mode.resolutionLabel)
                .font(.body.weight(.medium))
            if isNative {
                Text(L10n.t("systemSettings.default", store.language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if isCurrent {
                Text(L10n.t("systemSettings.current", store.language))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.16), in: Capsule())
            }
            Spacer()
            Text(mode.isHiDPI ? "HiDPI" : "1x")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(isCurrent ? 0.7 : 0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private var displayRoleText: String {
        let active = display.metadata.isActive ? L10n.t("display.active", store.language) : L10n.t("display.inactive", store.language)
        guard display.metadata.isMain else { return active }
        return "\(L10n.t("display.main", store.language)) · \(active)"
    }

    private var diagnosticPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("hidpi.diagnosis", store.language))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text(L10n.t("display.product", store.language))
                        .foregroundStyle(.secondary)
                    Text(display.metadata.productName ?? display.shortName(language: store.language))
                        .font(.body.weight(.medium))
                }

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

                GridRow {
                    Text(L10n.t("display.physicalSize", store.language))
                        .foregroundStyle(.secondary)
                    Text("\(display.metadata.physicalSizeText) · \(display.metadata.diagonalText(language: store.language))")
                }

                GridRow {
                    Text(L10n.t("display.estimatedPPI", store.language))
                        .foregroundStyle(.secondary)
                    Text(display.metadata.estimatedPPI(nativeMode: display.nativeMode))
                }

                GridRow {
                    Text(L10n.t("display.modes", store.language))
                        .foregroundStyle(.secondary)
                    Text("\(display.availableModes.count) · HiDPI \(display.availableModes.filter(\.isHiDPI).count)")
                }

                GridRow {
                    Text(L10n.t("display.identifiers", store.language))
                        .foregroundStyle(.secondary)
                    Text("\(display.metadata.vendorHex) / \(display.metadata.productHex) / \(display.metadata.serialText)")
                        .textSelection(.enabled)
                }

                GridRow {
                    Text(L10n.t("display.manufactured", store.language))
                        .foregroundStyle(.secondary)
                    Text(display.metadata.manufactureText)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
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
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
