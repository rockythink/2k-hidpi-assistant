import AppKit
import SwiftUI

struct PhysicalHiDPIControls: View {
    @Bindable var store: DisplayStore
    let display: DisplayDevice
    let onRequest: () -> Void

    private var status: PhysicalHiDPIStatus { store.physicalStatus(for: display.id) }
    private var target: DisplayResolutionTarget? { store.physicalProbeTarget(for: display.id) ?? status.target }
    private var targetAvailable: Bool { store.physicalTargetAvailable(for: display.id) }
    private var actionsDisabled: Bool {
        store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil ||
        store.isPreparingVirtualHiDPI || store.pendingModeChange != nil ||
        store.pendingVirtualSeconds != nil || store.virtualSession != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status.phase == .conflict {
                statusText("physical.conflict", symbol: "exclamationmark.triangle")
            } else if status.phase == .restored {
                statusText("physical.restored", symbol: "arrow.uturn.backward")
            } else if status.phase == .installed && !targetAvailable {
                statusText("physical.installed", symbol: "clock")
            }
            if targetAvailable, let target {
                Label(String(format: L10n.t("physical.available", store.language), target.resolutionLabel), systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = status.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.isChangingPhysicalConfiguration && store.physicalConfigurationRequest?.display.id == display.id {
                ProgressView(L10n.t("physical.changing", store.language)).controlSize(.small)
            }
            if !targetAvailable, store.physicalProbeTarget(for: display.id) != nil,
               status.phase == .notInstalled || status.phase == .restored {
                Button(L10n.t("physical.enableMore", store.language)) {
                    store.requestPhysicalHiDPI(for: display.id)
                    onRequest()
                }
                .buttonStyle(.bordered)
                .disabled(actionsDisabled)
            }
            if status.canRestore || status.phase == .conflict {
                Button(L10n.t("physical.restore", store.language)) {
                    store.requestRestorePhysicalHiDPI(for: display.id)
                    onRequest()
                }
                .buttonStyle(.bordered)
                .disabled(actionsDisabled || !status.canRestore || status.phase == .conflict)
            }
        }
        .controlSize(.small)
    }

    private func statusText(_ key: String, symbol: String) -> some View {
        Label(L10n.t(key, store.language), systemImage: symbol)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ExperimentalHiDPIControls: View {
    @Bindable var store: DisplayStore
    let display: DisplayDevice

    var body: some View {
        DisclosureGroup(L10n.t("virtual.compatibility", store.language)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("virtual.warning", store.language))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if display.virtualHiDPITargets.isEmpty {
                    Text(L10n.t("virtual.none", store.language))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu(L10n.t("virtual.chooseTarget", store.language)) {
                        ForEach(display.virtualHiDPITargets) { target in
                            Button(target.resolutionLabel) { store.applyVirtualHiDPI(target, for: display.id) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil || store.isPreparingVirtualHiDPI || store.pendingModeChange != nil || store.pendingVirtualSeconds != nil)
                }
            }
            .padding(.top, 8)
        }
        .font(.caption)
    }
}

extension View {
    func physicalHiDPIConfirmation(store: DisplayStore, requestID: Binding<UUID?>) -> some View {
        modifier(PhysicalHiDPIConfirmationPresenter(store: store, requestID: requestID))
    }
}

private struct PhysicalHiDPIConfirmationPresenter: ViewModifier {
    @Bindable var store: DisplayStore
    @Binding var requestID: UUID?

    private var requestBinding: Binding<PhysicalHiDPIRequest?> {
        Binding {
            guard let request = store.physicalConfigurationRequest, request.id == requestID else { return nil }
            return request
        } set: { request in
            if request == nil {
                if store.physicalConfigurationRequest?.id == requestID {
                    store.cancelPhysicalConfiguration()
                }
                requestID = nil
            }
        }
    }

    func body(content: Content) -> some View {
        content.sheet(item: requestBinding, onDismiss: {
            requestID = nil
        }) { request in
            PhysicalHiDPIConfirmationView(store: store, request: request)
        }
    }
}

private struct PhysicalHiDPIConfirmationView: View {
    @Bindable var store: DisplayStore
    let request: PhysicalHiDPIRequest

    private var isInstall: Bool { request.operation == .install }
    private var maximumHeight: CGFloat {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        return min(480, max(220, (screen?.visibleFrame.height ?? 640) - 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t(isInstall ? "physical.title.install" : "physical.title.restore", store.language))
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(request.display.shortName(language: store.language))
                        .font(.callout.weight(.semibold))
                        .textSelection(.enabled)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        detailRow("physical.target", String(format: L10n.t("physical.resolution", store.language), request.target.resolutionLabel))
                        detailRow("physical.vendorID", "0x" + String(request.key.vendorID, radix: 16, uppercase: true))
                        detailRow("physical.productID", "0x" + String(request.key.productID, radix: 16, uppercase: true))
                    }
                    .font(.caption).textSelection(.enabled)
                    Text(String(format: L10n.t("physical.matchingModels", store.language), request.matchingDisplayCount))
                    Text(L10n.t("physical.authorization", store.language))
                    Text(L10n.t(isInstall ? "physical.installWarning" : "physical.restoreWarning", store.language))
                    Text(L10n.t("physical.notFirmware", store.language))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            if store.isChangingPhysicalConfiguration {
                ProgressView(L10n.t("physical.changing", store.language)).controlSize(.small)
            }
            HStack {
                Button(L10n.t("physical.cancel", store.language)) { store.cancelPhysicalConfiguration() }
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                Button(L10n.t(isInstall ? "physical.confirm.install" : "physical.confirm.restore", store.language)) {
                    Task { await store.confirmPhysicalConfiguration() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .disabled(store.isChangingPhysicalConfiguration)
        }
        .padding(16)
        .frame(width: 328, height: maximumHeight)
        .interactiveDismissDisabled(store.isChangingPhysicalConfiguration)
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(L10n.t(key, store.language)).foregroundStyle(.secondary)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
