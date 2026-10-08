import Darwin
import Foundation
import Testing
@testable import PixelFit

@Suite("Physical HiDPI configuration", .serialized)
struct PhysicalHiDPIConfigurationTests {
    private let target = DisplayResolutionTarget(width: 1600, height: 1000)
    private let native = DisplayResolutionTarget(width: 2560, height: 1600)

    @Test func preservesFieldsAndExistingScaleEntries() throws {
        let key = DisplayOverrideKey(display: display())
        let opaque = Data([0xFF, 0, 3])
        let companion = Data([0, 0, 12, 128, 0, 0, 7, 208])
        let original: [String: Any] = ["DisplayVendorID": key.vendorID, "DisplayProductID": key.productID,
                                       "DisplayProductName": ["en_US": "Sculptor"],
                                       "IODisplayEDID": Data([1, 2, 3]), "unknown-field": ["nested": true],
                                       "scale-resolutions": [opaque, companion], "target-default-ppmm": 12.34]
        let bytes = try plist(original)
        let generated = try PhysicalHiDPIConfiguration.generate(existing: bytes, key: key, target: target, native: native)
        let fields = try #require(PropertyListSerialization.propertyList(from: generated, format: nil) as? [String: Any])
        #expect(fields["IODisplayEDID"] as? Data == Data([1, 2, 3]))
        #expect(fields["DisplayProductName"] as? [String: String] == ["en_US": "Sculptor"])
        #expect(fields["unknown-field"] as? [String: Bool] == ["nested": true])
        #expect(fields["target-default-ppmm"] as? Double == 12.34)
        let entries = try #require(fields["scale-resolutions"] as? [Data])
        #expect(entries == [opaque, companion])
        #expect(fields["DisplayPixelDimensions"] as? Data == Data([0, 0, 10, 0, 0, 0, 6, 64]))
        let repeated = try PhysicalHiDPIConfiguration.generate(existing: generated, key: key, target: target, native: native)
        #expect(repeated == generated)
    }
    @Test func encodesPhysicalPanelAndDoubleRenderPixels() throws {
        let generated = try PhysicalHiDPIConfiguration.generate(existing: nil, key: DisplayOverrideKey(display: display()),
                                                                target: target, native: native)
        let fields = try #require(PropertyListSerialization.propertyList(from: generated, format: nil) as? [String: Any])
        #expect(fields["DisplayPixelDimensions"] as? Data == Data([0, 0, 10, 0, 0, 0, 6, 64]))
        #expect(fields["scale-resolutions"] as? [Data] == [Data([0, 0, 12, 128, 0, 0, 7, 208])])
    }

    @Test func rejectsMalformedOrAmbiguousPlists() throws {
        let invalid: [Any] = [[], [["DisplayVendorID": 1], ["DisplayVendorID": 1]],
                              ["DisplayVendorID": "4660"], ["DisplayVendorID": true],
                              ["DisplayVendorID": 99], ["DisplayProductID": 99],
                              ["scale-resolutions": "wrong"], ["scale-resolutions": [Data(), "wrong"]],
                              ["target-default-ppmm": "10"], ["target-default-ppmm": -1],
                              ["DisplayPixelDimensions": "wrong"], ["DisplayPixelDimensions": Data([1, 2, 3])],
                              ["DisplayPixelDimensions": Data([0, 0, 7, 128, 0, 0, 4, 56])]]
        for object in invalid {
            let bytes = try plist(object)
            #expect(throws: (any Error).self) {
                try PhysicalHiDPIConfiguration.generate(existing: bytes, key: DisplayOverrideKey(display: display()),
                                                        target: target, native: native)
            }
        }
        #expect(throws: (any Error).self) {
            try PhysicalHiDPIConfiguration.generate(existing: Data("not a plist".utf8),
                                                    key: DisplayOverrideKey(display: display()), target: target, native: native)
        }
    }

    @Test func rejectsInvalidDimensionsBeforeArithmetic() {
        for dimensions in [DisplayResolutionTarget(width: 0, height: 0), .init(width: -1600, height: -1000),
                           .init(width: Int.max, height: Int.max), .init(width: 1600, height: 900),
                           .init(width: 8192, height: 5120)] {
            #expect(throws: (any Error).self) {
                try PhysicalHiDPIConfiguration.validate(target: dimensions, native: native)
            }
        }
        #expect(throws: (any Error).self) {
            try PhysicalHiDPIConfiguration.validate(target: target, native: .init(width: Int.max, height: 1600))
        }
    }

    @Test(arguments: [false, true])
    func realInstallAndExactRestore(originalExists: Bool) async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let service = sandbox.service
        let key = DisplayOverrideKey(display: display())
        let original = try plist(["DisplayProductName": ["en_US": "Original"], "opaque": Data([5, 7, 9])])
        if originalExists { try sandbox.write(original, to: sandbox.product(key)) }
        let sibling = sandbox.product(DisplayOverrideKey(display: display(product: 0x5679)))
        try sandbox.write(Data("untouched sibling".utf8), to: sibling)
        let plan = try service.prepare(for: display(), target: target)
        #expect(plan.expectedInstalledData == (originalExists ? original : nil))
        try await service.install(plan)
        #expect(try Data(contentsOf: sandbox.product(key)) == plan.generatedData)
        let installed = try service.status(for: key)
        #expect(installed.phase == .installed)
        #expect(installed.nativeResolution == native)
        #expect(installed.target == target)
        let receiptPath = sandbox.state.appendingPathComponent(key.vendorDirectory + "-" + key.productFile + ".json")
        let receipt = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: receiptPath)) as? [String: Any])
        #expect((receipt["originalData"] as? String).flatMap { Data(base64Encoded: $0) } == (originalExists ? original : nil))
        var info = stat()
        #expect(lstat(receiptPath.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o644)
        #expect(lstat(sandbox.state.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o755)
        try await service.restore(for: key)
        #expect(try service.status(for: key).phase == .restored)
        if originalExists { #expect(try Data(contentsOf: sandbox.product(key)) == original) }
        else { #expect(!FileManager.default.fileExists(atPath: sandbox.product(key).path)) }
        #expect(try Data(contentsOf: sibling) == Data("untouched sibling".utf8))
        #expect(FileManager.default.fileExists(atPath: sandbox.product(key).deletingLastPathComponent().path))
        try await service.restore(for: key)
        // A restored receipt can be reused for a newly prepared installation.
        try await service.install(service.prepare(for: display(), target: target))
        #expect(try service.status(for: key).phase == .installed)
    }

    @Test func systemFallbackIsNotAnOriginalApplicationFile() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let key = DisplayOverrideKey(display: display())
        let templateURL = sandbox.system.appendingPathComponent(key.vendorDirectory).appendingPathComponent(key.productFile)
        let template = try plist(["system-only": "keep", "scale-resolutions": [Data([42])]])
        try sandbox.write(template, to: templateURL)
        let plan = try sandbox.service.prepare(for: display(), target: target)
        #expect(plan.expectedInstalledData == nil)
        let fields = try #require(PropertyListSerialization.propertyList(from: plan.generatedData, format: nil) as? [String: Any])
        #expect(fields["system-only"] as? String == "keep")
        #expect((fields["scale-resolutions"] as? [Data])?.contains(Data([0, 0, 12, 128, 0, 0, 7, 208])) == true)
        try await sandbox.service.install(plan)
        try await sandbox.service.restore(for: key)
        #expect(!FileManager.default.fileExists(atPath: sandbox.product(key).path))
        #expect(try Data(contentsOf: templateURL) == template)
    }

    @Test func rejectsChangedOriginalAndChangedInstalledConfiguration() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let key = DisplayOverrideKey(display: display())
        let plan = try sandbox.service.prepare(for: display(), target: target)
        let foreign = try plist(["foreign": "changed after preparation"])
        try sandbox.write(foreign, to: sandbox.product(key))
        await #expect(throws: (any Error).self) { try await sandbox.service.install(plan) }
        #expect(try Data(contentsOf: sandbox.product(key)) == foreign)
        let newPlan = try sandbox.service.prepare(for: display(), target: target)
        try await sandbox.service.install(newPlan)
        let changed = Data("third party changed installed file".utf8)
        try changed.write(to: sandbox.product(key))
        #expect(try sandbox.service.status(for: key).phase == .conflict)
        await #expect(throws: (any Error).self) { try await sandbox.service.restore(for: key) }
        #expect(try Data(contentsOf: sandbox.product(key)) == changed)
    }

    @Test(arguments: [false, true])
    func rejectsSymbolicAndHardLinkedProducts(hardLink: Bool) async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let key = DisplayOverrideKey(display: display())
        let plan = try sandbox.service.prepare(for: display(), target: target)
        let victim = sandbox.root.appendingPathComponent("victim")
        try sandbox.write(Data("victim".utf8), to: victim)
        try FileManager.default.createDirectory(at: sandbox.product(key).deletingLastPathComponent(), withIntermediateDirectories: true)
        if hardLink { try FileManager.default.linkItem(at: victim, to: sandbox.product(key)) }
        else { try FileManager.default.createSymbolicLink(at: sandbox.product(key), withDestinationURL: victim) }
        #expect(try sandbox.service.status(for: key).phase == .conflict)
        await #expect(throws: (any Error).self) { try await sandbox.service.install(plan) }
        await #expect(throws: (any Error).self) { try await sandbox.service.restore(for: key) }
        #expect(try Data(contentsOf: victim) == Data("victim".utf8))
    }

    @Test func rejectsUnsafeDirectoryAndReceipt() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let key = DisplayOverrideKey(display: display())
        let plan = try sandbox.service.prepare(for: display(), target: target)
        try FileManager.default.createDirectory(at: sandbox.overrides, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: sandbox.overrides.path)
        await #expect(throws: (any Error).self) { try await sandbox.service.install(plan) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sandbox.overrides.path)
        try await sandbox.service.install(plan)
        let receipt = sandbox.state.appendingPathComponent(key.vendorDirectory + "-" + key.productFile + ".json")
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: receipt.path)
        #expect(try sandbox.service.status(for: key).phase == .conflict)
        await #expect(throws: (any Error).self) { try await sandbox.service.restore(for: key) }
        #expect(try Data(contentsOf: sandbox.product(key)) == plan.generatedData)
    }

    @Test func interruptedReceiptBeforeProductCommitIsRecoverable() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let key = DisplayOverrideKey(display: display())
        let plan = try sandbox.service.prepare(for: display(), target: target)
        try await sandbox.service.install(plan)
        // Reproduce the durable on-disk state at the receipt/product commit boundary.
        try FileManager.default.removeItem(at: sandbox.product(key))
        #expect(try sandbox.service.status(for: key).phase == .restored)
        try await sandbox.service.restore(for: key)
        try await sandbox.service.install(plan)
        #expect(try sandbox.service.status(for: key).phase == .installed)
    }

    @Test func concurrentInstallationsSerializeAndKeepExactBackup() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let key = DisplayOverrideKey(display: display())
        let plan = try sandbox.service.prepare(for: display(), target: target)
        @Sendable func attempt() async -> Bool {
            do { try await sandbox.service.install(plan); return true }
            catch { return false }
        }
        async let first = attempt()
        async let second = attempt()
        let results = await [first, second]
        #expect(results.filter { $0 }.count == 1)
        #expect(try sandbox.service.status(for: key).phase == .installed)
        try await sandbox.service.restore(for: key)
        #expect(try sandbox.service.status(for: key).phase == .restored)
        #expect(!FileManager.default.fileExists(atPath: sandbox.product(key).path))
    }

    @Test func rejectsSpecialFileAndDirectorySymlink() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let key = DisplayOverrideKey(display: display())
        let plan = try sandbox.service.prepare(for: display(), target: target)
        let vendor = sandbox.product(key).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        #expect(mkfifo(sandbox.product(key).path, 0o644) == 0)
        await #expect(throws: (any Error).self) { try await sandbox.service.install(plan) }
        #expect(try sandbox.service.status(for: key).phase == .conflict)
        try FileManager.default.removeItem(at: sandbox.product(key))
        try FileManager.default.removeItem(at: vendor)
        let otherDirectory = sandbox.root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: vendor, withDestinationURL: otherDirectory)
        await #expect(throws: (any Error).self) { try await sandbox.service.install(plan) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: otherDirectory.path).isEmpty)
    }

    @Test func rejectsPermissionGrantACL() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let key = DisplayOverrideKey(display: display())
        let plan = try sandbox.service.prepare(for: display(), target: target)
        try await sandbox.service.install(plan)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+a", "everyone allow write,append", sandbox.product(key).path]
        try chmod.run()
        chmod.waitUntilExit()
        #expect(chmod.terminationStatus == 0)
        #expect(try sandbox.service.status(for: key).phase == .conflict)
        await #expect(throws: (any Error).self) { try await sandbox.service.restore(for: key) }
        #expect(try Data(contentsOf: sandbox.product(key)) == plan.generatedData)
    }

    private func plist(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }
    private func display(product: UInt32 = 0x5678) -> DisplayDevice {
        let mode = DisplayMode(modeID: 1, cgsModeNumber: nil, width: 2560, height: 1600,
                               pixelWidth: 2560, pixelHeight: 1600, refreshRate: 60, isHiDPI: false, scaleDensity: 1)
        return DisplayDevice(id: 1, name: "Sculptor", vendorID: 0x1234, modelID: product, serialNumber: 0,
                             metadata: DisplayMetadata(productName: "Sculptor", vendorID: 0x1234, productID: product,
                                                       serialNumber: 0, manufactureWeek: nil, manufactureYear: nil,
                                                       physicalWidthMM: 300, physicalHeightMM: 200, unitNumber: 1,
                                                       colorSpaceName: nil, isMain: false, isActive: true),
                             isBuiltin: false, isOnline: true, frame: CGRectCodable(CGRect(x: 0, y: 0, width: 2560, height: 1600)),
                             currentMode: mode, availableModes: [mode], rotation: 0)
    }

    private struct Sandbox {
        let root: URL
        let overrides: URL
        let system: URL
        let state: URL
        var service: PhysicalHiDPIService {
            PhysicalHiDPIService(testPaths: .init(overrides: overrides, systemOverrides: system,
                                                state: state, boundary: root, owner: getuid(), authorize: false))
        }
        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("PhysicalHiDPITests-" + UUID().uuidString)
            overrides = root.appendingPathComponent("Library/Displays/Contents/Resources/Overrides")
            system = root.appendingPathComponent("System/Library/Displays/Contents/Resources/Overrides")
            state = root.appendingPathComponent("Library/Application Support/HiDPIBuddy")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o755])
        }
        func product(_ key: DisplayOverrideKey) -> URL {
            overrides.appendingPathComponent(key.vendorDirectory).appendingPathComponent(key.productFile)
        }
        func write(_ data: Data, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o755])
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
