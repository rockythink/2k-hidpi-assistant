import SwiftUI

struct DisplaysView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.t("nav.displays", store.language))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
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
                .scrollContentBackground(.hidden)
            }
            .frame(width: 300)
            .background(AppTheme.sidebar)

            Divider()
                .overlay(AppTheme.border)

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
        .background(AppTheme.background)
        .tint(AppTheme.accent)
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
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 4)
    }
}

struct DisplayDetailView: View {
    @Bindable var store: DisplayStore
    var display: DisplayDevice
    @State private var showTechnicalDetails = false
    @State private var cachedDisplayID: UInt32?
    @State private var cachedModeSignature = ""
    @State private var cachedSystemScaledModes: [DisplayMode] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if store.pendingModeChange?.displayID == display.id {
                    pendingStatusPanel
                }
                primaryStatusPanel
                systemSettingsSnapshot
                technicalDetailsDisclosure
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(display.shortName(language: store.language))
        .onAppear {
            refreshCachedModesIfNeeded()
        }
        .onChange(of: display.id) { _, _ in
            refreshCachedModes(force: true)
        }
        .onChange(of: modeSignature) { _, _ in
            refreshCachedModesIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(display.shortName(language: store.language))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(displaySubtitle)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(display.currentMode?.label ?? L10n.t("display.modeUnavailable", store.language))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var primaryStatusPanel: some View {
        HStack(alignment: .center, spacing: 18) {
            Label(
                display.isCurrentHiDPI ? L10n.t("hidpi.currentOn", store.language) : L10n.t("hidpi.currentOff", store.language),
                systemImage: display.isCurrentHiDPI ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(display.isCurrentHiDPI ? .green : .orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(display.currentMode?.resolutionWithAspectLabel ?? L10n.t("display.modeUnavailable", store.language))
                    .font(.title3.weight(.semibold))
                Text(display.currentMode?.detailLabel ?? L10n.t("display.modeUnavailable", store.language))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                if let error = store.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            if let bestMode = display.recommendedHiDPIModes.first {
                Button {
                    store.applyDisplayMode(bestMode, for: display.id)
                } label: {
                    Label(bestMode.resolutionWithAspectLabel, systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(L10n.t("hidpi.none", store.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
        }
        .padding(16)
        .appCard(cornerRadius: 10)
    }

    private var pendingStatusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pending = store.pendingModeChange, pending.displayID == display.id {
                Text("\(L10n.t("hidpi.pending", store.language)) · \(pending.remainingSeconds)s")
                    .font(.headline)
                    .foregroundStyle(.orange)

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
        }
        .padding(16)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private var displaySubtitle: String {
        [
            "\(L10n.t("display.vendor", store.language)) \(display.metadata.vendorHex)",
            "\(L10n.t("display.model", store.language)) \(display.metadata.productHex)",
            "\(L10n.t("display.serial", store.language)) \(display.metadata.serialText)"
        ].joined(separator: " · ")
    }

    private var systemSettingsSnapshot: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.t("systemSettings.resolutions", store.language))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Button {
                    store.openSystemDisplaySettings()
                } label: {
                    Label(L10n.t("hidpi.openSettings", store.language), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }

            systemResolutionList
        }
    }

    private var systemSummaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Text(L10n.t("display.defaultResolution", store.language))
                    .foregroundStyle(.secondary)
                Text(display.nativeMode?.resolutionWithAspectLabel ?? L10n.t("display.modeUnavailable", store.language))
                    .font(.body.weight(.medium))
            }

            GridRow {
                Text(L10n.t("display.currentResolution", store.language))
                    .foregroundStyle(.secondary)
                Text(display.currentMode?.resolutionWithAspectLabel ?? L10n.t("display.modeUnavailable", store.language))
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
        .appCard(cornerRadius: 10)
    }

    private var systemResolutionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cachedSystemScaledModes) { mode in
                systemResolutionRow(mode)
            }

            if !display.unavailableRecommendedHiDPITargets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("hidpi.unavailableTargets", store.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(display.unavailableRecommendedHiDPITargets) { target in
                        unavailableHiDPIRow(target)
                    }
                }
                .padding(.top, 6)
            }

            Text(L10n.t("hidpi.modeAvailabilityNote", store.language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .appCard(cornerRadius: 10)
    }

    private var modeSignature: String {
        display.availableModes
            .map { "\($0.id):\($0.width)x\($0.height):\($0.pixelWidth)x\($0.pixelHeight):\($0.isHiDPI)" }
            .joined(separator: "|")
    }

    private func refreshCachedModesIfNeeded() {
        if cachedDisplayID != display.id || cachedModeSignature != modeSignature || cachedSystemScaledModes.isEmpty {
            refreshCachedModes(force: true)
        }
    }

    private func refreshCachedModes(force: Bool = false) {
        guard force || cachedDisplayID != display.id || cachedModeSignature != modeSignature else { return }
        cachedDisplayID = display.id
        cachedModeSignature = modeSignature
        cachedSystemScaledModes = display.systemScaledModes
    }

    private func systemResolutionRow(_ mode: DisplayMode) -> some View {
        let isNative = display.nativeMode?.width == mode.width && display.nativeMode?.height == mode.height
        let isCurrent = display.currentMode?.matchesEffectiveMode(mode) == true

        return HStack(spacing: 10) {
            Text(mode.resolutionWithAspectLabel)
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
            if !isCurrent {
                Button(L10n.t("hidpi.apply", store.language)) {
                    store.applyDisplayMode(mode, for: display.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(isCurrent ? 0.7 : 0.3), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isCurrent ? AppTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private func unavailableHiDPIRow(_ target: DisplayResolutionTarget) -> some View {
        HStack(spacing: 10) {
            Text(target.resolutionWithAspectLabel)
                .font(.body.weight(.medium))
            Spacer()
            Text("HiDPI")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.t("hidpi.notExposed", store.language))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var displayRoleText: String {
        let active = display.metadata.isActive ? L10n.t("display.active", store.language) : L10n.t("display.inactive", store.language)
        guard display.metadata.isMain else { return active }
        return "\(L10n.t("display.main", store.language)) · \(active)"
    }

    private var technicalDetailsDisclosure: some View {
        DisclosureGroup(isExpanded: $showTechnicalDetails) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    systemSummaryGrid
                        .frame(width: 340, alignment: .topLeading)
                    technicalDetailsGrid
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    systemSummaryGrid
                    technicalDetailsGrid
                }
            }
            .padding(.top, 12)
        } label: {
            Text(L10n.t("display.technicalDetails", store.language))
                .font(.headline)
        }
        .padding(16)
        .appCard(cornerRadius: 10)
    }

    private var technicalDetailsGrid: some View {
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
        .padding(16)
        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

}
