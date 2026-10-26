# Study RPG — Flashcards & decks

Part of the game design reference; `game.md` is the index. Section numbers (§) are shared across all docs.

## 4. Flashcards **[Built]**

### 4.1 Card format

- A card = one question + **one correct answer**, where each `CardFace` may have any combination of `text`, `imageID` (photo/illustration), `symbol` (SF Symbol), and `color` (`#RRGGBB` swatch — tints `symbol` if both are present, or renders as a color swatch alone). A card may also have any number of **author-written wrong answers** (same `CardFace` shape), optional.
- Optional card teaching fields:
  - `prompt`: short question framing shown above the question face on forward cards (e.g. `"Was ist das?"`). Not used when a card is asked in reverse; reverse cards show "⇄ Which one matches?" instead.
  - `hint`: clue hidden behind the **Hint** lightbulb button on the quiz overlay.
  - `explanation`: teaching note revealed on the quiz overlay after the player answers.
  - `reversible`: defaults to `true`. When `false`, the card is only asked in its forward direction even if the deck has `reverseCards` enabled (used for sentence/fill-in-the-blank/comparison questions).
- Optional deck metadata: `subtitle` (shown in deck lists and run setup), `icon` (SF Symbol), `color` (`#RRGGBB` tint), `sourceID` (stable id from an imported deck file), and `reverseCards` (`"Ask cards both ways"` toggle in the deck editor).
- **Reverse cards (`reverseCards: true`)**: every card in the deck with `reversible != false` also enters the draw pool in reverse (`answer` → `question`, using deterministic `reverseID` so forward and reverse stats are tracked separately, and drawing wrong answers from `deck.reversedDeck` so answer kinds match).
- When a card is presented, up to 3 author-written wrong answers are shuffled in first; any remaining slots are filled from other cards' correct answers **in the same deck** (or `reversedDeck` when reversed), preferring the same kind (picture-only vs text) as the correct answer, skipping anything that duplicates an answer already in the pool (trimmed, case-insensitive text match, or same image/symbol/color). When all 4 options are picture-only, the quiz overlay lays them out in a 2×2 tile grid; otherwise as vertical rows.
- **"None of these"**: with probability `balance.json → flashcards.noneOfTheseChance` (0.2), the correct answer is withheld and all 4 shown options are wrong; the player must recognize that none of them is right. This only happens if the card has at least 4 unique wrong-answer candidates (own + deck-fill combined); otherwise the card is shown normally. This is what stops a player from winning by elimination alone — they have to know the actual answer, not just rule out three options.
- The 4 shown options are shuffled on every presentation.
- **Teaching moments:** after answering, the overlay marks the right option (green check) and the chosen wrong one (red cross) and shows the card's `explanation` if it has one. A **wrong** answer waits for a tap on Continue (Settings → *Pause after a wrong answer*, on by default; with it off, it moves on after 1.6s). A **right** answer moves on immediately (Settings → *Pause after a right answer*, off by default; with it on, it waits for Continue too). The Continue button sits to the right of the question, so it never has to be scrolled to; its space is always reserved (invisible until needed), so the options never jump when it appears. Tall cards (pictures + hint + explanation) scroll instead of being cut off. Card text follows the system text size (up to 1.5×).
- A deck needs at least `balance.json → flashcards.minDeckSize` (4) cards before it can be used in a run — guarantees 3 cards' worth of deck-fill wrong answers. The deck editor shows "needs N more cards" below that threshold.
- Decks are created/edited in-app (deck editor): create/rename/delete decks, toggle "Ask cards both ways", add/delete/reorder cards, edit question/answer/wrong-answers (text, photo, SF Symbol, `#RRGGBB` color), and edit `prompt`, `hint`, `explanation`, and `reversible`.
- Images come from the user's Photos library, camera, or deck import, downscaled to a 1024px long edge (~0.8 JPEG quality), and stored as separate files in the app's own sandboxed storage — never embedded in JSON (agents.md).

### 4.2 Stats

- **Per-card stats are the base unit** (not just per-deck): every answer, including a "None of these" answer, adds 1 to that card's total and 1 to its correct count if right. When a deck has `reverseCards` enabled, forward (`card.id`) and reverse (`card.reverseID`) stats are tracked and weighted independently. Shown per-card (percentage + correct/total, or "Not answered yet") and can be reset per-card or per-deck.
- **Deck accuracy** = sum of correct ÷ sum of attempts across the deck's active cards (including reverse entries when `reverseCards` is enabled, not an average of each card's rate). Shown as a color-coded bar: ≥80% green, ≥50% gold, below that red, grey with no data yet (ported from an earlier prototype's thresholds).
- The deck editor can sort cards by "Weakest first" to surface the ones worth studying.
- **Answer history**: every answer is additionally logged as its own permanent record (card/deck id, the card's content-revision number, correct/incorrect, whether it was a "None of these" case, which option was chosen, where each of the 4 shown options came from, response time in ms, and — currently always empty — run/combat context for later use). This is strictly more than `CardStatsStore` needs today; it exists so later features (spaced repetition, confusion-pair detection, slow-but-correct detection, difficulty-to-enemy matching — see §16) can be built from history already being collected, without a data migration. Local only, never sent anywhere, never pruned.
- **Weighted redraw**: a card's draw weight is higher the worse its accuracy, read from `balance.json → cardWeight`:
  - `weight = cardWeight.noHistory` (0.9) for a card with no history yet.
  - `weight = cardWeight.base + (1 - accuracy)^cardWeight.accuracyExponent * cardWeight.accuracyScale` (0.35 + (1-acc)^1.5 × 1.65) once it has at least one attempt.
  - When drawing the next card: prefer a card that isn't the same card as the immediately previous draw (if alternatives exist), then prefer one from a different deck than the immediately previous draw (if alternatives exist), then pick randomly from the remaining pool weighted by the formula above.
- **[Future]** Using accuracy/difficulty tags to match harder cards to harder enemies is a stated future goal; the answer history above already captures what this would need, but no difficulty-based card selection ships now.

### 4.3 Where this lives in code

- `Models/FlashcardModels.swift` — `CardFace`, `Flashcard`, `Deck`, `AnswerOptionSource`, `PresentedOption`, `PresentedCard`, `AnswerEvent`.
- `Services/FlashcardServices.swift` — `CardImageStore`, `AnswerLog`, `UserDataBackup`, `CardStatsStore`, `CardPresenter`, `CardDrawer`. `Services/DeckStore.swift` — `DeckStore`, `DeckFile`, `DeckImporter`. `Services/FlashcardSession.swift` — the shared question source for fights/shop/events.
- `Views/DeckViews.swift` — `MasteryBar`, `ImageSlotView`, `CardFaceThumbnailView`, `CardEditorView`, `DeckEditorView`, `DeckListView`. `Views/FlashcardQuizOverlay.swift` — the quiz.
- `MyApp.swift` — creates and injects `DeckStore`/`CardStatsStore` via `.environment(...)`.

### 4.4 Deck import (`studyrpg-deck` v1) **[Built]**

- The deck manager (`DeckListView`) has an **Import** toolbar button that opens the system file importer, accepting `.json` files and folders. Picking a folder recursively imports every `studyrpg-deck` JSON file inside it.
- Each deck file uses `"format": "studyrpg-deck"` and `"version": 1`, with deck-level `id`, `name`, optional `subtitle`, `icon`, `color`, `reverseCards`, and `cards`.
- Each card in `cards` has a stable string `id` (hashed with the deck `id` into a deterministic `UUID` via `UUID.stable("<deck.id>/<card.id>")`), `question` and `answer` faces (`text`, relative `image` path, `symbol`, `color`), optional `wrongAnswers`, `prompt`, `hint`, `explanation`, and `reversible`.
- Relative `image` paths (e.g. `"images/art-dog.png"`) are resolved against the JSON file's directory and copied into `CardImageStore`.
- Re-importing a deck with the same `id` (`Deck.sourceID`) updates the existing deck in place, preserves its `UUID` and per-card `UUID`s so accuracy stats carry over, and bumps `revision` on any card whose content changed.

### 4.5 Starter decks **[Built]**

So there's always something to play with, the app ships three sample decks in `Content/starter_decks.json` (a `{"decks": [...]}` list of `studyrpg-deck` v1 decks, §4.4, without picture files — text, `symbol` and `color` faces only):
- **World Capitals** (16 cards, asked both ways; prompts, hints and explanations on some cards),
- **Colors & Signs** (14 picture cards: color swatches and SF Symbols ↔ names, asked both ways, so the reverse direction shows the 2×2 picture grid),
- **Quick Math** (12 mental-arithmetic cards with near-miss wrong answers, never reversed).

They're loaded and validated with the rest of the content (`ContentLoader.loadStarterDecks` → `GameContent.starterDecks`; a broken one fails loudly naming `starter_decks.json` and the deck/card — unique ids, `#RRGGBB` colors, no images, valid cards, at least `minDeckSize` cards). They get the same stable ids an import would (`UUID.stable`), so re-adding one keeps its stats.
- **Seeding:** added once, on the first launch that has them (`DeckStore.seedStarterDecksIfNeeded`; the flag file `Decks/.starterDecksSeeded` lives next to the decks). Deleting one afterwards sticks.
- **Re-adding:** the deck list offers **Add Starter Decks** in its ⋯ menu whenever one is missing, and on its empty state ("No decks yet" card with Add Starter Decks / New Deck). Re-adding refreshes a present starter deck in place, like a re-import.
