import ApplicationServices
import AppKit
import Foundation

enum KeyboardMediaAction {
    case brightnessUp
    case brightnessDown
    case volumeUp
    case volumeDown
    case mute
    case unknown(keyCode: Int32, keyState: Int32)
    case diagnostic(String)
}

final class KeyboardControlService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var handler: (@MainActor (KeyboardMediaAction) -> Void)?
    private var diagnosticHandler: (@MainActor (String) -> Void)?
    private var lastActionKey: String?
    private var lastActionTime: TimeInterval = 0

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func startMediaKeyMonitoring(handler: @escaping @MainActor (KeyboardMediaAction) -> Void) -> Bool {
        stopMediaKeyMonitoring()
        self.handler = handler
        self.diagnosticHandler = { message in
            handler(.diagnostic(message))
        }
        startNSEventFallbackMonitoring()

        let systemDefinedEventType = CGEventType(rawValue: 14)!
        let keyDownEventType = CGEventType.keyDown
        let mask = CGEventMask(1 << systemDefinedEventType.rawValue) | CGEventMask(1 << keyDownEventType.rawValue)

        let tapOptions: CGEventTapOptions = AXIsProcessTrusted() ? .defaultTap : .listenOnly
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: tapOptions,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            dispatchDiagnostic("亮度键监听：媒体键 Event Tap 启动失败，AX=\(AXIsProcessTrusted())")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        dispatchDiagnostic("亮度键监听：Event Tap 已启动，AX=\(AXIsProcessTrusted())，mode=\(tapOptions == .defaultTap ? "intercept" : "listen")")
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stopMediaKeyMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        handler = nil
        diagnosticHandler = nil
    }

    private func startNSEventFallbackMonitoring() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let action = Self.mediaAction(from: event) else { return }
            self?.dispatch(action)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let action = Self.mediaAction(from: event) else { return event }
            self?.dispatch(action)
            return event
        }
    }

    private func dispatch(_ action: KeyboardMediaAction) {
        guard let handler else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let actionKey = action.dedupeKey
        if lastActionKey == actionKey, now - lastActionTime < 0.08 {
            return
        }
        lastActionKey = actionKey
        lastActionTime = now
        Task { @MainActor in handler(action) }
    }

    private func dispatchDiagnostic(_ message: String) {
        guard let diagnosticHandler else { return }
        Task { @MainActor in diagnosticHandler(message) }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let service = Unmanaged<KeyboardControlService>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = service.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = Int32(event.getIntegerValueField(.keyboardEventKeycode))
            guard let action = functionKeyAction(keyCode: keyCode) else {
                return Unmanaged.passUnretained(event)
            }

            service.dispatchDiagnostic("亮度键事件：keyDown keyCode=\(keyCode)")
            service.dispatch(action)
            return AXIsProcessTrusted() ? nil : Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        let parsed = parseSystemDefinedEvent(nsEvent)
        guard let parsed else {
            return Unmanaged.passUnretained(event)
        }

        service.dispatchDiagnostic("媒体键事件：keyCode=\(parsed.keyCode), state=\(parsed.keyState)")
        guard let action = mediaAction(fromKeyCode: parsed.keyCode, keyState: parsed.keyState) else {
            service.dispatch(.unknown(keyCode: parsed.keyCode, keyState: parsed.keyState))
            return Unmanaged.passUnretained(event)
        }

        service.dispatch(action)
        switch action {
        case .brightnessUp, .brightnessDown:
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static func parseSystemDefinedEvent(_ event: NSEvent) -> (keyCode: Int32, keyState: Int32)? {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return nil }
        let keyCode = Int32((event.data1 & 0xFFFF0000) >> 16)
        let keyFlags = Int32(event.data1 & 0x0000FFFF)
        let keyState = (keyFlags & 0xFF00) >> 8
        return (keyCode, keyState)
    }

    private static func mediaAction(from event: NSEvent) -> KeyboardMediaAction? {
        guard let parsed = parseSystemDefinedEvent(event) else { return nil }
        return mediaAction(fromKeyCode: parsed.keyCode, keyState: parsed.keyState)
    }

    private static func mediaAction(fromKeyCode keyCode: Int32, keyState: Int32) -> KeyboardMediaAction? {
        guard keyState == 0x0A else { return nil }

        switch keyCode {
        case 0:
            return .volumeUp
        case 1:
            return .volumeDown
        case 2:
            return .brightnessUp
        case 3:
            return .brightnessDown
        case 7:
            return .mute
        default:
            return .unknown(keyCode: keyCode, keyState: keyState)
        }
    }

    private static func functionKeyAction(keyCode: Int32) -> KeyboardMediaAction? {
        switch keyCode {
        case 107, 122, 145:
            return .brightnessDown
        case 113, 120, 144:
            return .brightnessUp
        default:
            return nil
        }
    }

}

private extension KeyboardMediaAction {
    var dedupeKey: String {
        switch self {
        case .brightnessUp:
            "brightnessUp"
        case .brightnessDown:
            "brightnessDown"
        case .volumeUp:
            "volumeUp"
        case .volumeDown:
            "volumeDown"
        case .mute:
            "mute"
        case .unknown(let keyCode, let keyState):
            "unknown-\(keyCode)-\(keyState)"
        case .diagnostic(let message):
            "diagnostic-\(message)"
        }
    }
}
