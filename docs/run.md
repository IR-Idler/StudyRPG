# Study RPG — Run structure, shop, campfire, events

Part of the game design reference; `game.md` is the index. Section numbers (§) are shared across all docs.

## 3. Run structure **[Built]**

- **Setup:** pick exactly 2 heroes of *different* classes. Today Warrior + Wizard are the only two, so both start preselected; tapping a third class would replace the oldest pick. Then pick any number (≥1) of decks with at least `minDeckSize` cards — every usable deck starts selected, tap to leave some out (`DeckPickerList`, shared with Test Fight). **The decks picked for the last run start selected** (`LastDeckSelection`, `lastRunDecks.json` in Application Support, via `UserDataLocation`); remembered decks that were deleted or are too small are dropped, and if none are left every usable deck starts selected (also on the very first run); a status line shows the pooled card count, and the gold **Begin** button sits bottom-right. All selected decks pool into one shared draw source (`FlashcardSession`), used by combat, the shop haggle and events alike, so the no-immediate-repeat rule holds across all of them.
- The run is one map per **act**, each from its start to its boss; beating an act's boss leads to the next act's map, the last act's boss wins the run (§16.0: The Old Kingdom, then Neon Frontier).
- **Carried between nodes** (`RunState`): each hero's HP, mana, permanent bonus max HP, known and equipped skills (§5) and worn gear (§6); gold; potions (max `maxPotionsCarried`); the gear bag; relics; campfire training stacks; and run stats (fights won, gold earned, cards answered/correct).
- **Saving:** the run is saved (`RunStore` → Application Support `currentRun.json`, a `RunSnapshot`) when it starts and after every change. **Everything random a node offers is rolled once and saved the moment it's first seen**, so closing the app can never re-roll or replay it: a fight's encounter and its victory reward (gold, relic, potion, gear, skill offer), a shop's stock, sold items and haggle result, an event's identity and — once answered — its outcome, and a pending skill offer. A fight in progress is not saved: closing the app mid-fight restarts that same encounter with the party's pre-fight state and the same reward. Content is saved by id and re-resolved on load (unknown ids are dropped). Fields added later are optional, so older saves still load. If the run's decks were deleted, every usable deck is used instead.
- **No retreat:** run fights have no back button. Abandoning the run happens on the map (flag button → confirmation) and is permadeath.
- **Permadeath:** if both heroes fall, or the run is abandoned, the run ends and its save is deleted. The only things that persist across runs are the decks, the flashcard accuracy history (§4.2), the run history and the Glossary/Bestiary discoveries (§16.1).
- **Fallen heroes:** a hero who falls during a fight that the party still wins gets back up afterwards at **half their max HP** (rounded down, min 1). Campfire Rest heals everyone. Event heals and potions affect living heroes only.
- **End:** beating the boss, or a defeat, shows the recap (`RunEndView`): fights won, gold earned, cards right/answered, relics found. Then it returns to the menu.
- **Run history** (`RunHistoryView`, menu → History): every finished run — victory, defeat or abandon — is written once, when it ends, as a `RunRecord` to Application Support `runHistory.json` (`RunHistoryStore`, user data that survives runs like card stats; an unreadable file is backed up first). A summary strip shows runs, wins, best depth, total fights won and overall card accuracy. Each run row shows (as symbols): outcome (crown / red shield-cross / slashed flag), end date and duration, both heroes with final HP, how far along the map it got (`rows reached / rows incl. boss`), fights won, elites beaten, gold earned, cards right/answered + %, relics, and the enemies of the fight that ended it. Tapping a row shows the decks used, gold spent at shops, and each hero's known skills and worn gear. Runs saved before this existed have no start time, so no duration.

## 10. Shop **[Built]**

`ShopView`: a market stall scene. Plank wall, striped awning and lantern (`shop_stall` art, or the `ShopStallBackdrop` placeholder); the shopkeeper behind the counter (`shop_keeper` art, or the `MerchantPlaceholder` hooded alchemist); potions on the left shelf, relics on the upper right shelf and gear on the lower right shelf. Each ware shows its effect as colored symbols and a parchment price tag with a coin. You can't buy what you can't afford (dimmed), and potions can't be bought into a full bag (bag icon instead of the price).
- **Stock:** every potion in `items.json` (unlimited), `shop.relicsMin`–`relicsMax` (1–2) random relics the party doesn't own, and `shop.gearMin`–`gearMax` (1–2) random pieces of gear the party can wear — rolled once per shop node and saved — plus **one skill scroll** on the relic shelf (`shop.skillScrollCost` 40, haggle applies; shown while some hero can still learn a skill). Bought relics, gear and the scroll show a check seal; bought gear goes to the gear bag. Buying the scroll opens a skill offer (§5) right over the shop (`RunSnapshot.Shop.scrollSold`); it can't be bought while another offer is waiting.
- **Haggle (once per visit, saved):** answer one flashcard. Right → every price × (1 − `shop.haggleDiscount`) (−25%, min 1) for this visit. Wrong → × (1 + `shop.haggleSurcharge`) (+25%). Prices turn green/red accordingly. The haggle is offered in the shopkeeper's speech bubble, showing both outcomes as symbols. The answer counts for card stats like any other.
- Leave with the arrow button.

## 11. Campfire **[Built]**

`CampfireView`: a static forest-clearing scene (`scene_campfire` art, or a placeholder) with the two heroes seated on either side of a flickering campfire, lit warm. The only motion is the flame (`CampfireFlameView`, 24 fps): crossed logs with glowing ends, layered additive flame tongues with a white-hot core, a breathing pool of light and sparks drifting up. A crackling-fire loop plays while the campfire is open (§19). Choose one (Rest on the left, Study and Train on the right):
- **Rest** (bed icon, `+12 ♥ ×2`): every hero heals `campfire.restHeal` (12), capped at max HP.
- **Train** (training icon, `+1 ↑ ×2`): permanently, for the rest of the run, both heroes deal `campfire.trainDamageBonus` (+1) more on **every damage roll** (not heals). Stacks with further Train choices, damage buffs, gear and Lucky Ring; shown as its own step in the combat log. (Changed by the user 2026-10-18 — it used to add a bonus die to each hero's first roll of every fight. Saves from before keep their training stacks, now as +damage.)

- **Study** (book icon, `✦ ↑`; shown while any known skill can still be upgraded): opens `StudyPickerView` (`Views/SkillUpgradeViews.swift`) — every upgradable known skill of both heroes as a row: emblem, name, then its current effects/AP/mana/cooldown → the upgraded ones. Tap one to upgrade it (§5 "Skill upgrades"), which uses up the campfire; the back arrow returns to the three choices.

A further button (sparkles ⇄ shield) opens the party sheet to swap skills and gear; it's free and doesn't use up the campfire.

## 12. Events **[Built]**

`EventView`, data-driven from `encounters.json → events` (kept there instead of a separate events.json because the Content JSONs are hand-wired into the Xcode project — see agents.md). One random event per event node. Each event has:
- a large SF Symbol `icon`;
- one short line of `text`;
- a `reward` (shown next to a green check) and a `penalty` (next to a red cross), both as symbols.

Tap the question button and answer one flashcard: right → the reward, wrong → the penalty. The result shows as a check/cross plus what actually happened.

| Outcome type | Effect |
|---|---|
| `gold` | +amount gold |
| `potion` | a random potion (→ `fullBagGoldConversion` gold if the bag is full) |
| `relic` | a random unowned relic (→ `rewards.relicFallbackGold` gold if all are owned) |
| `heal` | living heroes heal amount |
| `maxHP` | both heroes +amount max HP (and HP if alive) |
| `loseHP` | living heroes lose amount, never below 1 (events can't kill) |
| `loseGold` | lose amount gold, never below 0 |
| `gear` | a random piece of gear the party can wear, into the gear bag |

Current events: Shrine (relic / −5 HP), Merchant Cart (potion / −10 gold), Spring (+10 HP / −4 HP), Riddle Chest (+25 gold / −6 HP), Ruined Library (+3 max HP / −8 gold), Hooded Stranger (+30 gold / −12 gold), Crossroads (potion / −3 HP), Fallen Knight (gear / −4 HP).

The event and, once answered, its outcome are saved immediately: reopening the app shows the result and Continue — an event can't be replayed.

**Event scenes:** the event screen is a static roadside scene with the party standing on the left, the event's illustration in the middle and the card on the right. The illustration is `event_<eventId>` art if it exists, otherwise a painted vignette chosen by the event's `scene` (`EventArt` in `Views/EventArt.swift`, via `EventScenePlaceholder`) — inked outlines and shaded fills like the hand-drawn heroes, on a grassy patch with a contact shadow, lit by its own glowing focal point:
- `shrine`: stepped stone base with glowing runes, mossy fluted columns with ivy, a cracked lintel, a floating violet crystal spilling light.
- `chest`: plank chest with a domed lid, riveted iron bands, gold lock, glowing carved runes, gold light leaking from the seam, spilled coins.
- `spring`: a ring of mossy rocks around a glowing pool with ripples, a rising light column and bubbles, reeds and fireflies.
- `library`: a broken brick wall with a moonlit arch, a bookcase of tilting books, cobwebs, rubble, and a lectern with an open glowing book and floating letters.
- `merchantCart`: the cart on its side with a wheel in the air, torn canvas, a crate, a spilled sack of coins, potion bottles and a still-burning lantern.
- `questGiver`: the hooded stranger — folded cloak rim-lit by the orb, glowing eyes in a deep hood, gnarled staff, mist at the feet.
- `signpost`: a grained post with three worn pointing planks, a crow on top, a hanging lantern, the road forking behind it.
- `fallenKnight`: an inscribed stele with glowing runes and ivy, a sword planted in the earth, a red shield with a gold chevron, a dented helm, wildflowers.
