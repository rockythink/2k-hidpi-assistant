import Foundation

struct PersistentSnapshot: Codable {
    var language: AppLanguage
    var presets: [DisplayPreset]

    init(language: AppLanguage = .system, presets: [DisplayPreset] = []) {
        self.language = language
        self.presets = presets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        presets = try container.decodeIfPresent([DisplayPreset].self, forKey: .presets) ?? []
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
            NSLog("Failed to save PixelFit state: \(error.localizedDescription)")
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
