import AppKit
import CoreGraphics
import Foundation

struct SystemControlService {
    var commandLineToolURL: URL {
        URL(fileURLWithPath: "/usr/local/bin/hidpibuddy")
    }

    func isDarkModeEnabled() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func setDarkMode(_ enabled: Bool) throws {
        let source = """
        tell application "System Events"
            tell appearance preferences to set dark mode to \(enabled ? "true" : "false")
        end tell
        """

        do {
            try runAppleScript(source)
        } catch {
            try runOSAScript(source)
        }
    }

    func setSystemOutputVolume(_ value: Double) {
        let clamped = Int((value.clamped(to: 0...1) * 100).rounded())
        try? runAppleScript("set volume output volume \(clamped)")
    }

    func sleepDisplays() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    func isCommandLineToolInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: commandLineToolURL.path)
    }

    func installCommandLineTool() throws {
        let executablePath = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let script = """
        #!/bin/zsh
        exec "\(executablePath.replacingOccurrences(of: "\"", with: "\\\""))" "$@"
        """

        let binDirectory = commandLineToolURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try script.write(to: commandLineToolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandLineToolURL.path)
    }

    private func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SystemControlError.appleScriptFailed("无法创建 AppleScript。")
        }
        script.executeAndReturnError(&error)
        if let error {
            throw SystemControlError.appleScriptFailed(error.description)
        }
    }

    private func runOSAScript(_ source: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SystemControlError.appleScriptFailed(output.isEmpty ? "osascript 退出码 \(process.terminationStatus)" : output)
        }
    }
}

enum SystemControlError: LocalizedError {
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .appleScriptFailed(let message):
            message
        }
    }
}

struct SoftwareDisplayControlService {
    func apply(_ state: DisplayControlState, nightShiftWarmth: Double = 0, to displayID: CGDirectDisplayID) {
        let brightness = Float(state.isPoweredOff ? 0.05 : state.brightness.clamped(to: 0.05...1.2))
        let contrast = Float(state.contrast.clamped(to: 0.4...1.8))
        let gamma = 1 / contrast
        let warmth = Float(nightShiftWarmth.clamped(to: 0...1))
        let redMax = brightness
        let greenMax = brightness * (1 - 0.18 * warmth)
        let blueMax = brightness * (1 - 0.42 * warmth)
        let blueGamma = gamma * (1 + 0.16 * warmth)

        CGSetDisplayTransferByFormula(
            displayID,
            0, redMax, gamma,
            0, greenMax, gamma,
            0, blueMax, blueGamma
        )
    }

    func applyNightShift(warmth value: Double, to displayID: CGDirectDisplayID) {
        let warmth = Float(value.clamped(to: 0...1))
        let redMax: Float = 1
        let greenMax = 1 - 0.24 * warmth
        let blueMax = 1 - 0.55 * warmth
        let redGamma: Float = 1
        let greenGamma: Float = 1
        let blueGamma = 1 + 0.22 * warmth

        CGSetDisplayTransferByFormula(
            displayID,
            0, redMax, redGamma,
            0, greenMax, greenGamma,
            0, blueMax, blueGamma
        )
    }

    func restore(displayID: CGDirectDisplayID) {
        CGDisplayRestoreColorSyncSettings()
    }
}
