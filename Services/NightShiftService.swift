import Foundation
import ObjectiveC

struct NightShiftService {
    func status() throws -> NightShiftStatus {
        let rawStatus = try readRawStatus()
        return NightShiftStatus(isScheduled: rawStatus.enabled, isActive: rawStatus.active)
    }

    func isActive() throws -> Bool {
        try status().isActive
    }

    func setEnabled(_ enabled: Bool) throws {
        let client = try makeClient()
        let selector = NSSelectorFromString("setEnabled:")
        guard client.responds(to: selector) else {
            throw NightShiftError.selectorUnavailable
        }

        let ok = objc_msgSend_bool_bool(client, selector, enabled)
        guard ok else {
            throw NightShiftError.setFailed
        }
    }

    private func readRawStatus() throws -> BlueLightStatus {
        let client = try makeClient()
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector) else {
            throw NightShiftError.selectorUnavailable
        }

        var status = BlueLightStatus()
        let ok = withUnsafeMutablePointer(to: &status) { pointer in
            objc_msgSend_bool_rawPointer(client, selector, UnsafeMutableRawPointer(pointer))
        }
        guard ok else {
            throw NightShiftError.statusUnavailable
        }

        return status
    }

    private func makeClient() throws -> NSObject {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              bundle.load() else {
            throw NightShiftError.frameworkUnavailable
        }

        guard let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            throw NightShiftError.clientUnavailable
        }

        return clientClass.init()
    }
}

struct NightShiftStatus {
    var isScheduled: Bool
    var isActive: Bool
}

enum NightShiftError: LocalizedError {
    case frameworkUnavailable
    case clientUnavailable
    case selectorUnavailable
    case statusUnavailable
    case setFailed

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            "无法加载 CoreBrightness.framework。"
        case .clientUnavailable:
            "无法创建 Night Shift 客户端。"
        case .selectorUnavailable:
            "当前系统不支持 Night Shift 开关接口。"
        case .statusUnavailable:
            "无法读取 Night Shift 当前状态。"
        case .setFailed:
            "系统拒绝切换 Night Shift。"
        }
    }
}

private struct BlueLightTime {
    var hour: Int32 = 0
    var minute: Int32 = 0
}

private struct BlueLightSchedule {
    var start: BlueLightTime = BlueLightTime()
    var end: BlueLightTime = BlueLightTime()
}

private struct BlueLightStatus {
    var enabled: Bool = false
    var active: Bool = false
    var available: Bool = false
    var mode: Int32 = 0
    var schedule: BlueLightSchedule = BlueLightSchedule()
    var disableFlags: UInt64 = 0
    var sunSchedulePermitted: Bool = false
}

private let objc_msgSend_bool_bool: @convention(c) (AnyObject, Selector, Bool) -> Bool = {
    let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
    return unsafeBitCast(symbol, to: (@convention(c) (AnyObject, Selector, Bool) -> Bool).self)
}()

private let objc_msgSend_bool_rawPointer: @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool = {
    let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
    return unsafeBitCast(symbol, to: (@convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool).self)
}()
