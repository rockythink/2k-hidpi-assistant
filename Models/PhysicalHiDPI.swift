import Foundation

struct DisplayOverrideKey: Codable, Hashable {
    let vendorID: UInt32
    let productID: UInt32

    init(display: DisplayDevice) {
        vendorID = display.vendorID
        productID = display.modelID
    }

    var vendorDirectory: String { "DisplayVendorID-" + String(vendorID, radix: 16) }
    var productFile: String { "DisplayProductID-" + String(productID, radix: 16) }
    var identifier: String { vendorDirectory + "/" + productFile }
}

struct PhysicalHiDPIStatus: Equatable {
    enum Phase: String, Codable { case notInstalled, installed, restored, conflict }
    var phase: Phase = .notInstalled
    var target: DisplayResolutionTarget?
    var nativeResolution: DisplayResolutionTarget?
    var problem: String?
    var canRestore: Bool { phase == .installed }
}

struct PhysicalHiDPIPlan {
    let key: DisplayOverrideKey
    let target: DisplayResolutionTarget
    let nativeResolution: DisplayResolutionTarget
    let expectedInstalledData: Data?
    let generatedData: Data
}

struct PhysicalHiDPIRequest: Identifiable {
    enum Operation { case install, restore }
    let id = UUID()
    let operation: Operation
    let display: DisplayDevice
    let target: DisplayResolutionTarget
    let matchingDisplayCount: Int
    var key: DisplayOverrideKey { DisplayOverrideKey(display: display) }
}
