import Foundation
import Testing
@testable import HiDPIBuddy

@Suite("Model compatibility")
struct ModelCompatibilityTests {
    @Test func aspectRatioLabelsAreReduced() {
        let mode = DisplayMode(
            modeID: 1,
            cgsModeNumber: 59,
            width: 1920,
            height: 1080,
            pixelWidth: 3840,
            pixelHeight: 2160,
            refreshRate: 60,
            isHiDPI: true,
            scaleDensity: 2
        )

        #expect(mode.aspectRatioLabel == "16:9")
        #expect(mode.resolutionWithAspectLabel == "1920 x 1080 · 16:9")
        #expect(mode.menuLabel == "1920 x 1080 · 16:9 @ 60Hz")
        #expect(mode.source == .coreGraphics)
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

    @Test func displayControlStateDecodesOldJSONWithoutNewFields() throws {
        let data = Data("""
        {
          "brightness": 0.7,
          "contrast": 1.1,
          "volume": 0.4,
          "inputSource": "HDMI 1",
          "isPoweredOff": false
        }
        """.utf8)

        let state = try JSONDecoder().decode(DisplayControlState.self, from: data)
        #expect(state.brightness == 0.7)
        #expect(state.contrast == 1.1)
        #expect(state.volume == 0.4)
        #expect(state.inputSource == "HDMI 1")
        #expect(state.controlMode == .automatic)
        #expect(state.powerOffKind == nil)
    }

    @Test func persistentSnapshotDecodesOldJSONWithoutRecentFields() throws {
        let data = Data("""
        {
          "language": "zhHans",
          "presets": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "main",
              "displayModes": []
            }
          ],
          "controlStates": {
            "1": {
              "brightness": 0.8,
              "contrast": 1.0,
              "volume": 0.5,
              "inputSource": "USB-C / HDMI",
              "isPoweredOff": false
            }
          },
          "nightShiftEnabled": true
        }
        """.utf8)

        let snapshot = try JSONDecoder().decode(PersistentSnapshot.self, from: data)
        #expect(snapshot.language == .zhHans)
        #expect(snapshot.presets.first?.name == "main")
        #expect(snapshot.presets.first?.syncSettings.isEnabled == false)
        #expect(snapshot.controlStates["1"]?.controlMode == .automatic)
        #expect(snapshot.syncSettings.syncBrightness == true)
        #expect(snapshot.nightShiftEnabled)
    }

    @Test func presetRoundTripsCompleteState() throws {
        let preset = DisplayPreset(
            name: "Work",
            displayModes: [],
            controlStates: ["1": DisplayControlState(brightness: 0.6, contrast: 1.2, volume: 0.3, controlMode: .software)],
            syncSettings: DisplaySyncSettings(isEnabled: true, leaderDisplayID: 1, syncBrightness: true, syncContrast: true, syncVolume: true),
            darkModeEnabled: true,
            nightShiftEnabled: true
        )

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(DisplayPreset.self, from: data)

        #expect(decoded.name == "Work")
        #expect(decoded.controlStates["1"]?.controlMode == .software)
        #expect(decoded.syncSettings.leaderDisplayID == 1)
        #expect(decoded.syncSettings.syncVolume)
        #expect(decoded.darkModeEnabled)
        #expect(decoded.nightShiftEnabled)
    }

    @Test func ddcChecksumUsesXorSeed() {
        let bytes: [UInt8] = [0x51, 0x84, 0x03, 0x10, 0x00, 0x32]
        #expect(DDCCodec.checksum(seed: 0x6E, bytes: bytes) == 0x9A)
    }

    @Test func ddcGetVCPReplyParsesCurrentAndMaximumValues() throws {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00]
        let value = try DDCCodec.parseGetVCPReply(reply, feature: 0x10)
        #expect(value.maximum == 100)
        #expect(value.current == 50)
        #expect(value.normalized == 0.5)
    }

    @Test func backendStatusEncodesStableJSON() throws {
        let status = NativeDDCService.BackendStatus(
            backend: .appleSiliconIOAVService,
            isAvailable: true,
            reason: "external DCPAVServiceProxy",
            matchScore: 5
        )
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(NativeDDCService.BackendStatus.self, from: data)
        #expect(decoded.backend == .appleSiliconIOAVService)
        #expect(decoded.isAvailable)
        #expect(decoded.matchScore == 5)
    }
}
