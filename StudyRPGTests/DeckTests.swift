import Foundation
import Testing
@testable import StudyRPG

/// Deck editing and the `studyrpg-deck` import format (game.md §4, §4.4). Runs in the test sandbox.
@MainActor
@Suite("Decks and import")
struct DeckTests {
    init() { Fixtures.isolateUserData() }

    @Test("Create, rename, add a card, delete — and it all persists")
    func editing() throws {
        let store = DeckStore()
        store.createDeck(name: "Test")
        let deck = try #require(store.decks.last)
        store.renameDeck(deck.id, to: "Renamed")
        store.addCard(Flashcard(question: CardFace(text: "Hund"), answer: CardFace(text: "Dog")), toDeck: deck.id)

        let reloaded = DeckStore()
        let saved = try #require(reloaded.decks.first { $0.id == deck.id })
        #expect(saved.name == "Renamed")
        #expect(saved.cards.count == 1)

        reloaded.deleteDeck(deck.id)
        #expect(!DeckStore().decks.contains { $0.id == deck.id })
    }

    @Test("Editing a card's content bumps its revision; saving it unchanged doesn't")
    func revisions() throws {
        let store = DeckStore()
        store.createDeck(name: "Revisions")
        let deckID = try #require(store.decks.last?.id)
        var card = Flashcard(question: CardFace(text: "Katze"), answer: CardFace(text: "Cat"))
        store.addCard(card, toDeck: deckID)

        store.updateCard(card, inDeck: deckID)
        #expect(store.decks.last?.cards.first?.revision == 0)
        for edit in [{ (c: inout Flashcard) in c.answer = CardFace(text: "Kitty") },
                     { (c: inout Flashcard) in c.hint = "meow" },
                     { (c: inout Flashcard) in c.prompt = "Translate" }] {
            let before = store.decks.last?.cards.first?.revision ?? -1
            edit(&card)
            store.updateCard(card, inDeck: deckID)
            #expect(store.decks.last?.cards.first?.revision == before + 1)
        }
        store.deleteDeck(deckID)
    }

    @Test("Only decks with at least minDeckSize cards are usable")
    func usable() throws {
        let minSize = try Fixtures.content().balance.flashcards.minDeckSize
        let store = DeckStore()
        #expect(!store.isUsable(Fixtures.deck(minSize - 1), minSize: minSize))
        #expect(store.isUsable(Fixtures.deck(minSize), minSize: minSize))
    }

    // MARK: Import (game.md §4.4)

    /// Writes a `studyrpg-deck` file into a fresh folder and returns the folder.
    private func deckFolder(answer: String, version: Int = 1, extra: [String: String] = [:]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = """
        {"format": "studyrpg-deck", "version": \(version), "id": "test-animals", "name": "Animals",
         "cards": [
           {"id": "dog", "question": {"text": "Hund"}, "answer": {"text": "\(answer)"}},
           {"id": "cat", "question": {"text": "Katze"}, "answer": {"text": "Cat"}, "wrongAnswers": [{"text": "Cow"}]}
         ]}
        """
        try json.write(to: folder.appendingPathComponent("animals.json"), atomically: true, encoding: .utf8)
        for (name, content) in extra {
            try content.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return folder
    }

    private func importFolder(_ folder: URL, into store: DeckStore) async -> DeckImporter.Report {
        await DeckImporter.importItemsAsync(at: [folder], into: store, onProgress: { _ in })
    }

    @Test("Importing a folder adds its decks with stable card ids; other JSON is ignored")
    func importAdds() async throws {
        let store = DeckStore()
        let report = await importFolder(try deckFolder(answer: "Dog", extra: ["notes.json": #"{"hello": 1}"#]), into: store)
        #expect(report.added == ["Animals"])
        #expect(report.errors.isEmpty)
        let deck = try #require(store.decks.first { $0.sourceID == "test-animals" })
        #expect(deck.cards.count == 2)
        #expect(deck.cards.first?.id == UUID.stable("test-animals/dog"))
        #expect(deck.cards.last?.wrongAnswers.first?.text == "Cow")
        store.deleteDeck(deck.id)
    }

    @Test("Re-importing updates the deck in place, keeps ids (and stats), bumps only changed cards")
    func reimportUpdates() async throws {
        let store = DeckStore()
        _ = await importFolder(try deckFolder(answer: "Dog"), into: store)
        let original = try #require(store.decks.first { $0.sourceID == "test-animals" })

        let report = await importFolder(try deckFolder(answer: "Doggo"), into: store)
        #expect(report.updated == ["Animals"])
        let updated = try #require(store.decks.first { $0.sourceID == "test-animals" })
        #expect(store.decks.filter { $0.sourceID == "test-animals" }.count == 1, "re-import duplicated the deck")
        #expect(updated.id == original.id)
        #expect(updated.cards.map(\.id) == original.cards.map(\.id))
        #expect(updated.cards[0].revision == original.cards[0].revision + 1, "changed card not bumped")
        #expect(updated.cards[1].revision == original.cards[1].revision, "unchanged card bumped")
        store.deleteDeck(updated.id)
    }

    @Test("A deck file from a newer format version is reported, not imported")
    func rejectsNewerVersion() async throws {
        let store = DeckStore()
        let report = await importFolder(try deckFolder(answer: "Dog", version: DeckFile.currentVersion + 1), into: store)
        #expect(report.added.isEmpty && report.updated.isEmpty)
        #expect(!report.errors.isEmpty)
        #expect(!store.decks.contains { $0.sourceID == "test-animals" })
    }

    // MARK: Starter decks (game.md §4.5)

    @Test("The bundled starter decks load and are usable in a run")
    func starterDecksLoad() throws {
        let content = try Fixtures.content()
        let starters = content.starterDecks
        let minSize = content.balance.flashcards.minDeckSize
        #expect(!starters.isEmpty)
        for deck in starters {
            let count = deck.cards.count
            let allValid = deck.cards.allSatisfy { $0.isValid }
            #expect(count >= minSize, "\(deck.name) is too small for a run")
            #expect(allValid, "\(deck.name) has an invalid card")
            #expect(deck.sourceID != nil, "\(deck.name) needs a stable source id so re-adding keeps stats")
        }
        let uniqueIDs = Set(starters.map { $0.id })
        #expect(uniqueIDs.count == starters.count)
    }

    @Test("A broken starter deck fails loudly, naming starter_decks.json")
    func starterDeckValidation() throws {
        let minSize = try Fixtures.content().balance.flashcards.minDeckSize
        func card(_ id: String, answer: String = "A", image: String? = nil) -> DeckFile.Card {
            DeckFile.Card(id: id, question: DeckFile.Face(text: "Q\(id)", image: image), answer: DeckFile.Face(text: "\(answer)\(id)"))
        }
        func file(_ cards: [DeckFile.Card], color: String? = nil) -> DeckFile {
            DeckFile(format: DeckFile.formatName, version: 1, id: "broken", name: "Broken", color: color, cards: cards)
        }
        let good = (0..<minSize).map { card("c\($0)") }
        _ = try ContentLoader.starterDecks(from: [file(good)], minDeckSize: minSize)

        let broken: [DeckFile] = [
            file(Array(good.dropLast())),                       // too small for a run
            file(good + [card("c0")]),                          // duplicate card id
            file(good + [card("pic", image: "a.png")]),         // picture files aren't bundled
            file(good, color: "red"),                           // not #RRGGBB
        ]
        for deck in broken {
            do {
                _ = try ContentLoader.starterDecks(from: [deck], minDeckSize: minSize)
                Issue.record("a broken starter deck was accepted")
            } catch let error as ContentError {
                #expect(error.file == "starter_decks.json")
            }
        }
    }

    @Test("Starter decks are seeded once; deleting one afterwards sticks")
    func starterDecksSeedOnce() throws {
        let starters = try Fixtures.content().starterDecks
        let flag = UserDataLocation.directory.appendingPathComponent("Decks/.starterDecksSeeded")
        try? FileManager.default.removeItem(at: flag)
        let store = DeckStore()
        store.seedStarterDecksIfNeeded(starters)
        for starter in starters {
            #expect(store.decks.contains { $0.sourceID == starter.sourceID })
        }
        let first = try #require(starters.first)
        store.deleteDeck(first.id)
        store.seedStarterDecksIfNeeded(starters)
        #expect(!store.decks.contains { $0.sourceID == first.sourceID }, "a deleted starter deck came back")
        #expect(store.isMissingStarterDecks(starters))
        store.addStarterDecks(starters)
        #expect(store.decks.filter { $0.sourceID == first.sourceID }.count == 1)
        for starter in starters { store.deleteDeck(starter.id) }
    }

    @Test("Run setup starts with the last run's decks that are still usable")
    func rememberedDeckSelection() {
        let a = Fixtures.deck(4, name: "A"), b = Fixtures.deck(4, name: "B"), c = Fixtures.deck(4, name: "C")
        LastDeckSelection.save([a.id, c.id])
        #expect(LastDeckSelection.initialSelection(usable: [a, b, c]) == [a.id, c.id])
        // A remembered deck that's gone (or too small) is dropped; none left → every usable deck.
        #expect(LastDeckSelection.initialSelection(usable: [a, b]) == [a.id])
        #expect(LastDeckSelection.initialSelection(usable: [b]) == [b.id])
    }
}
