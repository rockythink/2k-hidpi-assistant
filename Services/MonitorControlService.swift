import CoreGraphics
import Foundation

struct MonitorControlService {
    func applyResolution(_ mode: DisplayMode, rotation: Double, for display: DisplayDevice, persist: Bool) throws {
        guard let cgMode = findCGMode(mode, for: display.id) else {
            throw MonitorControlError.unsupported(L10n.t("error.modeUnavailable", .system))
        }

        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            throw MonitorControlError.unsupported(L10n.t("error.configBegin", .system))
        }

        let configure = CGConfigureDisplayWithDisplayMode(config, display.id, cgMode, nil)
        guard configure == .success else {
            CGCancelDisplayConfiguration(config)
            throw MonitorControlError.unsupported(L10n.t("error.configMode", .system))
        }

        let complete = CGCompleteDisplayConfiguration(config, persist ? .permanently : .forSession)
        guard complete == .success else {
            throw MonitorControlError.unsupported(L10n.t("error.configApply", .system))
        }
    }

    private func findCGMode(_ target: DisplayMode, for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        let options = [
            kCGDisplayShowDuplicateLowResolutionModes as String: true
        ] as CFDictionary

        guard let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return nil
        }

        return modes.first { mode in
            mode.ioDisplayModeID == target.modeID &&
            mode.width == target.width &&
            mode.height == target.height &&
            mode.pixelWidth == target.pixelWidth &&
            mode.pixelHeight == target.pixelHeight
        }
    }
}

enum MonitorControlError: LocalizedError {
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message):
            message
        }
    }
}
