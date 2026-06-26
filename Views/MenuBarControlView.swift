import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @Bindable var store: DisplayStore
    @Environment(\.openWindow) private var openWindow
    @State private var presetName = "main"

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            LinearGradient(
                colors: [
                    AppTheme.glassOverlayStart,
                    AppTheme.glassOverlayEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    presetsPanel
                    globalPanel

                    ForEach(store.displays) { display in
                        displayPanel(display)
                    }

                    footer
                }
                .padding(14)
            }
        }
        .frame(width: 420, height: 620)
        .tint(AppTheme.accent)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("app.name", store.language))
                    .font(.title3.weight(.semibold))
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                AppWindowController.showMainWindow {
                    openWindow(id: "main")
                }
            } label: {
                Label(L10n.t("settings.title", store.language), systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(6)
                    .background(AppTheme.controlFill, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppTheme.primaryText)
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var presetsPanel: some View {
        controlPanel(
            title: L10n.t("preset.title", store.language),
            subtitle: "保存并快速恢复分辨率、亮度、音量和夜览等组合。"
        ) {

            HStack(spacing: 8) {
                if store.presets.isEmpty {
                    Button(presetName) {
                        store.savePreset(named: presetName)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ForEach(store.presets) { preset in
                        Button(preset.name) {
                            store.applyPreset(preset)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Button {
                    store.savePreset(named: presetName)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t("preset.saveCurrent", store.language))
            }
        }
    }

    private var globalPanel: some View {
        controlPanel(
            title: L10n.t("display.all", store.language),
            subtitle: "影响所有屏幕的系统级状态。"
        ) {

            HStack(spacing: 8) {
                Button {
                    store.toggleDarkMode()
                } label: {
                    Label(
                        store.isDarkModeEnabled ? L10n.t("darkMode.on", store.language) : L10n.t("darkMode.off", store.language),
                        systemImage: store.isDarkModeEnabled ? "moon.fill" : "moon"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(StatusPillButtonStyle(isOn: store.isDarkModeEnabled, onColor: .blue))

                Button {
                    store.toggleNightShift()
                } label: {
                    Label(
                        store.isNightShiftEnabled ? L10n.t("nightShift.on", store.language) : L10n.t("nightShift.off", store.language),
                        systemImage: store.isNightShiftEnabled ? "moon.stars.fill" : "moon.stars"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(StatusPillButtonStyle(isOn: store.isNightShiftEnabled, onColor: AppTheme.accent))
            }

            HStack(spacing: 8) {
                Button {
                    store.toggleSync()
                } label: {
                    Label(
                        store.syncSettings.isEnabled ? L10n.t("sync.on", store.language) : L10n.t("sync.off", store.language),
                        systemImage: "link"
                    )
                }
                .buttonStyle(StatusPillButtonStyle(isOn: store.syncSettings.isEnabled, onColor: .green))

                Menu {
                    Button {
                        store.setFollowDisplay(nil)
                    } label: {
                        HStack {
                            if store.syncSettings.leaderDisplayID == nil {
                                Image(systemName: "checkmark")
                            }
                            Text(L10n.t("sync.followOff", store.language))
                        }
                    }

                    Divider()

                    ForEach(store.displays) { display in
                        Button {
                            store.setFollowDisplay(display.id)
                        } label: {
                            HStack {
                                if store.syncSettings.leaderDisplayID == display.id {
                                    Image(systemName: "checkmark")
                                }
                                Text(display.shortName(language: store.language))
                            }
                        }
                    }
                } label: {
                    Label(L10n.t("sync.follow", store.language), systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text("联动开启后，亮度/音量会按当前策略同步到多台显示器。跟随显示器用于指定主控屏。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func displayPanel(_ display: DisplayDevice) -> some View {
        let state = store.controlState(for: display.id)

        return controlPanel(
            title: display.shortName(language: store.language),
            subtitle: displayControlSubtitle(for: display),
            systemImage: display.isBuiltin ? "macbook" : "display"
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text(display.currentMode?.resolutionWithAspectLabel ?? "-")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(display.currentMode?.detailLabel ?? "")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            controlSlider(
                icon: "sun.max",
                title: "亮度",
                description: "拖动时只发送最新值，避免硬件 DDC 读回拖慢手感。",
                valueText: percentText(store.controlState(for: display.id).brightness),
                value: Binding(
                    get: { store.controlState(for: display.id).brightness },
                    set: { store.updateBrightness($0, for: display.id) }
                ),
                range: 0.05...1.2
            )

            controlSlider(
                icon: "circle.lefthalf.filled",
                title: "对比度",
                description: "影响显示器硬件对比度，过高可能丢失暗部或亮部细节。",
                valueText: percentText(store.controlState(for: display.id).contrast / 1.8),
                value: Binding(
                    get: { store.controlState(for: display.id).contrast },
                    set: { store.updateContrast($0, for: display.id) }
                ),
                range: 0.4...1.8
            )

            controlSlider(
                icon: "speaker.wave.2",
                title: "音量",
                description: "仅对支持 DDC 音量的显示器有效；失败时不会保存为成功状态。",
                valueText: percentText(store.controlState(for: display.id).volume),
                value: Binding(
                    get: { store.controlState(for: display.id).volume },
                    set: { store.updateVolume($0, for: display.id) }
                ),
                range: 0...1
            )

            HStack(spacing: 8) {
                controlModeMenu(display, state: state)
                    .frame(maxWidth: .infinity)

                inputSourceMenu(display, state: state)
                    .frame(maxWidth: .infinity)
            }
            Text("自动模式会优先 Apple 原生亮度、Apple Silicon DDC、Framebuffer DDC，最后回退软件控制。输入源当前只记录，不默认发送真实切换。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                resolutionDisclosure(display)
                    .frame(maxWidth: .infinity)

                Button {
                    store.toggleDisplayPower(for: display.id)
                } label: {
                    Label(
                        state.isPoweredOff ? L10n.t("power.on", store.language) : L10n.t("power.off", store.language),
                        systemImage: "power"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                Menu {
                    Button {
                        store.openSystemDisplaySettings()
                    } label: {
                        Label(L10n.t("hidpi.openSettings", store.language), systemImage: "gearshape")
                    }

                    Button {
                        store.sleepDisplays()
                    } label: {
                        Label(L10n.t("display.sleep", store.language), systemImage: "display.trianglebadge.exclamationmark")
                    }
                } label: {
                    Label(L10n.t("menu.more", store.language), systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
            Text("分辨率只切换 macOS 当前暴露的真实模式；电源类硬件写入会保守回退。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func controlModeMenu(_ display: DisplayDevice, state: DisplayControlState) -> some View {
        Menu {
            ForEach(DisplayControlMode.allCases) { mode in
                Button {
                    store.setControlMode(mode, for: display.id)
                } label: {
                    HStack {
                        if state.controlMode == mode {
                            Image(systemName: "checkmark")
                        }
                        Text(mode.label(language: store.language))
                    }
                }
            }

            Divider()

            Button {
                store.explainControlModes()
            } label: {
                Text(L10n.t("controlMode.whatIsThis", store.language))
            }

            Divider()

            Button {
                store.explainM1HDMILimitation()
            } label: {
                Text(L10n.t("controlMode.m1HDMI", store.language))
            }
        } label: {
            Label(
                store.protocolStatus(for: display.id),
                systemImage: "slider.horizontal.3"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func inputSourceMenu(_ display: DisplayDevice, state: DisplayControlState) -> some View {
        Menu {
            ForEach(store.inputSourceOptions(for: display).filter { !$0.contains("Specific") }, id: \.self) { input in
                Button {
                    store.selectInputSourcePreview(input, for: display.id)
                } label: {
                    HStack {
                        if state.inputSource == input {
                            Image(systemName: "checkmark")
                        }
                        Text(input)
                    }
                }
            }

            Divider()

            Label(L10n.t("inputSource.experimentalWarning", store.language), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        } label: {
            Label(L10n.t("inputSource.title", store.language), systemImage: "cable.connector")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func resolutionDisclosure(_ display: DisplayDevice) -> some View {
        let switchableModes = display.menuSwitchModes

        return Menu {
            let hiDPIModes = switchableModes.filter(\.isHiDPI)
            let standardModes = switchableModes.filter { !$0.isHiDPI }

            if !hiDPIModes.isEmpty {
                Section("HiDPI") {
                    ForEach(hiDPIModes) { mode in
                        quickModeButton(mode, display: display)
                    }
                }
            }

            if !standardModes.isEmpty {
                Section(L10n.t("hidpi.standard", store.language)) {
                    ForEach(standardModes) { mode in
                        quickModeButton(mode, display: display)
                    }
                }
            }
        } label: {
            Label(L10n.t("systemSettings.resolutions", store.language), systemImage: "rectangle.inset.filled")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func quickModeButton(_ mode: DisplayMode, display: DisplayDevice) -> some View {
        let isCurrent = display.currentMode?.matchesEffectiveMode(mode) == true
        return Button {
            store.applyDisplayMode(mode, for: display.id)
        } label: {
            HStack {
                Text(mode.menuLabel)
                if isCurrent {
                    Image(systemName: "checkmark")
                }
            }
        }
        .disabled(isCurrent)
    }

    private func displayControlSubtitle(for display: DisplayDevice) -> String {
        let protocolText = store.protocolStatus(for: display.id)
        if display.isBuiltin {
            return "内建屏优先使用 Apple 原生亮度能力；分辨率仍只切换系统暴露的真实模式。"
        }
        return "硬件控制：\(protocolText)。读写失败时会回退软件控制。"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func controlSlider(
        icon: String,
        title: String,
        description: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(AppTheme.primaryText)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
            Text(description)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private func controlPanel<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(14)
        .appCard(cornerRadius: 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pending = store.pendingModeChange {
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
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct StatusPillButtonStyle: ButtonStyle {
    var isOn: Bool
    var onColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? Color.white : AppTheme.primaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(background(configuration: configuration), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isOn ? Color.clear : AppTheme.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> Color {
        if isOn {
            return onColor.opacity(configuration.isPressed ? 0.72 : 0.92)
        }
        return AppTheme.controlFill.opacity(configuration.isPressed ? 1.35 : 1)
    }
}
