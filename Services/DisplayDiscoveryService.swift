import AppKit
import CoreGraphics
import Foundation
import IOKit

struct DisplayDiscoveryService {
    func discover(language: AppLanguage) -> [DisplayDevice] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)

        var ids = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)

        return ids.map { id in
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            let mode = CGDisplayCopyDisplayMode(id).map(makeMode)
            let modes = availableModes(for: id)
            let frame = CGDisplayBounds(id)
            return DisplayDevice(
                id: id,
                name: displayName(
                    for: id,
                    fallback: isBuiltin ? L10n.t("display.builtin", language) : L10n.t("display.external", language)
                ),
                vendorID: CGDisplayVendorNumber(id),
                modelID: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                isBuiltin: isBuiltin,
                isOnline: CGDisplayIsOnline(id) != 0,
                frame: CGRectCodable(frame),
                currentMode: mode,
                availableModes: modes,
                rotation: CGDisplayRotation(id)
            )
        }
    }

    private func makeMode(_ mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(
            modeID: mode.ioDisplayModeID,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate == 0 ? 60 : mode.refreshRate,
            isHiDPI: mode.pixelWidth > mode.width || mode.pixelHeight > mode.height
        )
    }

    private func availableModes(for id: CGDirectDisplayID) -> [DisplayMode] {
        let options = [
            kCGDisplayShowDuplicateLowResolutionModes as String: true
        ] as CFDictionary

        guard let rawModes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else {
            return []
        }

        let modes = rawModes.map(makeMode)
        var seen = Set<String>()
        return modes
            .filter { mode in
                let key = "\(mode.modeID)-\(mode.width)-\(mode.height)-\(mode.pixelWidth)-\(mode.pixelHeight)-\(Int(mode.refreshRate.rounded()))"
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            .sorted { lhs, rhs in
                if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI && !rhs.isHiDPI }
                if lhs.width != rhs.width { return lhs.width > rhs.width }
                if lhs.height != rhs.height { return lhs.height > rhs.height }
                return lhs.refreshRate > rhs.refreshRate
            }
    }

    private func displayName(for id: CGDirectDisplayID, fallback: String) -> String {
        guard let info = displayInfoDictionary(for: id),
              let productNames = info[kDisplayProductName as String] as? [String: String] else {
            return fallback
        }
        return productNames.values.first ?? fallback
    }

    private func displayInfoDictionary(for id: CGDirectDisplayID) -> [String: Any]? {
        let matching = IOServiceMatching("IODisplayConnect")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let info = IODisplayCreateInfoDictionary(service, UInt32(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any] else {
                continue
            }

            let vendor = info[kDisplayVendorID as String] as? UInt32
            let product = info[kDisplayProductID as String] as? UInt32
            if vendor == CGDisplayVendorNumber(id), product == CGDisplayModelNumber(id) {
                return info
            }
        }

        return nil
    }
}
