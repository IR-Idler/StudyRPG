import Foundation
import Observation
import SwiftUI
import CryptoKit

// MARK: - DeckStore (game.md §4)

/// Owns every deck, persisted to Application Support/Decks/decks.json. Deleting a card or deck
/// also deletes its image files; editing a card's content bumps its `revision`.
@Observable
final class DeckStore {
    private(set) var decks: [Deck] = []

    private static var fileURL: URL {
        let dir = UserDataLocation.directory
            .appendingPathComponent("Decks", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("decks.json")
    }

    init() {
        load()
    }

    func isUsable(_ deck: Deck, minSize: Int) -> Bool {
        deck.cards.count >= minSize
    }

    func createDeck(name: String) {
        decks.append(Deck(name: name))
        save()
    }

    func renameDeck(_ deckID: UUID, to name: String) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        decks[index].name = name
        save()
    }

    func deleteDeck(_ deckID: UUID) {
        guard let deck = decks.first(where: { $0.id == deckID }) else { return }
        for card in deck.cards {
            deleteImages(of: card)
        }
        decks.removeAll { $0.id == deckID }
        save()
    }

    /// Adds an imported deck, or replaces the one imported earlier from the same file id (card
    /// ids are stable, so their stats carry over). Returns true if an existing deck was updated.
    @discardableResult
    func importDeck(_ deck: Deck) -> Bool {
        let updated = applyImportedDeck(deck)
        save()
        return updated
    }

    func importDecks(_ importedDecks: [Deck]) -> (added: [String], updated: [String], cardCount: Int) {
        var added: [String] = []
        var updated: [String] = []
        var cardCount = 0
        for deck in importedDecks {
            if applyImportedDeck(deck) {
                updated.append(deck.name)
            } else {
                added.append(deck.name)
            }
            cardCount += deck.cards.count
        }
        save()
        return (added, updated, cardCount)
    }

    private func applyImportedDeck(_ deck: Deck) -> Bool {
        if let index = decks.firstIndex(where: { $0.sourceID != nil && $0.sourceID == deck.sourceID }) {
            for card in decks[index].cards { deleteImages(of: card) }
            var updated = deck
            updated.id = decks[index].id
            // Bump revisions of cards whose content changed, like a manual edit would.
            let old = Dictionary(uniqueKeysWithValues: decks[index].cards.map { ($0.id, $0) })
            updated.cards = deck.cards.map { card in
                var card = card
                if let previous = old[card.id] {
                    let changed = previous.question != card.question || previous.answer != card.answer
                        || previous.wrongAnswers != card.wrongAnswers
                        || previous.prompt != card.prompt || previous.hint != card.hint
                        || previous.explanation != card.explanation || previous.reversible != card.reversible
                    card.revision = previous.revision + (changed ? 1 : 0)
                }
                return card
            }
            decks[index] = updated
            return true
        }
        decks.append(deck)
        return false
    }

    /// Whether any bundled starter deck is missing from the deck list (deleted or never added).
    func isMissingStarterDecks(_ starters: [Deck]) -> Bool {
        starters.contains { starter in !decks.contains { $0.sourceID == starter.sourceID } }
    }

    /// Adds the bundled starter decks (game.md §4.5). Like a re-import: a starter deck that's
    /// already there is refreshed in place, so its card stats survive.
    func addStarterDecks(_ starters: [Deck]) {
        _ = importDecks(starters)
    }

    /// Adds the starter decks once, on the very first launch that has them; never again after
    /// that, so deleting them sticks. The flag lives next to the decks, so test sandboxes
    /// (`UserDataLocation`) start fresh.
    func seedStarterDecksIfNeeded(_ starters: [Deck]) {
        let flag = UserDataLocation.directory.appendingPathComponent("Decks/.starterDecksSeeded")
        guard !starters.isEmpty, !FileManager.default.fileExists(atPath: flag.path) else { return }
        addStarterDecks(starters)
        FileManager.default.createFile(atPath: flag.path, contents: Data())
    }

    func setReverseCards(_ deckID: UUID, enabled: Bool) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        decks[index].reverseCards = enabled
        save()
    }

    func moveDecks(fromOffsets: IndexSet, toOffset: Int) {
        decks.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func addCard(_ card: Flashcard, toDeck deckID: UUID) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        decks[index].cards.append(card)
        save()
    }

    func updateCard(_ card: Flashcard, inDeck deckID: UUID) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }),
              let cardIndex = decks[deckIndex].cards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = card
        let old = decks[deckIndex].cards[cardIndex]
        if old.question != updated.question || old.answer != updated.answer || old.wrongAnswers != updated.wrongAnswers
            || old.prompt != updated.prompt || old.hint != updated.hint || old.explanation != updated.explanation
            || old.reversible != updated.reversible {
            updated.revision = old.revision + 1
            let obsoleteImages = imageIDs(of: old).subtracting(imageIDs(of: updated))
            for imageID in obsoleteImages {
                CardImageStore.delete(imageID)
            }
        }
        decks[deckIndex].cards[cardIndex] = updated
        save()
    }

    func deleteCard(_ cardID: UUID, fromDeck deckID: UUID) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }),
              let card = decks[deckIndex].cards.first(where: { $0.id == cardID }) else { return }
        deleteImages(of: card)
        decks[deckIndex].cards.removeAll { $0.id == cardID }
        save()
    }

    func moveCards(inDeck deckID: UUID, fromOffsets: IndexSet, toOffset: Int) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }) else { return }
        decks[deckIndex].cards.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    private func imageIDs(of card: Flashcard) -> Set<String> {
        var ids: Set<String> = []
        if let id = card.question.imageID { ids.insert(id) }
        if let id = card.answer.imageID { ids.insert(id) }
        for wrong in card.wrongAnswers {
            if let id = wrong.imageID { ids.insert(id) }
        }
        return ids
    }

    private func deleteImages(of card: Flashcard) {
        for id in imageIDs(of: card) {
            CardImageStore.delete(id)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        do {
            decks = try JSONDecoder().decode([Deck].self, from: data)
        } catch {
            // Never let the next save silently overwrite decks we couldn't read.
            UserDataBackup.preserve(Self.fileURL)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(decks) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

// MARK: - DeckImporter (game.md §4.4)

/// The on-disk deck format people import (`format: "studyrpg-deck"`, version 1). One JSON file
/// per deck; pictures are separate image files referenced by a path relative to the JSON file.
/// See game.md §4.4 and the README that ships next to exported decks.
nonisolated struct DeckFile: Codable, Sendable {
    struct Face: Codable, Sendable {
        var text: String?
        /// Path of a PNG/JPEG, relative to the deck JSON file.
        var image: String?
        /// SF Symbol name.
        var symbol: String?
        /// `#RRGGBB` swatch.
        var color: String?
    }

    struct Card: Codable, Sendable {
        /// Stable within the deck; keeps a card's stats when the deck is re-imported.
        var id: String
        var question: Face
        var answer: Face
        var wrongAnswers: [Face]?
        var prompt: String?
        var hint: String?
        var explanation: String?
        var reversible: Bool?
    }

    var format: String
    var version: Int
    /// Stable deck id; importing a file with the same id again updates that deck.
    var id: String
    var name: String
    var subtitle: String?
    var icon: String?
    var color: String?
    var reverseCards: Bool?
    var cards: [Card]

    static let formatName = "studyrpg-deck"
    static let currentVersion = 1
}

nonisolated enum DeckImporter {
    struct Progress: Sendable {
        var currentFileIndex: Int
        var totalFiles: Int
        var currentDeckName: String
        var completedCards: Int
        var totalCards: Int

        var fractionCompleted: Double {
            guard totalCards > 0 else {
                guard totalFiles > 0 else { return 0 }
                return Double(currentFileIndex) / Double(totalFiles)
            }
            return min(1, max(0, Double(completedCards) / Double(totalCards)))
        }
    }

    struct Report: Sendable {
        var added: [String] = []
        var updated: [String] = []
        var cardCount = 0
        var errors: [String] = []

        var summary: String {
            var lines: [String] = []
            if !added.isEmpty { lines.append(L("Added: \(added.joined(separator: ", "))")) }
            if !updated.isEmpty { lines.append(L("Updated: \(updated.joined(separator: ", "))")) }
            if added.isEmpty && updated.isEmpty && errors.isEmpty { lines.append(L("No deck files found.")) }
            if cardCount > 0 { lines.append(L("\(cardCount) cards")) }
            lines.append(contentsOf: errors)
            return lines.joined(separator: "\n")
        }
    }

    /// Asynchronously imports every deck JSON in the picked files and folders off the main thread,
    /// deduplicating shared image paths and reporting progress so the UI never freezes.
    @MainActor
    static func importItemsAsync(
        at urls: [URL],
        into store: DeckStore,
        onProgress: @escaping @MainActor (Progress) -> Void
    ) async -> Report {
        struct PendingDeck: Sendable {
            var url: URL
            var fileName: String
            var deckFile: DeckFile
        }

        let workerTask = Task.detached(priority: .userInitiated) { () -> (decks: [Deck], report: Report) in
            var report = Report()
            var scopedURLs: [URL] = []
            for url in urls {
                if url.startAccessingSecurityScopedResource() {
                    scopedURLs.append(url)
                }
            }
            defer {
                for url in scopedURLs {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let allCandidateFiles = urls.flatMap { deckFiles(at: $0) }
            var pendingDecks: [PendingDeck] = []

            for fileURL in allCandidateFiles {
                let fileName = fileURL.lastPathComponent
                do {
                    let data = try Data(contentsOf: fileURL)
                    guard let probe = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          probe["format"] as? String == DeckFile.formatName else { continue }
                    let deckFile = try JSONDecoder().decode(DeckFile.self, from: data)
                    guard deckFile.version <= DeckFile.currentVersion else {
                        report.errors.append(L("\(fileName): format version \(deckFile.version) is newer than this app supports"))
                        continue
                    }
                    guard !deckFile.name.trimmingCharacters(in: .whitespaces).isEmpty, !deckFile.id.isEmpty else {
                        report.errors.append(L("\(fileName): deck needs an id and a name"))
                        continue
                    }
                    pendingDecks.append(PendingDeck(url: fileURL, fileName: fileName, deckFile: deckFile))
                } catch {
                    report.errors.append(L("\(fileName): couldn't read (\(error.localizedDescription))"))
                }
            }

            let totalFiles = pendingDecks.count
            let totalCards = pendingDecks.reduce(0) { $0 + $1.deckFile.cards.count }
            var completedCards = 0
            var importedDecks: [Deck] = []

            for (fileIdx, pending) in pendingDecks.enumerated() {
                let deckFile = pending.deckFile
                let fileName = pending.fileName
                let currentProg = Progress(
                    currentFileIndex: fileIdx + 1,
                    totalFiles: totalFiles,
                    currentDeckName: deckFile.name,
                    completedCards: completedCards,
                    totalCards: totalCards
                )
                await onProgress(currentProg)

                let baseDirectory = pending.url.deletingLastPathComponent()
                var savedImages: [String] = []
                var imageCache: [String: String] = [:]
                var cards: [Flashcard] = []
                var problems: [String] = []
                var seenIDs = Set<String>()

                func face(_ source: DeckFile.Face, _ label: String, card: String) -> CardFace? {
                    var result = CardFace(text: source.text, symbol: source.symbol, color: source.color)
                    if let color = source.color, HexColor.parse(color) == nil {
                        problems.append(L("card \"\(card)\": \(label) color \"\(color)\" is not #RRGGBB"))
                        return nil
                    }
                    if let path = source.image {
                        let imageURL = baseDirectory.appendingPathComponent(path).standardizedFileURL
                        if let cachedID = imageCache[imageURL.path] {
                            result.imageID = cachedID
                        } else {
                            guard let image = PlatformImage(contentsOfFile: imageURL.path) else {
                                problems.append(L("card \"\(card)\": \(label) image \"\(path)\" not found"))
                                return nil
                            }
                            let id = CardImageStore.save(image)
                            savedImages.append(id)
                            imageCache[imageURL.path] = id
                            result.imageID = id
                        }
                    }
                    return result
                }

                for (cardOffset, card) in deckFile.cards.enumerated() {
                    defer { completedCards += 1 }
                    if cardOffset % 3 == 0 {
                        let stepProg = Progress(
                            currentFileIndex: fileIdx + 1,
                            totalFiles: totalFiles,
                            currentDeckName: deckFile.name,
                            completedCards: completedCards,
                            totalCards: totalCards
                        )
                        await onProgress(stepProg)
                    }
                    guard seenIDs.insert(card.id).inserted else {
                        problems.append(L("card \"\(card.id)\": duplicate id"))
                        continue
                    }
                    guard let question = face(card.question, L("question"), card: card.id),
                          let answer = face(card.answer, L("answer"), card: card.id) else { continue }
                    let wrong = (card.wrongAnswers ?? []).enumerated().compactMap {
                        face($0.element, L("wrong answer \($0.offset + 1)"), card: card.id)
                    }
                    let flashcard = Flashcard(
                        id: UUID.stable("\(deckFile.id)/\(card.id)"),
                        question: question,
                        answer: answer,
                        wrongAnswers: wrong,
                        prompt: card.prompt,
                        hint: card.hint,
                        explanation: card.explanation,
                        reversible: card.reversible
                    )
                    if let issue = flashcard.validationIssues.first {
                        problems.append(L("card \"\(card.id)\": \(issue)"))
                        continue
                    }
                    cards.append(flashcard)
                }

                guard problems.isEmpty else {
                    savedImages.forEach(CardImageStore.delete)
                    report.errors.append(contentsOf: problems.prefix(5).map { "\(fileName): \($0)" })
                    if problems.count > 5 {
                        report.errors.append(L("\(fileName): … and \(problems.count - 5) more problems"))
                    }
                    continue
                }

                let deck = Deck(
                    id: UUID.stable("deck/\(deckFile.id)"),
                    name: deckFile.name,
                    cards: cards,
                    subtitle: deckFile.subtitle,
                    icon: deckFile.icon,
                    color: deckFile.color,
                    reverseCards: deckFile.reverseCards,
                    sourceID: deckFile.id
                )
                importedDecks.append(deck)
            }

            let doneProg = Progress(
                currentFileIndex: totalFiles,
                totalFiles: totalFiles,
                currentDeckName: pendingDecks.last?.deckFile.name ?? "",
                completedCards: totalCards,
                totalCards: totalCards
            )
            await onProgress(doneProg)

            return (importedDecks, report)
        }

        let (importedDecks, partialReport) = await workerTask.value
        var finalReport = partialReport
        let batchResult = store.importDecks(importedDecks)
        finalReport.added = batchResult.added
        finalReport.updated = batchResult.updated
        finalReport.cardCount = batchResult.cardCount
        return finalReport
    }

    private static func deckFiles(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return url.pathExtension.lowercased() == "json" ? [url] : [] }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let next = enumerator?.nextObject() as? URL {
            if next.pathExtension.lowercased() == "json" { files.append(next) }
        }
        return files.sorted { $0.path < $1.path }
    }
}

extension UUID {
    /// Deterministic UUID from a string, so imported decks/cards keep their identity (and stats)
    /// across re-imports.
    nonisolated static func stable(_ key: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(key.utf8)))
        var bytes = (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                     digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15])
        bytes.6 = (bytes.6 & 0x0F) | 0x50 // name-based version
        bytes.8 = (bytes.8 & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: bytes)
    }
}
