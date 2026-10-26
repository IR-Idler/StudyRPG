# Study RPG — Heroes, skills & items

Part of the game design reference; `game.md` is the index. Section numbers (§) are shared across all docs.

## 5. Heroes & classes **[Built]**

Defined in `Content/classes.json`. Fields per class: id, display name, sprite id, max HP, max resource (e.g. mana) and its starting value, the class's whole **skill pool** (`skills`) and the ids a fresh hero starts with (`startingSkills`).

| Class | Max HP | Resource | Starting resource | Starting skills |
|---|---|---|---|---|
| Warrior | 30 | — | — | Sword, Shield Wall |
| Wizard | 30 | Mana (max 3) | 1 | Bolt, Fireball, Heal |

### Levels **[Built 2026-10-22; die upgrades 2026-10-27]**

- **Experience:** every enemy has an `xp` value (`enemies.json`). When the party wins a **run** fight, **every hero** (fallen or not) gains the sum of its enemies' XP (`RunState.experience(for:)`, applied in `finishFight`); Test Fight gives none. XP is saved with the run (`RunSnapshot.Hero.xp`; older saves load with 0).
- **Levels** come from `balance.json → leveling.levels` (`[{xp}]`), in order: level 1 at 0 XP, then each further level at its `xp` total (15, 32, 50, 70, 95, 125, 160, 200, 245, 295).
- **Every level gained offers a die upgrade** (replaced "level 2 = d8", §16.3): in `finishFight`, each level a hero passes queues one `DieUpgradeOffer` (`RunState.pendingDieUpgrades`, saved as `RunSnapshot.pendingDieUpgrades`): `dice.offerCount` (**3**) different upgrades from `dice.upgrades` that fit that hero — at least one face can take it, and resource stickers only for classes with a resource. Back on the map, `DieUpgradeView` (`Views/HeroDieViews.swift`) shows them before any skill offer and the map waits: tap an upgrade, then the face it goes on (each face shows before → after; faces it can't change are dimmed), or skip. Upgrades: **raise a face** (+2, capped at `dice.maxFaceValue` 9) or **put a sticker** on it (replacing any sticker it had) — see §8 "Hero dice". Saves from before hero dice load with the starting die and no offers.
- **Pacing:** about 3–4 level-ups per act on a fight-heavy route (~60–75 XP before the boss), 1–2 on a fight-light one (~25–35); `LevelTests` checks that over 200 generated maps the most fight-heavy route averages level 4 and the fight-lightest doesn't.

  | Enemy | XP |
  |---|---|
  | Goblin | 5 |
  | Skeleton | 6 |
  | Wolf | 6 |
  | Small Spider | 2 |
  | Troll (elite) | 20 |
  | Witch (elite) | 22 |
  | Dragon (boss) | 50 |
- **Shown:** a gold level badge + thin XP bar next to each hero in the run HUD (§9); level, XP bar and `xp/next` on the hero's party-sheet page, with the hero's six die faces below (`HeroDieStrip`); the victory screen fills each hero's large XP bar from a `+N` that counts down into it, with a gold **LEVEL UP** + a die for a hero who just reached a level (the upgrade itself is picked on the map, §7.5).

### Skill loadout & learning

- A hero has **known** skills and **equipped** skills. Only equipped skills appear in the fight console. At most `balance.json → skills.maxEquipped` (**4**) can be equipped, at least 1.
- **Learning [changed 2026-10-27, §16.3]:** skills come from **won elites** (not normal fights, not the boss) and the shop's **skill scroll** (§10). A skill offer (`SkillOffer.choices`) holds, for **every hero** who doesn't know their whole class yet, `skills.offerCount` (**3**) random unknown skills — all rolled up front (the elite's with its reward, the scroll's on purchase), so switching heroes can't re-roll them. `SkillRewardView` first asks **which hero learns** (each hero with a preview of their three emblems; skipped when only one hero is in the offer, with a back button otherwise), then shows that hero's skills: tap one to learn it. Only one skill is learned per offer. Saves with the old one-hero offer load as an offer for that hero. With a free slot it's equipped right away; with a full loadout, tap the equipped skill it replaces, or keep it unequipped in the skill book. Skipping is allowed. Travelling is locked until the offer is resolved.
- **Changing the loadout:** any time outside a fight, on the hero's page of the party sheet (§9) — tap a known skill to equip/unequip it. The campfire has a shortcut button (free, doesn't use up the campfire).
- **Skill upgrades [Built 2026-10-27]:** every skill has an `upgrade` in `classes.json` (`SkillUpgradeDef`): any of `cost`, `cooldown`, `actionPoints` (each replaces the base value; `cost`/`cooldown` 0 = none) and `effects` (replaces the whole list). The campfire's **Study** (§11) upgrades one known skill of either hero for the rest of the run (`HeroState.upgradedSkillIDs`, saved as `RunSnapshot.Hero.upgradedSkillIDs`); each skill upgrades once. `HeroState.skill(id:)` returns the upgraded version, so fights, the console and the party sheet all use it; its name shows with a `+` (`SkillDef.displayName`). Validation (blames `classes.json`): an upgrade must change something, and the upgraded skill needs effects, ≥ 1 AP and no mana cost on a class without a resource.
- **Cooldowns:** a skill with `cooldown: N` can't be used in the next N rounds after it resolves — cooldowns tick at the end of each round, not in the round they started (a fizzled skill doesn't go on cooldown). Shown as an hourglass badge on the skill card.

### Skill art

Every skill is shown as a painted emblem (`SkillIcon` / `SkillEmblem` in `Views/SkillArt.swift`) wherever it appears — fight console skill cards, the skill offer, the party sheet's skill book, the character info sheet and the run history: a gilded, beveled tile whose background is painted in the skill's **element**, with the skill's **motif** painted on top — an object drawn in the same ink-outlined, shaded style as the item art (§6), chosen to show what the skill does (table below), with a soft drop shadow and an element-colored glow, under a glossy top highlight. The motif comes from `classes.json → art` (`SkillMotif` in `Views/SkillMotifs.swift`, which reuses the `ItemArt` drawing kit); a skill without `art`, or with a name `SkillMotif` can't draw, gets its SF Symbol `icon` embossed instead (gradient fill, dark drop, glow) — never a crash. `icon` is still used for the small combat-log symbols. Unusable skills are shown desaturated and dimmed. The element is presentation only; it comes from `classes.json → element` and, when that's missing, from the skill's main effect (magic damage → arcane, physical damage → steel, heal → nature, block → guard, damage buff → war, stun/weaken/vulnerable → shadow, resource → mana). An unknown element fails content loading, naming classes.json.

| Element | Background painting | Skills today |
|---|---|---|
| `steel` | slate-blue, diagonal sheen, crossing slash arcs | Sword, Heavy Strike, Cleave, Sunder |
| `guard` | steel plate with a faint hex lattice | Shield Wall, Shield Bash |
| `war` | ember-gold sunburst | Battle Cry |
| `shadow` | near-black violet with curling mist | Intimidate, Hex |
| `nature` | forest green with falling light rays and motes | Second Wind, Heal, Mend |
| `earth` | brown, cracks spreading from below | Ground Slam |
| `arcane` | deep violet rune circle and stars | Bolt, Empower |
| `fire` | crimson with rising flame tongues and embers | Fireball, Meteor |
| `frost` | navy with radiating ice shards and flakes | Ice Lance, Frost Nova |
| `lightning` | indigo with forked bolts | Chain Lightning |
| `mana` | deep blue with floating mana diamonds | Mana Surge |

| `art` motif | Painting | Skill (what it does) |
|---|---|---|
| `sword_slash` | sword with a bright crescent slash | Sword (single hit) |
| `shield_wall` | two overlapping shields | Shield Wall (party block) |
| `heavy_strike` | war hammer swung down into an impact burst | Heavy Strike (2 dice) |
| `cleave` | broad axe with a wide sweep trail | Cleave (hits all enemies) |
| `shield_bash` | round buckler slamming an impact burst, stun stars | Shield Bash (hit + stun) |
| `sunder` | breastplate split by a glowing crack | Sunder (hit + vulnerable) |
| `battle_cry` | war horn blasting sound rings | Battle Cry (party damage buff) |
| `intimidate` | horned helm with burning red eyes | Intimidate (weaken all) |
| `second_wind` | heart wrapped in wind gusts | Second Wind (self heal) |
| `ground_slam` | cracked ground, flying rocks, shock ring | Ground Slam (stun all) |
| `arcane_bolt` | violet missile with a small mana diamond | Bolt (magic hit + mana) |
| `fireball` | blazing ball with a flame tail | Fireball (2 dice magic) |
| `heal` | herb sprig shedding glowing drops | Heal (party heal) |
| `chain_lightning` | bolt jumping between three glowing nodes | Chain Lightning (magic, all enemies) |
| `ice_lance` | faceted ice spear with frost chips | Ice Lance (magic hit + stun) |
| `frost_nova` | six-armed ice burst in a frost ring | Frost Nova (stun all) |
| `mend` | bandaged heart | Mend (big single heal) |
| `empower` | glowing sword with rising gold chevrons | Empower (ally damage buff) |
| `hex` | rag doll pierced by pins | Hex (weaken + vulnerable) |
| `meteor` | burning boulder with a huge fire tail | Meteor (3 dice magic) |
| `mana_surge` | mana crystal cluster with rising streams | Mana Surge (restore mana) |

Hand-drawn art: a `skill_<skillId>` PNG in the asset catalog replaces the painting (it keeps the gilded frame).

### Skill effects (schema)

A skill's `target` is `enemy` (tap one), `allEnemies`, `party` (both living heroes), `ally` (tap one living hero — skipped if only one is alive) or `self`. Each skill has at most one rolling effect.

| Effect | Meaning |
|---|---|
| `damage` (dice, optional `damageType`) | Roll and deal damage to the target enemy / every living enemy (one roll, applied to each). `damageType: "magic"` ignores enemy armor (§7.4); default `physical` |
| `heal` (dice) | Roll and heal the target hero(es); never revives |
| `block` (amount, rounds) | Party-wide Shield Wall: −amount per hit |
| `resource` (amount) | The user gains resource (mana) |
| `stun` (amount) | Target enemies skip their next *amount* charge ticks and can't counterattack while stunned |
| `damageBuff` (amount, rounds) | Target heroes deal +amount on every damage roll |
| `weaken` (amount, rounds) | Target enemies deal −amount per hit |
| `vulnerable` (amount, rounds) | Target enemies take +amount per hit |

### Skills (this table is the current content, not a schema)

| Class | Skill | AP | Cost | Target | Effect | Study upgrade |
|---|---|---|---|---|---|---|
| Warrior | Sword | 1 | free | enemy | 1d6 damage | 1d6+2 |
| Warrior | Shield Wall | 1 | free, only when not active | party | −2 damage per hit for 2 rounds | −3 per hit |
| Warrior | Heavy Strike | 2 | cooldown 2 | enemy | 2d6 damage | 3d6 |
| Warrior | Cleave | 2 | cooldown 2 | all enemies | 1d6 damage to each | cooldown 1 |
| Warrior | Shield Bash | 1 | cooldown 2 | enemy | 1d6 damage + stun 1 | cooldown 1 |
| Warrior | Sunder | 1 | cooldown 2 | enemy | 1d6 damage + vulnerable +2 for 2 rounds | vulnerable +3 |
| Warrior | Battle Cry | 1 | cooldown 3 | party | +2 damage for 2 rounds | +3 damage |
| Warrior | Intimidate | 1 | cooldown 3 | all enemies | weaken −2 for 2 rounds | cooldown 2 |
| Warrior | Second Wind | 1 | cooldown 3 | self | heal 1d6+3 | heal 2d6+3 |
| Warrior | Ground Slam | 2 | cooldown 4 | all enemies | stun 1 | cooldown 3 |
| Wizard | Bolt | 1 | free | enemy | 1d6 magic damage; +1 mana (capped) | 1d6+2 magic |
| Wizard | Fireball | 2 | 2 mana | enemy | 2d6 magic damage | 3d6 magic |
| Wizard | Heal | 1 | 2 mana | party | heal 1d6+2 | heal 2d6+2 |
| Wizard | Chain Lightning | 2 | 2 mana | all enemies | 1d6 magic damage to each | costs 1 mana |
| Wizard | Ice Lance | 1 | 2 mana | enemy | 1d6 magic damage + stun 1 | costs 1 mana |
| Wizard | Frost Nova | 2 | 2 mana | all enemies | stun 1 | 1 AP |
| Wizard | Mend | 1 | 1 mana | ally | heal 2d6+1 | heal 3d6+1 |
| Wizard | Empower | 1 | 1 mana | ally | +3 damage for 2 rounds | +4 damage |
| Wizard | Hex | 1 | 1 mana | enemy | weaken −2 and vulnerable +1 for 2 rounds | weaken −3, vulnerable +2 |
| Wizard | Meteor | 2 | 3 mana | enemy | 3d6 magic damage | 4d6 magic |
| Wizard | Mana Surge | 1 | cooldown 3 | self | +2 mana | +3 mana |

A skill use always requires answering a flashcard correctly first (see §7), and costs its `actionPoints` (the AP column: **2** for the big ones, else **1**) from the hero's action points for the turn (§7.2).

## 6. Items **[Built]**

Defined in `Content/items.json` (potions in `items`, gear in `gear`) and `Content/relics.json`.

- **Consumables (potions)** — a shared party bag: no flashcard needed. In a fight, drinking costs the potion's `actionPoints` (every potion: **1**) from the **selected hero**, who can give it to either hero, and only works during the party's turn (§7.2): tap a potion and pick which hero drinks it (only heroes it would help are offered — not at full HP / full mana, never a fallen hero). Outside fights, healing and mana potions can be drunk from the Bag page (§9). Max `maxPotionsCarried` (3) carried at once. Picking up one more converts it to `fullBagGoldConversion` (5) gold instead, and the shop won't sell potions into a full bag. In the fight console, duplicate potions stack into one button with a count. Potions heal a **fixed** amount (`dice.flat`, `count` must be 0 — validated), never a hidden roll.
  | Item | Effect |
  |---|---|
  | Health Potion | +8 HP to one hero |
  | Strength Potion | +1 bonus die on that hero's next damage/heal roll |
  | Mana Potion | +2 mana to the Wizard |
- **Gear** — per hero: every hero has three slots, **weapon**, **armor** and **trinket**, each holding one piece that only affects *that* hero. Unworn gear sits in the party's gear bag. Equip / take off any time outside a fight on the hero's page (§9); a class-restricted piece (`classId`) can only be worn by that class. Taking off max-HP gear lowers current HP to the new max if needed. Sources: normal fight victories (`rewards.fightGearChance` 12%), elite/boss victories (`rewards.eliteGearChance` 60%), the shop (`shop.gearMin`–`gearMax` pieces, 1–2) and the `gear` event outcome. Drops only pick gear someone in the party can wear; duplicates are possible.
  | Effect type | Meaning (for the wearer only) |
  |---|---|
  | `maxHP` | +amount max HP |
  | `damageBonus` | +amount on damage rolls (only `skillId`'s, if set) |
  | `healBonus` | +amount on healing rolls |
  | `startResource` | Start each fight with +amount mana (capped) |
  | `block` | −amount damage from every physical hit (magic ignores it) |
  | `firstRollBonusDice` | +amount bonus dice on the first roll of each fight |

  | Gear | Slot | Class | Cost | Effect |
  |---|---|---|---|---|
  | Iron Sword | weapon | Warrior | 30 | +1 damage |
  | Executioner's Axe | weapon | Warrior | 28 | +3 damage on Heavy Strike |
  | Oak Staff | weapon | Wizard | 30 | +1 damage |
  | Ember Wand | weapon | Wizard | 28 | +2 damage on Fireball |
  | Chainmail | armor | any | 35 | block 1 |
  | Padded Robe | armor | any | 25 | +5 max HP |
  | Troll Hide | armor | any | 40 | +8 max HP |
  | Mana Crystal | trinket | Wizard | 30 | +1 starting mana |
  | Healer's Charm | trinket | any | 25 | +2 healing |
  | Whetstone | trinket | any | 30 | +1 die on the first roll |
- **Item art:** every potion, relic and piece of gear without a PNG is painted by `ItemArt` (`Views/ItemArt.swift`, keyed by `spriteId`) in the hand-drawn style — ink outlines, shaded fills, a highlight and a glint — so each piece is recognizable from a 14pt HUD icon to a shop ware (§17).
- **Relics**: passive, party-wide, permanent for the run once found, do not take inventory space. Never duplicated: every relic source only offers relics the party doesn't own yet. Owned relics show in the fight's top bar and in the run HUD.
  | Relic | Effect |
  |---|---|
  | Iron Shield | −1 damage from every physical hit on the party (stacks with Shield Wall; magic attacks incl. the Dragon's Fire Breath ignore both) |
  | Lucky Ring | +1 to every hero damage/heal roll (added to the roll's flat part) |
  | Heart Amulet | +6 max HP (and current HP for living heroes) to both heroes, once, on pickup |
