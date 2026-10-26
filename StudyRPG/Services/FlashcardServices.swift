import Foundation
import Observation
import SwiftUI
import CryptoKit

// MARK: - CardImageStore (game.md §4)

/// Saves/loads/deletes flashcard images on disk. Images are never embedded in JSON (agents.md).
/// See the file-layout note at the top of GameContent.swift's "Cards & decks" section for why this
/// lives here instead of its own file.
nonisolated enum CardImageStore {
    private static let directoryName = "CardImages"

    private static var directory: URL {
        let dir = UserDataLocation.directory
            .appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Downscales to a 1024px long edge and returns the new image's id. Saved as ~0.8-quality
    /// JPEG, or as PNG when the image has transparency (drawn pictures from imported decks).
    static func save(_ image: PlatformImage) -> String {
        let id = UUID().uuidString
        let resized = resized(image, maxDimension: 1024)
        if hasAlpha(resized), let png = resized.pngData() {
            try? png.write(to: directory.appendingPathComponent(id).appendingPathExtension("png"), options: .atomic)
        } else {
            let data = resized.jpegData(compressionQuality: 0.8) ?? Data()
            try? data.write(to: directory.appendingPathComponent(id).appendingPathExtension("jpg"), options: .atomic)
        }
        return id
    }

    static func load(_ id: String) -> PlatformImage? {
        for ext in ["jpg", "png"] {
            let url = directory.appendingPathComponent(id).appendingPathExtension(ext)
            if let data = try? Data(contentsOf: url) { return PlatformImage(data: data) }
        }
        return nil
    }

    static func delete(_ id: String) {
        for ext in ["jpg", "png"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(id).appendingPathExtension(ext))
        }
    }

    private static func hasAlpha(_ image: PlatformImage) -> Bool {
        guard let alpha = image.cgImage?.alphaInfo else { return false }
        return ![.none, .noneSkipFirst, .noneSkipLast].contains(alpha)
    }

    private static func resized(_ image: PlatformImage, maxDimension: CGFloat) -> PlatformImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension, longEdge > 0 else { return image }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return PlatformGraphics.image(size: newSize) { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - AnswerLog (game.md §4)

/// Append-only local history of every flashcard answer. Never sent anywhere, never pruned.
enum AnswerLog {
    private static var fileURL: URL {
        UserDataLocation.existingDirectory
            .appendingPathComponent("answerLog.jsonl")
    }

    static func append(_ event: AnswerEvent) {
        guard let data = try? JSONEncoder().encode(event),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        guard let lineData = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                try? handle.close()
            }
        } else {
            try? lineData.write(to: fileURL, options: .atomic)
        }
    }

    static func readAll() -> [AnswerEvent] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(AnswerEvent.self, from: data)
        }
    }
}

// MARK: - UserDataLocation (game.md §4.2, §3)

/// Where every user-data file lives (decks, card images, card stats, answer log, saved run, run
/// history). Application Support in the app (on Mac inside the app's sandbox container, game.md
/// §15); tests point it at a throwaway folder so they can never touch the player's real data.
nonisolated enum UserDataLocation {
    nonisolated(unsafe) static var directory: URL =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// `directory`, created first if it doesn't exist yet — a fresh install or Mac container may
    /// not have Application Support, and a write there would silently fail.
    static var existingDirectory: URL { ensureExists(directory) }

    @discardableResult
    static func ensureExists(_ dir: URL) -> URL {
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

// MARK: - UserDataBackup (game.md §4)

/// Keeps a copy of a user-data file that failed to decode (e.g. after a format change), so the
/// next save can't destroy the user's decks or stats. Copies sit next to the original as
/// `<name>.unreadable-<timestamp>.json`.
nonisolated enum UserDataBackup {
    static func preserve(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension()
            .appendingPathExtension("unreadable-\(stamp)")
            .appendingPathExtension(url.pathExtension)
        try? FileManager.default.copyItem(at: url, to: backup)
    }
}

// MARK: - CardStatsStore (game.md §4)

/// Per-card correct/total stats, the base unit stats are tracked at (game.md §4: cards have their
/// own accuracy, not just decks). Deck-level figures are derived by summing their cards' entries.
@Observable
final class CardStatsStore {
    struct Entry: Codable {
        var correct: Int = 0
        var total: Int = 0
    }

    private(set) var entries: [UUID: Entry] = [:]

    private static var fileURL: URL {
        UserDataLocation.existingDirectory
            .appendingPathComponent("cardStats.json")
    }

    init() {
        load()
    }

    func record(cardID: UUID, correct: Bool) {
        var entry = entries[cardID] ?? Entry()
        entry.total += 1
        if correct { entry.correct += 1 }
        entries[cardID] = entry
        save()
    }

    func stats(for cardID: UUID) -> (correct: Int, total: Int) {
        let entry = entries[cardID] ?? Entry()
        return (entry.correct, entry.total)
    }

    func accuracy(for cardID: UUID) -> Double? {
        guard let entry = entries[cardID], entry.total > 0 else { return nil }
        return Double(entry.correct) / Double(entry.total)
    }

    /// See game.md §4 for the weight formula; numbers come from balance.json → cardWeight.
    func weight(for cardID: UUID, config: CardWeightConfig) -> Double {
        guard let accuracy = accuracy(for: cardID) else { return config.noHistory }
        return config.base + pow(1 - accuracy, config.accuracyExponent) * config.accuracyScale
    }

    /// Sum of correct ÷ sum of attempts across the deck's cards (game.md §4).
    func deckAccuracy(_ deck: Deck) -> Double? {
        var correct = 0
        var total = 0
        for card in deck.cards {
            for id in [card.id, card.reverseID] {
                let entry = entries[id] ?? Entry()
                correct += entry.correct
                total += entry.total
            }
        }
        guard total > 0 else { return nil }
        return Double(correct) / Double(total)
    }

    func reset(cardID: UUID) {
        entries[cardID] = nil
        entries[Flashcard.reverseID(of: cardID)] = nil
        save()
    }

    func reset(deck: Deck) {
        for card in deck.cards {
            entries[card.id] = nil
            entries[card.reverseID] = nil
        }
        save()
    }

    /// Rebuilds all stats from the answer history. The log is the source of truth if this file
    /// and the log ever disagree (game.md §4).
    func rebuildFromLog() {
        var rebuilt: [UUID: Entry] = [:]
        for event in AnswerLog.readAll() {
            var entry = rebuilt[event.cardID] ?? Entry()
            entry.total += 1
            if event.correct { entry.correct += 1 }
            rebuilt[event.cardID] = entry
        }
        entries = rebuilt
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        do {
            entries = try JSONDecoder().decode([UUID: Entry].self, from: data)
        } catch {
            // The answer log is the source of truth: keep the unreadable file and rebuild from it.
            UserDataBackup.preserve(Self.fileURL)
            rebuildFromLog()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

// MARK: - CardPresenter (game.md §4)

/// Builds what's shown for a card: exactly 4 options, the author's own wrong answers first, then
/// filled from other cards in the same deck (preferring the same kind — text vs image — as the
/// correct answer), deduplicated, and sometimes ("None of these") withholding the correct answer
/// so elimination alone can't win.
enum CardPresenter {
    static func present(
        card: Flashcard,
        deck: Deck,
        config: FlashcardConfig,
        using rng: inout some RandomNumberGenerator
    ) -> PresentedCard {
        let correctIsImage = card.answer.isPictureOnly

        var pool: [PresentedOption] = card.wrongAnswers
            .shuffled(using: &rng)
            .map { PresentedOption(face: $0, source: .ownWrong) }

        if pool.count < 4 {
            var sameKindIndices: [Int] = []
            var otherKindIndices: [Int] = []
            sameKindIndices.reserveCapacity(min(deck.cards.count, 64))

            for (i, c) in deck.cards.enumerated() {
                guard c.id != card.id else { continue }
                if c.answer.isPictureOnly == correctIsImage {
                    sameKindIndices.append(i)
                } else {
                    otherKindIndices.append(i)
                }
            }

            sameKindIndices.shuffle(using: &rng)
            for idx in sameKindIndices {
                let other = deck.cards[idx]
                let candidate = PresentedOption(face: other.answer, source: .deckFill(cardID: other.id))
                let isDuplicate = candidate.face.matches(card.answer) || pool.contains { $0.face.matches(candidate.face) }
                if !isDuplicate {
                    pool.append(candidate)
                    if pool.count >= 4 { break }
                }
            }

            if pool.count < 4 {
                otherKindIndices.shuffle(using: &rng)
                for idx in otherKindIndices {
                    let other = deck.cards[idx]
                    let candidate = PresentedOption(face: other.answer, source: .deckFill(cardID: other.id))
                    let isDuplicate = candidate.face.matches(card.answer) || pool.contains { $0.face.matches(candidate.face) }
                    if !isDuplicate {
                        pool.append(candidate)
                        if pool.count >= 4 { break }
                    }
                }
            }
        }

        let canOmitCorrect = pool.count >= 4
        let omitCorrect = canOmitCorrect && Double.random(in: 0..<1, using: &rng) < config.noneOfTheseChance

        var options: [PresentedOption]
        let correctOptionIndex: Int?

        if omitCorrect {
            options = Array(pool.prefix(4))
            options.shuffle(using: &rng)
            correctOptionIndex = nil
        } else {
            options = Array(pool.prefix(3)) + [PresentedOption(face: card.answer, source: .correct)]
            options.shuffle(using: &rng)
            correctOptionIndex = options.firstIndex { $0.source == .correct }
        }

        return PresentedCard(
            cardID: card.id,
            deckID: deck.id,
            question: card.question,
            options: options,
            correctOptionIndex: correctOptionIndex,
            prompt: card.prompt,
            hint: card.hint,
            explanation: card.explanation
        )
    }
}

// MARK: - CardDrawer (game.md §4)

/// Picks the next card to show: skip the previous card, then the previous deck (if alternatives
/// exist), then a weighted random pick favoring cards with worse accuracy.
enum CardDrawer {
    struct PoolEntry {
        var card: Flashcard
        var deckID: UUID
        /// `card` is the reversed version of an authored card (game.md §4 reverse cards).
        var isReversed: Bool = false
    }

    /// Every askable card of these decks: each card, plus its reverse when the deck asks both ways.
    static func pool(for decks: [Deck]) -> [PoolEntry] {
        decks.flatMap { deck in
            deck.cards.flatMap { card -> [PoolEntry] in
                var entries = [PoolEntry(card: card, deckID: deck.id)]
                if deck.includesReverse, card.reversible != false {
                    entries.append(PoolEntry(card: card.reversed, deckID: deck.id, isReversed: true))
                }
                return entries
            }
        }
    }

    static func draw(
        pool: [PoolEntry],
        lastCardID: UUID?,
        lastDeckID: UUID?,
        weight: (UUID) -> Double
    ) -> PoolEntry? {
        guard !pool.isEmpty else { return nil }

        let hasDifferentCard = lastCardID != nil && pool.contains(where: { $0.card.id != lastCardID })
        let excludeCardID = hasDifferentCard ? lastCardID : nil

        let hasDifferentDeck = lastDeckID != nil && pool.contains(where: {
            (excludeCardID == nil || $0.card.id != excludeCardID) && $0.deckID != lastDeckID
        })
        let excludeDeckID = hasDifferentDeck ? lastDeckID : nil

        var validIndices: [Int] = []
        validIndices.reserveCapacity(pool.count)
        var weights: [Double] = []
        weights.reserveCapacity(pool.count)
        var total = 0.0

        for i in 0..<pool.count {
            let entry = pool[i]
            if let excludeCardID, entry.card.id == excludeCardID { continue }
            if let excludeDeckID, entry.deckID == excludeDeckID { continue }
            let w = weight(entry.card.id)
            validIndices.append(i)
            weights.append(w)
            total += w
        }

        guard total > 0 else {
            return validIndices.randomElement().map { pool[$0] } ?? pool.randomElement()
        }

        var roll = Double.random(in: 0..<total)
        for (idx, poolIdx) in validIndices.enumerated() {
            roll -= weights[idx]
            if roll <= 0 { return pool[poolIdx] }
        }
        return validIndices.last.map { pool[$0] } ?? pool.last
    }
}
