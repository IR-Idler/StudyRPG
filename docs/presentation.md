# Study RPG — Visual style & sound

Part of the game design reference; `game.md` is the index. Section numbers (§) are shared across all docs.

## 17. Visual style **[Built]**

Decision: **fantasy / paper / moody / muted.** Implemented in `Views/Theme.swift` (`Palette`, `Font.serif`, `PanelModifier`/`.panel()`, `ParchmentModifier`/`.parchment()`, `ParchmentRowModifier`/`.parchmentRow()`, `QuestButtonStyle`, `SectionHeaderLabel`, `EffectBadge`/`StatusEffectRow`, `HPBarView`, `ManaDiamonds`, `ChargePips`, `ShakeEffect`, `SpriteView`), with `ProceduralSpriteArt.swift`, `SceneBackdrops.swift` (`SceneryBackground`, `FightBackdrop`/`ThemePlaceholderPainting`), `ScenePlaceholders.swift`, `ArtCache.swift`, `CharacterInfoSheet.swift` and `CombatVFX.swift` alongside it in `Views/`.

- **Static scenes:** nothing moves on its own anywhere; on the world map only the party's walk animates. Fights, shop, campfire, events, menus and lists are static; there are no parallax layers or ambient drift anywhere else.
- **Backgrounds:** fights use their own themed backdrop (§7.6). The main menu and the run's screens (run setup, run recap, party and character sheets) use `SceneryBackground`, a calm static night painting (stars, moon, snow-capped peaks). The reading screens — decks, deck editor, card editor, History, Glossary, Bestiary and Settings — sit on the **study desk** (`DeskBackground`, user decision 2026-10-26): the candlelit wooden table the map lies on (`TabletopSurfaceView`); list screens get it via `.deskList()`. No art assets either way.
- **The user's hand-drawn mountains/trees** (`map_fantasy_*`) are currently used only as illustrations on the painted world map (§9), not as fight/menu backgrounds. Fight backgrounds are meant to get their own per-theme art (`bg_<themeId>`).
- **Performance rules for the fight screen:** no perpetual animations on the stage (no bobbing, breathing or drifting); no blur filters on persistent views (glows are radial gradients); VFX are single time-driven `Canvas` views that remove themselves; sprite anchors are read *before* shake/lunge effects, and `figureRects` is only written when it actually changes, so animations never re-render the whole fight screen every frame.
- **Art sizing (applies to all current and future PNGs):** art can be exported at any resolution — nothing has to be resized by hand. Every catalog image the game shows goes through `ArtCache` (`Views/ArtCache.swift`), which keeps only a copy scaled to the size it is actually displayed (in points × the screen's pixel scale) and caches it; it never upscales. Sprites (`SpriteView`, `GearArt`) are scaled to their on-screen height (e.g. a 135 pt skeleton → ~405 px), map illustrations to their drawn size (mountains 105 pt, trees 34 pt), and full-screen art (`bg_<themeId>`, `scene_*`, `shop_*`, `event_*` via `FightBackdrop`/`ArtOrPlaceholder`) to cover up to iPad Pro 13" landscape canvas (1366×768 pt, `ArtCache.largestScreen`). On Mac, bigger windows lay out at that size and scale up (§15), so every copy is made at the screen's pixel scale × `ArtCache.canvasUpscale` — the most the canvas can be scaled on the largest screen attached at launch. Any new art-showing view must load through `ArtCache`, never `PlatformImage(named:)`/`Image("…")` directly. `ArtCache` downsamples with UIKit's thumbnail decoder (`preparingThumbnail(of:)`, not a full-size draw; on Mac a high-quality redraw at the target size, `PlatformGraphics.downsampled`), remembers art that doesn't exist yet (so placeholders never re-query the catalog on every render) and remembers each art's size for `aspect`/`covering` lookups. Recommended exports: crop tightly to the drawing on a transparent background; characters ≥ ~600 px tall so they stay sharp everywhere.
- **Readable content** sits on warm, fully opaque parchment cards (`.parchment()`, `.parchmentRow()`). Chrome uses the darker, translucent `.panel()` style. No screen has a visible navigation bar or title: `.themedNavigationBar()` hides the bar background and title and keeps only its buttons in light chrome, always inline (§2). Form headers use gilded capsule labels (`SectionHeaderLabel`).
- **Semantic combat colors:** `Palette.damage` (red), `.health` (green), `.mana` (blue), `.strength` (yellow — also damage buffs), `.block` (silver), `.control` (violet — stun, weaken, vulnerable), mapped from log kinds by `Palette.combatColor(_:)`. Use these, never ad-hoc colors, for anything that conveys a combat meaning.
- **Typography:** serif throughout. `Font.serif(size:weight:)` is fixed-size (fight HUD, map); `Font.readable(size:weight:)` follows the system text size up to 1.5× and is used for reading content (flashcards, deck manager and card editor, party sheet, settings).
- **Buttons:** `QuestButtonStyle` (`.primary` gold fill with ink text, `.secondary` gold-tinted fill with ink text for parchment cards, `.quiet` full-cream text for nav bars — never inside parchment). Every `QuestButtonStyle` / menu plaque plays the same soft click on press (§19). Icon-only buttons over scenery use `ChromeIconButtonStyle` (round dark chip, gold rim). Titles on non-navigation screens use `ScreenTitle` (gilded serif + `OrnamentDivider`, a gold rule with a diamond).
- **Sprites & Bespoke Procedural Vector Art:**
  - `SpriteView` checks `Assets.xcassets` for PNGs first (`hero_<id>`, `enemy_<id>`, `item_<id>`). If found, it displays the hand-drawn PNG.
  - For missing assets, `SpriteView` automatically falls back to `ProceduralSpriteArt` — vector `Canvas` drawings on a normalized 100×100 `ArtGrid` (static; `IdleBreathing` is off by default and only used by the walking party on the world map):
    - **Mountain Troll (`troll`):** burly stone skin, tusks, spiked wooden club, glowing amber eyes, stone cracks.
    - **Bog Witch (`witch`):** crooked hat with gold buckle, ragged purple cloak, hooked nose, staff with glowing green orb and magical sparkles.
    - **Dragon (`dragon`):** winged red dragon, horn-crested skull, reptilian glowing eye, spiked tail, embers at the snout.
    - **Sentinel (`sentinel`, Act II):** clean white armor plates over dark joints, a glowing cyan visor band and chest core, a small antenna, and a laser-cannon arm aimed left at the heroes.
  - Potions, relics and gear fall back to `ItemArt` (`Views/ItemArt.swift`; `SpriteView` routes item ids there, `GearArt` uses it before the slot badge), painted with ink outlines to match the hand-drawn heroes:
    - **Potions:** Health Potion (round flask of red liquid, heart label, cork), Strength Potion (conical amber flask with a crossed-swords tag), Mana Potion (slim glowing blue vial with a wax seal).
    - **Relics:** Iron Shield (steel heater shield in a gold rim, cross bands, boss and rivets), Lucky Ring (gold band with a faceted emerald), Heart Amulet (gold-set ruby heart on a two-strand chain).
    - **Gear:** Iron Sword, Executioner's Axe (bearded blade with a stain), Oak Staff (gnarled wood, twig claws holding a green gem), Ember Wand (dark wand, gold bands, flaming tip), Chainmail (ring-mesh shirt with leather collar and belt), Padded Robe (quilted violet robe with gold trim), Troll Hide (warty green pelt cloak with a fur collar), Mana Crystal (blue crystal in a silver claw), Healer's Charm (wooden disc with a green cross in gold), Whetstone (grey stone with a bright streak and sparks).
  - Skills are painted emblems (§5 "Skill art"), `skill_<skillId>` PNGs replace them.
  - Any other ID falls back to a themed parchment badge with the kind's SF Symbol.
  - When the user adds hand-drawn PNGs into `Assets.xcassets` in the future, `SpriteView` will automatically display the PNGs without requiring code changes.

### 17.1 Asset Status Table (Hand-drawn vs. Placeholder)

Keep this table updated whenever art is added or replaced in `StudyRPG/Assets.xcassets`. To add art: copy the PNG at full resolution into `Assets.xcassets/<name>.imageset/` with a `Contents.json` (universal, 1x), then update this table. Unmapped in `resource/`: `mountain 1.png`. All current art is provisional; the user will replace it with hand-drawn art.


| Category | Entity / Slot | Catalog Asset Name | Status | Source / Fallback |
|---|---|---|---|---|
| **Heroes** | Warrior | `hero_warrior` | **Hand-drawn** | `resource/knight.png` |
| **Heroes** | Wizard | `hero_wizard` | **Hand-drawn** | `resource/wizard.png` |
| **Enemies** | Goblin | `enemy_goblin` | **Hand-drawn** | `resource/goblin.png` |
| **Enemies** | Skeleton | `enemy_skeleton` | **Hand-drawn** | `resource/skeleton.png` |
| **Enemies** | Wolf | `enemy_wolf` | **Hand-drawn** | `resource/wolf.png` |
| **Enemies** | Mountain Troll | `enemy_troll` | **Hand-drawn** | `resource/troll.png` |
| **Enemies** | Small Spider | `enemy_spider` | **Hand-drawn** | `resource/spider.png` |
| **Enemies** | Bog Witch | `enemy_witch` | **Hand-drawn** | `resource/witch.png` (trimmed to the drawing; procedural `witch` stays as the fallback) |
| **Enemies** | Sentinel (Act II) | `enemy_sentinel` | Placeholder (procedural vector) | `ProceduralSpriteArt` (`sentinel`) |
| **Map Props** | Act II tower / city block | `map_future_tower`, `map_future_block` | Placeholder (procedural) | `HoloMapTerrain` (`Views/HoloMapArt.swift`) |
| **Enemies** | Dragon (Boss) | `enemy_dragon` | Placeholder (procedural vector) | `ProceduralSpriteArt` (`dragon`) |
| **Map Props** | Mountain 1 | `map_fantasy_mountain` | **Hand-drawn** | `resource/mountain.png` |
| **Map Props** | Mountain 2 | `map_fantasy_mountain_alt1` | **Hand-drawn** | `resource/mountain 2.png` |
| **Map Props** | Mountain 3 | `map_fantasy_mountain_alt2` | **Hand-drawn** | `resource/mountain 3.png` |
| **Map Props** | Tree 1 | `map_fantasy_tree` | **Hand-drawn** | `resource/tree_1.png` |
| **Map Props** | Tree 2 | `map_fantasy_tree_alt` | **Hand-drawn** | `resource/tree_1 1.png` |
| **Map Props** | Trees 3–8 (oak, poplar, bush, round oak, autumn, cypress) | `map_fantasy_tree_1` … `map_fantasy_tree_6` | **Hand-drawn** | `resource/6_trees.png`, cut into six along its transparent gaps (left→right, top row first); the map draws each at its own aspect ratio |
| **Scenes & UI** | Victory Treasure Chest | — | Placeholder (procedural vector) | `VictoryTreasureIllustration` (`ScenePlaceholders.swift`) |
| **Scenes & UI** | Campfire Scene | `scene_campfire` | Placeholder (procedural vector) | `CampfireScenePlaceholder` |
| **Scenes & UI** | Shop Stall Backdrop | `shop_stall` | Placeholder (procedural vector) | `ShopStallBackdrop` |
| **Scenes & UI** | Shopkeeper | `shop_keeper` | Placeholder (procedural vector) | `MerchantPlaceholder` |
| **Fight Backdrops** | All 11 Fight Themes | `bg_<themeId>` | Placeholder (procedural vector) | `ThemePlaceholderPainting` |
| **Events** | Per-event Illustrations (8) | `event_<eventId>` | Placeholder (procedural, painted) | `EventArt` (`EventArt.swift`) via `EventScenePlaceholder` |
| **Potions** | Health / Strength / Mana | `item_health_potion`, `item_strength_potion`, `item_mana_potion` | Placeholder (procedural, painted) | `ItemArt` |
| **Relics** | Iron Shield / Lucky Ring / Heart Amulet | `item_iron_shield`, `item_lucky_ring`, `item_heart_amulet` | Placeholder (procedural, painted) | `ItemArt` |
| **Gear** | Weapons, Armor & Trinkets (10) | `item_<spriteId>` | Placeholder (procedural, painted) | `ItemArt` via `GearArt` (`PartySheet.swift`) |
| **App** | App icon (iPhone, iPad, Mac) | `AppIcon` | Placeholder (generated): night sky, parchment flashcard with a gilded "?", gold sword, red die; full-bleed square, the system applies the shape | `tools/make_app_icon.swift` (run `swift tools/make_app_icon.swift out.png`, then resize with `sips` for the Mac sizes 16–512 @1x/@2x) |
| **Skills** | All 21 skills | `skill_<skillId>` | Placeholder (procedural emblem + painted motif) | `SkillEmblem` (`SkillArt.swift`) + `SkillMotif` (`SkillMotifs.swift`) |

## 19. Sound effects **[Built]**

Every sound is **synthesized at launch** on a background queue (`SoundSynth` in `Services/SoundEngine.swift`) — no audio files ship. Recipes are built from a few DSP blocks: struck inharmonic partials (wood, metal, bells, coins, dice), filtered noise (whooshes, paper, claws, fire), a soft band-limited brass voice (fanfares, war cry), pitch-dropping thumps (hits, drums), scattered crackle pops (fire), then a small offline Schroeder reverb so everything sits in the same moody "stone hall". Frequently repeated sounds (hits, clacks, steps, card flips) have 2–4 pitch variants picked at random. Buttons deliberately don't: every button press plays the one identical `tap` — a soft, low, muffled wooden "tock" (330 Hz, ~30 ms, quiet) chosen so frequent presses don't grate. Presentation only, like all settings.

**Muted for now (user decision 2026-10-26):** only `tap` (button presses) plays; every other effect returns early in `Sound.play` / `Sound.startLoop` (`SoundEffect.isMuted`). The recipes below are kept and tested so they can be re-enabled one by one. The volume slider's sample is the `tap`.

**Playback** (`SoundEngine`): one `AVAudioEngine` with 10 round-robin `AVAudioPlayerNode` voices plus one loop voice, all on a private serial queue, so `Sound.play` is safe from any thread . The same effect can't restart within 35 ms (bursts of clacks/steps don't smear). Session category `.ambient` + mix with others: the silent switch mutes the game and the player's music keeps playing. Settings → *Sound effects* / *Effects volume* (§2) drive the master volume.

| Sound | When |
|---|---|
| `tap` | every button press, identical everywhere: any button or menu plaque, closing settings, skipping a skill offer, tapping a map place or a target, arming a skill, picking a hero class or encounter, toggling a setting or a deck |
| `deny` | (synthesized, currently unused) |
| `cardFlip` | a flashcard appears (fights, shop haggle, events) |
| `correct` / `wrong` | the answer is chosen (bell arpeggio / dull dissonant bonk) |
| `diceThrow` / `diceClack` / `diceTotal` | the dice start spinning / each die stops / the total banner |
| `slash` / `missile` / `fireball` | the hero's attack animation by skill `vfx` (`fireball` has its explosion baked in at the VFX impact, 0.52s) |
| `claw` / `fireBreath` / `laser` | an enemy move by its `vfx`: claw (default), `fire`, `laser` (a short rising charge, then a falling zap with a buzzing edge) |
| `hit` / `block` | a hit lands for damage / is fully blocked (0) |
| `heal`, `mana`, `buff`, `debuff`, `stun`, `shield` | the matching effect resolves (Shield Wall and enemy armor = `shield`; strength/bonus dice and damage buffs = `buff`) |
| `potion` | drinking a potion in a fight |
| `victory` / `defeat` | the fight ends (brass fanfare + timpani / slow descending minor line) |
| `footstep` | five footfalls in step with the 0.9s map walk |
| `coin` / `purchase` | volume slider sample / buying at the shop |
| `skillLearn` | learning a skill from a skill offer |
| `campfire` (loop) | while the campfire screen is open (seamless 5s crackle loop) |

Tests (`SoundTests`) render every recipe and check it's non-empty, finite, within full scale, audible and under 6 s.
