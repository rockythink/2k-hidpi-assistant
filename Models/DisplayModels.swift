import CoreGraphics
import Foundation

struct DisplayDevice: Identifiable, Codable, Hashable {
    var id: UInt32
    var name: String
    var vendorID: UInt32
    var modelID: UInt32
    var serialNumber: UInt32
    var metadata: DisplayMetadata
    var isBuiltin: Bool
    var isOnline: Bool
    var frame: CGRectCodable
    var currentMode: DisplayMode?
    var availableModes: [DisplayMode]
    var rotation: Double

    func shortName(language: AppLanguage) -> String {
        name.isEmpty ? "\(L10n.t("display.fallbackName", language)) \(id)" : name
    }

    var shortName: String {
        shortName(language: .system)
    }

    var nativeMode: DisplayMode? {
        let standardModes = availableModes.filter { !$0.isHiDPI }
        return standardModes.max { lhs, rhs in
            if lhs.pixelArea != rhs.pixelArea { return lhs.pixelArea < rhs.pixelArea }
            return lhs.refreshRate < rhs.refreshRate
        } ?? availableModes.max { $0.pixelArea < $1.pixelArea }
    }

    var displayClass: DisplayClass {
        guard let nativeMode else { return .unknown }
        return DisplayClass(width: nativeMode.width, height: nativeMode.height)
    }

    var systemScaledModes: [DisplayMode] {
        var grouped = [String: DisplayMode]()
        for mode in availableModes where mode.width >= 1024 && mode.height >= 576 {
            let key = "\(mode.width)x\(mode.height)-\(mode.isHiDPI ? "hidpi" : "1x")"
            guard let existing = grouped[key] else {
                grouped[key] = mode
                continue
            }

            let currentScore = mode.systemSettingsScore(currentMode: currentMode)
            let existingScore = existing.systemSettingsScore(currentMode: currentMode)
            if currentScore > existingScore {
                grouped[key] = mode
            }
        }

        return grouped.values.sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            return lhs.refreshRate > rhs.refreshRate
        }
    }

    var menuSwitchModes: [DisplayMode] {
        var grouped = [String: DisplayMode]()
        for mode in availableModes where mode.width >= 1024 && mode.height >= 576 {
            let key = "\(mode.width)x\(mode.height)-\(Int(mode.refreshRate.rounded()))-\(mode.isHiDPI ? "hidpi" : "1x")"
            guard let existing = grouped[key] else {
                grouped[key] = mode
                continue
            }

            if mode.depthScore > existing.depthScore {
                grouped[key] = mode
            }
        }

        return grouped.values.sorted { lhs, rhs in
            if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI && !rhs.isHiDPI }
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
            return lhs.depthScore > rhs.depthScore
        }
    }

    var isCurrentHiDPI: Bool {
        currentMode?.isHiDPI == true
    }

    var recommendedHiDPIModes: [DisplayMode] {
        let hidpiModes = availableModes.filter(\.isHiDPI)
        guard !hidpiModes.isEmpty else { return [] }

        return hidpiModes
            .sorted { lhs, rhs in
                let lhsRank = displayClass.preferenceRank(for: lhs)
                let rhsRank = displayClass.preferenceRank(for: rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
                return lhs.pixelArea > rhs.pixelArea
            }
            .reduce(into: [DisplayMode]()) { result, mode in
                guard !result.contains(where: { $0.width == mode.width && $0.height == mode.height }) else { return }
                result.append(mode)
            }
            .prefix(5)
            .map { $0 }
    }

    var unavailableRecommendedHiDPITargets: [DisplayResolutionTarget] {
        displayClass.preferredHiDPIResolutions
            .filter { target in
                !availableModes.contains { mode in
                    mode.isHiDPI && mode.width == target.width && mode.height == target.height
                }
            }
            .prefix(4)
            .map { DisplayResolutionTarget(width: $0.width, height: $0.height) }
    }
}

struct DisplayResolutionTarget: Codable, Hashable, Identifiable {
    var id: String { "\(width)x\(height)" }
    var width: Int
    var height: Int

    var resolutionLabel: String {
        "\(width) x \(height)"
    }

    var resolutionWithAspectLabel: String {
        "\(resolutionLabel) · \(aspectRatioLabel)"
    }

    var aspectRatioLabel: String {
        let divisor = DisplayMode.greatestCommonDivisor(width, height)
        return "\(width / divisor):\(height / divisor)"
    }
}

struct DisplayMetadata: Codable, Hashable {
    var productName: String?
    var vendorID: UInt32
    var productID: UInt32
    var serialNumber: UInt32
    var manufactureWeek: UInt32?
    var manufactureYear: UInt32?
    var physicalWidthMM: Double
    var physicalHeightMM: Double
    var unitNumber: UInt32
    var colorSpaceName: String?
    var isMain: Bool
    var isActive: Bool

    var vendorHex: String {
        "0x" + String(vendorID, radix: 16, uppercase: true)
    }

    var productHex: String {
        "0x" + String(productID, radix: 16, uppercase: true)
    }

    var serialText: String {
        serialNumber == 0 ? "-" : "\(serialNumber)"
    }

    var manufactureText: String {
        guard let manufactureYear else { return "-" }
        if let manufactureWeek, manufactureWeek > 0 {
            return "\(manufactureYear) W\(manufactureWeek)"
        }
        return "\(manufactureYear)"
    }

    var physicalSizeText: String {
        guard physicalWidthMM > 0, physicalHeightMM > 0 else { return "-" }
        return "\(Int(physicalWidthMM.rounded())) x \(Int(physicalHeightMM.rounded())) mm"
    }

    var diagonalInches: Double? {
        guard physicalWidthMM > 0, physicalHeightMM > 0 else { return nil }
        let diagonalMM = sqrt(physicalWidthMM * physicalWidthMM + physicalHeightMM * physicalHeightMM)
        return diagonalMM / 25.4
    }

    func diagonalText(language: AppLanguage) -> String {
        guard let diagonalInches else { return "-" }
        let suffix = language.resolvedCode == "zh" ? "英寸" : "in"
        return String(format: "%.1f %@", diagonalInches, suffix)
    }

    func estimatedPPI(nativeMode: DisplayMode?) -> String {
        guard let nativeMode, let diagonalInches, diagonalInches > 0 else { return "-" }
        let pixelDiagonal = sqrt(Double(nativeMode.pixelWidth * nativeMode.pixelWidth + nativeMode.pixelHeight * nativeMode.pixelHeight))
        return "\(Int((pixelDiagonal / diagonalInches).rounded())) PPI"
    }

    func colorSpaceText(language: AppLanguage) -> String {
        guard let colorSpaceName, !colorSpaceName.isEmpty else { return "-" }
        return colorSpaceName
    }
}

enum DisplayClass: Codable, Hashable {
    case twoK
    case twoPointFiveK
    case fourKOrAbove
    case lowResolution
    case unknown

    init(width: Int, height: Int) {
        let longEdge = max(width, height)
        let shortEdge = min(width, height)

        if longEdge >= 3840 || shortEdge >= 2160 {
            self = .fourKOrAbove
        } else if (longEdge == 2560 && shortEdge == 1600) || (longEdge == 2880 && shortEdge == 1800) {
            self = .twoPointFiveK
        } else if longEdge == 2560 && shortEdge == 1440 {
            self = .twoK
        } else if longEdge < 2560 || shortEdge < 1440 {
            self = .lowResolution
        } else {
            self = .unknown
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .twoK:
            L10n.t("display.class.2k", language)
        case .twoPointFiveK:
            L10n.t("display.class.2_5k", language)
        case .fourKOrAbove:
            L10n.t("display.class.4k", language)
        case .lowResolution:
            L10n.t("display.class.low", language)
        case .unknown:
            L10n.t("display.class.unknown", language)
        }
    }

    var preferredHiDPIResolutions: [(width: Int, height: Int)] {
        switch self {
        case .twoK:
            [(1920, 1080), (1680, 945), (1600, 900), (1440, 810), (1280, 720)]
        case .twoPointFiveK:
            [(1920, 1200), (1680, 1050), (1600, 1000), (1440, 900), (1280, 800), (1920, 1080), (1600, 900)]
        case .fourKOrAbove:
            [(2560, 1440), (2304, 1296), (2048, 1152), (1920, 1080)]
        case .lowResolution, .unknown:
            [(1920, 1080), (1680, 1050), (1600, 900), (1440, 900), (1280, 800), (1280, 720)]
        }
    }

    func preferenceRank(for mode: DisplayMode) -> Int {
        let preferredSizes = preferredHiDPIResolutions

        return preferredSizes.firstIndex { width, height in
            mode.width == width && mode.height == height
        } ?? preferredSizes.count + abs(mode.width - 1600) / 100
    }
}

struct PendingDisplayModeChange: Codable, Hashable {
    var displayID: UInt32
    var previousMode: DisplayMode
    var targetMode: DisplayMode
    var remainingSeconds: Int
}

struct DisplayControlState: Codable, Hashable {
    var brightness: Double = 1
    var contrast: Double = 1
    var volume: Double = 0.5
    var inputSource: String = "USB-C / HDMI"
    var controlMode: DisplayControlMode = .automatic
    var isPoweredOff: Bool = false
    var powerOffKind: DisplayPowerOffKind?

    init(
        brightness: Double = 1,
        contrast: Double = 1,
        volume: Double = 0.5,
        inputSource: String = "USB-C / HDMI",
        controlMode: DisplayControlMode = .automatic,
        isPoweredOff: Bool = false,
        powerOffKind: DisplayPowerOffKind? = nil
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.volume = volume
        self.inputSource = inputSource
        self.controlMode = controlMode
        self.isPoweredOff = isPoweredOff
        self.powerOffKind = powerOffKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 1
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.5
        inputSource = try container.decodeIfPresent(String.self, forKey: .inputSource) ?? "USB-C / HDMI"
        controlMode = try container.decodeIfPresent(DisplayControlMode.self, forKey: .controlMode) ?? .automatic
        isPoweredOff = try container.decodeIfPresent(Bool.self, forKey: .isPoweredOff) ?? false
        powerOffKind = try container.decodeIfPresent(DisplayPowerOffKind.self, forKey: .powerOffKind)
    }
}

enum DisplayControlMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case automatic
    case ddcCI
    case appleDisplayProtocol
    case software
    case samsungSmart

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .automatic:
            return language.resolvedCode == "zh" ? "自动" : "Auto"
        case .ddcCI:
            return "DDC/CI"
        case .appleDisplayProtocol:
            return "Apple Display Protocol"
        case .software:
            return language.resolvedCode == "zh" ? "软件控制" : "Software Control"
        case .samsungSmart:
            return "Samsung/LG Smart"
        }
    }
}

struct AppPreferences: Codable, Hashable {
    var launchAtLogin: Bool = false
    var anonymousAnalytics: Bool = false
    var smoothTransitions: Bool = true
    var modernIndicators: Bool = true
    var ultraBright: Bool = false
    var ultraBrightBuiltInOnly: Bool = false
    var readDisplayControlValues: Bool = false
    var showPresetsInMenu: Bool = true
    var showAllDisplaySettingsInMenu: Bool = true
    var frontPresetCount: Int = 5
    var keyboardBrightnessControlsAllDisplays: Bool = true
    var keyboardVolumeControlsAllDisplays: Bool = true
    var keyboardVolumeOnlyCurrentAudioOutput: Bool = true
    var keyboardTargetMode: KeyboardTargetMode = .allDisplays
    var hudPosition: HUDPosition = .lowerCenter
    var preferPhysicalDisplayPowerOff: Bool = true
    var protocolDetectionSchemaVersion: Int = 1

    init(
        launchAtLogin: Bool = false,
        anonymousAnalytics: Bool = false,
        smoothTransitions: Bool = true,
        modernIndicators: Bool = true,
        ultraBright: Bool = false,
        ultraBrightBuiltInOnly: Bool = false,
        readDisplayControlValues: Bool = false,
        showPresetsInMenu: Bool = true,
        showAllDisplaySettingsInMenu: Bool = true,
        frontPresetCount: Int = 5,
        keyboardBrightnessControlsAllDisplays: Bool = true,
        keyboardVolumeControlsAllDisplays: Bool = true,
        keyboardVolumeOnlyCurrentAudioOutput: Bool = true,
        keyboardTargetMode: KeyboardTargetMode = .allDisplays,
        hudPosition: HUDPosition = .lowerCenter,
        preferPhysicalDisplayPowerOff: Bool = true,
        protocolDetectionSchemaVersion: Int = 1
    ) {
        self.launchAtLogin = launchAtLogin
        self.anonymousAnalytics = anonymousAnalytics
        self.smoothTransitions = smoothTransitions
        self.modernIndicators = modernIndicators
        self.ultraBright = ultraBright
        self.ultraBrightBuiltInOnly = ultraBrightBuiltInOnly
        self.readDisplayControlValues = readDisplayControlValues
        self.showPresetsInMenu = showPresetsInMenu
        self.showAllDisplaySettingsInMenu = showAllDisplaySettingsInMenu
        self.frontPresetCount = frontPresetCount
        self.keyboardBrightnessControlsAllDisplays = keyboardBrightnessControlsAllDisplays
        self.keyboardVolumeControlsAllDisplays = keyboardVolumeControlsAllDisplays
        self.keyboardVolumeOnlyCurrentAudioOutput = keyboardVolumeOnlyCurrentAudioOutput
        self.keyboardTargetMode = keyboardTargetMode
        self.hudPosition = hudPosition
        self.preferPhysicalDisplayPowerOff = preferPhysicalDisplayPowerOff
        self.protocolDetectionSchemaVersion = protocolDetectionSchemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        anonymousAnalytics = try container.decodeIfPresent(Bool.self, forKey: .anonymousAnalytics) ?? false
        smoothTransitions = try container.decodeIfPresent(Bool.self, forKey: .smoothTransitions) ?? true
        modernIndicators = try container.decodeIfPresent(Bool.self, forKey: .modernIndicators) ?? true
        ultraBright = try container.decodeIfPresent(Bool.self, forKey: .ultraBright) ?? false
        ultraBrightBuiltInOnly = try container.decodeIfPresent(Bool.self, forKey: .ultraBrightBuiltInOnly) ?? false
        readDisplayControlValues = try container.decodeIfPresent(Bool.self, forKey: .readDisplayControlValues) ?? false
        showPresetsInMenu = try container.decodeIfPresent(Bool.self, forKey: .showPresetsInMenu) ?? true
        showAllDisplaySettingsInMenu = try container.decodeIfPresent(Bool.self, forKey: .showAllDisplaySettingsInMenu) ?? true
        frontPresetCount = try container.decodeIfPresent(Int.self, forKey: .frontPresetCount) ?? 5
        keyboardBrightnessControlsAllDisplays = try container.decodeIfPresent(Bool.self, forKey: .keyboardBrightnessControlsAllDisplays) ?? true
        keyboardVolumeControlsAllDisplays = try container.decodeIfPresent(Bool.self, forKey: .keyboardVolumeControlsAllDisplays) ?? true
        keyboardVolumeOnlyCurrentAudioOutput = try container.decodeIfPresent(Bool.self, forKey: .keyboardVolumeOnlyCurrentAudioOutput) ?? true
        keyboardTargetMode = try container.decodeIfPresent(KeyboardTargetMode.self, forKey: .keyboardTargetMode) ?? .allDisplays
        hudPosition = try container.decodeIfPresent(HUDPosition.self, forKey: .hudPosition) ?? .lowerCenter
        preferPhysicalDisplayPowerOff = try container.decodeIfPresent(Bool.self, forKey: .preferPhysicalDisplayPowerOff) ?? true
        protocolDetectionSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .protocolDetectionSchemaVersion) ?? 0
    }
}

enum HUDPosition: String, Codable, Hashable, CaseIterable, Identifiable {
    case lowerCenter
    case bottomCenter
    case topRight

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .lowerCenter:
            language.resolvedCode == "zh" ? "下方居中" : "Lower Center"
        case .bottomCenter:
            language.resolvedCode == "zh" ? "更靠下" : "Bottom Center"
        case .topRight:
            language.resolvedCode == "zh" ? "右上角" : "Top Right"
        }
    }
}

enum DisplayPowerOffKind: String, Codable, Hashable {
    case physical
    case displaySleep
    case softBlackout
}

enum KeyboardTargetMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case allDisplays
    case pointerDisplay

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .allDisplays:
            language.resolvedCode == "zh" ? "所有显示器" : "All Displays"
        case .pointerDisplay:
            language.resolvedCode == "zh" ? "鼠标所在显示器" : "Display Under Pointer"
        }
    }
}

struct DisplaySchedule: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var presetID: UUID?
    var timeText: String
    var isEnabled: Bool = true
    var lastRunDay: String?
}

struct DisplayPreset: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var displayModes: [DisplayPresetMode]
    var controlStates: [String: DisplayControlState] = [:]
    var syncSettings: DisplaySyncSettings = DisplaySyncSettings()
    var darkModeEnabled: Bool = false
    var nightShiftEnabled: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        displayModes: [DisplayPresetMode],
        controlStates: [String: DisplayControlState] = [:],
        syncSettings: DisplaySyncSettings = DisplaySyncSettings(),
        darkModeEnabled: Bool = false,
        nightShiftEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.displayModes = displayModes
        self.controlStates = controlStates
        self.syncSettings = syncSettings
        self.darkModeEnabled = darkModeEnabled
        self.nightShiftEnabled = nightShiftEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        displayModes = try container.decodeIfPresent([DisplayPresetMode].self, forKey: .displayModes) ?? []
        controlStates = try container.decodeIfPresent([String: DisplayControlState].self, forKey: .controlStates) ?? [:]
        syncSettings = try container.decodeIfPresent(DisplaySyncSettings.self, forKey: .syncSettings) ?? DisplaySyncSettings()
        darkModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .darkModeEnabled) ?? false
        nightShiftEnabled = try container.decodeIfPresent(Bool.self, forKey: .nightShiftEnabled) ?? false
    }
}

struct DisplayPresetMode: Codable, Hashable, Identifiable {
    var id: UInt32 { displayID }
    var displayID: UInt32
    var displayName: String
    var mode: DisplayMode
}

struct DisplaySyncSettings: Codable, Hashable {
    var isEnabled: Bool = false
    var leaderDisplayID: UInt32?
    var syncBrightness: Bool = true
    var syncContrast: Bool = true
    var syncVolume: Bool = false

    init(
        isEnabled: Bool = false,
        leaderDisplayID: UInt32? = nil,
        syncBrightness: Bool = true,
        syncContrast: Bool = true,
        syncVolume: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.leaderDisplayID = leaderDisplayID
        self.syncBrightness = syncBrightness
        self.syncContrast = syncContrast
        self.syncVolume = syncVolume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        leaderDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .leaderDisplayID)
        syncBrightness = try container.decodeIfPresent(Bool.self, forKey: .syncBrightness) ?? true
        syncContrast = try container.decodeIfPresent(Bool.self, forKey: .syncContrast) ?? true
        syncVolume = try container.decodeIfPresent(Bool.self, forKey: .syncVolume) ?? false
    }

    func isLeader(_ displayID: UInt32) -> Bool {
        leaderDisplayID == nil || leaderDisplayID == displayID
    }
}

struct DisplayMode: Codable, Hashable, Identifiable {
    var id: String { "\(modeID)-\(cgsModeNumber ?? -1)-\(width)x\(height)-\(pixelWidth)x\(pixelHeight)@\(refreshRate)-\(scaleDensity)-\(source.rawValue)" }
    var modeID: Int32
    var cgsModeNumber: Int32?
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
    var isHiDPI: Bool
    var scaleDensity: Double
    var source: DisplayModeSource

    init(
        modeID: Int32,
        cgsModeNumber: Int32?,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        isHiDPI: Bool,
        scaleDensity: Double,
        source: DisplayModeSource = .coreGraphics
    ) {
        self.modeID = modeID
        self.cgsModeNumber = cgsModeNumber
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isHiDPI = isHiDPI
        self.scaleDensity = scaleDensity
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modeID = try container.decode(Int32.self, forKey: .modeID)
        cgsModeNumber = try container.decodeIfPresent(Int32.self, forKey: .cgsModeNumber)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        refreshRate = try container.decode(Double.self, forKey: .refreshRate)
        isHiDPI = try container.decode(Bool.self, forKey: .isHiDPI)
        scaleDensity = try container.decodeIfPresent(Double.self, forKey: .scaleDensity) ?? (isHiDPI ? 2 : 1)
        source = try container.decodeIfPresent(DisplayModeSource.self, forKey: .source) ?? .coreGraphics
    }

    var label: String {
        let scale = isHiDPI ? "HiDPI" : "1x"
        return "\(width) x \(height) @ \(Int(refreshRate.rounded()))Hz \(scale)"
    }

    var detailLabel: String {
        "\(label) · framebuffer \(pixelWidth) x \(pixelHeight)"
    }

    var resolutionLabel: String {
        "\(width) x \(height)"
    }

    var resolutionWithAspectLabel: String {
        "\(resolutionLabel) · \(aspectRatioLabel)"
    }

    var aspectRatioLabel: String {
        let divisor = Self.greatestCommonDivisor(width, height)
        return "\(width / divisor):\(height / divisor)"
    }

    var refreshRateLabel: String {
        "\(Int(refreshRate.rounded()))Hz"
    }

    var menuLabel: String {
        "\(resolutionWithAspectLabel) @ \(refreshRateLabel)"
    }

    var pixelArea: Int {
        pixelWidth * pixelHeight
    }

    var depthScore: Int {
        pixelArea + Int(scaleDensity * 1_000)
    }

    func systemSettingsScore(currentMode: DisplayMode?) -> Int {
        var score = 0
        if let currentMode, matchesEffectiveMode(currentMode) {
            score += 100
        }
        if isHiDPI {
            score += 20
        }
        score += Int(refreshRate.rounded())
        score += min(pixelArea / 1_000_000, 20)
        return score
    }

    func matchesEffectiveMode(_ other: DisplayMode) -> Bool {
        modeID == other.modeID &&
        cgsModeNumber == other.cgsModeNumber &&
        width == other.width &&
        height == other.height &&
        pixelWidth == other.pixelWidth &&
        pixelHeight == other.pixelHeight &&
        Int(refreshRate.rounded()) == Int(other.refreshRate.rounded()) &&
        isHiDPI == other.isHiDPI &&
        abs(scaleDensity - other.scaleDensity) < 0.01
    }

    static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }
}

enum DisplayModeSource: String, Codable, Hashable {
    case coreGraphics
    case coreGraphicsCurrent
    case privateCGS

    func label(language: AppLanguage) -> String {
        switch self {
        case .coreGraphics:
            language.resolvedCode == "zh" ? "CoreGraphics 公开枚举" : "CoreGraphics public list"
        case .coreGraphicsCurrent:
            language.resolvedCode == "zh" ? "CoreGraphics 当前模式" : "CoreGraphics current mode"
        case .privateCGS:
            language.resolvedCode == "zh" ? "CGS 私有枚举" : "CGS private list"
        }
    }
}

struct CGRectCodable: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
