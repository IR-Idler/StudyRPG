# Study RPG — Game Design Reference (index)

The source of truth for every rule, formula, stat and screen behavior is this file plus the docs in `docs/`. Sections are numbered (§) across all of them; code comments cite `game.md §N` — look the § up in the table below. Keep code and docs in sync (`agents.md`).

Status legend: **[Built]** implemented and playable · **[Planned]** designed, not built · **[Future]** deferred, not designed.

## 1. Concept

An iPhone, iPad and Mac (native macOS app; landscape-only on iOS) roguelike RPG in the shape of Slay the Spire, where every offensive/defensive action in combat is gated behind correctly answering a flashcard. Flashcards are user-authored and can be about anything. Difficulty is tuned assuming the player answers every flashcard correctly; the challenge comes from the combat/roguelike systems, not from flashcard failure.

## Index: section → doc → code

Paths are relative to `StudyRPG/` (the app source folder); docs are in `docs/` at the repo root.

| § | Topic | Doc | Code |
|---|---|---|---|
| 2 | Screens, menu, settings, language | `docs/screens.md` | `ContentView.swift` (menu), `Views/SettingsView.swift` (incl. `SettingsGearButton`), `Services/GameSettings.swift`, `Services/Localization.swift`, `themedNavigationBar` in `Views/Theme.swift` |
| 3 | Run structure, save, history, run end | `docs/run.md` | `Services/RunState.swift`, `Services/RunStores.swift`, `Models/RunModels.swift`, `Views/RunSetupView.swift`, `Views/RunEndViews.swift` |
| 4 | Flashcards, decks, stats, import, starter decks | `docs/flashcards.md` | `Models/FlashcardModels.swift`, `Services/FlashcardServices.swift`, `Services/DeckStore.swift`, `Services/FlashcardSession.swift`, `Views/DeckViews.swift`, `Views/FlashcardQuizOverlay.swift`, `Content/starter_decks.json` |
| 5 | Heroes, skills, learning, levels & XP, skill art | `docs/heroes-items.md` | `Content/classes.json`, `Models/GameContent.swift` (`LevelingConfig`), `Views/SkillRewardView.swift`, `Views/SkillUpgradeViews.swift` (Study), `Views/PartySheet.swift`, `Views/SkillArt.swift`, `Views/SkillMotifs.swift` |
| 6 | Items, gear, potions, item art | `docs/heroes-items.md` | `Content/items.json`, `Models/GameContent.swift`, `Views/PartySheet.swift`, `Views/ItemArt.swift` |
| 7 | Combat rules | `docs/combat.md` | `Services/CombatEngine.swift`, `Models/CombatState.swift`; monster moves: `Services/EnemyBrain.swift`, `Views/EnemySkillText.swift` |
| 7.6 | Fight screen | `docs/combat.md` | `Views/FightView.swift`, `Views/BattleStage.swift`, `Views/CombatConsole.swift`, `Views/CombatVFX.swift`, `Views/CharacterInfoSheet.swift` |
| 8 | Dice, hero dice & stickers | `docs/combat.md` | `Views/DiceTrayView.swift`, `Models/HeroDie.swift`, `Views/HeroDieViews.swift` (face tiles, level-up pick) |
| 9 | Map | `docs/map.md` | `Services/MapGenerator.swift`, `Views/RunMapView.swift`, `Views/ParchmentMapArt.swift` (scroll, painted places, road shimmer), `Views/RunSymbols.swift` (HUD, `MapPeekButton`) |
| 10–12 | Shop, campfire, events | `docs/run.md` | `Views/ShopView.swift`, `Views/CampfireView.swift`, `Views/EventView.swift`, `Views/ScenePlaceholders.swift`, `Views/EventArt.swift`, `Content/encounters.json` |
| 13–14 | Content files, localization, stats snapshot | `docs/content.md` | `Content/*.json`, `Content/Content.xcstrings`, `Localizable.xcstrings`, `Models/GameContent.swift`, `Services/ContentLoader.swift`, `Services/Localization.swift` |
| 15 | Platform | `docs/screens.md` | `Views/StageFrame.swift` (`WidescreenCanvas`, `CanvasFit`), `Views/Platform.swift` (UIKit/AppKit bridge), `MyApp.swift` (Mac window, Settings scene), `Views/GameMenuCommands.swift` (Mac menu bar) |
| 16.0, 16.2, 16.3, 18 | Acts (built), boss relics / ascension plan, core loop rework plan, future ideas | `docs/roadmap.md` | `RunState` (`actIndex`, `startNextAct`), `encounters.json → acts`, `Views/HoloMapArt.swift` (Act II map) |
| 16.1 | Glossary, Bestiary, discoveries | `docs/screens.md` | `Views/CodexViews.swift`, `Services/DiscoveryStore.swift`, hooks in `Services/RunState.swift` |
| 17 | Visual style, sprites, art sizing, asset table | `docs/presentation.md` | `Views/Theme.swift`, `Views/ArtCache.swift`, `Views/ProceduralSpriteArt.swift`, `Views/SceneBackdrops.swift`, `DeskBackground` in `Views/StageFrame.swift` |
| 19 | Sound effects | `docs/presentation.md` | `Services/SoundEngine.swift` |
| — | Dev harness | — | `Views/TestFightSetupView.swift`, `FrameRateHUD` in `ContentView.swift`, `Views/ScenePreviews.swift` |
| — | Tests | — | `../StudyRPGTests/`: `ContentTests` (§13), `FlashcardTests` + `DeckTests` (§4, §3 deck memory), `MapGeneratorTests` (§9), `CombatEngineTests` + `SkillEffectTests` (§5–7), `EnemySkillTests` (§7.3), `RunTests` (§3, §5, §6), `ShopCampfireEventTests` (§10–12), `DiscoveryTests` (§16.1), `LevelTests` (§5 "Levels"), `DiceFaceTests` (§8 "Hero dice"), `ActTests` (§16.0), `SoundTests` (§19), `CanvasFitTests` (§15), `LocalizationTests` (§2 Language, §13 "Localization") |

## Decisions already made (don't re-litigate without asking)

Full detail in the cited §; original wording in `HISTORY.md`.

- Flashcards: one question, one correct answer, optional wrong answers, images allowed; missing options filled from the deck; "None of these" sometimes withholds the answer. Decks authored in-app (§4).
- Accuracy tracked per card; deck accuracy = Σcorrect ÷ Σattempts. Every answer logged permanently as `AnswerEvent` — don't drop fields without checking §16 (§4.2).
- Any number of active decks, pooled for both heroes; wrong cards weighted to return more (§4).
- Fights: 1–3 enemies. A round = the party's turn (heroes act in any order — tap a hero's sprite — spending action points: every skill and potion costs AP, 2 AP per hero per turn, skills cost 1 or 2 — user decision 2026-10-27), then the enemies' turn (each enemy acts once; stunned ones visibly skip). Every skill takes two taps: skill, then target; group skills mark the whole group (§7.2).
- Wrong answer: skill fizzles (its AP are spent); the single strongest living un-stunned enemy hits the answering hero with at most `combat.wrongAnswerMaxDice` dice; charges are untouched (§7.2).
- Scheduled enemy attacks hit both heroes, rolled separately (batched visually in Fast mode) (§7.3).
- Heroes gain XP from won fights (per-enemy `xp`), about 3–4 levels per act on a fight-heavy route and 1–2 on a fight-light one; every level offers a die upgrade — raise a face or add a sticker to the hero's own six-faced die (user decision 2026-10-27, replaced "level 2 = d8") (§5 "Levels", §8 "Hero dice").
- Skills are learned from won elites and the shop's skill scroll — the player picks which hero, then 1 of 3 or skip; normal fights teach none (user decision 2026-10-27). Every skill can be upgraded once at a campfire (Study). Max `skills.maxEquipped` equipped, loadout editable outside fights (§5).
- Gear is per hero (weapon/armor/trinket); potions are a shared bag; potions need no flashcard but cost AP in fights, skills always need a correct answer (§6, §7).
- Physical vs magic damage; magic ignores block and armor (§7.4).
- Map: no shop/campfire at start, every route passes one, row before the boss is all campfires, never two shops in a row, more fights than all other places together; one run = one map + boss per act (two acts: The Old Kingdom, then the futuristic Neon Frontier with a laser robot), everything carries over between acts; permadeath, only flashcard history survives (§3, §9).
- Settings are presentation only (UserDefaults), never balance, and reachable from every screen (§2).
- The game is localized (English, German — more later); the language is an in-game setting that switches live. Content text is translated by its English text in `Content/Content.xcstrings`, never in JSON or Swift (§2, §13). For now new text is English only; German is caught up later in one pass (user decision 2026-10-27).
- During a run the map can always be looked at, from any screen (§9).
- No visible navigation bars, only their buttons (§2, §17). Exception: on Mac the window keeps its standard title bar (§15).
- Combat is strictly sequential — no overlapping actions/animations (§7.6).
- All random numbers come from the visible dice tray (`DiceTrayView`): the faces shown are the numbers used (§8). Flat 2D on purpose — replaced the 3D SceneKit dice and must not imitate 3D (user decision 2026-10-27).
- Difficulty: meaningfully hard even with every flashcard answered correctly (§14).
- Monster skills & rules (§7.3): deterministic (no random targets/choices — dice only), the nameplate telegraphs the exact next move. Glossary & Bestiary discoveries persist across runs; only real runs discover.
