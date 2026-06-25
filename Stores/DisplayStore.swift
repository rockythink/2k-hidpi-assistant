import AppKit
import Foundation
import Observation

@Observable
final class DisplayStore {
    var displays: [DisplayDevice] = []
    var selectedDisplayID: UInt32?
    var language: AppLanguage = .system
    var statusMessage = L10n.t("status.ready", .system)
    var lastError: String?
    var pendingModeChange: PendingDisplayModeChange?

    private let discovery = DisplayDiscoveryService()
    private let control = MonitorControlService()
    private let persistence = PersistenceService()
    @ObservationIgnored private var rollbackTimer: Timer?

    init() {
        load()
        refreshDisplays()
    }

    var selectedDisplay: DisplayDevice? {
        get {
            displays.first { $0.id == selectedDisplayID } ?? displays.first
        }
        set {
            selectedDisplayID = newValue?.id
        }
    }

    func refreshDisplays() {
        displays = discovery.discover(language: language)

        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first?.id
        }

        persist()
    }

    func applyDisplayMode(_ mode: DisplayMode, for displayID: UInt32) {
        guard let display = displays.first(where: { $0.id == displayID }),
              let previousMode = display.currentMode else { return }

        do {
            try control.applyResolution(mode, rotation: display.rotation, for: display, persist: false)
            lastError = nil
            statusMessage = "\(L10n.t("status.updated", language))：\(display.shortName(language: language))"
        } catch {
            lastError = error.localizedDescription
            statusMessage = L10n.t("status.localOnly", language)
            return
        }

        pendingModeChange = PendingDisplayModeChange(
            displayID: displayID,
            previousMode: previousMode,
            targetMode: mode,
            remainingSeconds: 15
        )
        startRollbackTimer()
        refreshDisplays()
    }

    func confirmDisplayModeChange() {
        guard let pending = pendingModeChange,
              let display = displays.first(where: { $0.id == pending.displayID }) else {
            self.pendingModeChange = nil
            rollbackTimer?.invalidate()
            rollbackTimer = nil
            return
        }

        do {
            try control.applyResolution(pending.targetMode, rotation: display.rotation, for: display, persist: true)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        self.pendingModeChange = nil
        rollbackTimer?.invalidate()
        rollbackTimer = nil
        statusMessage = L10n.t("hidpi.confirmed", language)
    }

    func rollbackDisplayModeChange() {
        guard let pending = pendingModeChange else { return }
        rollbackTimer?.invalidate()
        rollbackTimer = nil
        do {
            if let display = displays.first(where: { $0.id == pending.displayID }) {
                try control.applyResolution(pending.previousMode, rotation: display.rotation, for: display, persist: true)
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
        self.pendingModeChange = nil
        refreshDisplays()
    }

    func openSystemDisplaySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Displays-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.displays"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        language = newLanguage
        statusMessage = L10n.t("status.ready", language)
        refreshDisplays()
        persist()
    }

    private func startRollbackTimer() {
        rollbackTimer?.invalidate()
        rollbackTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            guard var pending = self.pendingModeChange else {
                timer.invalidate()
                return
            }

            pending.remainingSeconds -= 1
            self.pendingModeChange = pending
            if pending.remainingSeconds <= 0 {
                self.rollbackDisplayModeChange()
            }
        }
    }

    private func load() {
        let snapshot = persistence.load()
        language = snapshot.language
        statusMessage = L10n.t("status.ready", language)
    }

    private func persist() {
        persistence.save(PersistentSnapshot(
            language: language
        ))
    }
}
