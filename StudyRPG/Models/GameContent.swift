import Foundation

// MARK: - Shared primitives

/// A dice expression: roll `count` d6 and add `flat`. The number used by game logic
/// is exactly the number shown on the settled physical dice (see game.md §8).
struct DiceExpr: Codable, Hashable {
    var count: Int
    var flat: Int
    /// Sides per die for monster rolls (`nil` = the standard d6). Hero rolls always use the
    /// hero's own six-faced die, whose faces change with level-ups (game.md §5 "Levels", §8).
    var sides: Int? = nil

    /// The die sizes the 3D dice can throw (game.md §8).
    static let supportedSides: Set<Int> = [6, 8]
    static let standardSides = 6
    var dieSides: Int { sides ?? Self.standardSides }

    /// Simulates a roll of this dice expression (sum of `count` dice of `dieSides` sides + `flat`).
    func roll() -> Int {
        guard count > 0 else { return flat }
        let sum = (0..<count).reduce(0) { total, _ in total + Int.random(in: 1...dieSides) }
        return sum + flat
    }
}

// MARK: - Hero classes & skills (Content/classes.json)

struct ResourceDef: Codable, Hashable {
    @ContentText var name: String
    var max: Int
    var start: Int
}

/// Who a skill is aimed at (game.md §5, §7.2). `enemy` and `ally` ask the player to tap a target.
enum SkillTarget: String, Codable {
    /// One enemy, tapped by the player.
    case enemy
    /// Every living enemy at once (one roll, applied to each).
    case allEnemies
    /// Both living heroes.
    case party
    /// One living hero, tapped by the player.
    case ally
    /// The hero using the skill.
    case selfHero = "self"

    var isEnemySide: Bool { self == .enemy || self == .allEnemies }
}

enum SkillEffectType: String, Codable {
    /// Rolls `dice` as damage to the skill's target(s).
    case damage
    /// Rolls `dice` as healing on the skill's target(s) (heroes only).
    case heal
    /// Party-wide damage reduction of `amount` per hit for `rounds` (Shield Wall).
    case block
    /// The user gains `amount` of its resource (e.g. mana).
    case resource
    /// The enemy target(s) skip their next `amount` enemy turns (game.md §7.3).
    case stun
    /// The hero target(s) deal +`amount` damage on every damage roll for `rounds`.\
    case damageBuff
    /// The enemy target(s) deal −`amount` damage per hit for `rounds`.
    case weaken
    /// The enemy target(s) take +`amount` damage per hit for `rounds`.
    case vulnerable

    /// Effects that roll the dice. A skill has at most one of these.
    var rolls: Bool { self == .damage || self == .heal }
}

/// Physical damage is reduced by block/armor; magic damage ignores every kind of block and armor
/// (game.md §7.4). Weaken and vulnerable still apply to both.
enum DamageType: String, Codable {
    case physical
    case magic
}

struct SkillEffectDef: Codable, Hashable {
    var type: SkillEffectType
    var dice: DiceExpr?
    var amount: Int?
    var rounds: Int?
    /// For `damage`: physical (default) or magic.
    var damageType: DamageType?

    var isMagic: Bool { damageType == .magic }
}

/// A skill's look (game.md §5 "Skill art"): which painted emblem it gets. Presentation only —
/// never changes what the skill does. Optional in classes.json; derived from the effects if absent.
enum SkillElement: String, Codable, CaseIterable {
    case steel, fire, frost, lightning, arcane, nature, `guard`, war, shadow, earth, mana
}

struct SkillDef: Codable, Hashable, Identifiable {
    var id: String
    @ContentText var name: String
    /// SF Symbol for small spots (combat log); also the emblem's fallback glyph.
    var icon: String
    /// The painted motif on the skill's emblem (game.md §5 "Skill art"), e.g. `sword_slash`.
    /// Presentation only; unknown or missing → the `icon` symbol is embossed instead.
    var art: String?
    /// Resource cost (e.g. mana). `nil` means free.
    var cost: Int?
    /// Action points it takes from the hero's turn (game.md §7.2).
    var actionPoints: Int
    var target: SkillTarget
    /// Name of a status (e.g. "block") that must NOT already be active for this skill to be usable.
    var requiresInactive: String?
    /// After a successful use, the skill can't be used for this many of the hero's own turns.
    var cooldown: Int?
    var effects: [SkillEffectDef]
    /// Which attack animation plays for this skill's damage roll: `blade`, `missile` or `fireball`
    /// (game.md §7.6). Optional; defaults to `blade`.
    var vfx: String?
    /// The painted emblem's element (game.md §5). nil = derived from the effects (`artElement`).
    var element: SkillElement?
    /// What the campfire's Study turns this skill into (game.md §5 "Skill upgrades"); nil = it
    /// can't be upgraded.
    var upgrade: SkillUpgradeDef?
    /// Set on the upgraded copy (`upgraded()`), never in JSON.
    var isUpgraded: Bool?

    /// The skill after Study: every field the upgrade sets replaces the base one.
    func upgraded() -> SkillDef {
        guard let upgrade else { return self }
        var skill = self
        if let cost = upgrade.cost { skill.cost = cost == 0 ? nil : cost }
        if let cooldown = upgrade.cooldown { skill.cooldown = cooldown == 0 ? nil : cooldown }
        if let actionPoints = upgrade.actionPoints { skill.actionPoints = actionPoints }
        if let effects = upgrade.effects { skill.effects = effects }
        skill.upgrade = nil
        skill.isUpgraded = true
        return skill
    }

    /// The name as shown: an upgraded skill gets a `+`.
    var displayName: String { isUpgraded == true ? name + "+" : name }

    /// The element the skill is painted with: the JSON's `element`, else what its main effect
    /// suggests (magic damage → arcane, physical → steel, heal → nature, block → guard,
    /// damage buff → war, stun/weaken/vulnerable → shadow, resource → mana).
    var artElement: SkillElement {
        if let element { return element }
        let main = diceEffect ?? effects.first
        switch main?.type {
        case .damage: return main?.isMagic == true ? .arcane : .steel
        case .heal: return .nature
        case .block: return .guard
        case .damageBuff: return .war
        case .stun, .weaken, .vulnerable: return .shadow
        case .resource, .none: return .mana
        }
    }

    var diceEffect: SkillEffectDef? { effects.first { $0.type.rolls && $0.dice != nil } }
    /// Whether this skill's damage roll is magic (ignores enemy armor).
    var dealsMagicDamage: Bool { diceEffect.map { $0.type == .damage && $0.isMagic } ?? false }
}

/// A skill's upgrade (`classes.json → skills[].upgrade`): each field set replaces the base one;
/// `cost`/`cooldown` 0 = none. `effects` replaces the whole effect list.
struct SkillUpgradeDef: Codable, Hashable {
    var cost: Int?
    var cooldown: Int?
    var actionPoints: Int?
    var effects: [SkillEffectDef]?
}

struct HeroClassDef: Codable, Hashable, Identifiable {
    var id: String
    @ContentText var name: String
    var spriteId: String
    var maxHP: Int
    var resource: ResourceDef?
    /// Every skill this class can ever know (game.md §5). Heroes start with `startingSkills` and
    /// learn the rest after fights.
    var skills: [SkillDef]
    /// Ids from `skills` a fresh hero knows and has equipped.
    var startingSkills: [String]

    func skill(id: String) -> SkillDef? { skills.first { $0.id == id } }
}

struct ClassesFile: Codable {
    var classes: [HeroClassDef]
}

// MARK: - Enemies (Content/enemies.json)

enum EnemyTier: String, Codable {
    case normal, elite, boss

    /// Display name, in the current language.
    var title: String {
        switch self {
        case .normal: return L("Normal")
        case .elite: return L("Elite")
        case .boss: return L("Boss")
        }
    }
}

/// Who a monster skill lands on (game.md §7.3). Picked by rule, never at random — every random
/// number comes from the dice (game.md §8).
enum EnemySkillTarget: String, Codable, CaseIterable {
    /// Every living hero (damage: a separate roll per hero).
    case heroes
    /// The living hero with the lowest share of their max HP (ties: party order).
    case hero
    /// The monster itself.
    case selfEnemy = "self"
    /// The living monster with the lowest share of its max HP, itself included (ties: roster order).
    case ally
    /// Every living monster, itself included.
    case allies

    var isHeroSide: Bool { self == .heroes || self == .hero }
}

/// The monster side of the skill vocabulary (game.md §5, §7.3): the same names as hero skills where
/// they mean the same thing.
enum EnemyEffectType: String, Codable {
    /// Rolls `dice` as damage on hero target(s); one roll per hero.
    case damage
    /// Rolls `dice` as healing on monster target(s); one roll applied to each.
    case heal
    /// Monster target(s) take −`amount` per hit for `rounds` (replaces any armor they had).
    case armor
    /// Hero target(s) lose their next `amount` turns.
    case stun
    /// Monster target(s) deal +`amount` per hit for `rounds`.
    case damageBuff
    /// Hero target(s) deal −`amount` on every damage roll for `rounds`.
    case weaken
    /// Hero target(s) take +`amount` per hit for `rounds`.
    case vulnerable

    var rolls: Bool { self == .damage || self == .heal }
    /// Whether this effect lands on heroes (otherwise on monsters).
    var hitsHeroes: Bool {
        switch self {
        case .damage, .stun, .weaken, .vulnerable: return true
        case .heal, .armor, .damageBuff: return false
        }
    }
}

struct EnemyEffectDef: Codable, Hashable {
    var type: EnemyEffectType
    var dice: DiceExpr?
    var amount: Int?
    var rounds: Int?
    /// For `damage`: physical (default) or magic (ignores the party's block, game.md §7.4).
    var damageType: DamageType?
    /// Overrides the skill's target for this one effect (e.g. a roar that weakens the heroes and
    /// buffs itself).
    var target: EnemySkillTarget?

    var isMagic: Bool { damageType == .magic }
}

/// One monster skill (game.md §7.3), defined in enemies.json like a hero skill.
struct EnemySkillDef: Codable, Hashable, Identifiable {
    var id: String
    @ContentText var name: String
    /// SF Symbol: the nameplate's next-move icon, the combat log, the Bestiary.
    var icon: String
    var target: EnemySkillTarget
    var effects: [EnemyEffectDef]
    /// Damage animation on the hero: `claw` (default), `fire` or `laser`.
    var vfx: String?

    static let knownVFX: Set<String> = ["claw", "fire", "laser"]

    var diceEffect: EnemyEffectDef? { effects.first { $0.type.rolls && $0.dice != nil } }
    func target(of effect: EnemyEffectDef) -> EnemySkillTarget { effect.target ?? target }
}

/// When a rule fires (game.md §7.3). Every condition that is set must hold; unset ones are ignored.
struct EnemyRuleConditions: Codable, Hashable {
    /// Its own HP is below this share of its max HP (0…1).
    var selfHPBelow: Double?
    /// Some living monster (itself included) is below this share of its max HP.
    var allyHPBelow: Double?
    /// Some living hero is below this share of their max HP.
    var heroHPBelow: Double?
    /// At least this many monsters are alive, itself included.
    var minAlliesAlive: Int?
    /// At most this many monsters are alive, itself included (1 = it's alone).
    var maxAlliesAlive: Int?
    /// Only if some target doesn't already have one of the skill's timed effects (no re-armoring).
    var unlessActive: Bool?
}

/// A rule picks a skill instead of the pattern's next move. Rules are checked in order each time
/// the monster acts; the first one that holds wins. A rule move doesn't advance the pattern.
struct EnemyRuleDef: Codable, Hashable {
    var skill: String
    var when: EnemyRuleConditions?
    /// After firing, the rule is skipped for the monster's next N moves.
    var cooldown: Int?
    /// Fires at most this many times per fight.
    var maxUses: Int?
}

struct EnemyDef: Codable, Hashable, Identifiable {
    /// The built-in basic attack's id: usable in `movePattern` and `rules` without defining it.
    static let basicAttackID = "attack"

    var id: String
    @ContentText var name: String
    var spriteId: String
    var tier: EnemyTier
    var baseHP: Int
    /// D&D-style hit dice for generating randomized health (e.g. 2d4+2, 2d8+3). Optional; if omitted, baseHP is used directly.
    var hpDice: DiceExpr? = nil
    /// The basic attack: the built-in `attack` move (every living hero, a roll each), the
    /// wrong-answer counterattack and the "strongest enemy" ranking (game.md §7.2).
    var attackDice: DiceExpr
    /// Charge counter threshold: ticks once every enemy turn; at this value the enemy plays its next move
    /// (1 = it acts every enemy turn, game.md §7.3).
    var attackEvery: Int
    var goldReward: Int
    /// Experience every hero gains when the party wins a fight against it (game.md §5 "Levels").
    var xp: Int
    /// Its own skills (game.md §7.3). Optional; an enemy without any only has the basic attack.
    var skills: [EnemySkillDef]?
    /// Skill ids (or `attack`) played in order, looping, whenever no rule fires.
    var movePattern: [String]
    /// Checked in order before the pattern each time it acts (game.md §7.3).
    var rules: [EnemyRuleDef]?
    /// On-screen sprite height in points on the fight stage (game.md §7.6). Optional; defaults to 125.
    var spriteHeight: Double?
    /// What its basic attack deals: physical (default) or magic (ignores the party's block).
    var attackDamageType: DamageType?
    /// Its basic attack's animation (`claw` default, `fire`, `laser`).
    var attackVfx: String?

    var basicAttackIsMagic: Bool { attackDamageType == .magic }

    /// The basic attack as a skill, so the engine plays every move the same way.
    var basicAttack: EnemySkillDef {
        EnemySkillDef(
            id: Self.basicAttackID,
            name: basicAttackIsMagic ? "Magic Attack" : "Attack",
            icon: basicAttackIsMagic ? "sparkles" : "burst.fill",
            target: .heroes,
            effects: [EnemyEffectDef(type: .damage, dice: attackDice, damageType: attackDamageType)],
            vfx: attackVfx
        )
    }

    var allRules: [EnemyRuleDef] { rules ?? [] }

    func skill(id: String) -> EnemySkillDef? {
        id == Self.basicAttackID ? basicAttack : skills?.first { $0.id == id }
    }

    /// The pattern's moves in order (unknown ids are rejected by `ContentLoader`).
    var patternSkills: [EnemySkillDef] { movePattern.compactMap(skill(id:)) }
    /// Every move it can make: pattern and rule skills, each once, pattern order first.
    var usableSkills: [EnemySkillDef] {
        var seen = Set<String>()
        return (movePattern + allRules.map(\.skill)).compactMap { id in
            seen.insert(id).inserted ? skill(id: id) : nil
        }
    }
}

struct EnemiesFile: Codable {
    var enemies: [EnemyDef]
}

// MARK: - Encounters (Content/encounters.json)

enum MapNodeType: String, Codable {
    case fight
    case elite
    case boss
    case shop
    case event
    case campfire
}

struct EncounterDef: Codable, Hashable {
    var enemyIds: [String]
    /// Which `themes` entry this fight is staged in — every fight has its own (game.md §7.6).
    var theme: String
}

/// Placeholder painting style for a fight theme until real background art exists.
enum ThemeStyle: String, Codable, CaseIterable {
    case forest, camp, graveyard, ruins, cave, crypt, mountain, swamp, lair
    /// Act II: a night city skyline over a glowing grid floor.
    case future
}

/// What the floating platforms under the combatants are made of.
enum PlatformMaterial: String, Codable, CaseIterable {
    case grass, stone, snow, moss, ash, rock
    /// Act II: a hovering steel disc with a cyan light underneath.
    case metal
}

/// How the run map is drawn (game.md §9, §16): the parchment map or the holographic one.
enum MapStyle: String, Codable, CaseIterable {
    case parchment, hologram
}

/// One act of a run (game.md §16): its own map look and encounter pools, ending in its boss.
struct ActDef: Codable, Hashable, Identifiable {
    var id: String
    @ContentText var name: String
    var mapStyle: MapStyle
}

/// One fight's stage (game.md §7.6). If an image named `bg_<id>` exists in the asset catalog it
/// is used as the full background; otherwise a static procedural placeholder is painted from
/// `style` and the colors (hex `#RRGGBB`).
struct FightThemeDef: Codable, Hashable, Identifiable {
    var id: String
    var style: ThemeStyle
    var skyTop: String
    var skyBottom: String
    var ground: String
    /// Light accent: moon, torches, crystals, lava, fog tint — depends on the style.
    var accent: String
    var platform: PlatformMaterial
}

struct EncounterPoolDef: Codable, Hashable {
    /// Which act (`encounters.json → acts`) this pool belongs to.
    var act: String
    var nodeType: MapNodeType
    var depthTier: Int
    var encounters: [EncounterDef]
}

struct EncountersFile: Codable {
    /// The run's acts, in order (game.md §16).
    var acts: [ActDef]
    var themes: [FightThemeDef]
    var pools: [EncounterPoolDef]
    /// Event-node vignettes (game.md §12). Kept in this file rather than a separate events.json
    /// because Content files are hand-wired into the Xcode project (see agents.md).
    var events: [EventDef]
}

// MARK: - Events (Content/encounters.json → events, game.md §12)

enum EventOutcomeType: String, Codable {
    /// +amount gold.
    case gold
    /// One random potion (converted to gold if the bag is full).
    case potion
    /// One random relic the party doesn't own (`rewards.relicFallbackGold` gold if they own all).
    case relic
    /// Both living heroes heal `amount`.
    case heal
    /// Both heroes gain `amount` max HP (and current HP).
    case maxHP
    /// Both living heroes lose `amount` HP (never below 1 — events can't kill).
    case loseHP
    /// Lose `amount` gold (never below 0).
    case loseGold
    /// One random piece of gear into the gear bag (game.md §6).
    case gear
}

struct EventOutcomeDef: Codable, Hashable {
    var type: EventOutcomeType
    var amount: Int?
}

/// A short, icon-led vignette whose outcome is decided by one flashcard: right → `reward`,
/// wrong → `penalty`.
/// Placeholder illustration for an event until real art exists (`event_<id>` in the asset catalog
/// replaces it automatically).
enum EventScene: String, Codable, CaseIterable {
    case questGiver, chest, shrine, spring, library, merchantCart, signpost, fallenKnight
}

struct EventDef: Codable, Hashable, Identifiable {
    var id: String
    /// SF Symbol used where the event is shown small (e.g. the combat log).
    var icon: String
    var scene: EventScene
    /// One short line of flavor.
    @ContentText var text: String
    var reward: EventOutcomeDef
    var penalty: EventOutcomeDef
}

// MARK: - Items (Content/items.json)

enum ItemEffectType: String, Codable {
    case heal
    case bonusDice
    case resource
}

enum ItemEffectTarget: String, Codable {
    case singleAlly
    case party
    case wizard
}

struct ItemEffectDef: Codable, Hashable {
    var type: ItemEffectType
    var target: ItemEffectTarget
    var dice: DiceExpr?
    var amount: Int?
}

struct ItemDef: Codable, Hashable, Identifiable {
    var id: String
    @ContentText var name: String
    var spriteId: String
    var cost: Int
    /// Action points drinking it in a fight takes from the hero who gives it (game.md §7.2).
    var actionPoints: Int
    var effect: ItemEffectDef
}

struct ItemsFile: Codable {
    var items: [ItemDef]
    /// Per-hero gear (game.md §6). Lives in items.json because Content files are hand-wired into
    /// the Xcode project (agents.md).
    var gear: [GearDef]?
}

// MARK: - Gear (Content/items.json → gear, game.md §6)

/// The three gear slots every hero has.
enum GearSlot: String, Codable, CaseIterable, Identifiable {
    case weapon, armor, trinket
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .weapon: return "hammer.fill"
        case .armor: return "tshirt.fill"
        case .trinket: return "sparkle"
        }
    }

    /// Display name, in the current language.
    var title: String {
        switch self {
        case .weapon: return L("Weapon")
        case .armor: return L("Armor")
        case .trinket: return L("Trinket")
        }
    }
}

/// What a piece of gear does — only ever to the hero wearing it.
enum GearEffectType: String, Codable {
    /// +amount max HP.
    case maxHP
    /// +amount on this hero's damage rolls (only `skillId`'s rolls if set).
    case damageBonus
    /// +amount on this hero's healing rolls.
    case healBonus
    /// Starts every fight with +amount resource (e.g. mana), capped at max.
    case startResource
    /// Every hit on this hero deals −amount damage.
    case block
    /// +amount bonus dice on this hero's first roll of every fight.
    case firstRollBonusDice
}

struct GearEffectDef: Codable, Hashable {
    var type: GearEffectType
    var amount: Int
    var skillId: String?
}

struct GearDef: Codable, Hashable, Identifiable {
    var id: String
    @ContentText var name: String
    var spriteId: String
    var slot: GearSlot
    var cost: Int
    /// Only this class can wear it. nil = anyone.
    var classId: String?
    var effects: [GearEffectDef]
}

// MARK: - Relics (Content/relics.json)

enum RelicEffectType: String, Codable {
    case damageReduction
    case rollBonus
    case maxHPBonus
}

struct RelicEffectDef: Codable, Hashable {
    var type: RelicEffectType
    var amount: Int
}

struct RelicDef: Codable, Hashable, Identifiable {
    var id: String
    @ContentText var name: String
    var spriteId: String
    var cost: Int
    var effect: RelicEffectDef
}

struct RelicsFile: Codable {
    var relics: [RelicDef]
}

// MARK: - Balance (Content/balance.json)

struct CardWeightConfig: Codable, Hashable {
    var noHistory: Double
    var base: Double
    var accuracyExponent: Double
    var accuracyScale: Double
}

/// Flashcard presentation tuning. See game.md §4.
struct FlashcardConfig: Codable, Hashable {
    /// Chance that a presented card withholds the correct answer and "None of these" is correct instead.
    var noneOfTheseChance: Double
    /// Minimum number of cards a deck needs before it can be used in a run (guarantees 3 deck-fill wrong answers).
    var minDeckSize: Int
}

/// Map generator tuning. See game.md §9.
struct MapConfig: Codable, Hashable {
    /// Rows between the start and the boss row (exclusive of the boss row itself).
    var rowCount: Int
    var minLanes: Int
    var maxLanes: Int
    /// How many random walks are unioned to build the branching path (game.md §9).
    var pathCount: Int
    /// Relative odds of each node type when the generator rolls a node.
    var nodeWeights: NodeWeights
    /// Elites can only roll from this far along the map (0…1 of the rows).
    var eliteMinProgress: Double
    /// Shops and campfires only appear from this far along the map (0…1 of the rows) — no
    /// resting right at the start.
    var restMinProgress: Double
    /// The last row before the boss is all campfires (Slay-the-Spire style).
    var campfireBeforeBoss: Bool
}

struct NodeWeights: Codable, Hashable {
    var fight: Double
    var elite: Double
    var event: Double
    var shop: Double
    var campfire: Double
}

/// Post-fight rewards (game.md §7.5).
struct RewardsConfig: Codable, Hashable {
    /// Chance an elite/boss victory also drops a random potion.
    var bonusPotionChance: Double
    /// Gold given instead of a relic when the party already owns every relic.
    var relicFallbackGold: Int
    /// Chance a normal fight victory drops a piece of gear.
    var fightGearChance: Double
    /// Chance an elite/boss victory drops a piece of gear.
    var eliteGearChance: Double
}

/// Skill learning (game.md §5).
struct SkillsConfig: Codable, Hashable {
    /// Most skills a hero can have equipped (the fight console shows only these).
    var maxEquipped: Int
    /// How many unknown skills a won fight offers to choose from.
    var offerCount: Int
}

/// Combat rules that are numbers rather than structure (game.md §7).
struct CombatConfig: Codable, Hashable {
    /// On a wrong answer, this many of the strongest living, un-stunned enemies hit the answering
    /// hero once each.
    var wrongAnswerCounterattacks: Int
    /// A counterattack rolls at most this many of the enemy's attack dice (its flat bonus still applies).
    var wrongAnswerMaxDice: Int
    /// Action points every hero gets at the start of each party turn (game.md §7.2).
    var actionPointsPerTurn: Int
}

/// Shop tuning (game.md §10).
struct ShopConfig: Codable, Hashable {
    /// Right haggle answer: prices × (1 − discount) for this visit.
    var haggleDiscount: Double
    /// Wrong haggle answer: prices × (1 + surcharge) for this visit.
    var haggleSurcharge: Double
    var relicsMin: Int
    var relicsMax: Int
    var gearMin: Int
    var gearMax: Int
    /// A skill scroll: buying it opens a skill offer (game.md §5, §10).
    var skillScrollCost: Int
}

/// Campfire tuning (game.md §11).
struct CampfireConfig: Codable, Hashable {
    /// Rest: HP healed on each living hero.
    var restHeal: Int
    /// Train: +this on every damage roll of every hero for the rest of the run (stacks).
    var trainDamageBonus: Int
}

/// One hero level (game.md §5 "Levels"): reached at `xp` total experience. Every level after the
/// first offers a die upgrade (`DiceConfig`).
struct LevelDef: Codable, Hashable {
    var xp: Int
}

struct LevelingConfig: Codable, Hashable {
    /// In order; the first is level 1 at 0 XP.
    var levels: [LevelDef]

    /// 1-based level for this much experience.
    func level(forXP xp: Int) -> Int {
        max(1, levels.lastIndex { xp >= $0.xp }.map { $0 + 1 } ?? 1)
    }

    /// XP of the current level and of the next one (`nil` at the top level), for progress bars.
    func bounds(forXP xp: Int) -> (current: Int, next: Int?) {
        let index = level(forXP: xp) - 1
        let current = levels.indices.contains(index) ? levels[index].xp : 0
        return (current, levels.indices.contains(index + 1) ? levels[index + 1].xp : nil)
    }
}

struct BalanceDef: Codable, Hashable {
    var startingGold: Int
    var maxPotionsCarried: Int
    var fullBagGoldConversion: Int
    var rewards: RewardsConfig
    var shop: ShopConfig
    var campfire: CampfireConfig
    var cardWeight: CardWeightConfig
    var flashcards: FlashcardConfig
    var map: MapConfig
    var skills: SkillsConfig
    var combat: CombatConfig
    var leveling: LevelingConfig
    var dice: DiceConfig
}

// MARK: - Aggregate content

/// Everything loaded from `Content/*.json`. See game.md §13 for the file-by-file schema
/// and agents.md for the rule that new content goes here, not into Swift code.
struct GameContent {
    var classes: [HeroClassDef]
    var enemies: [EnemyDef]
    var items: [ItemDef]
    var gear: [GearDef]
    var relics: [RelicDef]
    var acts: [ActDef]
    var encounterPools: [EncounterPoolDef]
    var themes: [FightThemeDef]
    var events: [EventDef]
    var balance: BalanceDef
    /// Bundled sample decks (`starter_decks.json`, game.md §4.5), seeded once on first launch.
    var starterDecks: [Deck] = []

    func classDef(id: String) -> HeroClassDef? {
        classes.first { $0.id == id }
    }

    func enemyDef(id: String) -> EnemyDef? {
        enemies.first { $0.id == id }
    }

    func itemDef(id: String) -> ItemDef? {
        items.first { $0.id == id }
    }

    func relicDef(id: String) -> RelicDef? {
        relics.first { $0.id == id }
    }

    func gearDef(id: String) -> GearDef? {
        gear.first { $0.id == id }
    }

    func event(id: String) -> EventDef? {
        events.first { $0.id == id }
    }

    func theme(id: String) -> FightThemeDef? {
        themes.first { $0.id == id }
    }
}
