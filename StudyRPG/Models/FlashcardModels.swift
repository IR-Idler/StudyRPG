import Foundation

// MARK: - Cards & decks (user-authored; see game.md §4)
//
// NOTE ON FILE LAYOUT: these types, plus the services in ContentLoader.swift and the views in
// ContentView.swift, were written as one logical feature (the flashcard/deck editor) but appended
// into these existing files rather than split into new ones. New files created in this project
// during this session were not reliably picked up by the Xcode build (they either compiled as
// bundle resources instead of Swift sources, or vanished from the project model on relaunch, with
// no persisted trace in project.pbxproj) and this could not be fixed without editing project.pbxproj
// directly, which is unsafe to do while Xcode is open. Consolidating into known-good files was the
// reliable path. If/when new files become safe to add in this project again, these are natural
// candidates to split out: Flashcard.swift, AnswerEvent.swift (both below), and — from
// ContentLoader.swift — CardImageStore, AnswerLog, CardStatsStore, CardPresenter, CardDrawer,
// DeckStore; and — from ContentView.swift — MasteryBar, ImageSlotView, CardEditorView,
// DeckEditorView, DeckListView.

/// One side of a card or one answer: text and/or a picture. A picture is a stored image, an SF
/// Symbol, or a color swatch. At least one part must be set for a face to be non-empty.
/// `imageID` names a file in `CardImageStore`, never raw image data (agents.md: never embed binary content in JSON).
nonisolated struct CardFace: Codable, Hashable, Sendable {
    var text: String? = nil
    var imageID: String? = nil
    /// SF Symbol name used as the picture (e.g. from an imported deck).
    var symbol: String? = nil
    /// `#RRGGBB` color swatch used as the picture (e.g. for color vocabulary).
    var color: String? = nil

    private var trimmedText: String? {
        guard let text, !text.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasPicture: Bool { imageID != nil || symbol != nil || color != nil }

    var isEmpty: Bool { !hasPicture && trimmedText == nil }

    /// A picture with no text — such answers are filled with other picture answers (game.md §4).
    var isPictureOnly: Bool { hasPicture && trimmedText == nil }

    /// Whether two faces should be treated as the same answer for dedup purposes (game.md §4 rule 1):
    /// trimmed, case-insensitive text match, or the identical picture when both are picture-only.
    func matches(_ other: CardFace) -> Bool {
        if let mine = trimmedText?.lowercased(), mine == other.trimmedText?.lowercased() {
            return true
        }
        if isPictureOnly, other.isPictureOnly {
            if let imageID, imageID == other.imageID { return true }
            if let symbol, symbol == other.symbol { return true }
            if let color, color.lowercased() == other.color?.lowercased() { return true }
        }
        return false
    }
}

/// A user-authored flashcard: one question, one correct answer, and optional author-written wrong answers.
/// Missing wrong-answer slots are filled from other cards in the same deck at presentation time (game.md §4).
nonisolated struct Flashcard: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var question: CardFace
    var answer: CardFace
    var wrongAnswers: [CardFace] = []
    /// Bumped by DeckStore whenever question/answer/wrongAnswers change, so stats from old wording
    /// can be told apart in the answer history (game.md §4).
    var revision: Int = 0
    /// Short instruction shown above the question (e.g. "Was sagst du?"). Forward direction only.
    var prompt: String? = nil
    /// Optional hint behind the light-bulb button.
    var hint: String? = nil
    /// Shown after answering (e.g. "die Giraffe = 长颈鹿").
    var explanation: String? = nil
    /// Overrides the deck's reverse setting for this card (`false` = never asked backwards).
    var reversible: Bool? = nil

    /// Stable id of this card's reverse direction (answer → question), which keeps its own stats.
    var reverseID: UUID { Flashcard.reverseID(of: id) }

    static func reverseID(of id: UUID) -> UUID {
        var bytes = id.uuid
        bytes.0 ^= 0xFF
        bytes.15 ^= 0xFF
        return UUID(uuid: bytes)
    }

    /// The same card asked backwards: the answer becomes the question. Its wrong answers come only
    /// from other cards' questions (deck fill), since the author's wrong answers belong to the
    /// forward direction.
    var reversed: Flashcard {
        Flashcard(id: reverseID, question: answer, answer: question, wrongAnswers: [], revision: revision,
                  prompt: nil, hint: hint, explanation: explanation, reversible: false)
    }

    /// Reasons this card can't be saved yet. Empty means the card is valid.
    var validationIssues: [String] {
        var issues: [String] = []
        if question.isEmpty {
            issues.append(L("Question is empty."))
        }
        if answer.isEmpty {
            issues.append(L("Correct answer is empty."))
        }
        for (index, wrong) in wrongAnswers.enumerated() {
            if wrong.isEmpty {
                issues.append(L("Wrong answer \(index + 1) is empty."))
            } else if wrong.matches(answer) {
                issues.append(L("Wrong answer \(index + 1) duplicates the correct answer."))
            }
        }
        return issues
    }

    var isValid: Bool { validationIssues.isEmpty }
}

/// A deck of user-authored cards, pooled with other active decks during a run (game.md §3).
nonisolated struct Deck: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var cards: [Flashcard] = []
    /// Second title line, e.g. the translation of the deck name.
    var subtitle: String? = nil
    /// SF Symbol shown for the deck.
    var icon: String? = nil
    /// `#RRGGBB` accent color for the deck.
    var color: String? = nil
    /// Also ask every card backwards (answer → question), each direction with its own stats.
    var reverseCards: Bool? = nil
    /// The imported deck file's `id`, so re-importing updates this deck instead of duplicating it.
    var sourceID: String? = nil

    var includesReverse: Bool { reverseCards ?? false }

    /// Every reversible card as asked backwards, for the reverse direction's deck-fill wrong answers.
    var reversedDeck: Deck {
        var copy = self
        copy.cards = cards.filter { $0.reversible != false }.map(\.reversed)
        return copy
    }
}

// MARK: - Card presentation (game.md §4)

/// Where a shown option's content came from, recorded in the answer history for later analysis.
enum AnswerOptionSource: Codable, Hashable {
    case correct
    case ownWrong
    case deckFill(cardID: UUID)
}

struct PresentedOption: Codable, Hashable {
    var face: CardFace
    var source: AnswerOptionSource
}

/// A card as shown to the player: 4 options, shuffled, plus optional prompt/hint/explanation
/// and an optional "None of these" state (`correctOptionIndex == nil` when enabled in balance.json).
struct PresentedCard {
    var cardID: UUID
    var deckID: UUID
    var question: CardFace
    var options: [PresentedOption]
    var correctOptionIndex: Int?
    var prompt: String? = nil
    var hint: String? = nil
    var explanation: String? = nil
    /// Asked backwards (answer → question); `cardID` is then the card's `reverseID`.
    var isReversed: Bool = false
}

// MARK: - Answer history (game.md §4)

/// One flashcard answer, as a permanent local record. Never pruned, never sent anywhere.
///
/// Intentionally richer than what `CardStatsStore` needs today — the extra fields (timing, option
/// sources, run context) exist so future features (spaced repetition, confusion pairs,
/// difficulty-to-enemy matching — game.md §16) can be built from history we already have, without
/// a data migration.
struct AnswerEvent: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date = Date()

    var cardID: UUID
    var deckID: UUID
    /// The card's `Flashcard.revision` at the moment it was shown.
    var cardRevision: Int

    var correct: Bool
    var wasNoneOfThese: Bool
    /// Index into the presented options the player chose, or `nil` if they chose "None of these".
    var chosenIndex: Int?
    /// Where each of the 4 shown options came from.
    var optionSources: [AnswerOptionSource]
    /// Milliseconds from options becoming visible to the tap being registered.
    var responseMs: Int
    /// Whether the card was asked backwards (answer → question). Nil in events logged before reverse cards existed.
    var reversed: Bool? = nil

    // Run context (filled for run answers; skill/enemy only in combat).
    var runID: UUID?
    var nodeDepth: Int?
    var enemyID: String?
    var enemyTier: EnemyTier?
    var skillID: String?
    var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
}
