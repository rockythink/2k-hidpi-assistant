import Foundation

enum DisplayPowerError: LocalizedError {
    case noDDCHelper
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDDCHelper:
            "没有找到可用的 DDC/CI 命令行工具。"
        case .commandFailed(let message):
            message
        }
    }
}

struct DisplayPowerService {
    private let nativeDDC = NativeDDCService()

    func physicalPowerOff(displayID: UInt32, displayIndex: Int) throws {
        var nativeErrors: [String] = []
        do {
            try nativeDDC.setPowerMode(4, for: displayID)
            return
        } catch {
            nativeErrors.append(error.localizedDescription)
        }

        do {
            try nativeDDC.setPowerMode(5, for: displayID)
            return
        } catch {
            nativeErrors.append(error.localizedDescription)
        }

        do {
            try runFirstAvailable(commands: [
            Command(
                executableCandidates: [
                    "/opt/homebrew/bin/ddcutil",
                    "/usr/local/bin/ddcutil",
                    "/usr/bin/ddcutil"
                ],
                arguments: ["--display", "\(displayIndex)", "setvcp", "D6", "4"]
            ),
            Command(
                executableCandidates: [
                    "/opt/homebrew/bin/ddcutil",
                    "/usr/local/bin/ddcutil",
                    "/usr/bin/ddcutil"
                ],
                arguments: ["--display", "\(displayIndex)", "setvcp", "D6", "5"]
            ),
            Command(
                executableCandidates: [
                    "/opt/homebrew/bin/ddcctl",
                    "/usr/local/bin/ddcctl",
                    "/usr/bin/ddcctl"
                ],
                arguments: ["-d", "\(displayIndex)", "-p", "4"]
            ),
            Command(
                executableCandidates: [
                    "/opt/homebrew/bin/ddcctl",
                    "/usr/local/bin/ddcctl",
                    "/usr/bin/ddcctl"
                ],
                arguments: ["-d", "\(displayIndex)", "-p", "5"]
            )
            ])
        } catch {
            throw DisplayPowerError.commandFailed(uniqueMessages(nativeErrors + [error.localizedDescription]).joined(separator: "\n"))
        }
    }

    func physicalPowerOn(displayID: UInt32, displayIndex: Int) throws {
        do {
            try nativeDDC.setPowerMode(1, for: displayID)
            return
        } catch {
            try runFirstAvailable(commands: [
            Command(
                executableCandidates: [
                    "/opt/homebrew/bin/ddcutil",
                    "/usr/local/bin/ddcutil",
                    "/usr/bin/ddcutil"
                ],
                arguments: ["--display", "\(displayIndex)", "setvcp", "D6", "1"]
            ),
            Command(
                executableCandidates: [
                    "/opt/homebrew/bin/ddcctl",
                    "/usr/local/bin/ddcctl",
                    "/usr/bin/ddcctl"
                ],
                arguments: ["-d", "\(displayIndex)", "-p", "1"]
            )
            ])
        }
    }

    private func runFirstAvailable(commands: [Command]) throws {
        var sawExecutable = false
        var failures: [String] = []

        for command in commands {
            guard let executable = command.existingExecutable else { continue }
            sawExecutable = true

            do {
                try run(executable: executable, arguments: command.arguments)
                return
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        if sawExecutable {
            throw DisplayPowerError.commandFailed(failures.joined(separator: "\n"))
        }
        throw DisplayPowerError.noDDCHelper
    }

    private func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw DisplayPowerError.commandFailed(output.isEmpty ? "\(executable) exited with \(process.terminationStatus)" : output)
        }
    }

    private func uniqueMessages(_ messages: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for message in messages {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}

private struct Command {
    var executableCandidates: [String]
    var arguments: [String]

    var existingExecutable: String? {
        executableCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
