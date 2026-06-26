import CoreGraphics
import Foundation

struct CGSDisplayModeDescription: Hashable {
    var modeNumber: UInt32
    var flags: UInt32
    var width: UInt32
    var height: UInt32
    var depth: UInt32
    var refreshRate: UInt16
    var density: Float
}

enum CGSDisplayModeAPI {
    private static let modeDescriptionLength = 256

    static func currentModeNumber(for displayID: CGDirectDisplayID) -> Int32? {
        var modeNumber: Int32 = -1
        let error = CGSGetCurrentDisplayMode(displayID, &modeNumber)
        guard error == .success, modeNumber >= 0 else { return nil }
        return modeNumber
    }

    static func displayModes(for displayID: CGDirectDisplayID) -> [CGSDisplayModeDescription]? {
        var count: Int32 = 0
        guard CGSGetNumberOfDisplayModes(displayID, &count) == .success, count > 0 else {
            return nil
        }

        return (0..<count).compactMap { index in
            var data = Data(repeating: 0, count: modeDescriptionLength)
            let error = data.withUnsafeMutableBytes { buffer in
                CGSGetDisplayModeDescriptionOfLength(displayID, index, buffer.baseAddress!, Int32(modeDescriptionLength))
            }
            guard error == .success else { return nil }

            return CGSDisplayModeDescription(
                modeNumber: data.readValue(at: 0, as: UInt32.self),
                flags: data.readValue(at: 4, as: UInt32.self),
                width: data.readValue(at: 8, as: UInt32.self),
                height: data.readValue(at: 12, as: UInt32.self),
                depth: data.readValue(at: 16, as: UInt32.self),
                refreshRate: data.readValue(at: 190, as: UInt16.self),
                density: data.readValue(at: 208, as: Float.self)
            )
        }
    }

    static func applyModeNumber(_ modeNumber: Int32, to displayID: CGDirectDisplayID, persist: Bool) throws {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            throw MonitorControlError.unsupported(L10n.t("error.configBegin", .system))
        }

        let configure = CGSConfigureDisplayMode(config, displayID, modeNumber)
        guard configure == .success else {
            CGCancelDisplayConfiguration(config)
            throw MonitorControlError.unsupported(L10n.t("error.configMode", .system))
        }

        let complete = CGCompleteDisplayConfiguration(config, persist ? .permanently : .forSession)
        guard complete == .success else {
            throw MonitorControlError.unsupported(L10n.t("error.configApply", .system))
        }
    }
}

private extension Data {
    func readValue<T>(at offset: Int, as type: T.Type) -> T {
        withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: T.self)
        }
    }
}

@_silgen_name("CGSGetCurrentDisplayMode")
private func CGSGetCurrentDisplayMode(_ display: CGDirectDisplayID, _ modeNumber: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSGetNumberOfDisplayModes")
private func CGSGetNumberOfDisplayModes(_ display: CGDirectDisplayID, _ count: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSGetDisplayModeDescriptionOfLength")
private func CGSGetDisplayModeDescriptionOfLength(
    _ display: CGDirectDisplayID,
    _ index: Int32,
    _ mode: UnsafeMutableRawPointer,
    _ length: Int32
) -> CGError

@_silgen_name("CGSConfigureDisplayMode")
private func CGSConfigureDisplayMode(
    _ config: CGDisplayConfigRef,
    _ display: CGDirectDisplayID,
    _ modeNumber: Int32
) -> CGError
