# Study RPG — Planned & future

Part of the game design reference; `game.md` is the index. Section numbers (§) are shared across all docs.

## 16. Acts & ascension

### 16.0 Acts **[Built 2026-10-22: two acts]**

A run plays every act in `encounters.json → acts` in order (`RunState.actIndex`, saved as `RunSnapshot.actIndex`; older saves are in act 1). Each act has an `id`, a `name` and a `mapStyle` (`parchment` / `hologram`, §9), and its own encounter pools (`pools[].act`).

| Act | Name | Map | Fights |
|---|---|---|---|
| 1 `kingdom` | The Old Kingdom | parchment | goblins … dragon (§14) |
| 2 `future` | Neon Frontier | hologram | the Sentinel laser robot only, 1–3 of them (elites 2–3, boss 3); themes `neon_city`, `server_vault` (style `future`, platform `metal`) |

- **Between acts:** beating an act's boss when another act follows doesn't end the run: the usual victory (gold, XP, fallen heroes up at half HP) and then a fresh map for the next act (generated from the same `balance.json → map`), starting at its trailhead. Everything the party carries — HP, mana, XP/levels, skills, gear, gold, potions, relics, training — stays; only the map and what its places had rolled are new. An "ACT II — Neon Frontier" card shows once on the new map. Only the last act's boss wins the run.
- **For now** (user decision 2026-10-22: "just the new map art and one enemy type"): Act II reuses the shop, campfire and event scenes and the event list, and has no boss of its own (its boss node is three Sentinels).

### 16.2 Planned **[Planned]**

Recorded from the user (2026-10-18); not designed in detail yet.

- **Three acts per run**, each with its own **visual theme** and its own **boss** (two acts are built, above).
- **Boss relics:** beating an act boss offers a **choice of powerful relics** (pick one of several), stronger than elite/shop relics.
- **Ascension:** beating the act-3 boss unlocks the next difficulty level of the run, up to ~20 levels, each adding one more modifier (to be designed and added one at a time). This is the first meta-progression besides card stats.
- Likely content shape for the rest: `balance.json → map` per act, a boss-relic pool, and an `ascension` list of modifiers.

### 16.3 Core loop rework **[Planned 2026-10-27]**

Agreed with the user (2026-10-27) because the game got samey fast: too few decisions per turn, skills arrived too quickly and were side-grades, and leveling only made numbers bigger. Balance is deliberately ignored while this is built. Done one phase at a time, each built, tested and checked by the user before the next; when a phase is built its rules move into the topic doc (§5, §7, …) and its line here is marked **[Built]**.

1. **Dice faces [Built 2026-10-27]** — rules in §8 "Hero dice" and §5 "Levels". Classes keep their differences (no Warrior-only sticker for now — user decision).
2. **Skills that matter [Built 2026-10-27]** — rules in §5 "Skill loadout & learning", §7.2, §10, §11.
3. **Card look: the table HUD** — one shared `GameCard` component; the fight console becomes a wooden table strip with the skill cards lying on it (tap lifts = armed, cooldown = face-down) and a hero stat card (HP, mana, AP gems, the six die faces). The flashcard quiz stays parchment so study cards never look like game cards.
4. **Enemy deck & Bestiary binder** — per-act fight/elite decks built from the encounter pools; previewing a fight node flips the top card, the HUD shows the pile. Enemy info becomes a trading card; the Bestiary becomes a binder (undiscovered = card back, elites/bosses holo foil).
5. **Hard cards & final exam** — card difficulty from its accuracy (easy/normal/hard); a correctly answered hard card gives +1 die. The boss gets a generic "exam seal" rule broken only by correctly answering the run's most-missed (or lowest-accuracy) cards.

Parked for a later round: walking back along routes with a danger clock (every step raises enemy level), and evolved enemies on revisited fight nodes.

## 18. Deferred / Future (explicitly not designed in detail yet)

- Difficulty-tiered flashcards matched to enemy difficulty.
- Persistent meta-progression between runs (unlocks beyond flashcard stats).
- iPad layout: supported natively via Framed Widescreen Canvas (`WidescreenCanvas` in `Views/StageFrame.swift`), presenting the 16:9 game stage centered on the display with candlelit wood tabletop letterbox framing and gilded filigree borders.
- CSV bulk import of decks (JSON import is built, §4.4).
- Typed-answer decks (recall instead of multiple choice) for short, unambiguous answers.
- Acts and ascension: see §16.
- Card-history-driven features the answer log already supports: spaced repetition, confusion-pair detection, slow-but-correct detection, difficulty-to-enemy matching.
