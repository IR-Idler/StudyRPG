import Foundation

// MARK: - Discoveries (game.md §16.1)

/// Everything the player has met in any run, by content id — what the Glossary and Bestiary reveal.
/// Meta-progression: survives runs like card stats.
struct Discoveries: Codable, Equatable {
    var skills: Set<String> = []
    var potions: Set<String> = []
    var gear: Set<String> = []
    var relics: Set<String> = []
    var enemies: Set<String> = []

    init() {}

    /// Missing categories decode as empty, so categories added later don't break older files.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = try container.decodeIfPresent(Set<String>.self, forKey: .skills) ?? []
        potions = try container.decodeIfPresent(Set<String>.self, forKey: .potions) ?? []
        gear = try container.decodeIfPresent(Set<String>.self, forKey: .gear) ?? []
        relics = try container.decodeIfPresent(Set<String>.self, forKey: .relics) ?? []
        enemies = try container.decodeIfPresent(Set<String>.self, forKey: .enemies) ?? []
    }

    /// Adds `ids` to one category; returns whether anything was new.
    @discardableResult
    mutating func insert(_ ids: some Sequence<String>, into category: WritableKeyPath<Discoveries, Set<String>>) -> Bool {
        let before = self[keyPath: category].count
        self[keyPath: category].formUnion(ids)
        return self[keyPath: category].count != before
    }
}

/// User data in Application Support (`discoveries.json`), via `UserDataLocation` so tests never
/// touch the player's real file. An unreadable file is backed up, never silently overwritten.
nonisolated enum DiscoveryStore {
    private static var url: URL {
        let dir = UserDataLocation.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("discoveries.json")
    }

    static func load() -> Discoveries {
        guard let data = try? Data(contentsOf: url) else { return Discoveries() }
        guard let discoveries = try? JSONDecoder().decode(Discoveries.self, from: data) else {
            UserDataBackup.preserve(url)
            return Discoveries()
        }
        return discoveries
    }

    /// Marks `ids` as discovered. Only writes when something is new.
    static func record(_ ids: some Sequence<String>, in category: WritableKeyPath<Discoveries, Set<String>>) {
        var discoveries = load()
        guard discoveries.insert(ids, into: category),
              let data = try? JSONEncoder().encode(discoveries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
