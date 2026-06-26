import Foundation

enum CLIService {
    static func runIfNeeded(arguments: [String] = CommandLine.arguments) {
        guard arguments.count > 1 else { return }
        let command = arguments[1]
        guard ["status", "list", "diagnose", "ddc", "get", "set", "help", "--help", "-h"].contains(command) else { return }

        let exitCode: Int32
        do {
            exitCode = try run(command: command, arguments: Array(arguments.dropFirst(2)))
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exitCode = 1
        }
        Foundation.exit(exitCode)
    }

    private static func run(command: String, arguments: [String]) throws -> Int32 {
        switch command {
        case "status":
            try printStatus()
        case "list":
            try printList()
        case "diagnose":
            try printDiagnose(arguments: arguments)
        case "ddc":
            try runDDC(arguments: arguments)
        case "get":
            try printGet(arguments: arguments)
        case "set":
            try setValues(arguments: arguments)
        case "help", "--help", "-h":
            printHelp()
        default:
            printHelp()
        }
        return 0
    }

    private static func printStatus() throws {
        let displays = DisplayDiscoveryService().discover(language: .system)
        let persistence = PersistenceService().load()
        print("Index\tName\tResolution\tMode\tBrightness\tContrast\tVolume\tInput")
        for (index, display) in displays.enumerated() {
            let state = persistence.controlStates["\(display.id)"] ?? DisplayControlState()
            print([
                "\(index + 1)",
                display.shortName(language: .system),
                display.currentMode?.resolutionWithAspectLabel ?? "-",
                display.currentMode?.isHiDPI == true ? "HiDPI" : "1x",
                percent(state.brightness / 1.2),
                percent((state.contrast - 0.4) / 1.4),
                percent(state.volume),
                state.inputSource
            ].joined(separator: "\t"))
        }
    }

    private static func printList() throws {
        let displays = DisplayDiscoveryService().discover(language: .system)
        for (index, display) in displays.enumerated() {
            print("#\(index + 1) \(display.shortName(language: .system))")
            print("  id: \(display.id)")
            print("  current: \(display.currentMode?.detailLabel ?? "-")")
            print("  control: \(display.isBuiltin ? "built-in/software" : "DDC/CI or software fallback")")
            print("  modes: \(display.availableModes.count)")
        }
    }

    private static func printDiagnose(arguments: [String]) throws {
        let displays = DisplayDiscoveryService().discover(language: .system)
        let transportDiagnostics = DisplayTransportDiagnosticsService()
        let ddc = NativeDDCService()
        let targets = arguments.contains("--all") ? displays : [try selectedDisplay(from: displays, arguments: arguments)]

        if arguments.contains("--json") {
            try printJSONReport(displays: targets, transportDiagnostics: transportDiagnostics, ddc: ddc)
            return
        }

        for (index, display) in targets.enumerated() {
            if index > 0 {
                print("")
            }
            print("# \(display.shortName(language: .system))")
            print("id=\(display.id)")
            print("role=\(display.isBuiltin ? "built-in" : "external"), online=\(display.isOnline), main=\(display.metadata.isMain), active=\(display.metadata.isActive)")
            print("vendor=\(display.metadata.vendorHex), product=\(display.metadata.productHex), serial=\(display.metadata.serialText), unit=\(display.metadata.unitNumber)")
            print("productName=\(display.metadata.productName ?? "-")")
            print("manufactured=\(display.metadata.manufactureText)")
            print("physicalSize=\(display.metadata.physicalSizeText), diagonal=\(display.metadata.diagonalText(language: .system))")
            print("frame=\(Int(display.frame.width))x\(Int(display.frame.height))@(\(Int(display.frame.x)),\(Int(display.frame.y))), rotation=\(Int(display.rotation.rounded()))")
            print("native=\(display.nativeMode?.detailLabel ?? "-")")
            print("current=\(display.currentMode?.detailLabel ?? "-")")
            print("currentSource=\(display.currentMode?.source.label(language: .system) ?? "-")")
            print("class=\(display.displayClass.label(language: .system))")
            print("modeCount=\(display.availableModes.count), hidpiCount=\(display.availableModes.filter(\.isHiDPI).count)")
            print("sources=\(modeSourceSummary(for: display))")
            print("ddcBackends:")
            for status in ddc.backendStatuses(for: display) {
                let marker = status.isAvailable ? "available" : "unavailable"
                let score = status.matchScore.map { " score=\($0)" } ?? ""
                print("  - \(status.backend.rawValue): \(marker) reason=\(status.reason)\(score)")
            }
            print("transportCandidates:")
            let candidates = transportDiagnostics.diagnostics(for: display).prefix(5)
            if candidates.isEmpty {
                print("  - none")
            } else {
                for candidate in candidates {
                    print("  - \(candidate.summary)")
                    if !candidate.edidUUID.isEmpty {
                        print("    edid=\(candidate.edidUUID)")
                    }
                    if !candidate.ioDisplayLocation.isEmpty {
                        print("    ioDisplayLocation=\(candidate.ioDisplayLocation)")
                    }
                }
            }

            print("recommendedHiDPI:")
            for mode in display.recommendedHiDPIModes {
                print("  - \(diagnosticLine(for: mode, current: display.currentMode))")
            }
            if display.recommendedHiDPIModes.isEmpty {
                print("  - none")
            }

            if !display.unavailableRecommendedHiDPITargets.isEmpty {
                print("notExposedRecommended:")
                for target in display.unavailableRecommendedHiDPITargets {
                    print("  - \(target.resolutionWithAspectLabel)")
                }
            }

            print("switchableModes:")
            for mode in display.menuSwitchModes {
                print("  - \(diagnosticLine(for: mode, current: display.currentMode))")
            }
        }
    }

    private static func runDDC(arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.invalidArguments("Missing ddc subcommand")
        }

        switch subcommand {
        case "probe":
            try runDDCProbe(arguments: Array(arguments.dropFirst()))
        case "set":
            try runDDCSet(arguments: Array(arguments.dropFirst()))
        default:
            throw CLIError.invalidArguments("Unknown ddc subcommand: \(subcommand)")
        }
    }

    private static func runDDCProbe(arguments: [String]) throws {
        let displays = DisplayDiscoveryService().discover(language: .system)
        let targets = arguments.contains("--all") ? displays : [try selectedDisplay(from: displays, arguments: arguments)]
        let ddc = NativeDDCService()

        for display in targets {
            print("# \(display.shortName(language: .system))")
            for status in ddc.backendStatuses(for: display) {
                let marker = status.isAvailable ? "available" : "unavailable"
                print("backend=\(status.backend.rawValue) \(marker) reason=\(status.reason)")
            }
            for probe in ddc.probe(display: display) {
                if probe.readable {
                    print("vcp=0x\(hex(probe.code)) \(probe.name) backend=\(probe.backend?.rawValue ?? "-") value=\(probe.current ?? 0)/\(probe.maximum ?? 0)")
                } else {
                    print("vcp=0x\(hex(probe.code)) \(probe.name) unreadable backend=\(probe.backend?.rawValue ?? "-") error=\(probe.error ?? "-")")
                }
            }
        }
    }

    private static func runDDCSet(arguments: [String]) throws {
        guard !arguments.contains("--all") else {
            throw CLIError.invalidArguments("ddc set requires a single display; use --index N")
        }

        let displays = DisplayDiscoveryService().discover(language: .system)
        let display = try selectedDisplay(from: displays, arguments: arguments)
        let requested: (code: UInt8, name: String, value: UInt16)?

        if let brightness = optionValue("--brightness", in: arguments).flatMap(Double.init) {
            requested = (0x10, "brightness", UInt16(brightness.clamped(to: 0...100).rounded()))
        } else if let contrast = optionValue("--contrast", in: arguments).flatMap(Double.init) {
            requested = (0x12, "contrast", UInt16(contrast.clamped(to: 0...100).rounded()))
        } else if let volume = optionValue("--volume", in: arguments).flatMap(Double.init) {
            requested = (0x62, "volume", UInt16(volume.clamped(to: 0...100).rounded()))
        } else {
            requested = nil
        }

        guard let requested else {
            throw CLIError.invalidArguments("ddc set requires --brightness, --contrast, or --volume")
        }

        let ddc = NativeDDCService()
        let result = try ddc.writeVCPFeature(requested.code, value: requested.value, for: display)
        print("display=\(display.shortName(language: .system))")
        print("vcp=0x\(hex(result.code)) \(result.name)")
        print("backend=\(result.backend.rawValue)")
        print("sent=\(result.sent)")
        print("verified=\(result.verified)")
        if let readBack = result.readBack {
            print("readBack=\(readBack.current)/\(readBack.maximum)")
        }
        if let error = result.error {
            print("status=\(error)")
        }

        guard result.verified else { return }
        var snapshot = PersistenceService().load()
        var state = snapshot.controlStates["\(display.id)"] ?? DisplayControlState()
        switch requested.code {
        case 0x10:
            state.brightness = Double(requested.value).clamped(to: 0...100) / 100
        case 0x12:
            state.contrast = 0.4 + Double(requested.value).clamped(to: 0...100) / 100 * 1.4
        case 0x62:
            state.volume = Double(requested.value).clamped(to: 0...100) / 100
        default:
            break
        }
        snapshot.controlStates["\(display.id)"] = state
        PersistenceService().save(snapshot)
    }

    private static func printGet(arguments: [String]) throws {
        let displays = DisplayDiscoveryService().discover(language: .system)
        let display = try selectedDisplay(from: displays, arguments: arguments)
        let state = PersistenceService().load().controlStates["\(display.id)"] ?? DisplayControlState()
        print("name=\(display.shortName(language: .system))")
        print("brightness=\(percent(state.brightness / 1.2))")
        print("contrast=\(percent((state.contrast - 0.4) / 1.4))")
        print("volume=\(percent(state.volume))")
        print("input=\(state.inputSource)")
        print("resolution=\(display.currentMode?.resolutionWithAspectLabel ?? "-")")
    }

    private static func setValues(arguments: [String]) throws {
        let displays = DisplayDiscoveryService().discover(language: .system)
        let targets = arguments.contains("--all") ? displays : [try selectedDisplay(from: displays, arguments: arguments)]
        let ddc = NativeDDCService()
        var snapshot = PersistenceService().load()

        for display in targets {
            var state = snapshot.controlStates["\(display.id)"] ?? DisplayControlState()

            if let brightness = optionValue("--brightness", in: arguments).flatMap(Double.init) {
                state.brightness = brightness.clamped(to: 0...100) / 100 * 1.2
                try? ddc.setBrightness(UInt16(brightness.clamped(to: 0...100).rounded()), for: display.id)
            }
            if let contrast = optionValue("--contrast", in: arguments).flatMap(Double.init) {
                state.contrast = 0.4 + contrast.clamped(to: 0...100) / 100 * 1.4
                try? ddc.setContrast(UInt16(contrast.clamped(to: 0...100).rounded()), for: display.id)
            }
            if let volume = optionValue("--volume", in: arguments).flatMap(Double.init) {
                state.volume = volume.clamped(to: 0...100) / 100
                try? ddc.setVolume(UInt16(volume.clamped(to: 0...100).rounded()), for: display.id)
            }
            if let input = optionValue("--input", in: arguments) {
                state.inputSource = input
                print("input source recorded only; real switching is disabled for safety")
            }

            snapshot.controlStates["\(display.id)"] = state
            print("updated \(display.shortName(language: .system))")
        }

        PersistenceService().save(snapshot)
    }

    private static func selectedDisplay(from displays: [DisplayDevice], arguments: [String]) throws -> DisplayDevice {
        if let indexText = optionValue("--index", in: arguments),
           let index = Int(indexText),
           displays.indices.contains(index - 1) {
            return displays[index - 1]
        }
        if let name = arguments.first(where: { !$0.hasPrefix("--") && Double($0) == nil }) {
            if let display = displays.first(where: { $0.shortName(language: .system).localizedCaseInsensitiveContains(name) }) {
                return display
            }
        }
        guard let first = displays.first else {
            throw CLIError.noDisplays
        }
        return first
    }

    private static func optionValue(_ option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value.clamped(to: 0...1) * 100).rounded()))"
    }

    private static func printJSONReport(
        displays: [DisplayDevice],
        transportDiagnostics: DisplayTransportDiagnosticsService,
        ddc: NativeDDCService
    ) throws {
        let report = DiagnosticReport(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            displays: displays.map { display in
                DiagnosticDisplayReport(
                    id: display.id,
                    name: display.shortName(language: .system),
                    role: display.isBuiltin ? "built-in" : "external",
                    online: display.isOnline,
                    main: display.metadata.isMain,
                    active: display.metadata.isActive,
                    vendorHex: display.metadata.vendorHex,
                    productHex: display.metadata.productHex,
                    serial: display.metadata.serialText,
                    productName: display.metadata.productName,
                    physicalSize: display.metadata.physicalSizeText,
                    diagonal: display.metadata.diagonalText(language: .system),
                    frame: "\(Int(display.frame.width))x\(Int(display.frame.height))@(\(Int(display.frame.x)),\(Int(display.frame.y)))",
                    rotation: display.rotation,
                    displayClass: display.displayClass.label(language: .system),
                    nativeMode: display.nativeMode.map(DiagnosticModeReport.init),
                    currentMode: display.currentMode.map(DiagnosticModeReport.init),
                    modeCount: display.availableModes.count,
                    hidpiCount: display.availableModes.filter(\.isHiDPI).count,
                    modeSources: modeSourceCounts(for: display),
                    recommendedHiDPI: display.recommendedHiDPIModes.map(DiagnosticModeReport.init),
                    notExposedRecommended: display.unavailableRecommendedHiDPITargets.map {
                        DiagnosticResolutionTarget(width: $0.width, height: $0.height, label: $0.resolutionWithAspectLabel)
                    },
                    switchableModes: display.menuSwitchModes.map(DiagnosticModeReport.init),
                    transportCandidates: transportDiagnostics.diagnostics(for: display),
                    ddcBackends: ddc.backendStatuses(for: display),
                    ddcProbe: ddc.probe(display: display)
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func modeSourceSummary(for display: DisplayDevice) -> String {
        modeSourceCounts(for: display)
            .map { "\($0.source):\($0.count)" }
            .joined(separator: ", ")
    }

    private static func modeSourceCounts(for display: DisplayDevice) -> [DiagnosticModeSourceCount] {
        let grouped = Dictionary(grouping: display.availableModes, by: \.source)
        return DisplayModeSource.allCasesForDiagnostics
            .compactMap { source in
                guard let count = grouped[source]?.count, count > 0 else { return nil }
                return DiagnosticModeSourceCount(source: source.rawValue, count: count)
            }
    }

    private static func diagnosticLine(for mode: DisplayMode, current: DisplayMode?) -> String {
        let currentMarker = current?.matchesEffectiveMode(mode) == true ? " current" : ""
        let hiDPIMarker = mode.isHiDPI ? "HiDPI" : "1x"
        return "\(mode.menuLabel) \(hiDPIMarker) framebuffer=\(mode.pixelWidth)x\(mode.pixelHeight) source=\(mode.source.rawValue) cgs=\(mode.cgsModeNumber.map(String.init) ?? "-")\(currentMarker)"
    }

    private static func printHelp() {
        print("""
        hidpibuddy status
        hidpibuddy list
        hidpibuddy diagnose [--index N|--all] [--json]
        hidpibuddy ddc probe [--index N|--all]
        hidpibuddy ddc set --index N [--brightness 0-100|--contrast 0-100|--volume 0-100]
        hidpibuddy get [--index N]
        hidpibuddy set [--index N|--all] [--brightness 0-100] [--contrast 0-100] [--volume 0-100] [--input name]
        """)
    }

    private static func hex(_ value: UInt8) -> String {
        String(format: "%02X", value)
    }
}

private extension DisplayModeSource {
    static var allCasesForDiagnostics: [DisplayModeSource] {
        [.privateCGS, .coreGraphics, .coreGraphicsCurrent]
    }
}

private enum CLIError: LocalizedError {
    case noDisplays
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            "No displays found"
        case .invalidArguments(let message):
            message
        }
    }
}

private struct DiagnosticReport: Codable {
    var generatedAt: String
    var displays: [DiagnosticDisplayReport]
}

private struct DiagnosticDisplayReport: Codable {
    var id: UInt32
    var name: String
    var role: String
    var online: Bool
    var main: Bool
    var active: Bool
    var vendorHex: String
    var productHex: String
    var serial: String
    var productName: String?
    var physicalSize: String
    var diagonal: String
    var frame: String
    var rotation: Double
    var displayClass: String
    var nativeMode: DiagnosticModeReport?
    var currentMode: DiagnosticModeReport?
    var modeCount: Int
    var hidpiCount: Int
    var modeSources: [DiagnosticModeSourceCount]
    var recommendedHiDPI: [DiagnosticModeReport]
    var notExposedRecommended: [DiagnosticResolutionTarget]
    var switchableModes: [DiagnosticModeReport]
    var transportCandidates: [DisplayTransportDiagnostic]
    var ddcBackends: [NativeDDCService.BackendStatus]
    var ddcProbe: [NativeDDCService.VCPProbeResult]
}

private struct DiagnosticModeReport: Codable {
    var id: String
    var modeID: Int32
    var cgsModeNumber: Int32?
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
    var isHiDPI: Bool
    var scaleDensity: Double
    var source: String
    var label: String

    init(_ mode: DisplayMode) {
        id = mode.id
        modeID = mode.modeID
        cgsModeNumber = mode.cgsModeNumber
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
        isHiDPI = mode.isHiDPI
        scaleDensity = mode.scaleDensity
        source = mode.source.rawValue
        label = mode.detailLabel
    }
}

private struct DiagnosticModeSourceCount: Codable {
    var source: String
    var count: Int
}

private struct DiagnosticResolutionTarget: Codable {
    var width: Int
    var height: Int
    var label: String
}
