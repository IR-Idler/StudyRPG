# Study RPG — Combat & dice

Part of the game design reference; `game.md` is the index. Section numbers (§) are shared across all docs.

## 7. Combat **[Built]**

Implemented by `CombatEngine` in `Services/CombatEngine.swift` (a real turn state machine — see `CombatPhase` and the other runtime state in `Models/CombatState.swift`) and the fight screen in `Views/FightView.swift` plus its subviews (`BattleStage`, `CombatConsole`, `CombatVFX`, `FlashcardQuizOverlay`, `DiceTrayView`, `CharacterInfoSheet` in `Views/`). Reached from fight/elite/boss map nodes in a run (`RunState.startFight`), or from the menu's **Test Fight** harness. Test Fight lets you pick any encounter plus decks and carries one of each potion, but no relics or training. Its setup shows every distinct encounter once (the same roster can sit in several depth pools) as a dark tile with the enemies' portraits, "Goblin ×2 + Wolf"-style names and an elite seal / boss crown; the first is preselected, every usable deck starts selected, and a gold **Fight** button starts it.

### 7.1 Setup
- 1–3 enemies per fight, defined per encounter in `Content/encounters.json`. Early map nodes: 1 weaker enemy. Mid nodes: 2–3 enemies and/or stronger stats. Elite/boss nodes: fewer enemies (often exactly 1) but much stronger stats.
- If both heroes fall, Game Over.

### 7.2 Rounds, turns and action points (user decision 2026-10-22)
A **round** is the **party's turn** followed by the **enemies' turn** (`CombatEngine.isEnemyTurn`).

**The party's turn:**
1. Every living hero gets `balance.json → combat.actionPointsPerTurn` (**2**, user decision 2026-10-27) **action points** (AP; `CombatEngine.maxActionPoints(heroAt:)` is the one place later AP boosts will add to). A hero stunned by a monster (§7.3) loses this turn instead: one stun point is used up, they get 0 AP, and a beat shows it (violet `moon.zzz`).
2. The first hero (party order) with AP is selected. **Tap a hero's sprite to select them instead** — the heroes act in any order, switching freely, until their AP are spent. A hero without AP can't be selected.
3. Each action costs AP: **every skill** costs its `actionPoints` (classes.json: **2** for the big skills — Heavy Strike, Cleave, Ground Slam, Fireball, Chain Lightning, Frost Nova, Meteor — else **1**; shown as a badge on the skill card) and **drinking a potion** costs the potion's `actionPoints` (items.json, all **1**), paid by the selected hero, who may give it to either hero. Skills always need a correct flashcard answer; potions don't.
4. **Two taps for every skill:** tap the skill (it's armed, red outline), then tap its target — even when the target is obvious. Single-target skills (`enemy`, `ally`, `self`) show a bouncing arrow over each valid target (`self`: only the selected hero); group skills (`allEnemies`, `party`) show one gilded bracket over the whole group with a group symbol, and tapping any member confirms (§7.6). Tap the armed card again to disarm it, or another skill to switch.
5. A flashcard is drawn and shown with 4 answers. **Correct** → the skill resolves: its cost is paid, its cooldown starts, dice are rolled (§8), its effects apply. **Wrong** → the skill **fizzles** (no mana, no cooldown, but the AP are spent) and the **strongest** living, un-stunned enemy hits the answering hero **once** (`combat.wrongAnswerCounterattacks` = 1 enemy) with at most `combat.wrongAnswerMaxDice` (**1**) of its attack dice plus its flat bonus; block and weaken apply. "Strongest" = highest average hit (attack dice average + flat − weaken), ties → most HP. Charge counters are untouched. (User decision 2026-10-18.)
6. After an action, the same hero stays selected while they have AP; otherwise the next hero with AP is selected. When nobody has AP left — or the player taps **End turn** (unspent AP are lost) — the enemies' turn starts.

**The enemies' turn:** every living enemy, in roster order, gets one slot: a **stunned** enemy sleeps through it (one stun point used up, shown with its own `moon.zzz` beat); otherwise its charge counter ticks and, once full, it plays its move (§7.3).

**End of round:** timed effects wear down (§7.4), cooldowns tick (§5), the round number goes up and the next party turn begins.

### 7.3 Enemy charge & moves
- Each enemy has its own `attackEvery` threshold and its own counter, starting at 0. The counter ticks once in each enemies' turn (§7.2) — **unless the enemy is stunned**: it skips that turn instead. Every enemy today has `attackEvery: 1` (it acts every enemies' turn); its charge pips are only shown when `attackEvery` > 1.
- When an enemy's counter reaches its threshold, it plays **one move** — one of its skills; the counter resets to 0 once the move has fully played. Enemies act one after another, and each picks its move only when it starts, so it reacts to what the previous one did.
- A wrong-answer counterattack (§7.2 step 5) happens during the party's turn, separate from scheduled moves. It always uses the enemy's basic attack.

**Monster skills [Built 2026-10-22]** — defined per enemy in `enemies.json → skills`, using the hero skill vocabulary (§5) where it means the same thing:
- **Basic attack:** every enemy has the built-in skill `attack` from its `attackDice` (+ `attackDamageType`): damage to every living hero. It needs no definition; `attack` is reserved as an id.
- **Targets** (`target`, per skill; any effect may override it with its own `target`): `heroes` (every living hero), `hero` (the **most hurt** living hero = lowest share of max HP, ties → party order), `self`, `ally` (the most hurt living monster, itself included, ties → roster order), `allies` (every living monster). No target is ever random — every random number comes from the dice (§8).
- **Effects** (`type`; at most one rolling effect per skill):

  | Effect | Lands on | Meaning |
  |---|---|---|
  | `damage` (dice, optional `damageType`) | heroes | A **separate roll per hero** (Fast mode: one batch, §7.6). `magic` ignores all block (§7.4) |
  | `heal` (dice) | monsters | One roll, applied to each target; capped at max HP, never revives |
  | `armor` (amount, rounds) | monsters | −amount per hit taken for `rounds` (replaces any armor it had) |
  | `damageBuff` (amount, rounds) | monsters | +amount per hit dealt for `rounds` |
  | `stun` (amount) | heroes | The hero loses their next *amount* party turns (§7.2 step 1) |
  | `weaken` (amount, rounds) | heroes | −amount on every damage roll of that hero (heals unaffected) |
  | `vulnerable` (amount, rounds) | heroes | +amount on every hit that hero takes |

  A skill plays its roll first (each hit with the usual banner → lunge → impact rhythm), then its other effects together in one beat. Optional `vfx` for damage: `claw` (default) or `fire` (flame burst + fire-breath sound).
- **Pattern:** `movePattern` is a list of skill ids (or `attack`) that loops. Simple enemies have `["attack"]`.
- **Rules** (`rules`, optional): checked **in order before the pattern** each time the enemy acts; the first rule whose conditions all hold — and that isn't cooling down or used up — picks its `skill`; otherwise the pattern's next move plays. **A rule move doesn't advance the pattern** (it resumes where it was). Conditions (`when`, all optional, all must hold): `selfHPBelow` (own HP below that share of max, 0…1), `allyHPBelow` (some living monster, itself included, below that share), `heroHPBelow` (some living hero below that share), `minAlliesAlive` / `maxAlliesAlive` (living monsters, itself included; 1…3), `unlessActive: true` (only if some target doesn't already have one of the skill's timed effects — e.g. no re-armoring). Limits: `cooldown: N` (after firing, skipped for its next N moves), `maxUses: N` (per fight).
- **Telegraph:** because nothing is random, the nameplate shows exactly what the enemy would play if its charge filled now (rules evaluated live) — the move can change when the situation changes (e.g. the Troll switches to Regenerate once it's hurt enough). While it acts, it keeps showing the move it's playing.

### 7.4 Damage, block, and armor
- **Physical vs magic damage:** every damage roll is physical (default) or magic. Physical damage is reduced by block/armor; **magic damage ignores every kind of block and armor** (Shield Wall, Iron Shield, block gear, enemy armor). Weaken and vulnerable still apply to both. Magic sources today: every Wizard damage skill (`damageType: "magic"` in classes.json), the Bog Witch's basic attack (`attackDamageType: "magic"` in enemies.json), and the Dragon's Fire Breath (`damageType: "magic"` on its skill). Magic is marked with a violet `sparkles` glyph on skill cards and log rows.
- A hit on a hero deals `roll + damageBuff(attacker) − weaken(attacker) + vulnerable(hero) − block`, min 0 (magic: no block), where block = Iron Shield relic + active Shield Wall + the hero's own `block` gear. On the battlefield these show as one summed silver shield badge per hero; the info sheet lists them separately.
- A hero's damage roll gets a flat bonus of Lucky Ring + campfire training + the hero's `damageBonus` gear + active damage buffs − monster `weaken` on that hero (§7.3); heal rolls get Lucky Ring + `healBonus` gear (training doesn't boost heals). Bonus dice (Strength Potion, `firstRollBonusDice` gear) add dice to the hero's next roll and are used up by it. First-roll gear dice are set at the start of every fight; they don't carry over.
- A hit on an enemy deals `roll + vulnerable − armor`, min 0 (magic: no armor).
- **A round** = the party's turn + the enemies' turn (§7.2). **Timed effects** — on heroes *and* on enemies (Shield Wall, damage buffs, enemy armor, weaken, vulnerable) — wear down at the end of a round, after the enemies' turn. An effect applied during a round isn't worn down at the end of that same round, so `rounds: 2` always means two full rounds after the current one.
- HP floors at 0 (dead) for heroes and enemies; healing caps at max HP and never revives.

### 7.5 Victory / loss
- All enemies at 0 HP → victory. The reward is rolled once, the first time the fight is opened, saved with the run (`NodeReward`), and shown on the victory screen as icons:
  - gold = the sum of each enemy's `goldReward`;
  - **elite** victories also give one random unowned relic, or `rewards.relicFallbackGold` (20) gold if the party owns every relic;
  - **elite and boss** victories have a `rewards.bonusPotionChance` (50%) chance of a random potion (converted to gold if the bag is full);
  - gear: `rewards.fightGearChance` (12%) for normal fights, `rewards.eliteGearChance` (60%) for elites/boss — into the gear bag;
  - run fights also pay **experience** to every hero (`VictoryExperience`, §5 "Levels"): each hero gets a large XP bar (`VictoryExperienceBar`) with their level and a `+N` that counts down while the bar fills by the same amount (~1.2 s); passing a level threshold fills the bar, restarts it at the new level and pops in **LEVEL UP** + the new die (with the `skillLearn` sound);
  - elites (not normal fights, not the boss) also carry a **skill offer** (§5), shown as a sparkle chip and picked on the map afterwards.
- Both heroes at 0 HP → Game Over (see §3). After a won fight, HP/mana/potions carry back into the run.

### 7.6 Battle stage & visual presentation **[Built]**

**Guiding rule: symbols and color, not words.** The battlefield carries almost no text beyond character names. Every number/icon is colored by meaning (`Palette` semantic colors, §17): **red = damage**, **green = health/healing**, **blue = mana**, **yellow = strength / bonus dice / damage buffs**, **silver = block/armor**, **violet = control on enemies (stun, weaken, vulnerable)**.

- **Strictly sequential combat:** only one thing happens at a time. `CombatEngine` applies each effect and then enters a `.resolving` beat (`CombatPhase.resolving`); it does nothing further until the fight screen has finished presenting that beat and calls `continueAfterResolution(id:)`. Every enemy action is one step in a single queue (`EnemyStep`), so rolls never overlap. The order of one hero action:
  1. *Action Selection:* tap a hero's sprite to pick who acts (optional), then a skill card in the bottom console — or a potion.
  2. *Targeting (every skill):* the tapped card is armed (red outline). Single-target skills get a **bouncing arrow** over every valid target — red over living enemies, green over living heroes (only the selected hero for `self` skills). Group skills get **one gilded bracket** (`TargetGroupBracket`) spanning every target with a group symbol in its middle (three people red over the enemies for `allEnemies`, two people green over the heroes for `party`) and no single arrows, so "hits everyone" never reads as "pick one". Tap a target. Tap the armed card again to disarm it, or tap another skill to switch. There is no separate scope/cancel button.
  3. *Flashcard Quiz:* parchment card with the question and 4 options (no title). Answer feedback and teaching moments as in §4.1. The real response time is logged (§4.2).
  4. *Dice:* the dice (§8) are thrown and settle, then a banner shows a die icon + total (gold for heroes, ember for enemies).
  5. *Attack:* **the actual attacker** lunges and its effect plays toward the actual target (§ VFX list below).
  6. *Impact:* the target flashes red and shakes, the engine applies the result, and a floating icon+number shows the **applied** amount (after armor/Shield Wall, capped healing). A fully blocked hit (0 damage) is always shown too: it clangs off a shield (`ShieldPulseAnimationView` at the target, no red flash) and floats a silver shield + `0`.
  7. *Beat:* the number and HP bar get ~0.85s to read, the dice clear, then the next step starts. Non-dice effects (Shield Wall, Bolt's +1 mana — which comes *after* the bolt hits — and enemy armor) each get their own ~1s beat. A skill's non-dice effects are **always** applied, even when its roll just won the fight (Bolt's killing blow still gives +1 mana).
  8. *Enemies' turn* (once no hero has AP left): each enemy in turn — a stun beat, or its move: one roll per hero, each with the same banner → lunge → impact → beat rhythm.
- **Fast mode** (Settings, §2): every pause above is halved, and an enemy's attack on both heroes is thrown as **one** batch of dice (each hero's dice in turn); the batch still plays strictly in sequence — banner (with the target hero's portrait) → lunge → impact for the first hero, then the second. Area skills (Cleave, Chain Lightning) roll once and hit every enemy in the same beat.
- **Who is acting is always visible:**
  - **Heroes:** the selected hero steps **forward** (closer and toward the enemies, full size); the other steps **back** (further, ~92% size). They glide between those positions when the turn passes. While the hero is acting, a golden glow sits **behind** the sprite (a halo plus a glow pooled on their platform), so the art stays fully visible. Their nameplate is gold-rimmed.
  - **Enemies:** while an enemy acts (its attack rolls, heal, or armor), it gets an ember glow behind its sprite, an ember-rimmed nameplate, and a slight scale-up. The active hero's glow dims during that time.
  - **Combat log** (`CombatLogView`, bottom-right of the console): a symbol-only running record of everything. Each row shows the actor's mini portrait, the skill/move icon, an arrow, the target's portrait, then the **whole calculation**: the die faces (`3+4`, bonus dice from Strength Potion / gear in yellow), the skill's own `+flat`, then every modifier as its own symbol + signed amount (`RollModifier`, in calculation order): yellow ↑ damage buff, yellow weightlifter campfire training, yellow hammer gear bonus, yellow seal relic bonus (green on heals), violet scope `+N` vulnerable, violet ↓ `−N` weaken, silver shield `−N` armor/block, yellow ★ `+N` crit stickers — or, when magic damage went through it, a faded crossed-out `shield.slash` (not subtracted). Then `=` and the colored result (`−5` red, `+5` green, `+1◆` blue, `+1🎲` yellow, shield + hourglass for buffs), plus a violet sparkle on magic hits. Answers show as a green check or red cross. It auto-scrolls to the newest row.
- **Floating platforms:** every hero and enemy stands on its own small floating island (`FloatingPlatformView`). It is drawn procedurally: a grass top with overhanging tufts, a dirt underside with strata, rocks and pebbles tapering to a jagged point, and ink outlines matching the hand-drawn art. Platform width follows the sprite's aspect ratio. Feet stand on the top's center line. The **material comes from the fight's theme** (`platform`): `grass` (green top + overhanging tufts), `moss`, `stone`, `snow` (white top + snow overhang), `ash` (charcoal top with glowing ember cracks) or `rock`.
- **Static stage:** nothing on the fight stage drifts, bobs or breathes — no background motion (lunges don't move the scenery), no platform bobbing, no idle sprite breathing. Only actual actions (lunges, hits, VFX, dice) and the small target arrows / shield pulse move.
- **Nameplates:** name capsule (no info glyph) + HP bar with the exact HP number beside it (it rolls to the new value), then one icon row: for heroes, **gold action-point pips** (hollow once spent) and mana diamonds (blue); for enemies, **charge pips colored by the next move** (only when `attackEvery` > 1) + that skill's own `icon` (color from its main effect: red damage, green heal, silver armor, yellow damage buff, violet stun/weaken/vulnerable; §7.3 "Telegraph"). **Only tapping a character's name** opens `CharacterInfoSheet` — tapping the sprite never does (it selects a target while a skill is armed, or selects that hero), so attacking and inspecting can't be mixed up.
- **Shield Wall:** shown as **one static party shield** (`PartyShieldView`) positioned directly in front of the two heroes (`x: stageW * 0.39`), with the block amount inside and an `hourglass` + remaining rounds badge underneath (turns red on the last round). There is no sphere/bubble around the characters; each hero's buff row below their feet (`StatusEffectRow`) shows the summed block amount (Shield Wall + Iron Shield).
- **Buff/debuff row:** every character shows *all* their effects in one badge row on the front of their floating platform, just below their feet (`StatusEffectRow`/`EffectBadge`). Effects of the same **kind** are summed into one badge, with no source shown:
  - block (Shield Wall + Iron Shield): silver `shield.fill` + total. No hourglass, because Shield Wall's rounds are on the party shield.
  - bonus dice (Strength Potion / gear): yellow `die.face.5.fill` + count.
  - campfire training: yellow `figure.strengthtraining.traditional` + damage bonus (no duration — it lasts the whole run).
  - roll bonus (Lucky Ring): yellow `arrow.up.circle.fill` + amount.
  - enemy armor: silver `shield.fill` + amount + `hourglass` + rounds.
  - damage buff (hero): yellow `arrow.up.circle.fill` + amount + rounds.
  - stun (enemy): violet `moon.zzz.fill` + ticks; weaken: violet `arrow.down.circle.fill`; vulnerable: violet `scope` (+ rounds).
  - from monster skills: hero stun (violet `moon.zzz.fill` + turns lost), hero weaken / vulnerable (same violet badges + rounds), enemy damage buff (yellow `arrow.up.circle.fill` + rounds).
  - Recharging skills (cooldowns) are **not** buffs and don't show here — they show on the skill button itself.

  Tapping a character's name opens `CharacterInfoSheet`, which lists **every** effect separately with its magnitude, duration, explanation and source, plus stats and skills/moves.
- **Skill cards** (`TacticalSkillCard` + `EmptySkillSlotCard` + `SkillEffectSummary`): always rendered as a **fixed 4-slot (2×2) grid** (`0..<4`) so the console never shifts height based on how many skills a hero currently has equipped. Unequipped slots show `EmptySkillSlotCard` (recessed dashed socket). Equipped slots show compact one-line cards: icon, name (shrinks to fit), the **action-point cost** as a gold pip with its number (`ActionPointCostBadge`), blue mana cost — replaced by a silver hourglass + turns capsule while the skill is recharging — and **what the skill does as colored symbols read straight from its JSON effects**: red dice = damage (violet sparkle = magic), green dice = healing, `+1◆` blue = mana, silver shield + hourglass = block, violet `moon.zzz` = stun, yellow ↑ = damage buff, violet ↓ = weaken, violet scope = vulnerable, plus a small target icon (three people = all enemies, two = party, person? = ally, circle = self). Pending bonus dice show as extra yellow dice; the flat bonus from relics, gear and buffs shows as a yellow `+N`. Unusable cards are dimmed.
- **Top bar:** the run's relics as small medallions, the **Round & Turn Indicator** (`RoundTurnIndicator`, always centered on the screen: hourglass + round number, then the party's side — each living hero's mini portrait with tiny AP pips, done ones dimmed with a green check, the selected one gold-rimmed — a chevron, then the enemies' side, each living enemy's mini portrait, the acting one ember-rimmed; whichever side's turn it is is lit, the other dimmed), the Fast mode toggle (tortoise/hare), the party button, the map chip (§9) and the settings gear. The party button (and tapping the relics) opens **the same party sheet as the map** (`PartyInventorySheet`, §9), opened on the active hero, showing the fight's live HP/mana/potions plus that hero's current effects; during a fight it is read-only (no gear/skill changes, potions are drunk from the console). Test Fight also gets a back button; run fights have none.
- **Console layout** (`FullWidthBottomConsoleView`): left is the selected hero's medallion portrait, a green heart + HP bar + HP number, the hero's **action points** (gold pips, `ActionPointPips`) with an **End turn** chip, and the potion tray from the fight's real inventory (vial rim colored by effect, AP-cost pip, count badge for duplicates; tap → pick who drinks it; dimmed when it would help nobody or the selected hero lacks the AP). The left column has a **fixed width** and the skill grid fills the space between it and the log, so switching heroes never moves anything. Center holds the 2×2 skill grid. Right holds the combat log (196pt wide); before the first entry it shows a faint scroll instead of an empty box.
- **Depth-sorted staging:** draw order follows floor position (`zIndex = feetY`). Enemy formation slots are fixed by roster position, so nobody slides when an ally dies: a lone enemy stands at 72% of the stage width; 2–3 enemies are packed left→right into the right half (52–98%) by their real art/platform widths (the raised middle one of three may overlap its neighbours by ~14%), and the whole formation shrinks only if it wouldn't fit. Sprite sizes are scaled to always fit the stage. Enemy sprite height comes from `enemies.json → spriteHeight`.
- **Per-fight backgrounds (`FightBackdrop`):** every encounter names its own theme (`encounters.json → themes`, §13). If `bg_<themeId>` exists in `Assets.xcassets` it is drawn full-screen; otherwise a static procedural placeholder (`ThemePlaceholderPainting`) paints the theme's `style` with its colors: `forest` (moon, layered pines, mist), `camp` (tents, campfire glow), `graveyard` (tombstones, dead tree, iron fence, fog), `ruins` (broken columns, arch, ivy), `cave` (stalactites, glowing crystals), `crypt` (brick wall, arched alcoves, torches), `mountain` (snow-capped peaks), `swamp` (dead trees, murky water, reeds, fireflies) and `lair` (cavern, lava pool, embers, bones). Painted once; never moves.

  | Theme | Encounter | Style | Platform |
  |---|---|---|---|
  | goblin_camp | Goblin | camp | grass |
  | old_graveyard | Skeleton | graveyard | stone |
  | moonlit_woods | Wolf | forest | grass |
  | goblin_hollow | Goblin ×2 | forest | moss |
  | haunted_ruins | Skeleton + Wolf | ruins | stone |
  | wolf_den | Wolf ×2 + Goblin | cave | rock |
  | bone_crypt | Skeleton ×2 + Wolf | crypt | stone |
  | frozen_pass | Wolf ×2 + Skeleton | mountain | snow |
  | troll_peak | Mountain Troll | mountain | rock |
  | witch_bog | Bog Witch | swamp | moss |
  | dragon_lair | Dragon | lair | ash |
  | neon_city | Sentinel ×1–3 (Act II) | future | metal |
  | server_vault | Sentinel ×1–3 (Act II) | future | metal |

  Act II (§16.0): `future` paints a night skyline of towers with lit windows and red beacons, a neon horizon line and a dark floor with a glowing perspective grid; the `metal` platform is a hovering steel disc with a cyan rim light, panel seams and a hover glow instead of rocks.
- **Anchored feedback:** every figure publishes its sprite bounds (`BattleAnchorKey`), so VFX and floaters land on the actual attacker/target. Floaters are generated from the engine's log entries, so the number shown is exactly what was applied: damage `heart.slash.fill` red (fully blocked: silver `shield.fill 0`), healing `cross.case.fill` green, mana `diamond.fill` blue, bonus dice `die.face.5.fill` yellow, armor `shield.fill` silver.
- **Dice tray (`DiceTrayView`):** see §8.
- **Attack animations (`AttackVFXOverlay`):** chosen by the skill's `vfx` field in `classes.json` (`blade` → `BladeSlashAnimationView`: two crossing white-hot crescent slashes with a blue-steel bloom, an impact flash and a spray of gold/white sparks; `fireball` → `FireballCometAnimationView`: a charge-up glow at the caster, a flickering comet with a flame-and-smoke trail along an arc, then an explosion with a shockwave ring, flying flames, rising smoke and a screen flash, plus a heavy haptic; `missile` → `MagicMissileAnimationView`: an arcane orb with a fading trail of motes and two orbiting sparks on a shallow arc, then a starburst + ring at 0.32s). Enemy damage skills with `vfx: claw` (default, incl. the basic attack) → `ClawSlashAnimationView`: three raking, tapered claw gashes torn diagonally across the hero with a dark-red glow, a hot core and flying droplets; `vfx: fire` → `FireBurstAnimationView`: flame tongues licking up around the hero, a hot base glow and rising embers (+ heavy haptic). `vfx: laser` (Act II robots; also the basic attack via `attackVfx`) → `LaserBeamAnimationView`: a charge glow at the robot's cannon, then a flickering cyan beam with a white-hot core to the hero, an impact flare and sparks (+ medium haptic). Heals / mana / bonus dice / control → `AuraBurstAnimationView` in green / blue / yellow / violet: a column of light, an expanding floor ring and the effect's symbol drifting up as motes. Every one of these is a single time-driven `Canvas` (smooth and cheap; no blur filters — the blade's bloom is wide translucent strokes). Shield Wall / armor → `ShieldPulseAnimationView`. Potions → a strong glow in the potion's own color (`PotionGlowAnimationView`).

## 8. Dice **[Built]**

**Dice tray (`DiceTrayView`)** — replaced the 3D SceneKit dice (user decision 2026-10-27). Deliberately **flat 2D**: no faux depth, tumbling, bouncing or shadows (the user rejected a 3D-imitating toss). One time-driven `Canvas` over the fight screen (like the attack VFX, §7.6), drawn only while dice are out. The faces are rolled (`Int.random`) when the spin starts and the dice stop on exactly those faces, which go to `CombatEngine` — the faces you see are the numbers used, never a hidden roll.

- **Tray:** a dark plaque with a double rim (gold for heroes, ember for enemies) and a diamond rivet at each end springs open over the arena floor, below the enemies' nameplates; one round socket per die, up to 5 per row.
- **Dice:** flat d6 = bone-parchment face with an inset rim line and ink pips (a hero's single pip is crimson; a raised face above 6 shows its number), or blood-red with bone pips for enemies (`Palette.dieBone`/`dieBlood`); d8 (monster dice with `sides: 8`) = a flat diamond with an inset rim and its number. A hero face with a sticker carries a small ink medallion with the sticker's symbol on its top-right corner, in the sticker's color (crit yellow, guard silver, spark blue, vigor green — `StickerStyle`); the spin flickers through the hero's real faces.
- **Spin:** every die spins in place (heroes clockwise, enemies counter-clockwise) with two fading after-images while fast, braking into the stop; its face changes each quarter turn (while the die is diagonal) and it stops upright on the rolled face. The dice stop one after another, left to right.
- **Stop:** a pop, a ring snapping outward and a ring of sparks; the socket then lights up as a rune circle with slowly turning ticks and a soft halo, until the tray fades out (0.3s) when the roll is done.
- **Sound:** a whoosh when the spin starts and a clack as each die stops (§19).
- **Timing:** the first die stops after 1.0s, each next one 0.14s later (Fast mode: 0.6s / 0.08s); the result is reported 0.15s after the last stop. A batched enemy roll spins every hero's dice at once (§7.6).
- A roll is described as a dice expression: `{count, flat}` (+ optional `sides` for monsters) meaning *count* dice plus a flat modifier; hero rolls throw *count* times the hero's own die (`PendingRoll.heroDie`, `DiceRollRequest.die`) (e.g. Fireball = `{count: 2, flat: 0}`, Heal = `{count: 1, flat: 2}`). Total = sum of rolled faces + flat (+ crits, below). Lucky Ring, gear and buffs add to the flat part; bonus dice add to the count (and also throw the hero's die).
- The tray reports the landed faces (`[DieFace]`: number + sticker) to `CombatEngine.applyRollSegment(_:rolled:)`; `segmentTotal` is the number the roll banner shows.
- Potions use fixed amounts (e.g. Health Potion's flat +8) and never roll.

### Hero dice **[Built 2026-10-27]** (§16.3 phase 1)

Every hero owns a **six-faced die** (`HeroState.die: [DieFace]`, saved as `RunSnapshot.Hero.die`; `Models/HeroDie.swift`). A face is a number plus at most one **sticker** (`balance.json → dice`). Every hero roll throws it; monster dice stay plain. A run starts with `dice.startingFaces` (1–6, no stickers); level-ups change faces (§5 "Levels").

| Sticker | Type | When its face lands on a hero roll |
|---|---|---|
| Crit (★ `star.fill`) | `crit` | that die's number counts `amount` (1) extra times — on damage and healing rolls; logged as a yellow ★ `+N` modifier |
| Guard (🛡 `shield.fill`) | `block` | the roller takes −`amount` (2) from every physical hit until their next party turn (`HeroState.stickerBlock`, part of `damageReduction(forHeroAt:)`, shown in the silver block badge) |
| Spark (◆ `diamond.fill`) | `resource` | the roller gains `amount` (1) resource; only offered to classes with a resource |
| Vigor (✚ `cross.fill`) | `heal` | the roller heals `amount` (2) HP |

- Stickers on several dice of one roll each count. An area roll's crit applies to every enemy it hits; guard/spark/vigor land once per face on the roller.
- Guard, spark and vigor play in the beat after the roll, together with the skill's other effects (§7.6) — also when the roll won the fight.
- Validation (`ContentLoader`, blames `balance.json`): exactly 6 starting faces, each 1…`maxFaceValue`; `offerCount` ≥ 1; unique sticker/upgrade ids; stickers need a symbol and amount > 0; `raiseFace` needs amount > 0; `sticker` upgrades must name a known sticker.
