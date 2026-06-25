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

    func preferenceRank(for mode: DisplayMode) -> Int {
        let preferredSizes: [(Int, Int)] = switch self {
        case .twoK:
            [(1920, 1080), (1680, 945), (1600, 900), (1440, 810), (1280, 720)]
        case .twoPointFiveK:
            [(1920, 1200), (1680, 1050), (1600, 1000), (1440, 900), (1280, 800), (1920, 1080), (1600, 900)]
        case .fourKOrAbove:
            [(2560, 1440), (2304, 1296), (2048, 1152), (1920, 1080)]
        case .lowResolution, .unknown:
            [(1920, 1080), (1680, 1050), (1600, 900), (1440, 900), (1280, 800), (1280, 720)]
        }

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

struct DisplayMode: Codable, Hashable, Identifiable {
    var id: String { "\(modeID)-\(width)x\(height)-\(pixelWidth)x\(pixelHeight)@\(refreshRate)" }
    var modeID: Int32
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
    var isHiDPI: Bool

    var label: String {
        let scale = isHiDPI ? "HiDPI" : "1x"
        return "\(width) x \(height) @ \(Int(refreshRate.rounded()))Hz \(scale)"
    }

    var detailLabel: String {
        "\(label) · framebuffer \(pixelWidth) x \(pixelHeight)"
    }

    var pixelArea: Int {
        pixelWidth * pixelHeight
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
