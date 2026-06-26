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
            let modes = availableModes(for: id)
            let mode = currentMode(for: id, availableModes: modes) ?? CGDisplayCopyDisplayMode(id).map { makeMode($0, source: .coreGraphicsCurrent) }
            let frame = CGDisplayBounds(id)
            let info = displayInfoDictionary(for: id)
            let metadata = makeMetadata(for: id, info: info)
            return DisplayDevice(
                id: id,
                name: displayName(
                    for: id,
                    info: info,
                    fallback: isBuiltin ? L10n.t("display.builtin", language) : L10n.t("display.external", language)
                ),
                vendorID: CGDisplayVendorNumber(id),
                modelID: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                metadata: metadata,
                isBuiltin: isBuiltin,
                isOnline: CGDisplayIsOnline(id) != 0,
                frame: CGRectCodable(frame),
                currentMode: mode,
                availableModes: modes,
                rotation: CGDisplayRotation(id)
            )
        }
    }

    private func makeMetadata(for id: CGDirectDisplayID, info: [String: Any]?) -> DisplayMetadata {
        let size = CGDisplayScreenSize(id)
        return DisplayMetadata(
            productName: productName(from: info),
            vendorID: CGDisplayVendorNumber(id),
            productID: CGDisplayModelNumber(id),
            serialNumber: CGDisplaySerialNumber(id),
            manufactureWeek: readUInt32(info?[kDisplayWeekOfManufacture as String]),
            manufactureYear: readUInt32(info?[kDisplayYearOfManufacture as String]),
            physicalWidthMM: size.width,
            physicalHeightMM: size.height,
            unitNumber: CGDisplayUnitNumber(id),
            colorSpaceName: displayColorSpaceName(for: id),
            isMain: CGDisplayIsMain(id) != 0,
            isActive: CGDisplayIsActive(id) != 0
        )
    }

    private func displayColorSpaceName(for id: CGDirectDisplayID) -> String? {
        guard let name = CGDisplayCopyColorSpace(id).name else {
            return nil
        }
        return name as String
    }

    private func makeMode(_ mode: CGDisplayMode, source: DisplayModeSource = .coreGraphics) -> DisplayMode {
        DisplayMode(
            modeID: mode.ioDisplayModeID,
            cgsModeNumber: nil,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate == 0 ? 60 : mode.refreshRate,
            isHiDPI: mode.pixelWidth > mode.width || mode.pixelHeight > mode.height,
            scaleDensity: mode.pixelWidth > mode.width || mode.pixelHeight > mode.height ? 2 : 1,
            source: source
        )
    }

    private func makeMode(_ mode: CGSDisplayModeDescription) -> DisplayMode {
        let density = mode.density > 0 ? Double(mode.density) : 1
        return DisplayMode(
            modeID: Int32(mode.modeNumber),
            cgsModeNumber: Int32(mode.modeNumber),
            width: Int(mode.width),
            height: Int(mode.height),
            pixelWidth: Int((Double(mode.width) * density).rounded()),
            pixelHeight: Int((Double(mode.height) * density).rounded()),
            refreshRate: mode.refreshRate == 0 ? 60 : Double(mode.refreshRate),
            isHiDPI: density > 1.5,
            scaleDensity: density,
            source: .privateCGS
        )
    }

    private func availableModes(for id: CGDirectDisplayID) -> [DisplayMode] {
        let privateModes = privateDisplayModes(for: id)
        if !privateModes.isEmpty {
            return privateModes
        }

        let options = [
            kCGDisplayShowDuplicateLowResolutionModes as String: true
        ] as CFDictionary

        guard let rawModes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else {
            return []
        }

        let modes = rawModes.map { makeMode($0) }
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

    private func currentMode(for id: CGDirectDisplayID, availableModes: [DisplayMode]) -> DisplayMode? {
        guard let currentModeNumber = CGSDisplayModeAPI.currentModeNumber(for: id) else {
            return nil
        }
        return availableModes.first { $0.cgsModeNumber == currentModeNumber }
    }

    private func privateDisplayModes(for id: CGDirectDisplayID) -> [DisplayMode] {
        guard let descriptions = CGSDisplayModeAPI.displayModes(for: id), !descriptions.isEmpty else {
            return []
        }

        let modes = descriptions.map(makeMode)
        var seen = Set<String>()
        return modes
            .filter { mode in
                guard mode.width >= 400, mode.height >= 300 else { return false }
                let key = "\(mode.cgsModeNumber ?? mode.modeID)-\(mode.width)-\(mode.height)-\(mode.pixelWidth)-\(mode.pixelHeight)-\(Int(mode.refreshRate.rounded()))-\(mode.isHiDPI)"
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            .sorted { lhs, rhs in
                if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI && !rhs.isHiDPI }
                if lhs.width != rhs.width { return lhs.width > rhs.width }
                if lhs.height != rhs.height { return lhs.height > rhs.height }
                if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
                return lhs.scaleDensity > rhs.scaleDensity
            }
    }

    private func displayName(for id: CGDirectDisplayID, info: [String: Any]?, fallback: String) -> String {
        guard let name = productName(from: info) else {
            return fallback
        }
        return name
    }

    private func productName(from info: [String: Any]?) -> String? {
        guard let productNames = info?[kDisplayProductName as String] as? [String: String] else {
            return nil
        }
        return productNames.values.first
    }

    private func readUInt32(_ value: Any?) -> UInt32? {
        switch value {
        case let number as UInt32:
            number
        case let number as Int:
            UInt32(number)
        case let number as NSNumber:
            number.uint32Value
        default:
            nil
        }
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

            guard let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as? [String: Any] else {
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
