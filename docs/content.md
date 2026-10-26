# Study RPG — Content files & stats

Part of the game design reference; `game.md` is the index. Section numbers (§) are shared across all docs.

## 13. Content files **[Built]**

All under `StudyRPG/Content/`, loaded and validated at launch by `ContentLoader`. A load/validation failure must name the offending file and field, not crash silently.

| File | Defines |
|---|---|
| `classes.json` | Hero classes: id, name, spriteId, maxHP, resource (name/max/start), `startingSkills` (ids), `skills` = the whole pool (id, name, icon, optional `art` (painted motif, §5 "Skill art"), cost, `actionPoints` (≥ 1, §7.2), optional `cooldown`, optional `upgrade` {`cost`, `cooldown`, `actionPoints`, `effects`} (§5 "Skill upgrades"), target `enemy`/`allEnemies`/`party`/`ally`/`self`, optional `requiresInactive`, optional `vfx` = `blade`/`missile`/`fireball`, optional `element` (skill art, §5: `steel`/`fire`/`frost`/`lightning`/`arcane`/`nature`/`guard`/`war`/`shadow`/`earth`/`mana`), effects: {type, dice, amount, rounds, optional `damageType` = `physical`/`magic`} — §5, §7.4) |
| `enemies.json` | Enemy templates: id, name, spriteId, optional `spriteHeight` (on-stage size in points, default 125), tier (normal/elite/boss), baseHP, attackDice + optional `attackDamageType` (`physical` default / `magic`, §7.4) = the basic attack, goldReward, `xp` (§5 "Levels"), optional `attackVfx` (`claw`/`fire`/`laser`, the basic attack's animation), attackEvery (enemies' turns per move, 1 = every turn), dice may set `sides` (6 or 8, default 6), optional `skills` (id, name, `icon` SF Symbol, target `heroes`/`hero`/`self`/`ally`/`allies`, optional `vfx` = `claw`/`fire`/`laser`, effects: {type `damage`/`heal`/`armor`/`stun`/`damageBuff`/`weaken`/`vulnerable`, dice, amount, rounds, optional `damageType`, optional `target`}), `movePattern` (skill ids or `attack`), optional `rules` ({skill, optional `when` {`selfHPBelow`, `allyHPBelow`, `heroHPBelow`, `minAlliesAlive`, `maxAlliesAlive`, `unlessActive`}, optional `cooldown`, `maxUses`}) — §7.3. Validation names the enemy and the skill/rule: unknown skill ids, an effect on the wrong side (e.g. damage on `self`), two rolling effects, missing dice/amount/rounds, HP shares outside 0…1 |
| `encounters.json → acts` | The run's acts in order: id, name, `mapStyle` (`parchment`/`hologram`) — §16.0. At least one; every act needs fight, elite and boss pools |
| `encounters.json → pools` | Per `act`: which enemies (and how many) spawn at which map-depth / node-type combination, and each encounter's `theme` |
| `encounters.json → themes` | Fight stages: id, style (placeholder painting), skyTop/skyBottom/ground/accent (`#RRGGBB`), platform material (§7.6) |
| `items.json` | `items` = potions: id, name, spriteId, cost, `actionPoints` (≥ 0, what drinking one costs in a fight, §7.2), effect. `gear` = per-hero gear: id, name, spriteId, slot (`weapon`/`armor`/`trinket`), cost, optional `classId`, effects [{type, amount, optional skillId}] (§6) |
| `relics.json` | Relics: id, name, spriteId, cost, effect |
| `encounters.json → events` | Event vignettes: id, icon, scene (placeholder illustration), text, reward {type, amount}, penalty {type, amount} (§12) |
| `starter_decks.json` | The bundled sample decks (§4.5): `{"decks": [studyrpg-deck v1 …]}`, no picture files |
| `balance.json` | Global tuning knobs not specific to one entity: starting gold, `maxPotionsCarried`, `fullBagGoldConversion`, `rewards` (`bonusPotionChance`, `relicFallbackGold`, `fightGearChance`, `eliteGearChance`), `shop` (`haggleDiscount`, `haggleSurcharge`, `relicsMin`/`relicsMax`, `gearMin`/`gearMax`, `skillScrollCost`), `campfire` (`restHeal`, `trainDamageBonus`), `skills` (`maxEquipped`, `offerCount`), `combat` (`wrongAnswerCounterattacks`, `wrongAnswerMaxDice`, `actionPointsPerTurn` ≥ 1), `leveling.levels` ([{`xp`}], first at 0 XP, rising — §5 "Levels"), `dice` (`startingFaces` [6 numbers], `maxFaceValue`, `offerCount`, `stickers` [{`id`, `name`, `symbol`, `type` crit/block/resource/heal, `amount`}], `upgrades` [{`id`, `type` raiseFace/sticker, `amount` or `sticker`}] — §8 "Hero dice"), card draw weight formula, `flashcards.noneOfTheseChance`, `flashcards.minDeckSize`, `map.rowCount` (≥ 4)/`minLanes`/`maxLanes`/`pathCount`/`nodeWeights`/`eliteMinProgress`/`restMinProgress` (0…1)/`campfireBeforeBoss` |

User-authored flashcard content (decks/cards, per-card stats, the answer log, and card images) is **not** in `Content/` — it's user data, not shipped content, and lives in the app's Application Support directory instead (`Decks/decks.json`, `cardStats.json`, `answerLog.jsonl`, `CardImages/`; the run history is `runHistory.json`, §3; discoveries are `discoveries.json`, §16.1). See §4. If `decks.json` or `cardStats.json` can't be decoded (e.g. after a format change), the unreadable file is first copied next to the original as `<name>.unreadable-<timestamp>.json` so the next save can't destroy it; card stats are then rebuilt from the answer log.

**How to add things yourself** (see also `agents.md`):
- **New enemy**: add an entry to `enemies.json` with a unique id and a `spriteId`; drop a PNG into the asset catalog named `enemy_<spriteId>` (or leave it out — a placeholder renders automatically). Add it to one or more entries in `encounters.json` so it actually appears on the map. Give it skills, a `movePattern` and optional `rules` (§7.3) — `"movePattern": ["attack"]` is enough for a simple monster.
- **New item/relic/gear**: add an entry to `items.json` (`items` or `gear`) or `relics.json`, same sprite convention (`item_<spriteId>`; gear without art shows its slot symbol).
- **New skill**: add it to a class's `skills` in `classes.json` (any SF Symbol `icon`; optionally an existing `art` motif from §5 — a brand-new motif needs a painter in `SkillMotifs.swift`; effects from §5). It becomes learnable automatically; add its id to `startingSkills` to give it from the start.
- **New fight background**: add a theme to `encounters.json → themes` and point an encounter's `theme` at it; drop a PNG named `bg_<themeId>` into the asset catalog to replace the placeholder painting.
- **Scene art**: `scene_campfire`, `shop_stall`, `shop_keeper` and `event_<eventId>` PNGs in the asset catalog replace the respective placeholders automatically.
- **New event**: add an entry to `encounters.json → events` (any SF Symbol for `icon`, one short line of `text`, a reward and a penalty from the outcome table in §12).
- **New hero class**: add an entry to `classes.json` with its skills; sprite convention `hero_<spriteId>`. (Party setup currently assumes exactly 2 *different* classes — revisit that assumption if you add a 3rd class.)
- **Rebalance anything**: edit the relevant number in the JSON file directly. No code change needed for pure numbers.
- **Any new or changed text** (a name, an event line, a starter-deck card): add its German translation to `Content/Content.xcstrings` (see "Localization" below) — `LocalizationTests` fails until every content text has one.

### Localization **[Built 2026-10-26]**

The game is fully localized into English (development language) and German; the player picks the language in Settings (§2 Language). Two String Catalogs:
- **`Localizable.xcstrings`** (app folder): every piece of UI text written in Swift. Xcode extracts it on build. `Text("…")`, `Button("…")`, `Label`, alerts etc. take `LocalizedStringKey` literals and follow the `\.locale` environment that `.gameLocale()` sets at the root of every window (`MyApp`). Text built as a `String` in code (combat log, skill/monster/gear descriptions, menu subtitles, deck import messages, the Mac menu bar) goes through `L("…")` (`Services/Localization.swift`), which resolves it in the chosen language. Custom views take `LocalizedStringKey` for their titles (`ScreenTitle`, settings rows, menu plaques); `SectionTitle`/`SectionHeaderLabel` also accept an already-localized `String`. Plurals are separate keys ("1 deck" / "%lld decks"); German reorders placeholders with `%1$@`-style positions. Dice read "W" in German (2W6).
- **`Content/Content.xcstrings`**: the names and texts in `Content/*.json` — class, resource, skill, enemy, monster skill, item, gear, relic and act names, event lines, the built-in "Attack"/"Magic Attack", and the starter decks' names, subtitles, prompts, faces, hints and explanations. Keyed by the English text, so the JSON stays English and Swift stays generic. Content structs mark these fields `@ContentText`: stored, decoded and saved as the English key (`$name` gives the key; saved runs and run history keep English), read in the current language. Lookup is a plain table read (content may contain "%"); an untranslated text shows its English.
- **Starter decks** are translated when they're added (first launch, or "Add Starter Decks" in the current language); after that they are the player's own decks and don't change language. Player-written decks are never translated.
- **Adding a language:** add its code to `Localization.supportedCodes` and an `AppLanguage` case, then translate both catalogs.

## 14. Current starting stats snapshot

**Difficulty target (user decision):** the game must stay meaningfully hard even when the player answers every flashcard correctly — balance around 100% accuracy, never around the player getting some wrong.

Rebalanced 2026-10-18 with a Monte Carlo of the real engine (1,000–2,000 fights per encounter, simple sensible play, no potions/gear/relics) at 100% and 80% card accuracy. Expect further changes.

| Enemy | Tier | HP | Attack | Acts every | Move pattern | Rules | Gold |
|---|---|---|---|---|---|---|---|
| Goblin | normal | 12 | 1d6 | 1 | attack | Rally (every monster +1 damage, 2 rounds) when 2+ monsters standing and not already active; then waits 2 moves | 12 |
| Skeleton | normal | 14 | 1d6 | 1 | attack | Bone Guard (armor −2, 2 rounds) when below 50% HP, once | 13 |
| Wolf | normal | 14 | 1d6 | 1 | attack | Go for the Throat (1d6+2 on the most hurt hero) when a hero is below 35% HP; then waits 1 move | 13 |
| Small Spider | normal | 6 | 1d6 | 1 | attack | — | 4 |
| Troll (elite) | elite | 26 | 1d6+2 | 1 | attack, Stone Skin (armor −2, 3 rounds), Regenerate (heal 2d6+2) | Regenerate when below 35% HP; then waits 2 moves | 28 |
| Witch (elite) | elite | 28 | 1d6+1 magic | 1 | attack, Bog Brew (heal 1d6+2 on the most hurt monster), Mire Ward (armor −2, 2 rounds), Bog Brew | Bog Brew when a monster is below 40% HP; then waits 1 move | 30 |
| Sentinel (Act II) | normal | 20 | 1d6+1 (laser) | 1 | Laser Beam (1d6+2 each hero), attack, Target Lock (most hurt hero vulnerable +2, 2 rounds), attack, Overcharge (self +2 damage, 2 rounds) | Overcharge when below 40% HP and not already active, once | 14 |
| Dragon (boss) | boss | 52 | 1d6+2 | 1 | Fire Breath (1d6+3 magic each hero), attack, Dragon Scales (armor −2, 2 rounds), Fire Breath, Devour (heal 2d6) | Terrifying Roar (stun the most hurt hero 1 turn + weaken each hero −1, 2 rounds) when below 50% HP, once | 100 |

**Rebalanced 2026-10-22 for the party-turn / enemies'-turn rounds (§7.2), not simulated:** every enemy now acts once every enemies' turn. Before, enemies charged per hero turn (2 hero turns per round): `attackEvery 2` already meant once a round (Wolf, Spider, Witch — unchanged), `attackEvery 3` meant ⅔ of a round. Those (Goblin, Skeleton, Troll, Dragon) now act every round, so their HP or dice were cut to keep roughly the same damage per round: Goblin 14→12 HP, Skeleton 16→14 HP, Troll attack 2d6+1→1d6+2, Dragon attack 2d6+2→1d6+2, Fire Breath 2d6+2→1d6+3, Devour 2d6+2→2d6. Potions now cost an action point, which makes the party a little weaker.

Encounter pools: elites are Troll (early/mid), Witch (mid), and Troll + Goblin / Witch + Skeleton late.

Simulated results (win % / party HP lost of 60), starting skills → with 3 learned skills (Cleave, Heavy Strike, Chain Lightning):

| Encounter | 100% right | 80% right |
|---|---|---|
| Goblin | 100 / 5 → 100 / 2 | 100 / 10 → 100 / 8 |
| Wolf ×2 + Goblin (late) | 99 / 27 → 100 / 23 | 68 / 46 → 82 / 39 |
| Troll + Goblin (late elite) | 99 / 29 → 100 / 26 | 51 / 51 → 78 / 43 |
| Dragon from full HP (with learned skills) | 88 | 18 |
| Dragon from 22/22 HP (with learned skills) | 65 | 5 |

**These numbers predate physical/magic damage (2026-10-18), monster rules and the round structure (2026-10-22)** — Wizard spells now ignore armor (helps vs Troll/Witch/Dragon armor) and the Witch's attacks ignore block (hurts) — so they need a re-run.

The boss is meant to be hard; at 80% accuracy it's still very hard. The remaining big lever (not applied — it would change a recorded rule) is letting wrong answers *not* tick enemy charge.

Economy: starting gold 20, max potions carried 3 (extra → +5 gold each), potion prices 15–18 gold, relic prices 25 gold, gear 25–40 gold, haggle ±25%. Elite: +1 relic. Elite/boss: 50% bonus potion, 60% gear. Normal fights: 12% gear. Elites: a skill offer; shop: a skill scroll for 40 gold. Campfire: Rest +12 HP, Train +1 damage on every damage roll for the rest of the run, or Study (upgrade one skill). 2 AP per hero per turn.
