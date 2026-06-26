import Foundation

struct PersistentSnapshot: Codable {
    var language: AppLanguage = .system
    var preferences: AppPreferences = AppPreferences()
    var presets: [DisplayPreset] = []
    var schedules: [DisplaySchedule] = []
    var syncSettings: DisplaySyncSettings = DisplaySyncSettings()
    var controlStates: [String: DisplayControlState] = [:]
    var globalShortcuts: [String: String] = [:]
    var customShortcuts: [String: String] = [:]
    var nightShiftEnabled: Bool = false

    init(
        language: AppLanguage = .system,
        preferences: AppPreferences = AppPreferences(),
        presets: [DisplayPreset] = [],
        schedules: [DisplaySchedule] = [],
        syncSettings: DisplaySyncSettings = DisplaySyncSettings(),
        controlStates: [String: DisplayControlState] = [:],
        globalShortcuts: [String: String] = [:],
        customShortcuts: [String: String] = [:],
        nightShiftEnabled: Bool = false
    ) {
        self.language = language
        self.preferences = preferences
        self.presets = presets
        self.schedules = schedules
        self.syncSettings = syncSettings
        self.controlStates = controlStates
        self.globalShortcuts = globalShortcuts
        self.customShortcuts = customShortcuts
        self.nightShiftEnabled = nightShiftEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        preferences = try container.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? AppPreferences()
        presets = try container.decodeIfPresent([DisplayPreset].self, forKey: .presets) ?? []
        schedules = try container.decodeIfPresent([DisplaySchedule].self, forKey: .schedules) ?? []
        syncSettings = try container.decodeIfPresent(DisplaySyncSettings.self, forKey: .syncSettings) ?? DisplaySyncSettings()
        controlStates = try container.decodeIfPresent([String: DisplayControlState].self, forKey: .controlStates) ?? [:]
        globalShortcuts = try container.decodeIfPresent([String: String].self, forKey: .globalShortcuts) ?? [:]
        customShortcuts = try container.decodeIfPresent([String: String].self, forKey: .customShortcuts) ?? [:]
        nightShiftEnabled = try container.decodeIfPresent(Bool.self, forKey: .nightShiftEnabled) ?? false
    }
}

struct PersistenceService {
    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "HiDPIBuddy/state.json")
    }

    func load() -> PersistentSnapshot {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PersistentSnapshot.self, from: data)
        } catch {
            return PersistentSnapshot()
        }
    }

    func save(_ snapshot: PersistentSnapshot) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("Failed to save HiDPIBuddy state: \(error.localizedDescription)")
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
