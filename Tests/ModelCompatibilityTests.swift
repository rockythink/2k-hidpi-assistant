import Foundation
import Testing
@testable import PixelFit

@Suite("Model compatibility")
struct ModelCompatibilityTests {
    @Test(arguments: [
        DisplayResolutionTarget(width: 1440, height: 900),
        DisplayResolutionTarget(width: 1600, height: 1000),
        DisplayResolutionTarget(width: 1680, height: 1050),
        DisplayResolutionTarget(width: 1920, height: 1200)
    ])
    func sixteenTenUsesConventionalAspectLabel(_ target: DisplayResolutionTarget) {
        let mode = makeMode(target.width, target.height, hiDPI: true)
        #expect(mode.aspectRatioLabel == "16:10")
        #expect(target.aspectRatioLabel == "16:10")
    }

    @Test func sixteenNineAspectLabelIsPreserved() {
        #expect(makeMode(1920, 1080, hiDPI: true).aspectRatioLabel == "16:9")
        #expect(DisplayResolutionTarget(width: 1920, height: 1080).aspectRatioLabel == "16:9")
    }

    @Test func displayModeDecodesOldJSONWithoutSourceOrScaleDensity() throws {
        let data = Data("""
        {
          "modeID": 1,
          "cgsModeNumber": 59,
          "width": 1920,
          "height": 1080,
          "pixelWidth": 3840,
          "pixelHeight": 2160,
          "refreshRate": 60,
          "isHiDPI": true
        }
        """.utf8)

        let mode = try JSONDecoder().decode(DisplayMode.self, from: data)
        #expect(mode.scaleDensity == 2)
        #expect(mode.source == .coreGraphics)
    }

    @Test func menuSwitchModesKeepHiDPIAndOneXAtSameLogicalResolution() {
        let hidpi = DisplayMode(
            modeID: 1,
            cgsModeNumber: 101,
            width: 1920,
            height: 1080,
            pixelWidth: 3840,
            pixelHeight: 2160,
            refreshRate: 60,
            isHiDPI: true,
            scaleDensity: 2,
            source: .privateCGS
        )
        let oneX = DisplayMode(
            modeID: 2,
            cgsModeNumber: 102,
            width: 1920,
            height: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRate: 60,
            isHiDPI: false,
            scaleDensity: 1,
            source: .privateCGS
        )
        let display = DisplayDevice(
            id: 1,
            name: "Test",
            vendorID: 1,
            modelID: 1,
            serialNumber: 0,
            metadata: DisplayMetadata(
                productName: "Test",
                vendorID: 1,
                productID: 1,
                serialNumber: 0,
                manufactureWeek: nil,
                manufactureYear: nil,
                physicalWidthMM: 600,
                physicalHeightMM: 340,
                unitNumber: 1,
                colorSpaceName: nil,
                isMain: true,
                isActive: true
            ),
            isBuiltin: false,
            isOnline: true,
            frame: CGRectCodable(.zero),
            currentMode: hidpi,
            availableModes: [oneX, hidpi],
            rotation: 0
        )

        #expect(display.menuSwitchModes.count == 2)
        #expect(display.menuSwitchModes.contains { $0.isHiDPI })
        #expect(display.menuSwitchModes.contains { !$0.isHiDPI })
    }

    @Test func twoKRecommendationsKeepExistingRanking() {
        let native = makeMode(2560, 1440)
        let sizes = [(1280, 720), (1600, 900), (1920, 1080), (1680, 945), (1440, 810)]
        let modes = sizes.reversed().map { makeMode($0.0, $0.1, hiDPI: true) }
        let display = makeDisplay(native: native, modes: modes + [makeMode(1680, 1050, hiDPI: true)])
        #expect(display.recommendedHiDPIModes.map { $0.width } == sizes.map { $0.0 })
    }

    @Test func fourKRecommendationsKeepExistingRanking() {
        let native = makeMode(3840, 2160)
        let sizes = [(2560, 1440), (2304, 1296), (2048, 1152), (1920, 1080)]
        let display = makeDisplay(native: native, modes: sizes.reversed().map { makeMode($0.0, $0.1, hiDPI: true) })
        #expect(display.recommendedHiDPIModes.map { $0.width } == sizes.map { $0.0 })
    }

    @Test(arguments: [2560, 3840])
    func mixedAspectRecommendationsFollowPhysicalSixteenTen(_ nativeWidth: Int) {
        let native = makeMode(nativeWidth, nativeWidth * 5 / 8)
        let display = makeDisplay(native: native, modes: [
            makeMode(1920, 1080, hiDPI: true, refreshRate: 120),
            makeMode(1600, 900, hiDPI: true, refreshRate: 120),
            makeMode(1280, 800, hiDPI: true),
            makeMode(1600, 1000, hiDPI: true),
            makeMode(1920, 1200, hiDPI: true)
        ])
        #expect(display.recommendedHiDPIModes.first?.width == 1920)
        #expect(display.recommendedHiDPIModes.first?.height == 1200)
        #expect(display.recommendedHiDPIModes.allSatisfy { $0.width * 5 == $0.height * 8 })
        #expect(display.unavailableRecommendedHiDPITargets.allSatisfy { $0.width * 5 == $0.height * 8 })
    }

    @Test func mismatchedHiDPIIsNotRecommendedWhenNoMatchingModeExists() {
        let display = makeDisplay(native: makeMode(2560, 1600), modes: [makeMode(1920, 1080, hiDPI: true)])
        #expect(display.recommendedHiDPIModes.isEmpty)
    }

    @Test func recommendationKeepsHighestRefreshAtEachResolution() {
        let display = makeDisplay(native: makeMode(2560, 1600), modes: [
            makeMode(1600, 1000, hiDPI: true),
            makeMode(1600, 1000, hiDPI: true, refreshRate: 120)
        ])
        #expect(display.recommendedHiDPIModes.count == 1)
        #expect(display.recommendedHiDPIModes.first?.refreshRate == 120)
    }

    @Test func sixteenTenVirtualTargetsProvideMissingLargerWorkspaces() {
        let display = makeDisplay(native: makeMode(2560, 1600), modes: [makeMode(1280, 800, hiDPI: true)])
        #expect(display.virtualHiDPITargets == [
            DisplayResolutionTarget(width: 1440, height: 900),
            DisplayResolutionTarget(width: 1600, height: 1000),
            DisplayResolutionTarget(width: 1680, height: 1050),
            DisplayResolutionTarget(width: 1920, height: 1200)
        ])
    }

    @Test func virtualTargetsExcludeAlreadyExposedHiDPIButNotOneX() {
        let display = makeDisplay(native: makeMode(2560, 1600), modes: [
            makeMode(1440, 900, hiDPI: true), makeMode(1600, 1000)
        ])
        #expect(!display.virtualHiDPITargets.contains { $0.width == 1440 })
        #expect(display.virtualHiDPITargets.contains { $0.width == 1600 })
    }

    @Test func virtualTargetsStayWithinNativeAndAbovePixelMatchedWorkspace() {
        let small = makeDisplay(native: makeMode(1600, 1000))
        #expect(small.virtualHiDPITargets.map { $0.width } == [1440, 1600])
        let large = makeDisplay(native: makeMode(3200, 2000))
        #expect(large.virtualHiDPITargets.map { $0.width } == [1680, 1920])
    }

    @Test func virtualTargetsRejectUnsupportedDisplays() {
        var display = makeDisplay(native: makeMode(2560, 1600))
        display.isBuiltin = true
        #expect(display.virtualHiDPITargets.isEmpty)
        display.isBuiltin = false
        display.isOnline = false
        #expect(display.virtualHiDPITargets.isEmpty)
        display.isOnline = true
        for rotation in [90.0, 180.0, 270.0] {
            display.rotation = rotation
            #expect(display.virtualHiDPITargets.isEmpty)
        }
        #expect(makeDisplay(native: makeMode(1600, 2560)).virtualHiDPITargets.isEmpty)
        #expect(makeDisplay(native: makeMode(2560, 1440)).virtualHiDPITargets.isEmpty)
        display.availableModes = []
        #expect(display.virtualHiDPITargets.isEmpty)
        #expect(display.recommendedHiDPIModes.isEmpty)
        #expect(display.unavailableRecommendedHiDPITargets.isEmpty)
    }

    @Test func portraitRecommendationsRetainPortraitAspect() {
        let display = makeDisplay(native: makeMode(1600, 2560), modes: [
            makeMode(800, 1280, hiDPI: true), makeMode(1080, 1920, hiDPI: true)
        ])
        #expect(display.recommendedHiDPIModes.map { $0.width } == [800])
        #expect(display.unavailableRecommendedHiDPITargets.allSatisfy { $0.width * 8 == $0.height * 5 })
    }

    @Test func resolutionPresetRoundTripsDisplayModes() throws {
        let mode = makeMode(1600, 1000, hiDPI: true, refreshRate: 120)
        let preset = DisplayPreset(name: "Work", displayModes: [
            DisplayPresetMode(displayID: 1, displayName: "Test", mode: mode)
        ])
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(DisplayPreset.self, from: data)
        #expect(decoded == preset)
        #expect(decoded.displayModes.first?.mode.refreshRate == 120)
    }

    @Test func resolutionPresetDecodesOldMinimalJSON() throws {
        let data = Data("""
        { "id": "11111111-1111-1111-1111-111111111111", "name": "main", "displayModes": [] }
        """.utf8)
        let decoded = try JSONDecoder().decode(DisplayPreset.self, from: data)
        #expect(decoded.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(decoded.name == "main")
        #expect(decoded.displayModes.isEmpty)
    }

    @Test func resolutionPresetIgnoresLegacyUnrelatedFields() throws {
        let data = Data("""
        { "name": "Work", "displayModes": [], "controlStates": {"1": {"brightness": 0.4}},
          "syncSettings": {"isEnabled": true}, "darkModeEnabled": true, "nightShiftEnabled": true }
        """.utf8)
        let decoded = try JSONDecoder().decode(DisplayPreset.self, from: data)
        let encoded = try JSONEncoder().encode(decoded)
        let keys = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(keys.keys) == ["id", "name", "displayModes"])
        #expect(decoded.name == "Work")
    }

    @Test func resolutionPresetDecodesNameWithoutModes() throws {
        let decoded = try JSONDecoder().decode(DisplayPreset.self, from: Data(#"{"name":"Work"}"#.utf8))
        #expect(decoded.name == "Work")
        #expect(decoded.displayModes.isEmpty)
    }

    @Test func defaultChoicesOnlyIncludeRegisteredHiDPIModesWithMatchingAspect() {
        let native = makeMode(2560, 1600)
        let display = makeDisplay(native: native, modes: [
            makeMode(1280, 800, hiDPI: true),
            makeMode(1600, 1000, hiDPI: true),
            makeMode(1600, 1000, hiDPI: true, refreshRate: 120),
            makeMode(1680, 1050),
            makeMode(1920, 1080, hiDPI: true)
        ])
        let choices = display.hiDPIResolutionChoices.all
        let expected = Set([(1280, 800), (1600, 1000)].map { DisplayResolutionTarget(width: $0.0, height: $0.1) })
        #expect(Set(choices) == expected)
        #expect(display.virtualHiDPITargets.contains(DisplayResolutionTarget(width: 1680, height: 1050)))
    }

    @Test func configuredRenderingCompanionDoesNotChangePhysicalPanelSize() {
        var display = makeDisplay(native: makeMode(2560, 1600), modes: [
            makeMode(3200, 2000), makeMode(1600, 1000, hiDPI: true)
        ])
        display.metadata.panelResolution = DisplayResolutionTarget(width: 2560, height: 1600)
        #expect(display.nativeMode?.pixelWidth == 2560)
        #expect(display.nativeMode?.pixelHeight == 1600)
        #expect(display.displayClass == .twoPointFiveK)
        #expect(display.physicalHiDPIProbeTarget == DisplayResolutionTarget(width: 1600, height: 1000))
        display.metadata.panelResolution = DisplayResolutionTarget(width: 2560, height: 1440)
        #expect(display.nativeMode == nil)
        #expect(display.physicalHiDPIProbeTarget == nil)
    }

    @Test func physicalProbeRejectsUnsupportedGeometryAndDisplays() {
        var display = makeDisplay(native: makeMode(2560, 1600))
        #expect(display.physicalHiDPIProbeTarget == DisplayResolutionTarget(width: 1600, height: 1000))
        display.rotation = 90
        #expect(display.physicalHiDPIProbeTarget == nil)
        display.rotation = 0
        display.isBuiltin = true
        #expect(display.physicalHiDPIProbeTarget == nil)
        display.isBuiltin = false
        display.isOnline = false
        #expect(display.physicalHiDPIProbeTarget == nil)
        display.isOnline = true
        display.vendorID = 0
        #expect(display.physicalHiDPIProbeTarget == nil)
        #expect(makeDisplay(native: makeMode(2560, 1440)).physicalHiDPIProbeTarget == nil)
    }

    @Test func duplicateDisplayNamesSurviveEnumerationAndIDChanges() {
        var left = makeDisplay(native: makeMode(2560, 1440))
        left.id = 10
        left.serialNumber = 20
        var right = left
        right.id = 11
        right.serialNumber = 10
        var first = [left, right]
        DisplayDiscoveryService.disambiguateNames(&first) { String($0.serialNumber) }
        #expect(first[0].name != first[1].name)
        left.id = 50
        right.id = 51
        var reconnected = [right, left]
        DisplayDiscoveryService.disambiguateNames(&reconnected) { String($0.serialNumber) }
        #expect(first[0].name == reconnected[1].name)
        #expect(first[1].name == reconnected[0].name)
    }

    @Test func duplicateHardwareIdentifiersStillProduceDistinctNames() {
        let first = makeDisplay(native: makeMode(2560, 1440))
        var second = first
        second.id = 2
        var displays = [first, second]
        DisplayDiscoveryService.disambiguateNames(&displays) { _ in "same-hardware-key" }
        #expect(displays[0].name != displays[1].name)
    }

    private func makeMode(_ width: Int, _ height: Int, hiDPI: Bool = false, refreshRate: Double = 60) -> DisplayMode {
        DisplayMode(modeID: Int32(width), cgsModeNumber: nil, width: width, height: height,
                    pixelWidth: width * (hiDPI ? 2 : 1), pixelHeight: height * (hiDPI ? 2 : 1),
                    refreshRate: refreshRate, isHiDPI: hiDPI, scaleDensity: hiDPI ? 2 : 1)
    }

    private func makeDisplay(native: DisplayMode, modes: [DisplayMode] = []) -> DisplayDevice {
        DisplayDevice(id: 1, name: "Test", vendorID: 1, modelID: 1, serialNumber: 0,
                      metadata: DisplayMetadata(productName: nil, vendorID: 1, productID: 1,
                                                serialNumber: 0, manufactureWeek: nil, manufactureYear: nil,
                                                physicalWidthMM: 0, physicalHeightMM: 0, unitNumber: 1,
                                                colorSpaceName: nil, isMain: true, isActive: true),
                      isBuiltin: false, isOnline: true, frame: CGRectCodable(.zero),
                      currentMode: native, availableModes: [native] + modes, rotation: 0)
    }
}
