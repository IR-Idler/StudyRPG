import Foundation
import Observation
import SwiftUI
import CryptoKit

// MARK: - RunStore (game.md §3)

/// Saves the in-progress run so "Continue" works after the app is closed. One run at a time;
/// deleted when the run ends (victory, defeat or abandon — permadeath).
enum RunStore {
    private static var url: URL {
        let dir = UserDataLocation.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("currentRun.json")
    }

    static var hasSavedRun: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func save(_ snapshot: RunSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> RunSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RunSnapshot.self, from: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - LastDeckSelection (game.md §3)

/// The decks picked for the most recent run (`lastRunDecks.json`), so run setup starts with the
/// same selection next time. Ids of decks that no longer exist are simply ignored.
enum LastDeckSelection {
    private static var url: URL {
        let dir = UserDataLocation.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lastRunDecks.json")
    }

    /// `nil` when no run was ever started (setup then selects every usable deck).
    static func load() -> Set<UUID>? {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return nil }
        return Set(ids)
    }

    static func save(_ ids: Set<UUID>) {
        guard let data = try? JSONEncoder().encode(ids.sorted { $0.uuidString < $1.uuidString }) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The setup's starting selection: the last run's decks that are still usable, or every
    /// usable deck if there's no (usable) remembered selection.
    static func initialSelection(usable: [Deck]) -> Set<UUID> {
        let usableIDs = Set(usable.map(\.id))
        if let remembered = load()?.intersection(usableIDs), !remembered.isEmpty { return remembered }
        return usableIDs
    }
}

// MARK: - RunHistoryStore (game.md §3)

/// Every finished run, newest first — user data in Application Support (`runHistory.json`), kept
/// across runs like card stats. An unreadable file is backed up, never silently overwritten.
enum RunHistoryStore {
    private static var url: URL {
        let dir = UserDataLocation.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("runHistory.json")
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func load() -> [RunRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([RunRecord].self, from: data) else {
            UserDataBackup.preserve(url)
            return []
        }
        return records.sorted { $0.endedAt > $1.endedAt }
    }

    static func append(_ record: RunRecord) {
        var records = load()
        guard !records.contains(where: { $0.id == record.id }) else { return }
        records.insert(record, at: 0)
        guard let data = try? encoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
