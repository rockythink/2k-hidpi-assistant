import CoreGraphics
import Darwin
import Foundation

struct AppleDisplayBrightnessService {
    private typealias GetBrightnessFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let getBrightnessFunction: GetBrightnessFunction? = {
        symbol(named: "DisplayServicesGetBrightness", as: GetBrightnessFunction.self)
    }()

    private static let setBrightnessFunction: SetBrightnessFunction? = {
        symbol(named: "DisplayServicesSetBrightness", as: SetBrightnessFunction.self)
    }()

    private static func symbol<T>(named name: String, as type: T.Type) -> T? {
        let candidates = [
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
        ]

        for candidate in candidates {
            guard let handle = dlopen(candidate, RTLD_LAZY | RTLD_LOCAL) else { continue }
            if let symbol = dlsym(handle, name) {
                return unsafeBitCast(symbol, to: type)
            }
        }

        return nil
    }

    func brightness(for displayID: CGDirectDisplayID) -> Double? {
        guard let getBrightness = Self.getBrightnessFunction else { return nil }
        var value: Float = 0
        let result = getBrightness(displayID, &value)
        guard result == 0 else { return nil }
        return Double(value).clamped(to: 0...1)
    }

    func setBrightness(_ value: Double, for displayID: CGDirectDisplayID) throws {
        guard let setBrightness = Self.setBrightnessFunction else {
            throw DisplayPowerError.commandFailed("当前系统没有可用的 Apple Display Protocol 写入入口。")
        }

        let result = setBrightness(displayID, Float(value.clamped(to: 0...1)))
        guard result == 0 else {
            throw DisplayPowerError.commandFailed("Apple Display Protocol 写入失败：\(result)。")
        }
    }
}
