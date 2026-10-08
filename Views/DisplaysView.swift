import SwiftUI

struct DisplaysView: View {
    @Bindable var store: DisplayStore
    @State private var physicalConfigurationRequestID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.t("nav.displays", store.language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                if store.displays.count > 1 {
                    DisplayArrangementView(displays: store.displays, selectedDisplayID: $store.selectedDisplayID, language: store.language)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                List(selection: $store.selectedDisplayID) {
                    ForEach(store.displays) { display in
                        DisplayRow(display: display, language: store.language, number: (store.displays.firstIndex { $0.id == display.id } ?? 0) + 1)
                            .tag(display.id)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(width: 220)
            .background(AppTheme.background)
            Divider()
            if let display = store.selectedDisplay {
                DisplayDetailView(store: store, display: display) {
                    physicalConfigurationRequestID = store.physicalConfigurationRequest?.id
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(L10n.t("empty.noDisplay", store.language), systemImage: "display.trianglebadge.exclamationmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            Button { store.refreshDisplays() } label: {
                Label(L10n.t("action.refresh", store.language), systemImage: "arrow.clockwise")
            }
            .help(L10n.t("menu.refresh", store.language))
            .disabled(store.isChangingPhysicalConfiguration)
        }
        .physicalHiDPIConfirmation(store: store, requestID: $physicalConfigurationRequestID)
    }
}

private struct DisplayRow: View {
    let display: DisplayDevice
    let language: AppLanguage
    let number: Int

    var body: some View {
        HStack(spacing: 9) {
            DisplayGlyph(display: display, number: number)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(display.shortName(language: language))
                        .font(.system(size: 13, weight: .medium))
                    if display.metadata.isMain {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .help(L10n.t("display.main", language))
                    }
                }
                if let mode = display.currentMode {
                    Text("\(String(mode.width))×\(String(mode.height)) · \(mode.refreshRateLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DisplayDetailView: View {
    @Bindable var store: DisplayStore
    let display: DisplayDevice
    let onRequestPhysicalConfiguration: () -> Void
    @State private var showAdvanced = false
    private var cachedNativeMode: DisplayMode? { store.hiDPIChoices[display.id]?.nativeMode }
    private var cachedSystemModes: [DisplayMode] { store.hiDPIChoices[display.id]?.systemModes ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    DisplayGlyph(display: display, number: (store.displays.firstIndex { $0.id == display.id } ?? 0) + 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(display.shortName(language: store.language))
                            .font(.system(size: 22, weight: .semibold))
                        if let native = cachedNativeMode {
                            Text("\(String(native.pixelWidth))×\(String(native.pixelHeight)) · \(native.aspectRatioLabel)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if display.metadata.isMain {
                        Label(L10n.t("display.main", store.language), systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.t("hidpi.current", store.language)).font(.caption).foregroundStyle(.secondary)
                            Text(display.currentMode?.resolutionWithAspectLabel ?? "—")
                                .font(.system(size: 23, weight: .semibold)).monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(display.currentMode?.refreshRateLabel ?? "—").font(.callout)
                            Text(display.isCurrentHiDPI ? "HiDPI" : L10n.t("ui.notHiDPI", store.language))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack {
                        Text(L10n.t("ui.hiDPIResolution", store.language)).font(.callout.weight(.medium))
                        Spacer()
                        HiDPIResolutionMenu(store: store, display: display)
                            .frame(width: 250)
                            .controlSize(.large)
                    }
                    Text(L10n.t("ui.confirmationNote", store.language))
                        .font(.caption).foregroundStyle(.secondary)
                    PhysicalHiDPIControls(store: store, display: display, onRequest: onRequestPhysicalConfiguration)
                }
                .padding(16)
                .appCard()
                if store.isPreparingVirtualHiDPI || store.pendingModeChange != nil || store.pendingVirtualSeconds != nil || store.virtualSession?.displayID == display.id {
                    ResolutionChangeControls(store: store)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                }
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(L10n.t("ui.advanced", store.language), isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 14) {
                        ExperimentalHiDPIControls(store: store, display: display)
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            detailRow("display.product", display.metadata.productName ?? display.shortName(language: store.language))
                            detailRow("display.class", display.displayClass.label(language: store.language))
                            detailRow("display.defaultResolution", cachedNativeMode?.resolutionWithAspectLabel ?? "—")
                            detailRow("display.physicalSize", "\(display.metadata.physicalSizeText) · \(display.metadata.diagonalText(language: store.language))")
                            detailRow("display.estimatedPPI", display.metadata.estimatedPPI(nativeMode: cachedNativeMode))
                            detailRow("display.colorProfile", display.metadata.colorSpaceText(language: store.language))
                            detailRow("display.role", L10n.t(display.metadata.isMain ? "display.main" : "display.active", store.language))
                            detailRow("display.modes", "\(display.availableModes.count)")
                            detailRow("display.identifiers", "\(display.metadata.vendorHex) / \(display.metadata.productHex) / \(display.metadata.serialText)")
                            detailRow("display.manufactured", display.metadata.manufactureText)
                        }
                        .font(.caption).textSelection(.enabled)
                        Menu(L10n.t("ui.moreModes", store.language)) {
                            ForEach(cachedSystemModes) { mode in
                                Button(mode.label) { store.applyDisplayMode(mode, for: display.id) }
                                    .disabled(display.currentMode?.matchesEffectiveMode(mode) == true)
                            }
                        }
                        .disabled(store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil || store.isPreparingVirtualHiDPI || store.pendingModeChange != nil || store.pendingVirtualSeconds != nil || store.virtualSession?.displayID == display.id)
                        Button(L10n.t("hidpi.openSettings", store.language)) { store.openSystemDisplaySettings() }
                    }
                    .padding(.top, 12)
                }
                .font(.callout)
            }
            .padding(24)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }


    private func detailRow(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(L10n.t(key, store.language)).foregroundStyle(.secondary)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HiDPIResolutionMenu: View {
    @Bindable var store: DisplayStore
    let display: DisplayDevice

    var body: some View {
        Menu {
            if let choices = store.hiDPIChoices[display.id] {
                ForEach(choices.recommended) { target in option(target) }
                if !choices.recommended.isEmpty { Divider() }
                ForEach(choices.all) { target in
                    if !choices.recommended.contains(target) { option(target) }
                }
            }
        } label: {
            Text(display.isCurrentHiDPI ? (display.currentMode?.resolutionLabel ?? "—") : L10n.t("ui.chooseResolution", store.language))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(L10n.t("ui.hiDPIResolution", store.language))
        .disabled(store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil || store.isPreparingVirtualHiDPI || store.pendingModeChange != nil || store.pendingVirtualSeconds != nil || store.hiDPIChoices[display.id]?.all.isEmpty != false)
    }

    private func option(_ target: DisplayResolutionTarget) -> some View {
        let isCurrent = display.isCurrentHiDPI && display.currentMode?.width == target.width && display.currentMode?.height == target.height
        return Button { store.applyHiDPIResolution(target, for: display.id) } label: {
            if isCurrent {
                Label(target.resolutionLabel, systemImage: "checkmark")
            } else {
                Text(target.resolutionLabel)
            }
        }
        .disabled(isCurrent)
    }
}

struct ResolutionChangeControls: View {
    @Bindable var store: DisplayStore

    var body: some View {
        if store.isPreparingVirtualHiDPI {
            ProgressView(L10n.t("ui.changing", store.language)).controlSize(.small)
        } else if let seconds = store.pendingModeChange?.remainingSeconds ?? store.pendingVirtualSeconds {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(L10n.t("ui.keepQuestion", store.language)) · \(seconds)s")
                    .font(.callout.weight(.medium)).foregroundStyle(.orange)
                if store.pendingVirtualSeconds != nil {
                    Text(L10n.t("ui.scalingRisk", store.language))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(L10n.t("ui.keep", store.language)) {
                        if store.pendingModeChange != nil { store.confirmDisplayModeChange() } else { store.confirmVirtualHiDPI() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(L10n.t("ui.restore", store.language)) {
                        if store.pendingModeChange != nil { store.rollbackDisplayModeChange() } else { store.stopVirtualHiDPI() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if store.virtualSession != nil {
            Button(L10n.t("ui.restore", store.language)) { store.stopVirtualHiDPI() }
                .buttonStyle(.bordered)
        }
    }
}
