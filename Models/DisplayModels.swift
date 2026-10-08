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
        if let panel = metadata.panelResolution {
            return availableModes.lazy.filter {
                !$0.isHiDPI && $0.pixelWidth == panel.width && $0.pixelHeight == panel.height
            }.max { $0.refreshRate < $1.refreshRate }
        }
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
        guard let nativeMode else { return [] }
        let targets = preferredHiDPITargets
        func rank(_ mode: DisplayMode) -> Int {
            targets.firstIndex { $0.width == mode.width && $0.height == mode.height }
                ?? targets.count + abs(mode.width - 1600) / 100
        }
        return availableModes.filter {
            $0.isHiDPI && $0.width * nativeMode.pixelHeight == $0.height * nativeMode.pixelWidth
        }.sorted { lhs, rhs in
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
            return lhs.pixelArea > rhs.pixelArea
        }.reduce(into: [DisplayMode]()) { result, mode in
            guard !result.contains(where: { $0.width == mode.width && $0.height == mode.height }) else { return }
            result.append(mode)
        }.prefix(5).map { $0 }
    }

    var unavailableRecommendedHiDPITargets: [DisplayResolutionTarget] {
        preferredHiDPITargets.filter { target in
            !availableModes.contains { $0.isHiDPI && $0.width == target.width && $0.height == target.height }
        }.prefix(4).map { $0 }
    }

    var virtualHiDPITargets: [DisplayResolutionTarget] {
        guard isOnline, !isBuiltin, rotation.truncatingRemainder(dividingBy: 360) == 0,
              let nativeMode, nativeMode.pixelWidth > 0, nativeMode.pixelHeight > 0,
              nativeMode.pixelWidth * 5 == nativeMode.pixelHeight * 8 else { return [] }
        return [
            DisplayResolutionTarget(width: 1440, height: 900),
            DisplayResolutionTarget(width: 1600, height: 1000),
            DisplayResolutionTarget(width: 1680, height: 1050),
            DisplayResolutionTarget(width: 1920, height: 1200)
        ].filter { target in
            target.width > nativeMode.pixelWidth / 2 &&
            target.width <= nativeMode.pixelWidth && target.height <= nativeMode.pixelHeight &&
            !availableModes.contains { $0.isHiDPI && $0.width == target.width && $0.height == target.height }
        }
    }

    var hiDPIResolutionChoices: HiDPIResolutionChoices {
        guard let native = nativeMode else { return HiDPIResolutionChoices(all: [], recommended: [], nativeMode: nil, systemModes: []) }
        let modes = systemScaledModes
        let systemTargets = modes.compactMap { mode -> DisplayResolutionTarget? in
            guard mode.isHiDPI, mode.width * native.pixelHeight == mode.height * native.pixelWidth else { return nil }
            return DisplayResolutionTarget(width: mode.width, height: mode.height)
        }
        let available = Set(systemTargets)
        let all = available.sorted { $0.width == $1.width ? $0.height > $1.height : $0.width > $1.width }
        var recommended = preferredHiDPITargets.filter { available.contains($0) }
        if let current = currentMode, current.isHiDPI {
            let target = DisplayResolutionTarget(width: current.width, height: current.height)
            if available.contains(target), !recommended.contains(target) { recommended.insert(target, at: 0) }
        }
        return HiDPIResolutionChoices(all: all, recommended: recommended, nativeMode: native, systemModes: modes)
    }

    private var preferredHiDPITargets: [DisplayResolutionTarget] {
        guard let nativeMode else { return [] }
        let isPortrait = nativeMode.pixelWidth < nativeMode.pixelHeight
        let width = max(nativeMode.pixelWidth, nativeMode.pixelHeight)
        let height = min(nativeMode.pixelWidth, nativeMode.pixelHeight)
        let sizes: [(Int, Int)]
        if width * 9 == height * 16 {
            switch displayClass {
            case .twoK:
                sizes = [(1280, 720), (1600, 900), (1920, 1080), (1680, 945), (1440, 810)]
            case .fourKOrAbove:
                sizes = [(2560, 1440), (2304, 1296), (2048, 1152), (1920, 1080)]
            case .twoPointFiveK, .lowResolution, .unknown:
                sizes = [(1920, 1080), (1600, 900), (1280, 720)]
            }
        } else if width * 5 == height * 8 {
            if displayClass == .fourKOrAbove {
                sizes = [(2560, 1600), (2304, 1440), (2048, 1280), (1920, 1200)]
            } else {
                sizes = [(1920, 1200), (1680, 1050), (1600, 1000), (1440, 900), (1280, 800)]
            }
        } else if width.isMultiple(of: 2), height.isMultiple(of: 2) {
            sizes = [(width / 2, height / 2)]
        } else {
            sizes = []
        }
        return sizes.filter { $0.0 <= width && $0.1 <= height }.map { size in
            DisplayResolutionTarget(width: isPortrait ? size.1 : size.0, height: isPortrait ? size.0 : size.1)
        }
    }

    var physicalHiDPIProbeTarget: DisplayResolutionTarget? {
        guard isOnline, !isBuiltin, vendorID != 0, modelID != 0,
              rotation.truncatingRemainder(dividingBy: 360) == 0,
              let native = nativeMode, native.pixelWidth == 2560, native.pixelHeight == 1600 else { return nil }
        return DisplayResolutionTarget(width: 1600, height: 1000)
    }
}

struct HiDPIResolutionChoices {
    let all: [DisplayResolutionTarget]
    let recommended: [DisplayResolutionTarget]
    let nativeMode: DisplayMode?
    let systemModes: [DisplayMode]
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
        DisplayMode.aspectRatioLabel(width: width, height: height)
    }
}

struct DisplayMetadata: Codable, Hashable {
    var panelResolution: DisplayResolutionTarget? = nil
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

}

struct PendingDisplayModeChange: Codable, Hashable {
    var displayID: UInt32
    var previousMode: DisplayMode
    var targetMode: DisplayMode
    var remainingSeconds: Int
}

struct DisplayPreset: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var displayModes: [DisplayPresetMode]

    init(id: UUID = UUID(), name: String, displayModes: [DisplayPresetMode]) {
        self.id = id
        self.name = name
        self.displayModes = displayModes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        displayModes = try container.decodeIfPresent([DisplayPresetMode].self, forKey: .displayModes) ?? []
    }
}

struct DisplayPresetMode: Codable, Hashable, Identifiable {
    var id: UInt32 { displayID }
    var displayID: UInt32
    var displayName: String
    var mode: DisplayMode
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
        Self.aspectRatioLabel(width: width, height: height)
    }

    static func aspectRatioLabel(width: Int, height: Int) -> String {
        if width > 0, height > 0, width * 5 == height * 8 { return "16:10" }
        let divisor = greatestCommonDivisor(width, height)
        return "\(width / divisor):\(height / divisor)"
    }

    var refreshRateLabel: String {
        "\(Int(refreshRate.rounded()))Hz"
    }

    var menuLabel: String {
        "\(resolutionWithAspectLabel) @ \(refreshRateLabel)"
    }

    func sharpnessLabel(nativeMode: DisplayMode?, language: AppLanguage) -> String? {
        guard isHiDPI, let nativeMode else { return nil }
        let widthScale = Double(pixelWidth) / Double(max(nativeMode.pixelWidth, 1))
        let heightScale = Double(pixelHeight) / Double(max(nativeMode.pixelHeight, 1))
        guard abs(widthScale - heightScale) < 0.02 else {
            return language.resolvedCode == "zh" ? "非等比缩放" : "Uneven scale"
        }
        if abs(widthScale - 1) < 0.02 {
            return language.resolvedCode == "zh" ? "像素匹配" : "Pixel matched"
        }
        if abs(widthScale.rounded() - widthScale) < 0.02 {
            return language.resolvedCode == "zh" ? "整数缩放" : "Integer scale"
        }
        return language.resolvedCode == "zh" ? "可能偏软" : "May soften text"
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
