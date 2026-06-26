import CoreGraphics
import Foundation

struct DisplayProtocolDetector {
    private let nativeDDC = NativeDDCService()
    private let appleBrightness = AppleDisplayBrightnessService()

    func detect(display: DisplayDevice) -> DisplayProtocolDetection {
        if display.isBuiltin || appleBrightness.brightness(for: display.id) != nil {
            return DisplayProtocolDetection(
                controlMode: .appleDisplayProtocol,
                isHardwareControl: true,
                reason: display.isBuiltin ? .builtinApple : .appleBrightness
            )
        }

        if let backend = nativeDDC.preferredBackendID(for: display) {
            return DisplayProtocolDetection(
                controlMode: .ddcCI,
                isHardwareControl: true,
                reason: backend == .appleSiliconIOAVService ? .appleSiliconDDC : .framebufferDDC
            )
        }

        if display.metadata.isLikelySmartDisplay {
            return DisplayProtocolDetection(
                controlMode: .samsungSmart,
                isHardwareControl: false,
                reason: .vendorSmartDisplay
            )
        }

        return DisplayProtocolDetection(
            controlMode: .software,
            isHardwareControl: false,
            reason: .softwareFallback
        )
    }

}

struct DisplayProtocolDetection: Codable, Hashable {
    var controlMode: DisplayControlMode
    var isHardwareControl: Bool
    var reason: DisplayProtocolDetectionReason
}

enum DisplayProtocolDetectionReason: String, Codable, Hashable {
    case builtinApple
    case appleBrightness
    case appleSiliconDDC
    case framebufferDDC
    case vendorSmartDisplay
    case softwareFallback

    func label(language: AppLanguage) -> String {
        guard language.resolvedCode == "zh" else {
            switch self {
            case .builtinApple:
                return "built-in Apple display"
            case .appleBrightness:
                return "Apple brightness API is available"
            case .appleSiliconDDC:
                return "Apple Silicon DDC via DCPAVServiceProxy"
            case .framebufferDDC:
                return "Framebuffer DDC/I2C is available"
            case .vendorSmartDisplay:
                return "smart display vendor detected"
            case .softwareFallback:
                return "no hardware protocol is available"
            }
        }

        switch self {
        case .builtinApple:
            return "内建 Apple 显示器"
        case .appleBrightness:
            return "可用 Apple 亮度协议"
        case .appleSiliconDDC:
            return "Apple Silicon DDC（DCPAVServiceProxy）"
        case .framebufferDDC:
            return "Framebuffer DDC/I2C"
        case .vendorSmartDisplay:
            return "识别到智能显示器厂商"
        case .softwareFallback:
            return "未检测到可用硬件协议"
        }
    }
}

private extension DisplayMetadata {
    var isLikelySmartDisplay: Bool {
        let vendorName = productName?.lowercased() ?? ""
        return vendorID == 0x4C2D
            || vendorID == 0x1E6D
            || vendorName.contains("samsung")
            || vendorName.contains("lg")
            || vendorName.contains("smart monitor")
    }
}
