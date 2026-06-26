import AppKit
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
    var preferences = AppPreferences()
    var presets: [DisplayPreset] = []
    var schedules: [DisplaySchedule] = []
    var syncSettings = DisplaySyncSettings()
    var controlStates: [String: DisplayControlState] = [:]
    var globalShortcuts: [String: String] = [:]
    var customShortcuts: [String: String] = [:]
    var isDarkModeEnabled = false
    var isNightShiftEnabled = false
    var commandLineToolInstalled = false
    var accessibilityTrusted = false
    var keyboardMonitorStatus = "未启动"

    private let discovery = DisplayDiscoveryService()
    private let control = MonitorControlService()
    private let systemControl = SystemControlService()
    private let nightShiftControl = NightShiftService()
    private let keyboardControl = KeyboardControlService()
    private let softwareControl = SoftwareDisplayControlService()
    private let displayPower = DisplayPowerService()
    private let nativeDDC = NativeDDCService()
    private let appleBrightness = AppleDisplayBrightnessService()
    private let protocolDetector = DisplayProtocolDetector()
    private let hud = ControlHUDService()
    private let persistence = PersistenceService()
    @ObservationIgnored private var rollbackTimer: Timer?
    @ObservationIgnored private var scheduleTimer: Timer?
    @ObservationIgnored private var ddcValueSyncTimer: Timer?
    @ObservationIgnored private var builtInBrightnessSyncTimer: Timer?
    @ObservationIgnored private var keyboardBrightnessTimers: [UInt32: Timer] = [:]
    @ObservationIgnored private var ddcWriteTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var detectedProtocols: [UInt32: DisplayProtocolDetection] = [:]
    @ObservationIgnored private var lastBuiltInBrightness: Double?
    @ObservationIgnored private var nightShiftFallbackTimer: Timer?
    @ObservationIgnored private var nightShiftFallbackWarmth: Double = 0

    init() {
        load()
        refreshDisplays()
        startKeyboardMediaMonitoring()
        startScheduleTimer()
        startDDCValueSyncTimer()
        startBuiltInBrightnessSyncTimer()
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
        isDarkModeEnabled = systemControl.isDarkModeEnabled()
        if let nightShiftActive = try? nightShiftControl.isActive() {
            isNightShiftEnabled = nightShiftActive
        }
        commandLineToolInstalled = systemControl.isCommandLineToolInstalled()
        accessibilityTrusted = keyboardControl.isAccessibilityTrusted()

        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first?.id
        }

        refreshDetectedProtocols()
        applyNightShiftFallback()
        syncDDCControlValues()
        persist()
    }

    func controlState(for displayID: UInt32) -> DisplayControlState {
        controlStates["\(displayID)"] ?? DisplayControlState()
    }

    func setControlState(_ state: DisplayControlState, for displayID: UInt32) {
        controlStates["\(displayID)"] = state
        applyControlState(state, to: displayID)
        persist()
    }

    func setControlMode(_ mode: DisplayControlMode, for displayID: UInt32) {
        var state = controlState(for: displayID)
        state.controlMode = mode
        controlStates["\(displayID)"] = state
        if mode == .automatic, let detection = detectedProtocols[displayID] {
            statusMessage = language.resolvedCode == "zh"
                ? "控制模式：自动（\(detection.controlMode.label(language: language))，\(detection.reason.label(language: language))）"
                : "Control mode: Auto (\(detection.controlMode.label(language: language)), \(detection.reason.label(language: language)))"
        } else {
            statusMessage = "\(L10n.t("controlMode.title", language))：\(mode.label(language: language))"
        }
        persist()
    }

    func updateBrightness(_ value: Double, for displayID: UInt32) {
        var state = controlState(for: displayID)
        state.brightness = value
        state.isPoweredOff = false
        state.powerOffKind = nil
        controlStates["\(displayID)"] = state
        applyBrightness(state, to: displayID)
        syncControlChange(kind: .brightness, value: value, sourceDisplayID: displayID)
        persist()
        hud.show(kind: .brightness, value: value / 1.2, label: L10n.t("app.name", language), position: preferences.hudPosition)
    }

    func updateContrast(_ value: Double, for displayID: UInt32) {
        var state = controlState(for: displayID)
        state.contrast = value
        state.isPoweredOff = false
        state.powerOffKind = nil
        controlStates["\(displayID)"] = state
        applyContrast(state, to: displayID)
        syncControlChange(kind: .contrast, value: value, sourceDisplayID: displayID)
        persist()
        hud.show(kind: .contrast, value: (value - 0.4) / 1.4, label: L10n.t("app.name", language), position: preferences.hudPosition)
    }

    func updateVolume(_ value: Double, for displayID: UInt32) {
        var state = controlState(for: displayID)
        state.volume = value
        controlStates["\(displayID)"] = state
        applyVolume(state, to: displayID)
        syncControlChange(kind: .volume, value: value, sourceDisplayID: displayID)
        persist()
        hud.show(kind: .volume, value: value, label: L10n.t("app.name", language), position: preferences.hudPosition)
    }

    func toggleDisplayPower(for displayID: UInt32) {
        guard let display = displays.first(where: { $0.id == displayID }) else { return }
        var state = controlState(for: displayID)

        if state.isPoweredOff {
            if state.powerOffKind == .softBlackout {
                softwareControl.restore(displayID: displayID)
            } else if state.powerOffKind == .physical, let displayIndex = displayIndex(for: displayID) {
                try? displayPower.physicalPowerOn(displayID: displayID, displayIndex: displayIndex)
            }

            state.isPoweredOff = false
            state.powerOffKind = nil
            controlStates["\(displayID)"] = state
            statusMessage = language.resolvedCode == "zh" ? "已恢复显示器控制状态" : "Display power state restored"
            persist()
            return
        }

        if preferences.preferPhysicalDisplayPowerOff, !display.isBuiltin, let displayIndex = displayIndex(for: displayID) {
            guard effectiveControlMode(for: state, displayID: displayID) == .ddcCI else {
                statusMessage = language.resolvedCode == "zh"
                    ? "当前显示器没有可用的 DDC/CI 电源协议，无法发送真实关屏指令"
                    : "This display has no available DDC/CI power protocol, so physical power off is unavailable"
                lastError = nil
                persist()
                return
            }

            do {
                try displayPower.physicalPowerOff(displayID: displayID, displayIndex: displayIndex)
                state.isPoweredOff = true
                state.powerOffKind = .physical
                controlStates["\(displayID)"] = state
                statusMessage = language.resolvedCode == "zh"
                    ? "已发送 DDC/CI 真实关闭指令；部分显示器需要物理按钮唤醒"
                    : "Sent DDC/CI physical power off; some displays need the physical button to wake"
                lastError = nil
                persist()
                return
            } catch {
                if isDDCUnavailable(error) {
                    markDDCUnavailable(for: displayID, reason: error)
                } else {
                    lastError = error.localizedDescription
                }
                statusMessage = language.resolvedCode == "zh"
                    ? "当前连接不支持 DDC/CI 真实关屏，未改用系统睡眠"
                    : "This connection does not support DDC/CI physical power off; system sleep was not used"
                persist()
                return
            }
        }

        systemControl.sleepDisplays()
        state.isPoweredOff = true
        state.powerOffKind = .displaySleep
        controlStates["\(displayID)"] = state
        statusMessage = language.resolvedCode == "zh"
            ? "未能发送 DDC 关机，已改为让系统显示器睡眠"
            : "DDC power off unavailable; put displays to sleep instead"
        persist()
    }

    func toggleDarkMode() {
        let newValue = !isDarkModeEnabled
        do {
            try systemControl.setDarkMode(newValue)
            isDarkModeEnabled = newValue
            statusMessage = newValue ? L10n.t("darkMode.on", language) : L10n.t("darkMode.off", language)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            statusMessage = language.resolvedCode == "zh" ? "深色模式切换失败" : "Dark Mode toggle failed"
        }
    }

    func toggleNightShift() {
        let newValue = !isNightShiftEnabled
        do {
            try nightShiftControl.setEnabled(newValue)
            isNightShiftEnabled = newValue
            applyNightShiftFallback()
            statusMessage = newValue
                ? (language.resolvedCode == "zh" ? "夜览已开启" : "Night Shift enabled")
                : (language.resolvedCode == "zh" ? "夜览已关闭" : "Night Shift disabled")
            lastError = nil
            persist()
        } catch {
            isNightShiftEnabled = newValue
            applyNightShiftFallback()
            lastError = nil
            statusMessage = newValue
                ? (language.resolvedCode == "zh" ? "系统夜览不可用，已使用软件夜览" : "System Night Shift unavailable; using software warmth")
                : (language.resolvedCode == "zh" ? "软件夜览已关闭" : "Software warmth disabled")
            persist()
        }
    }

    func sleepDisplays() {
        systemControl.sleepDisplays()
    }

    func toggleSync() {
        syncSettings.isEnabled.toggle()
        if syncSettings.leaderDisplayID == nil {
            syncSettings.leaderDisplayID = selectedDisplayID ?? displays.first?.id
        }
        statusMessage = syncSettings.isEnabled
            ? (language.resolvedCode == "zh" ? "同步模式已开启" : "Sync mode enabled")
            : (language.resolvedCode == "zh" ? "同步模式已关闭" : "Sync mode disabled")
        persist()
    }

    func setFollowDisplay(_ displayID: UInt32?) {
        syncSettings.leaderDisplayID = displayID
        syncSettings.isEnabled = displayID != nil
        statusMessage = displayID == nil
            ? (language.resolvedCode == "zh" ? "Follow 模式已关闭" : "Follow mode disabled")
            : (language.resolvedCode == "zh" ? "Follow 模式已更新" : "Follow mode updated")
        persist()
    }

    func updatePreferences(_ newPreferences: AppPreferences) {
        let previousReadPreference = preferences.readDisplayControlValues
        preferences = newPreferences
        if previousReadPreference != newPreferences.readDisplayControlValues {
            startDDCValueSyncTimer()
        }
        startBuiltInBrightnessSyncTimer()
        persist()
    }

    func requestKeyboardControlPermission() {
        keyboardControl.requestAccessibilityTrust()
        accessibilityTrusted = keyboardControl.isAccessibilityTrusted()
        startKeyboardMediaMonitoring()
        statusMessage = accessibilityTrusted
            ? (language.resolvedCode == "zh" ? "已获得辅助功能权限" : "Accessibility permission granted")
            : (language.resolvedCode == "zh" ? "请在系统设置中允许辅助功能权限" : "Allow Accessibility permission in System Settings")
    }

    private func startKeyboardMediaMonitoring() {
        let didStart = keyboardControl.startMediaKeyMonitoring { [weak self] action in
            self?.handleKeyboardMediaAction(action)
        }
        if !didStart {
            keyboardMonitorStatus = "Event Tap 未启动"
            statusMessage = language.resolvedCode == "zh"
                ? "键盘亮度/音量键监听未启动，请授予辅助功能权限后重启应用"
                : "Keyboard media key monitoring is not running; grant Accessibility permission and restart the app"
        }
    }

    private func handleKeyboardMediaAction(_ action: KeyboardMediaAction) {
        switch action {
        case .brightnessUp:
            guard preferences.keyboardBrightnessControlsAllDisplays else { return }
            adjustKeyboardBrightness(by: 0.0625)
        case .brightnessDown:
            guard preferences.keyboardBrightnessControlsAllDisplays else { return }
            adjustKeyboardBrightness(by: -0.0625)
        case .volumeUp, .volumeDown, .mute:
            return
        case .unknown(let keyCode, let keyState):
            statusMessage = "媒体键未识别：keyCode=\(keyCode), keyState=\(keyState)"
        case .diagnostic(let message):
            keyboardMonitorStatus = message
            statusMessage = message
        }
    }

    private func keyboardTargetDisplays() -> [DisplayDevice] {
        switch preferences.keyboardTargetMode {
        case .allDisplays:
            return displays
        case .pointerDisplay:
            let mouseLocation = NSEvent.mouseLocation
            let matchedDisplays = displays.filter { display in
                display.frame.cgRect.contains(mouseLocation)
            }
            if !matchedDisplays.isEmpty {
                return matchedDisplays
            }
            if let selectedDisplay {
                return [selectedDisplay]
            }
            return displays
        }
    }

    private func adjustKeyboardBrightness(by delta: Double) {
        for display in keyboardTargetDisplays() {
            let current = controlState(for: display.id).brightness
            animateKeyboardBrightness(from: current, to: (current + delta).clamped(to: 0.05...1.2), for: display.id)
        }
    }

    private func animateKeyboardBrightness(from startValue: Double, to targetValue: Double, for displayID: UInt32) {
        keyboardBrightnessTimers[displayID]?.invalidate()

        let delta = targetValue - startValue
        guard abs(delta) > 0.001 else { return }

        let steps = preferences.smoothTransitions ? 4 : 1
        let interval = preferences.smoothTransitions ? 0.025 : 0.001
        var currentStep = 2

        let firstProgress = min(1 / Double(steps), 1)
        let firstEased = firstProgress * firstProgress * (3 - 2 * firstProgress)
        updateBrightness(startValue + delta * firstEased, for: displayID)

        keyboardBrightnessTimers[displayID] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }

                let progress = min(Double(currentStep) / Double(steps), 1)
                let eased = progress * progress * (3 - 2 * progress)
                self.updateBrightness(startValue + delta * eased, for: displayID)

                if currentStep >= steps {
                    timer.invalidate()
                    self.keyboardBrightnessTimers[displayID] = nil
                    self.updateBrightness(targetValue, for: displayID)
                }
                currentStep += 1
            }
        }
    }

    private func adjustKeyboardVolume(by delta: Double) {
        for display in keyboardTargetDisplays() {
            let current = controlState(for: display.id).volume
            updateVolume((current + delta).clamped(to: 0...1), for: display.id)
        }
    }

    private func setKeyboardVolume(_ value: Double) {
        for display in keyboardTargetDisplays() {
            updateVolume(value.clamped(to: 0...1), for: display.id)
        }
    }

    func savePreset(named name: String) {
        let modes = displays.compactMap { display -> DisplayPresetMode? in
            guard let mode = display.currentMode else { return nil }
            return DisplayPresetMode(
                displayID: display.id,
                displayName: display.shortName(language: language),
                mode: mode
            )
        }
        guard !modes.isEmpty else { return }

        presets.append(DisplayPreset(
            name: name,
            displayModes: modes,
            controlStates: controlStates,
            syncSettings: syncSettings,
            darkModeEnabled: isDarkModeEnabled,
            nightShiftEnabled: isNightShiftEnabled
        ))
        persist()
    }

    func deletePreset(_ preset: DisplayPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func applyPreset(_ preset: DisplayPreset) {
        controlStates.merge(preset.controlStates) { _, new in new }
        syncSettings = preset.syncSettings
        if isDarkModeEnabled != preset.darkModeEnabled {
            toggleDarkMode()
        }
        if isNightShiftEnabled != preset.nightShiftEnabled {
            toggleNightShift()
        }
        for (key, state) in preset.controlStates {
            guard let displayID = UInt32(key) else { continue }
            applyControlState(state, to: displayID)
        }
        for presetMode in preset.displayModes {
            applyDisplayMode(presetMode.mode, for: presetMode.displayID)
        }
        persist()
    }

    func addSchedule() {
        let presetID = presets.first?.id
        schedules.append(DisplaySchedule(
            name: language.resolvedCode == "zh" ? "新的计划任务" : "New Schedule",
            presetID: presetID,
            timeText: "09:00"
        ))
        persist()
    }

    func updateSchedule(_ schedule: DisplaySchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule
        persist()
    }

    func deleteSchedule(_ schedule: DisplaySchedule) {
        schedules.removeAll { $0.id == schedule.id }
        persist()
    }

    func shortcutText(for key: String, custom: Bool = false) -> String {
        let value = custom ? customShortcuts[key] : globalShortcuts[key]
        return value?.isEmpty == false ? value! : (language.resolvedCode == "zh" ? "未设置" : "Not Set")
    }

    func assignPlaceholderShortcut(for key: String, custom: Bool = false) {
        let placeholder = "⌥⌘\(custom ? "I" : "K")"
        if custom {
            customShortcuts[key] = placeholder
        } else {
            globalShortcuts[key] = placeholder
        }
        statusMessage = language.resolvedCode == "zh" ? "快捷键已保存为占位配置" : "Shortcut saved as a placeholder"
        persist()
    }

    func clearShortcut(for key: String, custom: Bool = false) {
        if custom {
            customShortcuts.removeValue(forKey: key)
        } else {
            globalShortcuts.removeValue(forKey: key)
        }
        persist()
    }

    func inputSourceOptions(for display: DisplayDevice) -> [String] {
        [
            "DisplayPort 1",
            "DisplayPort 2",
            "HDMI 1",
            "HDMI 2",
            "HDMI 3",
            "HDMI 4",
            "Thunderbolt / USB-C 1",
            "Thunderbolt / USB-C 2",
            "Thunderbolt / USB-C 3",
            "\(display.shortName(language: language)) Specific: DisplayPort 1",
            "\(display.shortName(language: language)) Specific: DisplayPort 2"
        ]
    }

    func selectInputSourcePreview(_ inputSource: String, for displayID: UInt32) {
        var state = controlState(for: displayID)
        state.inputSource = inputSource
        controlStates["\(displayID)"] = state
        statusMessage = language.resolvedCode == "zh"
            ? "已记录输入源：\(inputSource)。真实切换暂未启用，避免显示器变砖风险。"
            : "Input source recorded: \(inputSource). Real switching is disabled to avoid monitor lock-up risk."
        persist()
    }

    func explainControlModes() {
        statusMessage = language.resolvedCode == "zh"
            ? "自动模式会依次探测 Apple Display Protocol、DDC/CI、智能显示器厂商协议，均不可用时降级为软件 gamma 控制。"
            : "Auto mode probes Apple Display Protocol, DDC/CI, and smart display vendor protocols, then falls back to software gamma control."
    }

    func explainM1HDMILimitation() {
        statusMessage = language.resolvedCode == "zh"
            ? "部分 Apple Silicon Mac 的 HDMI 通道不暴露 DDC/CI，建议尝试 USB-C/DisplayPort 或显示器菜单中开启 DDC/CI。"
            : "Some Apple Silicon HDMI paths do not expose DDC/CI. Try USB-C/DisplayPort or enable DDC/CI in the monitor OSD."
    }

    private func displayIndex(for displayID: UInt32) -> Int? {
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else { return nil }
        return index + 1
    }

    private func applyControlState(_ state: DisplayControlState, to displayID: UInt32) {
        applyBrightness(state, to: displayID)
        applyContrast(state, to: displayID)
        applyVolume(state, to: displayID)
    }

    private func applyBrightness(_ state: DisplayControlState, to displayID: UInt32) {
        switch effectiveControlMode(for: state, displayID: displayID) {
        case .ddcCI:
            let value = UInt16((state.brightness.clamped(to: 0...1) * 100).rounded())
            scheduleDDCWrite(displayID: displayID, feature: 0x10, value: value)
            lastError = nil
        case .software:
            softwareControl.apply(state, nightShiftWarmth: nightShiftFallbackWarmth, to: displayID)
        case .appleDisplayProtocol:
            do {
                try appleBrightness.setBrightness(state.brightness, for: displayID)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                softwareControl.apply(state, nightShiftWarmth: nightShiftFallbackWarmth, to: displayID)
            }
        case .samsungSmart:
            softwareControl.apply(state, nightShiftWarmth: nightShiftFallbackWarmth, to: displayID)
            statusMessage = language.resolvedCode == "zh" ? "已识别智能显示器；网络遥控协议待绑定，当前使用软件控制" : "Smart display detected; network remote protocol is pending, using software control"
        case .automatic:
            softwareControl.apply(state, nightShiftWarmth: nightShiftFallbackWarmth, to: displayID)
        }
    }

    private func applyContrast(_ state: DisplayControlState, to displayID: UInt32) {
        switch effectiveControlMode(for: state, displayID: displayID) {
        case .ddcCI:
            let value = UInt16(((state.contrast - 0.4) / 1.4 * 100).clamped(to: 0...100).rounded())
            scheduleDDCWrite(displayID: displayID, feature: 0x12, value: value)
            lastError = nil
        case .software:
            softwareControl.apply(state, nightShiftWarmth: nightShiftFallbackWarmth, to: displayID)
        case .appleDisplayProtocol, .samsungSmart, .automatic:
            softwareControl.apply(state, nightShiftWarmth: nightShiftFallbackWarmth, to: displayID)
        }
    }

    private func applyVolume(_ state: DisplayControlState, to displayID: UInt32) {
        switch effectiveControlMode(for: state, displayID: displayID) {
        case .ddcCI:
            let value = UInt16((state.volume.clamped(to: 0...1) * 100).rounded())
            scheduleDDCWrite(displayID: displayID, feature: 0x62, value: value)
            lastError = nil
        case .software, .appleDisplayProtocol, .samsungSmart, .automatic:
            systemControl.setSystemOutputVolume(state.volume)
        }
    }

    private func scheduleDDCWrite(displayID: UInt32, feature: UInt8, value: UInt16) {
        let key = "\(displayID)-\(feature)"
        ddcWriteTasks[key]?.cancel()

        let display = displays.first(where: { $0.id == displayID })
        let nativeDDC = self.nativeDDC
        ddcWriteTasks[key] = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 18_000_000)
            guard !Task.isCancelled else { return }

            do {
                if let display {
                    try nativeDDC.writeVCPFeatureUnverified(feature, value: value, for: display)
                } else {
                    try nativeDDC.writeVCPFeatureUnverified(feature, value: value, for: displayID)
                }
            } catch {
                // High-frequency slider updates must not block the main UI path.
                // Verified CLI writes and explicit probes surface detailed errors.
            }
        }
    }

    private func refreshDetectedProtocols() {
        var next: [UInt32: DisplayProtocolDetection] = [:]
        for display in displays {
            next[display.id] = protocolDetector.detect(display: display)
        }
        detectedProtocols = next
    }

    func protocolStatus(for displayID: UInt32) -> String {
        let state = controlState(for: displayID)
        let effective = effectiveControlMode(for: state, displayID: displayID)
        guard state.controlMode == .automatic, let detection = detectedProtocols[displayID] else {
            return effective.label(language: language)
        }
        return language.resolvedCode == "zh"
            ? "自动：\(effective.label(language: language)) · \(detection.reason.label(language: language))"
            : "Auto: \(effective.label(language: language)) · \(detection.reason.label(language: language))"
    }

    private func effectiveControlMode(for state: DisplayControlState, displayID: UInt32) -> DisplayControlMode {
        guard state.controlMode == .automatic else {
            return state.controlMode
        }
        return detectedProtocols[displayID]?.controlMode ?? .software
    }

    private func applyNightShiftFallback() {
        guard !displays.isEmpty else { return }
        animateNightShiftFallback(to: isNightShiftEnabled ? 1 : 0)
    }

    private func isDDCUnavailable(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return message.contains("framebuffer")
            || message.contains("I2C")
            || message.contains("DDC/CI")
            || message.contains("DDC 指令")
    }

    private func markDDCUnavailable(for displayID: UInt32, reason: Error) {
        var state = controlState(for: displayID)
        if state.controlMode == .automatic {
            detectedProtocols[displayID] = DisplayProtocolDetection(
                controlMode: .software,
                isHardwareControl: false,
                reason: .softwareFallback
            )
        } else if state.controlMode == .ddcCI {
            state.controlMode = .software
            controlStates["\(displayID)"] = state
        }
        lastError = nil
        statusMessage = language.resolvedCode == "zh"
            ? "DDC/CI 不可用，已切换到软件控制；真实关屏不可用"
            : "DDC/CI is unavailable; switched to software control. Physical power off is unavailable"
    }

    private func animateNightShiftFallback(to targetWarmth: Double) {
        nightShiftFallbackTimer?.invalidate()

        let startWarmth = nightShiftFallbackWarmth
        let delta = targetWarmth - startWarmth
        guard abs(delta) > 0.001 else {
            applyNightShiftFallbackFrame(warmth: targetWarmth)
            return
        }

        let steps = 36
        let interval = 0.033
        var currentStep = 0
        nightShiftFallbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }

                currentStep += 1
                let progress = min(Double(currentStep) / Double(steps), 1)
                let eased = progress * progress * (3 - 2 * progress)
                self.applyNightShiftFallbackFrame(warmth: startWarmth + delta * eased)

                if currentStep >= steps {
                    timer.invalidate()
                    self.nightShiftFallbackTimer = nil
                    self.applyNightShiftFallbackFrame(warmth: targetWarmth)
                }
            }
        }
    }

    private func applyNightShiftFallbackFrame(warmth: Double) {
        nightShiftFallbackWarmth = warmth.clamped(to: 0...1)

        if nightShiftFallbackWarmth <= 0.001 {
            softwareControl.restore(displayID: displays[0].id)
            for display in displays {
                let state = controlState(for: display.id)
                if effectiveControlMode(for: state, displayID: display.id) == .software || state.powerOffKind == .softBlackout {
                    softwareControl.apply(state, nightShiftWarmth: 0, to: display.id)
                }
            }
            return
        }

        for display in displays {
            softwareControl.applyNightShift(warmth: nightShiftFallbackWarmth, to: display.id)
        }
    }

    private enum SyncedControlKind {
        case brightness
        case contrast
        case volume
    }

    private func syncControlChange(kind: SyncedControlKind, value: Double, sourceDisplayID: UInt32) {
        guard syncSettings.isEnabled, syncSettings.isLeader(sourceDisplayID) else { return }

        switch kind {
        case .brightness where !syncSettings.syncBrightness:
            return
        case .contrast where !syncSettings.syncContrast:
            return
        case .volume where !syncSettings.syncVolume:
            return
        default:
            break
        }

        for display in displays where display.id != sourceDisplayID {
            var state = controlState(for: display.id)
            switch kind {
            case .brightness:
                state.brightness = value
                state.isPoweredOff = false
                state.powerOffKind = nil
                controlStates["\(display.id)"] = state
                applyBrightness(state, to: display.id)
            case .contrast:
                state.contrast = value
                state.isPoweredOff = false
                state.powerOffKind = nil
                controlStates["\(display.id)"] = state
                applyContrast(state, to: display.id)
            case .volume:
                state.volume = value
                controlStates["\(display.id)"] = state
                applyVolume(state, to: display.id)
            }
        }
    }

    func installCommandLineTool() {
        do {
            try systemControl.installCommandLineTool()
            commandLineToolInstalled = true
            statusMessage = language.resolvedCode == "zh" ? "命令行工具已安装" : "Command line tool installed"
            lastError = nil
        } catch {
            commandLineToolInstalled = false
            lastError = error.localizedDescription
            statusMessage = language.resolvedCode == "zh" ? "命令行工具安装失败" : "Command line install failed"
        }
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
            Task { @MainActor in
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
    }

    private func startScheduleTimer() {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runDueSchedules()
            }
        }
        runDueSchedules()
    }

    private func startDDCValueSyncTimer() {
        ddcValueSyncTimer?.invalidate()
        ddcValueSyncTimer = nil

        guard preferences.readDisplayControlValues else { return }

        ddcValueSyncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncDDCControlValues()
            }
        }
    }

    private func startBuiltInBrightnessSyncTimer() {
        builtInBrightnessSyncTimer?.invalidate()
        builtInBrightnessSyncTimer = nil
        lastBuiltInBrightness = nil

        guard preferences.keyboardBrightnessControlsAllDisplays,
              displays.contains(where: \.isBuiltin),
              displays.contains(where: { !$0.isBuiltin }) else { return }

        sampleBuiltInBrightnessForSync()
        builtInBrightnessSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleBuiltInBrightnessForSync()
            }
        }
    }

    private func sampleBuiltInBrightnessForSync() {
        guard preferences.keyboardBrightnessControlsAllDisplays,
              let builtInDisplay = displays.first(where: \.isBuiltin),
              let brightness = appleBrightness.brightness(for: builtInDisplay.id) else { return }

        guard let previous = lastBuiltInBrightness else {
            lastBuiltInBrightness = brightness
            return
        }

        guard abs(brightness - previous) >= 0.01 else { return }
        lastBuiltInBrightness = brightness
        applyBuiltInBrightnessSync(brightness)
    }

    private func applyBuiltInBrightnessSync(_ brightness: Double) {
        let normalizedBrightness = brightness.clamped(to: 0.05...1)
        var changed = false

        for display in displays {
            var state = controlState(for: display.id)
            if abs(state.brightness - normalizedBrightness) > 0.01 {
                state.brightness = normalizedBrightness
                state.isPoweredOff = false
                state.powerOffKind = nil
                controlStates["\(display.id)"] = state
                changed = true
            }

            guard !display.isBuiltin else { continue }
            applyBrightness(state, to: display.id)
        }

        if changed {
            statusMessage = language.resolvedCode == "zh" ? "已同步键盘亮度键到外接显示器" : "Synced keyboard brightness to external displays"
            persist()
            hud.show(kind: .brightness, value: normalizedBrightness, label: L10n.t("app.name", language), position: preferences.hudPosition)
        }
    }

    private func syncDDCControlValues() {
        guard preferences.readDisplayControlValues else { return }

        var changed = false
        for display in displays where !display.isBuiltin {
            var state = controlState(for: display.id)
            guard effectiveControlMode(for: state, displayID: display.id) == .ddcCI, !state.isPoweredOff else { continue }

            do {
                let brightness = try nativeDDC.getBrightness(for: display.id).normalized.clamped(to: 0.05...1)
                if abs(state.brightness - brightness) > 0.015 {
                    state.brightness = brightness
                    changed = true
                }
            } catch {
                continue
            }

            if let contrast = try? nativeDDC.getContrast(for: display.id).normalized {
                let mappedContrast = (0.4 + contrast.clamped(to: 0...1) * 1.4).clamped(to: 0.4...1.8)
                if abs(state.contrast - mappedContrast) > 0.02 {
                    state.contrast = mappedContrast
                    changed = true
                }
            }

            if let volume = try? nativeDDC.getVolume(for: display.id).normalized.clamped(to: 0...1),
               abs(state.volume - volume) > 0.015 {
                state.volume = volume
                changed = true
            }

            controlStates["\(display.id)"] = state
        }

        if changed {
            persist()
        }
    }

    private func runDueSchedules() {
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let currentTime = timeFormatter.string(from: now)

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let today = dayFormatter.string(from: now)

        for index in schedules.indices {
            guard schedules[index].isEnabled,
                  schedules[index].timeText == currentTime,
                  schedules[index].lastRunDay != today,
                  let presetID = schedules[index].presetID,
                  let preset = presets.first(where: { $0.id == presetID }) else { continue }

            schedules[index].lastRunDay = today
            applyPreset(preset)
            statusMessage = language.resolvedCode == "zh"
                ? "已执行计划任务：\(schedules[index].name)"
                : "Schedule applied: \(schedules[index].name)"
        }
        persist()
    }

    private func load() {
        let snapshot = persistence.load()
        language = snapshot.language
        preferences = snapshot.preferences
        presets = snapshot.presets
        schedules = snapshot.schedules
        syncSettings = snapshot.syncSettings
        controlStates = snapshot.controlStates
        migrateAutomaticProtocolDetectionIfNeeded()
        globalShortcuts = snapshot.globalShortcuts
        customShortcuts = snapshot.customShortcuts
        isNightShiftEnabled = snapshot.nightShiftEnabled
        isDarkModeEnabled = systemControl.isDarkModeEnabled()
        commandLineToolInstalled = systemControl.isCommandLineToolInstalled()
        accessibilityTrusted = keyboardControl.isAccessibilityTrusted()
        statusMessage = L10n.t("status.ready", language)
    }

    private func migrateAutomaticProtocolDetectionIfNeeded() {
        guard preferences.protocolDetectionSchemaVersion < 1 else { return }
        controlStates = controlStates.mapValues { state in
            var migrated = state
            migrated.controlMode = .automatic
            return migrated
        }
        preferences.protocolDetectionSchemaVersion = 1
    }

    private func persist() {
        persistence.save(PersistentSnapshot(
            language: language,
            preferences: preferences,
            presets: presets,
            schedules: schedules,
            syncSettings: syncSettings,
            controlStates: controlStates,
            globalShortcuts: globalShortcuts,
            customShortcuts: customShortcuts,
            nightShiftEnabled: isNightShiftEnabled
        ))
    }
}
