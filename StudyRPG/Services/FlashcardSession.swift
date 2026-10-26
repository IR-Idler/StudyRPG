import Foundation
import Observation
import SwiftUI
import CryptoKit

// MARK: - FlashcardSession (game.md §4)

/// One run's (or one Test Fight's) flashcard source: draws from the pooled decks with the usual
/// weighting and no-immediate-repeat rules, records every answer to the stats store and the
/// permanent answer log, and tallies this session's answers for the run recap. Shared by combat,
/// the shop haggle and events, so "don't repeat the last card" holds across all of them.
final class FlashcardSession {
    let decks: [Deck]
    private let statsStore: CardStatsStore
    private let cardWeightConfig: CardWeightConfig
    private let flashcardConfig: FlashcardConfig
    private var lastCardID: UUID?
    private var lastDeckID: UUID?
    private var currentCardRevision = 0
    private var current: PresentedCard?
    private var rng = SystemRandomNumberGenerator()
    private(set) var answered = 0
    private(set) var correct = 0
    /// Run context written into the answer history (game.md §4.2).
    var runID: UUID?
    var nodeDepth: Int?

    private let drawPool: [CardDrawer.PoolEntry]
    private let decksByID: [UUID: Deck]
    private var reversedDecks: [UUID: Deck] = [:]

    init(decks: [Deck], statsStore: CardStatsStore, balance: BalanceDef) {
        self.decks = decks
        self.statsStore = statsStore
        self.cardWeightConfig = balance.cardWeight
        self.flashcardConfig = balance.flashcards
        self.drawPool = CardDrawer.pool(for: decks)
        self.decksByID = Dictionary(uniqueKeysWithValues: decks.map { ($0.id, $0) })
    }

    private func deckForPresentation(id: UUID, isReversed: Bool) -> Deck? {
        guard let deck = decksByID[id] else { return nil }
        guard isReversed else { return deck }
        if let cached = reversedDecks[id] { return cached }
        let rev = deck.reversedDeck
        reversedDecks[id] = rev
        return rev
    }

    func present() -> PresentedCard? {
        guard let picked = CardDrawer.draw(
            pool: drawPool,
            lastCardID: lastCardID,
            lastDeckID: lastDeckID,
            weight: { [statsStore, cardWeightConfig] cardID in statsStore.weight(for: cardID, config: cardWeightConfig) }
        ) else { return nil }
        guard let deck = deckForPresentation(id: picked.deckID, isReversed: picked.isReversed) else { return nil }

        lastCardID = picked.card.id
        lastDeckID = picked.deckID
        currentCardRevision = picked.card.revision
        var presented = CardPresenter.present(card: picked.card, deck: deck,
                                              config: flashcardConfig, using: &rng)
        presented.isReversed = picked.isReversed
        current = presented
        return presented
    }

    /// Records the answer to the card last returned by `present()`; returns whether it was right.
    @discardableResult
    func record(chosenOptionIndex: Int?, responseMs: Int, skillID: String? = nil, enemy: EnemyDef? = nil) -> Bool {
        guard let presented = current else { return false }
        current = nil
        let isCorrect = chosenOptionIndex == presented.correctOptionIndex
        statsStore.record(cardID: presented.cardID, correct: isCorrect)
        AnswerLog.append(AnswerEvent(
            cardID: presented.cardID,
            deckID: presented.deckID,
            cardRevision: currentCardRevision,
            correct: isCorrect,
            wasNoneOfThese: presented.correctOptionIndex == nil,
            chosenIndex: chosenOptionIndex,
            optionSources: presented.options.map(\.source),
            responseMs: responseMs,
            reversed: presented.isReversed,
            runID: runID,
            nodeDepth: nodeDepth,
            enemyID: enemy?.id,
            enemyTier: enemy?.tier,
            skillID: skillID
        ))
        answered += 1
        if isCorrect { correct += 1 }
        return isCorrect
    }
}
