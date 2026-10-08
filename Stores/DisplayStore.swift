import AppKit
import CoreGraphics
import Foundation
import Observation

@Observable
@MainActor
final class DisplayStore {
    var displays: [DisplayDevice] = []
    var selectedDisplayID: UInt32?
    var language: AppLanguage = .system
    var statusMessage = L10n.t("status.ready", .system)
    var lastError: String?
    var pendingModeChange: PendingDisplayModeChange?
    var presets: [DisplayPreset] = []
    var virtualSession: VirtualHiDPISession?
    var pendingVirtualSeconds: Int?
    var isPreparingVirtualHiDPI = false
    var hiDPIChoices: [UInt32: HiDPIResolutionChoices] = [:]
    var physicalConfigurationRequest: PhysicalHiDPIRequest?
    var isChangingPhysicalConfiguration = false
    private var physicalConfigurations: [DisplayOverrideKey: PhysicalHiDPIStatus] = [:]
    private var preparingDisplayID: UInt32?

    private let discovery = DisplayDiscoveryService()
    private let control = MonitorControlService()
    private let persistence = PersistenceService()
    private let virtualHiDPI = VirtualHiDPIService()
    private let physicalHiDPI = PhysicalHiDPIService()
    @ObservationIgnored private var rollbackTimer: Timer?
    @ObservationIgnored private var virtualPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var virtualSessionTimer: Timer?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var screenParametersObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingNativeChanges: [(display: DisplayDevice, previous: DisplayMode, target: DisplayMode)] = []

    init() {
        let snapshot = persistence.load()
        language = snapshot.language
        presets = snapshot.presets
        refreshDisplays()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rollbackDisplayModeChange()
                self?.stopVirtualHiDPI()
            }
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
        }
    }

    var selectedDisplay: DisplayDevice? {
        get { displays.first { $0.id == selectedDisplayID } ?? displays.first }
        set { selectedDisplayID = newValue?.id }
    }

    func refreshDisplays() {
        let protectedID = virtualSession?.displayID ?? (isPreparingVirtualHiDPI ? preparingDisplayID : nil)
        var discovered = discovery.discover(language: language).filter { $0.id != virtualHiDPI.session?.virtualDisplayID }
        var configurations: [DisplayOverrideKey: PhysicalHiDPIStatus] = [:]
        for index in discovered.indices {
            let key = DisplayOverrideKey(display: discovered[index])
            if configurations[key] == nil {
                do { configurations[key] = try physicalHiDPI.status(for: key) }
                catch { configurations[key] = PhysicalHiDPIStatus(phase: .conflict, problem: error.localizedDescription) }
            }
            discovered[index].metadata.panelResolution = configurations[key]?.nativeResolution
        }
        physicalConfigurations = configurations
        var choices: [UInt32: HiDPIResolutionChoices] = [:]
        for index in discovered.indices {
            let id = discovered[index].id
            if id == protectedID, let old = displays.first(where: { $0.id == id }), let cached = hiDPIChoices[id] {
                discovered[index].name = old.name
                discovered[index].metadata.productName = old.metadata.productName
                choices[id] = cached
            } else {
                choices[id] = discovered[index].hiDPIResolutionChoices
            }
        }
        displays = discovered
        hiDPIChoices = choices
        if !displays.contains(where: { $0.id == selectedDisplayID }) { selectedDisplayID = displays.first?.id }
    }

    func applyHiDPIResolution(_ target: DisplayResolutionTarget, for displayID: UInt32) {
        guard canBeginNativeChange, hiDPIChoices[displayID]?.all.contains(target) == true,
              let current = displays.first(where: { $0.id == displayID }) else { return }
        if let mode = current.currentMode, mode.isHiDPI, mode.width == target.width, mode.height == target.height { return }
        if let session = virtualSession, session.displayID == displayID {
            isPreparingVirtualHiDPI = true
            preparingDisplayID = displayID
            stopVirtualHiDPI()
            guard virtualSession == nil, lastError == nil else {
                isPreparingVirtualHiDPI = false
                preparingDisplayID = nil
                return
            }
            // WindowServer invalidates this process's mode cache on the main run loop.
            // Do not route or capture a rollback mode while the old mirror is still cached.
            virtualPreparationTask = Task { [weak self] in
                guard let self else { return }
                let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                var restored = false
                do {
                    repeat {
                        try Task.checkCancellation()
                        self.refreshDisplays()
                        if let mode = self.displays.first(where: { $0.id == displayID })?.currentMode,
                           CGDisplayMirrorsDisplay(displayID) == 0,
                           mode.width == session.originalMode.width, mode.height == session.originalMode.height,
                           mode.pixelWidth == session.originalMode.pixelWidth, mode.pixelHeight == session.originalMode.pixelHeight,
                           Int(mode.refreshRate.rounded()) == Int(session.originalMode.refreshRate.rounded()) {
                            restored = true
                            break
                        }
                        try await Task.sleep(for: .milliseconds(50))
                    } while ContinuousClock.now < deadline
                } catch {}
                self.isPreparingVirtualHiDPI = false
                self.preparingDisplayID = nil
                self.virtualPreparationTask = nil
                self.refreshDisplays()
                if restored {
                    self.applyHiDPIResolution(target, for: displayID)
                } else if !Task.isCancelled {
                    self.lastError = L10n.t("error.restorePending", self.language)
                }
            }
            return
        }
        guard let display = displays.first(where: { $0.id == displayID }) else { return }
        if let mode = display.systemScaledModes.first(where: { $0.isHiDPI && $0.width == target.width && $0.height == target.height }) {
            applyDisplayMode(mode, for: displayID)
        } else {
            lastError = L10n.t("physical.errorUnavailable", language)
        }
    }

    func physicalStatus(for displayID: UInt32) -> PhysicalHiDPIStatus {
        guard let display = displays.first(where: { $0.id == displayID }) else { return PhysicalHiDPIStatus() }
        return physicalConfigurations[DisplayOverrideKey(display: display)] ?? PhysicalHiDPIStatus()
    }

    func physicalProbeTarget(for displayID: UInt32) -> DisplayResolutionTarget? {
        guard virtualSession == nil, let display = displays.first(where: { $0.id == displayID }),
              CGDisplayMirrorsDisplay(displayID) == 0, CGDisplayIsInMirrorSet(displayID) == 0 else { return nil }
        return display.physicalHiDPIProbeTarget
    }

    func physicalTargetAvailable(for displayID: UInt32) -> Bool {
        guard let display = displays.first(where: { $0.id == displayID }),
              let target = physicalStatus(for: displayID).target ?? display.physicalHiDPIProbeTarget else { return false }
        return display.availableModes.contains {
            $0.isHiDPI && $0.width == target.width && $0.height == target.height &&
            $0.pixelWidth == target.width * 2 && $0.pixelHeight == target.height * 2
        }
    }

    func requestPhysicalHiDPI(for displayID: UInt32) {
        guard canBeginNativeChange, virtualSession == nil else { return }
        refreshDisplays()
        let status = physicalStatus(for: displayID)
        guard status.phase == .notInstalled || status.phase == .restored,
              !physicalTargetAvailable(for: displayID), let target = physicalProbeTarget(for: displayID),
              let display = displays.first(where: { $0.id == displayID }) else { return }
        physicalConfigurationRequest = PhysicalHiDPIRequest(
            operation: .install, display: display, target: target,
            matchingDisplayCount: displays.count { DisplayOverrideKey(display: $0) == DisplayOverrideKey(display: display) }
        )
    }

    func requestRestorePhysicalHiDPI(for displayID: UInt32) {
        guard canBeginNativeChange, virtualSession == nil else { return }
        refreshDisplays()
        let status = physicalStatus(for: displayID)
        guard status.canRestore, let target = status.target,
              let display = displays.first(where: { $0.id == displayID }) else { return }
        physicalConfigurationRequest = PhysicalHiDPIRequest(
            operation: .restore, display: display, target: target,
            matchingDisplayCount: displays.count { DisplayOverrideKey(display: $0) == DisplayOverrideKey(display: display) }
        )
    }

    func cancelPhysicalConfiguration() {
        guard !isChangingPhysicalConfiguration else { return }
        physicalConfigurationRequest = nil
    }

    func confirmPhysicalConfiguration() async {
        guard !isChangingPhysicalConfiguration, let request = physicalConfigurationRequest,
              !isPreparingVirtualHiDPI, pendingModeChange == nil, pendingVirtualSeconds == nil,
              virtualSession == nil else { return }
        refreshDisplays()
        guard let display = displays.first(where: { $0.id == request.display.id }),
              DisplayOverrideKey(display: display) == request.key,
              display.serialNumber == request.display.serialNumber,
              CGDisplayMirrorsDisplay(display.id) == 0, CGDisplayIsInMirrorSet(display.id) == 0 else {
            physicalConfigurationRequest = nil
            lastError = L10n.t("physical.errorUnavailable", language)
            return
        }
        isChangingPhysicalConfiguration = true
        lastError = nil
        defer {
            physicalConfigurationRequest = nil
            isChangingPhysicalConfiguration = false
            refreshDisplays()
        }
        do {
            switch request.operation {
            case .install:
                guard physicalProbeTarget(for: display.id) == request.target,
                      !physicalTargetAvailable(for: display.id) else {
                    throw MonitorControlError.unsupported(L10n.t("physical.errorUnavailable", language))
                }
                let plan = try physicalHiDPI.prepare(for: display, target: request.target)
                try await physicalHiDPI.install(plan)
                statusMessage = L10n.t("physical.installed", language)
            case .restore:
                guard physicalStatus(for: display.id).canRestore else {
                    throw MonitorControlError.unsupported(L10n.t("physical.errorUnavailable", language))
                }
                try await physicalHiDPI.restore(for: request.key)
                statusMessage = L10n.t("physical.restored", language)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        language = newLanguage
        refreshDisplays()
        persist()
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canBeginNativeChange, virtualSession == nil else { return }
        let modes = displays.compactMap { display -> DisplayPresetMode? in
            guard let mode = display.currentMode else { return nil }
            return DisplayPresetMode(displayID: display.id, displayName: display.shortName(language: language), mode: mode)
        }
        guard !modes.isEmpty else { return }
        presets.append(DisplayPreset(name: trimmed, displayModes: modes))
        persist()
    }

    func deletePreset(_ preset: DisplayPreset) {
        guard !isChangingPhysicalConfiguration, physicalConfigurationRequest == nil else { return }
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func applyPreset(_ preset: DisplayPreset) {
        guard canBeginNativeChange else { return }
        var targets: [(DisplayDevice, DisplayMode)] = []
        for saved in preset.displayModes {
            guard let display = displays.first(where: { $0.id == saved.displayID }),
                  let mode = display.availableModes.first(where: {
                      $0.width == saved.mode.width && $0.height == saved.mode.height &&
                      $0.pixelWidth == saved.mode.pixelWidth && $0.pixelHeight == saved.mode.pixelHeight &&
                      Int($0.refreshRate.rounded()) == Int(saved.mode.refreshRate.rounded()) &&
                      $0.isHiDPI == saved.mode.isHiDPI
                  }) else {
                lastError = L10n.t("error.modeUnavailable", language)
                return
            }
            targets.append((display, mode))
        }
        beginNativeChange(targets)
    }

    private var canBeginNativeChange: Bool {
        !isPreparingVirtualHiDPI && pendingVirtualSeconds == nil && pendingModeChange == nil &&
        !isChangingPhysicalConfiguration && physicalConfigurationRequest == nil
    }

    func applyDisplayMode(_ mode: DisplayMode, for displayID: UInt32) {
        guard canBeginNativeChange, virtualSession?.displayID != displayID,
              let display = displays.first(where: { $0.id == displayID }),
              display.availableModes.contains(where: { $0.matchesEffectiveMode(mode) }) else { return }
        beginNativeChange([(display, mode)])
    }

    private func beginNativeChange(_ targets: [(DisplayDevice, DisplayMode)]) {
        guard !targets.isEmpty, targets.allSatisfy({ $0.0.id != virtualSession?.displayID }) else { return }
        lastError = nil
        for (display, target) in targets {
            guard let previous = display.currentMode else {
                lastError = L10n.t("error.modeUnavailable", language)
                rollbackDisplayModeChange()
                return
            }
            if previous.matchesEffectiveMode(target) { continue }
            do {
                try control.applyResolution(target, rotation: display.rotation, for: display, persist: false)
                pendingNativeChanges.append((display, previous, target))
            } catch {
                lastError = error.localizedDescription
                rollbackDisplayModeChange()
                return
            }
        }
        guard let first = pendingNativeChanges.first else { return }
        pendingModeChange = PendingDisplayModeChange(
            displayID: first.display.id, previousMode: first.previous, targetMode: first.target, remainingSeconds: 15
        )
        rollbackTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, var pending = self.pendingModeChange else { return }
                pending.remainingSeconds -= 1
                self.pendingModeChange = pending
                if pending.remainingSeconds <= 0 { self.rollbackDisplayModeChange() }
            }
        }
        statusMessage = L10n.t("status.updated", language)
        refreshDisplays()
    }

    func confirmDisplayModeChange() {
        guard pendingModeChange != nil else { return }
        do {
            for change in pendingNativeChanges {
                guard CGDisplayIsOnline(change.display.id) != 0,
                      let actual = CGDisplayCopyDisplayMode(change.display.id),
                      actual.width == change.target.width, actual.height == change.target.height,
                      actual.pixelWidth == change.target.pixelWidth, actual.pixelHeight == change.target.pixelHeight,
                      (actual.refreshRate == 0 || Int(actual.refreshRate.rounded()) == Int(change.target.refreshRate.rounded())) else {
                    throw MonitorControlError.unsupported(L10n.t("physical.modeNotApplied", language))
                }
            }
            for change in pendingNativeChanges {
                try control.applyResolution(change.target, rotation: change.display.rotation, for: change.display, persist: true)
            }
            clearNativeChange()
            lastError = nil
            statusMessage = L10n.t("hidpi.confirmed", language)
        } catch {
            lastError = error.localizedDescription
            rollbackDisplayModeChange()
        }
        refreshDisplays()
    }

    func rollbackDisplayModeChange() {
        guard !pendingNativeChanges.isEmpty else { return }
        for change in pendingNativeChanges.reversed() where CGDisplayIsOnline(change.display.id) != 0 {
            do {
                try control.applyResolution(change.previous, rotation: change.display.rotation, for: change.display, persist: false)
            } catch {
                lastError = error.localizedDescription
            }
        }
        clearNativeChange()
        refreshDisplays()
    }

    private func clearNativeChange() {
        rollbackTimer?.invalidate()
        rollbackTimer = nil
        pendingNativeChanges.removeAll()
        pendingModeChange = nil
    }

    func applyVirtualHiDPI(_ target: DisplayResolutionTarget, for displayID: UInt32) {
        guard canBeginNativeChange else { return }
        if virtualSession != nil {
            stopVirtualHiDPI()
            guard virtualHiDPI.session == nil, lastError == nil else { return }
        }
        guard let display = displays.first(where: { $0.id == displayID }),
              display.virtualHiDPITargets.contains(target) else { return }
        isPreparingVirtualHiDPI = true
        preparingDisplayID = displayID
        lastError = nil
        virtualPreparationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isPreparingVirtualHiDPI = false
                self.preparingDisplayID = nil
                self.virtualPreparationTask = nil
            }
            do {
                try await self.virtualHiDPI.start(display: display, target: target)
                try Task.checkCancellation()
                self.virtualSession = self.virtualHiDPI.session
                self.pendingVirtualSeconds = 15
                self.statusMessage = L10n.t("ui.confirmationNote", self.language)
                self.startVirtualSessionTimer()
                self.refreshDisplays()
            } catch {
                let startError = error
                do {
                    try self.virtualHiDPI.stop()
                    self.lastError = startError is CancellationError ? nil : startError.localizedDescription
                } catch {
                    self.lastError = "\(startError.localizedDescription) · \(error.localizedDescription)"
                }
                self.virtualSession = self.virtualHiDPI.session
                self.pendingVirtualSeconds = nil
                self.refreshDisplays()
            }
        }
    }

    func confirmVirtualHiDPI() {
        guard virtualSession != nil, virtualHiDPI.isRunning, pendingVirtualSeconds != nil else { return }
        pendingVirtualSeconds = nil
        statusMessage = L10n.t("ui.kept", language)
    }

    func stopVirtualHiDPI() {
        guard isPreparingVirtualHiDPI || virtualSession != nil || virtualHiDPI.session != nil else { return }
        virtualPreparationTask?.cancel()
        virtualSessionTimer?.invalidate()
        virtualSessionTimer = nil
        pendingVirtualSeconds = nil
        do {
            try virtualHiDPI.stop()
            lastError = nil
            statusMessage = L10n.t("ui.restored", language)
        } catch {
            lastError = error.localizedDescription
        }
        virtualSession = virtualHiDPI.session
        refreshDisplays()
    }

    private func startVirtualSessionTimer() {
        virtualSessionTimer?.invalidate()
        virtualSessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let session = self.virtualSession else { return }
                guard self.virtualHiDPI.isRunning, CGDisplayIsOnline(session.displayID) != 0 else {
                    self.stopVirtualHiDPI()
                    return
                }
                if let remaining = self.pendingVirtualSeconds {
                    self.pendingVirtualSeconds = remaining - 1
                    if remaining <= 1 { self.stopVirtualHiDPI() }
                }
            }
        }
    }

    func openSystemDisplaySettings() {
        for rawURL in ["x-apple.systempreferences:com.apple.Displays-Settings.extension", "x-apple.systempreferences:com.apple.preference.displays"] {
            if let url = URL(string: rawURL), NSWorkspace.shared.open(url) { return }
        }
    }

    private func persist() {
        persistence.save(PersistentSnapshot(language: language, presets: presets))
    }
}
