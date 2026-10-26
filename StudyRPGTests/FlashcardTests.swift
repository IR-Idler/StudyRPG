import Foundation
import Testing
@testable import StudyRPG

/// Card weighting, drawing, presentation and accuracy (game.md §4).
@MainActor
@Suite("Flashcards")
struct FlashcardTests {
    init() { Fixtures.isolateUserData() }

    // MARK: User data folder (game.md §4.2, §15)

    @Test("The user-data folder is created before writing when it doesn't exist yet (fresh install or Mac container)")
    func userDataFolderIsCreated() throws {
        let fresh = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyRPGTests-fresh-\(UUID().uuidString)/Application Support", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fresh.deletingLastPathComponent()) }
        #expect(!FileManager.default.fileExists(atPath: fresh.path))
        let dir = UserDataLocation.ensureExists(fresh)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        try Data("x".utf8).write(to: dir.appendingPathComponent("probe"), options: .atomic)
    }

    // MARK: Weight & accuracy (game.md §4.2)

    @Test("Card weight follows the balance.json formula: unseen, 100% and 0% accuracy")
    func weightFormula() throws {
        let config = try Fixtures.content().balance.cardWeight
        let store = CardStatsStore()
        let perfect = UUID(), hopeless = UUID(), unseen = UUID()
        defer { store.reset(cardID: perfect); store.reset(cardID: hopeless) }

        store.record(cardID: perfect, correct: true)
        store.record(cardID: hopeless, correct: false)

        #expect(store.weight(for: unseen, config: config) == config.noHistory)
        #expect(store.weight(for: perfect, config: config) == config.base)
        #expect(abs(store.weight(for: hopeless, config: config) - (config.base + config.accuracyScale)) < 1e-9)
        // Getting a card wrong must make it come back more often than getting it right.
        #expect(store.weight(for: hopeless, config: config) > store.weight(for: perfect, config: config))
    }

    @Test("Deck accuracy is Σcorrect ÷ Σattempts, not an average of card rates")
    func deckAccuracyIsPooled() {
        let store = CardStatsStore()
        let deck = Fixtures.deck(2)
        defer { store.reset(deck: deck) }

        store.record(cardID: deck.cards[0].id, correct: true)          // 1/1
        store.record(cardID: deck.cards[1].id, correct: true)          // 1/3
        store.record(cardID: deck.cards[1].id, correct: false)
        store.record(cardID: deck.cards[1].id, correct: false)

        // Pooled: 2/4 = 0.5. An average of rates would be (1 + 1/3) / 2 ≈ 0.667.
        #expect(store.deckAccuracy(deck) == 0.5)
    }

    // MARK: Drawing (game.md §4)

    @Test("The drawer returns nothing for an empty pool")
    func emptyPool() {
        #expect(CardDrawer.draw(pool: [], lastCardID: nil, lastDeckID: nil, weight: { _ in 1 }) == nil)
    }

    @Test("The drawer never repeats the previous card when there's another one")
    func noImmediateRepeat() throws {
        let pool = CardDrawer.pool(for: [Fixtures.deck(2)])
        let last = pool[0].card.id
        for _ in 0..<500 {
            let drawn = try #require(CardDrawer.draw(pool: pool, lastCardID: last, lastDeckID: nil, weight: { _ in 1 }))
            #expect(drawn.card.id != last)
        }
    }

    @Test("The drawer switches decks when another deck is active")
    func prefersOtherDeck() throws {
        let a = Fixtures.deck(3, name: "A"), b = Fixtures.deck(3, name: "B")
        let pool = CardDrawer.pool(for: [a, b])
        for _ in 0..<300 {
            let drawn = try #require(CardDrawer.draw(pool: pool, lastCardID: nil, lastDeckID: a.id, weight: { _ in 1 }))
            #expect(drawn.deckID == b.id)
        }
    }

    @Test("Heavier cards are drawn proportionally more often")
    func weightedDraw() throws {
        let pool = CardDrawer.pool(for: [Fixtures.deck(2)])
        let heavy = pool[0].card.id
        let trials = 6000
        var heavyCount = 0
        for _ in 0..<trials {
            let drawn = try #require(CardDrawer.draw(pool: pool, lastCardID: nil, lastDeckID: nil, weight: { $0 == heavy ? 3 : 1 }))
            if drawn.card.id == heavy { heavyCount += 1 }
        }
        // Expected share 3/4; allow a generous margin for randomness.
        #expect(abs(Double(heavyCount) / Double(trials) - 0.75) < 0.04)
    }

    // MARK: Presentation (game.md §4.1)

    @Test("A presented card always has 4 distinct options with the answer at most once")
    func presentsFourUniqueOptions() throws {
        let config = try Fixtures.content().balance.flashcards
        let deck = Fixtures.deck(6)
        var rng = SeededRNG(seed: 42)
        for trial in 0..<500 {
            let card = deck.cards[trial % deck.cards.count]
            let presented = CardPresenter.present(card: card, deck: deck, config: config, using: &rng)
            let texts = presented.options.compactMap(\.face.text)
            #expect(presented.options.count == 4)
            #expect(Set(texts).count == 4)
            let correctCount = presented.options.filter { $0.source == .correct }.count
            if let index = presented.correctOptionIndex {
                #expect(correctCount == 1)
                #expect(presented.options[index].face == card.answer)
            } else {
                #expect(correctCount == 0, "a 'None of these' card must not show the answer")
            }
        }
    }

    @Test("Own wrong answers are used before deck-fill ones")
    func ownWrongAnswersFirst() throws {
        let config = try Fixtures.content().balance.flashcards
        var deck = Fixtures.deck(6)
        deck.cards[0].wrongAnswers = [CardFace(text: "own1"), CardFace(text: "own2")]
        var rng = SeededRNG(seed: 7)
        for _ in 0..<200 {
            let presented = CardPresenter.present(card: deck.cards[0], deck: deck, config: config, using: &rng)
            let own = presented.options.filter { $0.source == .ownWrong }.count
            #expect(own == 2)
        }
    }

    @Test("'None of these' appears at about balance.json's noneOfTheseChance")
    func noneOfTheseRate() throws {
        let config = try Fixtures.content().balance.flashcards
        let deck = Fixtures.deck(6)
        var rng = SeededRNG(seed: 2026)
        let trials = 4000
        var withheld = 0
        for trial in 0..<trials {
            let presented = CardPresenter.present(card: deck.cards[trial % deck.cards.count], deck: deck, config: config, using: &rng)
            if presented.correctOptionIndex == nil { withheld += 1 }
        }
        #expect(abs(Double(withheld) / Double(trials) - config.noneOfTheseChance) < 0.03)
    }

    @Test("A deck too small to fill 4 options never withholds the answer")
    func smallDeckAlwaysShowsAnswer() throws {
        let config = try Fixtures.content().balance.flashcards
        let deck = Fixtures.deck(3)
        var rng = SeededRNG(seed: 1)
        for _ in 0..<300 {
            let presented = CardPresenter.present(card: deck.cards[0], deck: deck, config: config, using: &rng)
            #expect(presented.correctOptionIndex != nil)
        }
    }

    @Test("Large decks (3,000 cards) present questions quickly with valid unique options")
    func largeDeckPerformanceAndUniqueness() throws {
        let content = try Fixtures.content()
        let count = 3000
        let cards = (0..<count).map { i in
            Flashcard(
                id: UUID(),
                question: CardFace(text: "Q\(i)"),
                answer: CardFace(text: "A\(i)")
            )
        }
        let deck = Deck(name: "Large", cards: cards, reverseCards: true)
        let store = CardStatsStore()
        let session = FlashcardSession(decks: [deck], statsStore: store, balance: content.balance)

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10 {
            let presented = try #require(session.present())
            #expect(presented.options.count == 4)
            let texts = presented.options.compactMap(\.face.text)
            #expect(Set(texts).count == 4)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) / 10.0
        #expect(elapsed < 0.05)
    }
}
