import SwiftUI

struct SettingsView: View {
    @Bindable var store: DisplayStore
    @State private var selectedPane: SettingsPane = .displays
    @State private var hoveredPane: SettingsPane?
    @State private var searchText = ""
    @State private var presetName = "main"

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)

            contentArea
        }
        .frame(width: 980, height: 680)
        .background(AppTheme.background)
        .tint(AppTheme.accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            searchField

            VStack(alignment: .leading, spacing: 6) {
                ForEach(filteredPanes) { pane in
                    sidebarButton(pane)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)
            TextField(store.language.resolvedCode == "zh" ? "搜索设置" : "Search Settings", text: $searchText)
                .textFieldStyle(.plain)
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func sidebarButton(_ pane: SettingsPane) -> some View {
        Button {
            selectedPane = pane
        } label: {
            HStack(spacing: 12) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                Text(pane.title(language: store.language))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(selectedPane == pane ? Color.white : AppTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                sidebarButtonBackground(for: pane),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredPane = isHovering ? pane : nil
        }
    }

    private func sidebarButtonBackground(for pane: SettingsPane) -> Color {
        if selectedPane == pane {
            return AppTheme.accent
        }
        if hoveredPane == pane {
            return AppTheme.controlFill
        }
        return .clear
    }

    private var filteredPanes: [SettingsPane] {
        guard !searchText.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter {
            $0.title(language: store.language).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var paneHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label(selectedPane.title(language: store.language), systemImage: selectedPane.systemImage)
                    .font(.title2.weight(.semibold))
                Text(selectedPane.subtitle(language: store.language))
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if selectedPane == .presets {
                Button {
                    store.savePreset(named: presetName)
                } label: {
                    Label(store.language.resolvedCode == "zh" ? "创建预设" : "Create Preset", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if selectedPane == .schedules {
                Button {
                    store.addSchedule()
                } label: {
                    Label(store.language.resolvedCode == "zh" ? "添加计划任务" : "Add Schedule", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if selectedPane == .displays {
            DisplaysSettingsPane(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    paneHeader
                    paneContent
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .displays:
            EmptyView()
        case .general:
            generalPane
        case .presets:
            presetsPane
        case .schedules:
            schedulesPane
        case .brightnessVolumeKeys:
            brightnessVolumeKeysPane
        case .globalShortcuts:
            globalShortcutsPane
        case .customShortcuts:
            customShortcutsPane
        case .commandLineAI:
            commandLineAIPane
        case .about:
            aboutPane
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(title: "启动与隐私", subtitle: "决定应用如何常驻，以及是否发送不含个人内容的诊断信息。") {
                ToggleRow(
                    title: "开机自动启动 2K HiDPI 助手",
                    description: "登录 macOS 后自动运行菜单栏工具，适合长期用外接显示器的工作台。",
                    note: "如果你只是偶尔切换分辨率，可以关闭它来减少后台常驻。",
                    binding: preferenceBinding(\.launchAtLogin)
                )
                SettingsDivider()
                ToggleRow(
                    title: "允许匿名分析",
                    description: "只用于了解功能是否稳定，例如模式切换是否成功、DDC 后端是否可用。",
                    note: "不会上传显示器序列号、屏幕内容、文件路径或个人数据。",
                    binding: preferenceBinding(\.anonymousAnalytics)
                )
            }

            settingsCard(title: "控制体验", subtitle: "影响滑块、快捷键和屏幕提示的手感。") {
                ToggleRow(
                    title: "平滑过渡",
                    description: "拖动亮度、对比度和音量时，让数值变化更自然，避免突然跳变。",
                    note: "外接显示器的硬件 DDC 写入本身较慢；应用会只发送最新值，减少卡顿。",
                    binding: preferenceBinding(\.smoothTransitions)
                )
                SettingsDivider()
                ToggleRow(
                    title: "现代亮度和音量指示器",
                    description: "使用键盘快捷键时显示应用自己的 HUD，方便确认当前调节的是哪台显示器。",
                    note: "如果你更喜欢系统原生提示，可以关闭。",
                    binding: preferenceBinding(\.modernIndicators)
                )
            }

            settingsCard(title: "UltraBright", subtitle: "为支持 HDR/高亮能力的屏幕预留的增强亮度选项。") {
                ToggleRow(
                    title: "启用 UltraBright",
                    description: "允许应用在系统支持时尝试使用更高亮度能力。",
                    note: "并不是所有显示器都支持；当前版本会保守保存偏好，不会强行越过系统能力。",
                    binding: preferenceBinding(\.ultraBright)
                )
                SettingsDivider()
                ToggleRow(
                    title: "仅用于内建显示器",
                    description: "把 UltraBright 限定在 MacBook 内建屏，避免影响外接显示器。",
                    note: "外接显示器通常由 DDC/CI 或软件伽马控制，不一定有同等增亮能力。",
                    binding: preferenceBinding(\.ultraBrightBuiltInOnly)
                )
            }

            settingsCard(title: "显示器读写", subtitle: "硬件显示器协议能力不统一，这里采用保守策略。") {
                ToggleRow(
                    title: "读取显示器当前控制值",
                    description: "定期读取外接显示器的亮度、对比度等硬件值，让界面尽量贴近真实状态。",
                    note: "某些显示器读取很慢或不稳定；关闭后会使用本地保存值，拖动滑块会更跟手。",
                    binding: preferenceBinding(\.readDisplayControlValues)
                )
            }

            settingsCard(title: "电源控制", subtitle: "关闭显示器属于高风险 DDC 指令，默认需要明确选择。") {
                ToggleRow(
                    title: "优先使用 DDC/CI 真实关闭外接显示器",
                    description: "可用时向显示器发送 VCP 0xD6 电源指令，而不是只让系统进入显示器睡眠。",
                    note: "部分显示器关闭后无法通过软件唤醒，需要按物理按钮；失败时会回退到系统显示器睡眠。",
                    binding: preferenceBinding(\.preferPhysicalDisplayPowerOff)
                )
            }

            settingsCard(title: "菜单栏显示内容", subtitle: "控制菜单栏浮窗里哪些模块默认露出。") {
                ToggleRow(
                    title: "显示预设",
                    description: "在菜单栏浮窗里展示常用预设，方便一键恢复显示器组合。",
                    note: "预设会包含分辨率、亮度、音量、深色模式、Night Shift 等状态。",
                    binding: preferenceBinding(\.showPresetsInMenu)
                )
                SettingsDivider()
                ToggleRow(
                    title: "显示所有显示器设置",
                    description: "在菜单栏浮窗里显示每台屏幕的亮度、对比度、音量和分辨率入口。",
                    note: "如果浮窗内容太长，可以关闭后只保留主窗口管理。",
                    binding: preferenceBinding(\.showAllDisplaySettingsInMenu)
                )
                SettingsDivider()
                SettingControlRow(
                    title: "前置显示的预设数",
                    description: "决定有多少个预设直接显示在菜单栏浮窗里。",
                    note: "设得太多会挤占显示器控制区；常用 3 到 5 个比较合适。"
                ) {
                    Stepper(value: frontPresetCountBinding, in: 0...12) {
                        Text("\(store.preferences.frontPresetCount)")
                            .monospacedDigit()
                            .frame(minWidth: 26, alignment: .trailing)
                    }
                }
            }

            settingsCard(title: "语言", subtitle: "只影响应用界面文字，不会改变系统显示器设置。") {
                SettingControlRow(
                    title: L10n.t("settings.appLanguage", store.language),
                    description: "选择 2K HiDPI 助手使用的界面语言。",
                    note: "跟随系统时，会根据 macOS 首选语言自动选择中文或英文。"
                ) {
                    Picker(L10n.t("settings.appLanguage", store.language), selection: Binding(
                        get: { store.language },
                        set: { store.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var presetsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                HStack {
                    TextField("预设名称", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        store.savePreset(named: presetName.isEmpty ? "main" : presetName)
                    } label: {
                        Label("保存当前显示器状态", systemImage: "bookmark")
                    }
                }
                Text("预设会保存当前分辨率、亮度、对比度、音量、输入源记录、电源状态、Sync/Follow、深色模式和 Night Shift。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if store.presets.isEmpty {
                EmptySettingsState(
                    systemImage: "bookmark",
                    title: "还没有预设",
                    message: "创建第一个预设后，可以从菜单栏快速切换当前显示器组合。"
                )
            } else {
                settingsCard {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                        GridRow {
                            Text("名称").foregroundStyle(.secondary)
                            Text("显示器").foregroundStyle(.secondary)
                            Text("保存内容").foregroundStyle(.secondary)
                            Text("操作").foregroundStyle(.secondary)
                        }
                        Divider()
                        ForEach(store.presets) { preset in
                            GridRow {
                                Text(preset.name).fontWeight(.medium)
                                Text("\(preset.displayModes.count)")
                                Text(presetSummary(preset))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                HStack {
                                    shortcutButton(key: "preset.\(preset.id.uuidString)")
                                    Button("应用") { store.applyPreset(preset) }
                                    Button("删除", role: .destructive) { store.deletePreset(preset) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var schedulesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.schedules.isEmpty {
                EmptySettingsState(
                    systemImage: "calendar",
                    title: "还没有计划任务",
                    message: "创建计划任务后，可以在固定时间自动应用显示器预设。"
                )
            } else {
                Text("计划任务现在会在应用运行时每 30 秒检查一次，到达 HH:mm 时间后每天执行一次关联预设。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                ForEach(store.schedules) { schedule in
                    scheduleCard(schedule)
                }
            }
        }
    }

    private var brightnessVolumeKeysPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(title: "键盘监听状态", subtitle: "接管亮度键和音量键需要 macOS 辅助功能权限。") {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("键盘亮度/音量键接管")
                            .font(.headline)
                        Text(store.accessibilityTrusted ? "已获得辅助功能权限" : "需要辅助功能权限才能监听全局亮度键和音量键。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(store.keyboardMonitorStatus)
                            .font(.footnote.monospaced())
                            .foregroundStyle(AppTheme.secondaryText)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(store.accessibilityTrusted ? "重新检查" : "授权") {
                        store.requestKeyboardControlPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            settingsCard(title: "亮度与音量键行为", subtitle: "决定系统键盘按键应该作用到哪台显示器。") {
                ToggleRow(
                    title: "亮度键控制所有显示器",
                    description: "按键盘亮度键时，同时调整所有已识别显示器的亮度。",
                    note: "外接显示器会优先走硬件协议；不支持时会退回软件控制。",
                    binding: preferenceBinding(\.keyboardBrightnessControlsAllDisplays)
                )
                SettingsDivider()
                ToggleRow(
                    title: "音量键控制所有显示器",
                    description: "按音量键时，同步调整支持音量控制的外接显示器。",
                    note: "并非所有显示器都支持 DDC 音量；失败时不会污染本地持久状态。",
                    binding: preferenceBinding(\.keyboardVolumeControlsAllDisplays)
                )
                SettingsDivider()
                ToggleRow(
                    title: "只控制当前音频输出的外接显示器",
                    description: "当外接屏是当前音频输出设备时，音量键才会作用到它。",
                    note: "适合同时连接显示器音箱、耳机和声卡的桌面环境。",
                    binding: preferenceBinding(\.keyboardVolumeOnlyCurrentAudioOutput)
                )
            }

            settingsCard(title: "快捷键目标", subtitle: "控制全局快捷键默认作用范围。") {
                SettingControlRow(
                    title: "键盘快捷键控制",
                    description: "选择亮度、对比度、音量快捷键默认控制所有显示器，还是只控制当前选中的显示器。",
                    note: "如果你经常只调外接屏，建议在显示器页先选中目标屏。"
                ) {
                    Picker("键盘快捷键控制", selection: keyboardTargetModeBinding) {
                        ForEach(KeyboardTargetMode.allCases) { mode in
                            Text(mode.label(language: store.language)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
            }
        }
    }

    private var globalShortcutsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            shortcutSection("亮度", rows: [
                ("brightness.down", "降低亮度"),
                ("brightness.up", "提高亮度")
            ])
            shortcutSection("对比度", rows: [
                ("contrast.down", "降低对比度"),
                ("contrast.up", "提高对比度")
            ])
            shortcutSection("音量", rows: [
                ("volume.down", "降低音量"),
                ("volume.up", "提高音量")
            ])
        }
    }

    private var customShortcutsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("为每台外接显示器配置用于切换输入源的键盘快捷键。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Label("实验性功能：真实输入源切换可能导致显示器无响应。当前版本只保存配置，不会发送切换指令。", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.yellow)
                .padding(12)
                .appCard(cornerRadius: 8)

            ForEach(store.displays) { display in
                settingsCard {
                    Text(display.shortName(language: store.language))
                        .font(.headline)
                    ForEach(store.inputSourceOptions(for: display), id: \.self) { input in
                        let key = "input.\(display.id).\(input)"
                        ShortcutRow(
                            title: "切换到 \(input)",
                            description: "保存一个用于选择 \(input) 的快捷键占位配置。",
                            note: "当前版本不会发送真实输入源切换指令，避免显示器无响应。",
                            value: store.shortcutText(for: key, custom: true),
                            setAction: { store.assignPlaceholderShortcut(for: key, custom: true) },
                            clearAction: { store.clearShortcut(for: key, custom: true) }
                        )
                    }
                }
            }
        }
    }

    private var commandLineAIPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "命令行工具", subtitle: "把常用诊断和显示器控制暴露给终端。") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("命令行工具")
                            .font(.headline)
                        Text(store.commandLineToolInstalled ? "已安装到 /usr/local/bin/hidpibuddy" : "未安装")
                            .foregroundStyle(.secondary)
                        Text("安装后可以运行 diagnose、ddc probe 和只读/受控写入命令。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("注意：写入类命令会走后端选择和读回验证；验证失败不会保存为成功状态。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button(store.commandLineToolInstalled ? "重新安装" : "安装") {
                        store.installCommandLineTool()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            settingsCard(title: "MCP 服务器", subtitle: "为支持 MCP 的 AI 客户端预留控制接口。") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MCP 服务器")
                            .font(.headline)
                        Text("用于让 Claude Desktop、Cursor、Windsurf 等支持 MCP 的 AI 客户端控制显示器。")
                            .foregroundStyle(.secondary)
                        Text("注意：默认不允许危险写入；电源和输入源切换仍需要明确能力检测。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("查看设置指南") {
                        store.statusMessage = "MCP 设置指南入口已预留"
                    }
                }
            }
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                Label(L10n.t("app.name", store.language), systemImage: "display")
                    .font(.title3.weight(.semibold))
                Text("专注快速切换 macOS 外接显示器分辨率、HiDPI、亮度、对比度和菜单栏控制。")
                    .foregroundStyle(.secondary)
                Text("当前状态：\(store.statusMessage)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let lastError = store.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func shortcutSection(_ title: String, rows: [(String, String)]) -> some View {
        settingsCard {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.0) { key, label in
                ShortcutRow(
                    title: label,
                    description: shortcutDescription(for: label, group: title),
                    note: "快捷键会全局监听；如果和系统或其他应用冲突，请换成不常用组合。",
                    value: store.shortcutText(for: key),
                    setAction: { store.assignPlaceholderShortcut(for: key) },
                    clearAction: { store.clearShortcut(for: key) }
                )
            }
        }
    }

    private func scheduleCard(_ schedule: DisplaySchedule) -> some View {
        settingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("计划任务名称", text: Binding(
                        get: { schedule.name },
                        set: { newValue in
                            var updated = schedule
                            updated.name = newValue
                            store.updateSchedule(updated)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("时间")
                        TextField("09:00", text: Binding(
                            get: { schedule.timeText },
                            set: { newValue in
                                var updated = schedule
                                updated.timeText = newValue
                                store.updateSchedule(updated)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                        Picker("预设", selection: Binding<UUID?>(
                            get: { schedule.presetID },
                            set: { newValue in
                                var updated = schedule
                                updated.presetID = newValue
                                store.updateSchedule(updated)
                            }
                        )) {
                            Text("无").tag(Optional<UUID>.none)
                            ForEach(store.presets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }
                        .frame(width: 220)
                    }
                }

                Spacer()
                Toggle("", isOn: Binding(
                    get: { schedule.isEnabled },
                    set: { newValue in
                        var updated = schedule
                        updated.isEnabled = newValue
                        store.updateSchedule(updated)
                    }
                ))
                .labelsHidden()
                Button(role: .destructive) {
                    store.deleteSchedule(schedule)
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    private func shortcutButton(key: String) -> some View {
        Button(store.shortcutText(for: key)) {
            store.assignPlaceholderShortcut(for: key)
        }
        .buttonStyle(.bordered)
    }

    private func presetSummary(_ preset: DisplayPreset) -> String {
        var items = ["分辨率", "亮度/对比度/音量"]
        if preset.syncSettings.isEnabled {
            items.append("Sync")
        }
        if preset.darkModeEnabled {
            items.append("深色")
        }
        if preset.nightShiftEnabled {
            items.append("Night Shift")
        }
        return items.joined(separator: " · ")
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        settingsCard(title: nil, subtitle: nil, content: content)
    }

    private func settingsCard<Content: View>(
        title: String?,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 2)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 8)
    }

    private func shortcutDescription(for label: String, group: String) -> String {
        "按下快捷键时会\(label)，目标范围由“亮度与音量键”里的快捷键目标决定。"
    }

    private func preferenceBinding(_ keyPath: WritableKeyPath<AppPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { newValue in
                var preferences = store.preferences
                preferences[keyPath: keyPath] = newValue
                store.updatePreferences(preferences)
            }
        )
    }

    private var frontPresetCountBinding: Binding<Int> {
        Binding(
            get: { store.preferences.frontPresetCount },
            set: { newValue in
                var preferences = store.preferences
                preferences.frontPresetCount = newValue
                store.updatePreferences(preferences)
            }
        )
    }

    private var keyboardTargetModeBinding: Binding<KeyboardTargetMode> {
        Binding(
            get: { store.preferences.keyboardTargetMode },
            set: { newValue in
                var preferences = store.preferences
                preferences.keyboardTargetMode = newValue
                store.updatePreferences(preferences)
            }
        )
    }
}

private struct DisplaysSettingsPane: View {
    @Bindable var store: DisplayStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(L10n.t("nav.displays", store.language), systemImage: "display")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                if store.displays.count > 1 {
                    Picker("", selection: selectedDisplayBinding) {
                        ForEach(store.displays) { display in
                            Text(display.shortName(language: store.language))
                                .tag(Optional(display.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 240)
                } else if let display = store.selectedDisplay {
                    Text(display.shortName(language: store.language))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Button {
                    store.refreshDisplays()
                } label: {
                    Label(L10n.t("action.refresh", store.language), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
            .background(AppTheme.background)

            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)

            if let display = store.selectedDisplay {
                DisplayDetailView(store: store, display: display)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(L10n.t("empty.noDisplay", store.language), systemImage: "display.trianglebadge.exclamationmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selectedDisplayBinding: Binding<UInt32?> {
        Binding(
            get: { store.selectedDisplay?.id },
            set: { store.selectedDisplayID = $0 }
        )
    }
}

private struct ToggleRow: View {
    var title: String
    var description: String
    var note: String?
    var binding: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Label(note, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 24)
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}

private struct SettingControlRow<Control: View>: View {
    var title: String
    var description: String
    var note: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 24)
            control()
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.border)
            .frame(height: 1)
            .padding(.vertical, 2)
    }
}

private struct ShortcutRow: View {
    var title: String
    var description: String
    var note: String?
    var value: String
    var setAction: () -> Void
    var clearAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Label(note, systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 18)
            HStack(spacing: 8) {
                Text(value)
                    .font(.callout.monospaced())
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.controlFill, in: Capsule())
                Button("设置", action: setAction)
                    .buttonStyle(.bordered)
                Button(role: .destructive, action: clearAction) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct EmptySettingsState: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.secondaryText)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .appCard(cornerRadius: 10)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case displays
    case general
    case presets
    case schedules
    case brightnessVolumeKeys
    case globalShortcuts
    case customShortcuts
    case commandLineAI
    case about

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .displays:
            "display"
        case .general:
            "gearshape.2"
        case .presets:
            "bookmark"
        case .schedules:
            "calendar.badge.clock"
        case .brightnessVolumeKeys:
            "sun.max"
        case .globalShortcuts:
            "keyboard"
        case .customShortcuts:
            "command"
        case .commandLineAI:
            "terminal"
        case .about:
            "info.circle"
        }
    }

    func title(language: AppLanguage) -> String {
        L10n.t("settingsPane.\(rawValue)", language)
    }

    func subtitle(language: AppLanguage) -> String {
        let zh = language.resolvedCode == "zh"
        switch self {
        case .displays:
            return zh ? "查看当前显示器、HiDPI 模式来源和可切换分辨率。" : "Inspect displays, HiDPI mode sources, and switchable resolutions."
        case .general:
            return zh ? "管理启动、协议读写、菜单栏显示和应用语言。" : "Manage launch, protocol I/O, menu visibility, and language."
        case .presets:
            return zh ? "保存一组可复现的显示器状态，适合工作、直播和录屏场景。" : "Save reproducible display setups for work, streaming, and recording."
        case .schedules:
            return zh ? "在固定时间自动应用预设，适合日夜场景切换。" : "Apply presets at fixed times for day and night workflows."
        case .brightnessVolumeKeys:
            return zh ? "接管键盘亮度键和音量键，并明确它们作用到哪台显示器。" : "Route brightness and volume keys to the intended displays."
        case .globalShortcuts:
            return zh ? "设置全局快捷键，快速调整亮度、对比度和音量。" : "Set global shortcuts for brightness, contrast, and volume."
        case .customShortcuts:
            return zh ? "为输入源切换预留快捷键；真实写入仍保持谨慎。" : "Reserve input-source shortcuts while keeping hardware switching conservative."
        case .commandLineAI:
            return zh ? "安装终端工具，并为后续 AI 客户端控制保留入口。" : "Install the CLI and prepare controlled AI-client integrations."
        case .about:
            return zh ? "查看应用定位、当前状态和最近错误。" : "Review the app focus, current status, and recent errors."
        }
    }
}
