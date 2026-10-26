import Foundation

// MARK: - Combat runtime state (game.md §7)
//
// In-memory only — a fight in progress is not saved (closing the app restarts the encounter,
// game.md §3). `HeroState` also carries everything a hero keeps between nodes of a run: HP,
// resource, bonus max HP, known/equipped skills and gear.

/// A timed buff or debuff. Wears down once per full round (game.md §7.4); a status applied during
/// a round isn't worn down at the end of that same round (`fresh`), so `rounds` always means full
/// rounds no matter which hero applied it.
struct TimedStatus: Hashable {
    var amount: Int
    var rounds: Int
    var fresh = true

    /// One round passed. Returns false once the status has run out.
    mutating func tick() -> Bool {
        if fresh {
            fresh = false
            return true
        }
        rounds -= 1
        return rounds > 0
    }
}

/// One hero's state for the current fight / run.
struct HeroState: Identifiable {
    var id: String { classDef.id }
    var classDef: HeroClassDef
    var hp: Int
    var resource: Int
    /// Set by a bonus-die effect (e.g. Strength Potion, gear); consumed and reset on the next
    /// damage/heal roll.
    var bonusDiceNextTurn: Int = 0
    /// Campfire training: +this on every damage roll (set from the run at fight start).
    var trainingDamageBonus: Int = 0
    /// Permanent extra max HP for this run (Heart Amulet, events).
    var bonusMaxHP: Int = 0
    /// Experience earned this run; sets the hero's level (game.md §5 "Levels").
    var xp: Int = 0
    /// The hero's own six-faced die: every hero roll throws it (game.md §8 "Hero dice").
    var die: [DieFace] = DieFace.plain()
    /// Every skill this hero has learned (game.md §5).
    var knownSkillIDs: [String]
    /// The equipped skills (at most `balance.skills.maxEquipped`), in console order.
    var loadoutSkillIDs: [String]
    /// Known skills upgraded at a campfire (game.md §5 "Skill upgrades").
    var upgradedSkillIDs: [String] = []
    /// Worn gear, at most one per slot (game.md §6).
    var gear: [GearDef] = []

    // Fight-only state.
    /// Action points left this party turn (game.md §7.2); skills and potions spend them.
    var actionPoints: Int = 0
    /// Own turns left before a skill can be used again.
    var cooldowns: [String: Int] = [:]
    /// Temporary damage buffs (e.g. Battle Cry).
    var damageBuffs: [TimedStatus] = []
    /// Monster skills (game.md §7.3): turns this hero still loses, −damage dealt, +damage taken.
    var stunTurns: Int = 0
    var weakens: [TimedStatus] = []
    var vulnerables: [TimedStatus] = []
    /// Block from landed guard stickers, until this hero's next party turn (game.md §8).
    var stickerBlock: Int = 0

    init(classDef: HeroClassDef, hp: Int, resource: Int) {
        self.classDef = classDef
        self.hp = hp
        self.resource = resource
        self.knownSkillIDs = classDef.startingSkills
        self.loadoutSkillIDs = classDef.startingSkills
    }

    var isAlive: Bool { hp > 0 }
    var maxHP: Int { classDef.maxHP + bonusMaxHP + gearTotal(.maxHP) }
    var maxResource: Int { classDef.resource?.max ?? 0 }

    /// The skill as this hero has it — upgraded if they studied it.
    func skill(id: String) -> SkillDef? {
        guard let base = classDef.skill(id: id) else { return nil }
        return upgradedSkillIDs.contains(id) ? base.upgraded() : base
    }

    var loadout: [SkillDef] { loadoutSkillIDs.compactMap(skill(id:)) }
    var knownSkills: [SkillDef] { knownSkillIDs.compactMap(skill(id:)) }
    /// Known skills that can still be upgraded.
    var upgradableSkills: [SkillDef] {
        knownSkillIDs.filter { !upgradedSkillIDs.contains($0) }.compactMap(classDef.skill(id:)).filter { $0.upgrade != nil }
    }
    func gear(in slot: GearSlot) -> GearDef? { gear.first { $0.slot == slot } }

    /// Sum of one gear effect over everything worn. `skillId` limits skill-specific bonuses.
    func gearTotal(_ type: GearEffectType, skillId: String? = nil) -> Int {
        gear.flatMap(\.effects)
            .filter { $0.type == type && ($0.skillId == nil || $0.skillId == skillId) }
            .reduce(0) { $0 + $1.amount }
    }

    var damageBuff: Int { damageBuffs.reduce(0) { $0 + $1.amount } }
    var weakenAmount: Int { weakens.reduce(0) { $0 + $1.amount } }
    var vulnerableAmount: Int { vulnerables.reduce(0) { $0 + $1.amount } }
    var isStunned: Bool { stunTurns > 0 }
}

/// One enemy's state for the current fight. Each instance ticks its own charge counter and move
/// index independently (game.md §7.3).
struct EnemyInstance: Identifiable, Hashable {
    var id: UUID = UUID()
    var def: EnemyDef
    var hp: Int
    /// Optional max HP override (e.g. when HP is rolled using hit dice). Defaults to `def.baseHP`.
    var maxHPOverride: Int? = nil
    var chargeCounter: Int = 0
    /// Position in its `movePattern` (rule moves don't advance it).
    var moveIndex: Int = 0
    /// The move it is playing right now (set when it starts, cleared when it's done), so the
    /// nameplate keeps showing it while it acts.
    var actingPlan: EnemyPlan?
    /// Moves left before each rule (by index) may fire again, and how often each has fired.
    var ruleCooldowns: [Int: Int] = [:]
    var ruleUses: [Int: Int] = [:]
    /// Armor from a monster skill: −amount per hit taken.
    var armor: TimedStatus?
    /// Deals more damage per hit (monster skills).
    var damageBuffs: [TimedStatus] = []
    /// Deals less damage per hit (hero Weaken / Hex skills).
    var weakens: [TimedStatus] = []
    /// Takes more damage per hit (hero Sunder skills).
    var vulnerables: [TimedStatus] = []
    /// Charge ticks it still skips (hero Stun skills).
    var stunTicks: Int = 0

    var isAlive: Bool { hp > 0 }
    var maxHP: Int { maxHPOverride ?? def.baseHP }
    var hasArmor: Bool { armor != nil }
    var armorRoundsRemaining: Int { armor?.rounds ?? 0 }
    var armorAmount: Int { armor?.amount ?? 0 }
    var damageBuff: Int { damageBuffs.reduce(0) { $0 + $1.amount } }
    var weakenAmount: Int { weakens.reduce(0) { $0 + $1.amount } }
    var vulnerableAmount: Int { vulnerables.reduce(0) { $0 + $1.amount } }
    var isStunned: Bool { stunTicks > 0 }
    /// Average damage of one of its hits — used to pick the "strongest" enemy (game.md §7.2).
    var threat: Double {
        Double(def.attackDice.count) * Double(def.attackDice.dieSides + 1) / 2 + Double(def.attackDice.flat + damageBuff - weakenAmount)
    }
    var hpShare: Double { Double(hp) / Double(max(1, maxHP)) }
}

/// Where a roll's result goes once the dice settle.
enum RollPurpose: Hashable {
    case heroDamage(targetEnemyID: UUID?)
    /// One roll applied to every living enemy.
    case heroDamageAll
    /// nil target = every living hero.
    case heroHeal(targetHeroID: String?)
    /// One enemy's skill hitting one hero (game.md §7.3); `skillID` is `attack` for the basic attack.
    case enemyAttack(enemyID: UUID, targetHeroID: String, skillID: String)
    /// One roll healing every listed enemy.
    case enemyHeal(enemyID: UUID, skillID: String, targetEnemyIDs: [UUID])
}

/// One named part of a roll's calculation, so the combat log can show every buff, debuff and
/// block that changed the number (game.md §7.6). Positive adds, negative subtracts.
struct RollModifier: Hashable {
    enum Kind: Hashable {
        /// Damage buffs (hero Battle Cry / Empower, monster skills).
        case damageBuff
        /// Worn gear (damage / healing bonus).
        case gear
        /// Relics (Lucky Ring).
        case relic
        /// Campfire training.
        case training
        /// The target is vulnerable.
        case vulnerable
        /// The attacker is weakened.
        case weaken
        /// The target enemy's armor.
        case armor
        /// The hero's personal block, party block and block gear combined.
        case block
        /// Ignored by magic damage (game.md §7.4).
        case ignoredBlock
        /// Crit stickers on the landed faces (game.md §8 "Hero dice").
        case crit
    }

    var kind: Kind
    var amount: Int
}

/// A roll that's been requested but hasn't settled yet. The dice view only reports the faces that
/// come up; `CombatEngine` decides what they mean (game.md §8).
struct PendingRoll: Identifiable, Equatable {
    var id: UUID = UUID()
    var expr: DiceExpr
    var sides: Int = DiceExpr.standardSides
    /// A hero roll throws the hero's own die (game.md §8 "Hero dice"); nil for monster dice.
    var heroDie: [DieFace]? = nil
    var isEnemyRoll: Bool
    var purpose: RollPurpose
    /// The hero skill that produced this roll (nil for enemy rolls).
    var skillID: String? = nil
    /// The skill's / move's own flat part; `expr.flat` minus this comes from `bonuses`.
    var baseFlat: Int = 0
    /// Where the rest of `expr.flat` came from (buffs, gear, relics).
    var bonuses: [RollModifier] = []
    /// How many of the dice are bonus dice (Strength Potion, training, gear) — the last ones thrown.
    var bonusDice: Int = 0
    /// Magic damage ignores block and armor (game.md §7.4).
    var isMagic: Bool = false
    /// Fast mode (game.md §7.6): one enemy's attack on several heroes thrown as one batch of dice.
    /// Each segment uses `expr.count` dice, in order, and is applied one after another.
    var batch: [RollPurpose] = []

    var segments: [RollPurpose] { batch.isEmpty ? [purpose] : batch }
    var diceCount: Int { expr.count * segments.count }
}

/// A real turn state machine (game.md §7.2).
enum CombatPhase: Equatable {
    case choosingAction
    /// An enemy-targeted skill is armed; tap an enemy.
    case choosingTarget(skillID: String)
    /// An ally-targeted skill is armed; tap a hero.
    case choosingAlly(skillID: String)
    case awaitingAnswer(skillID: String, targetEnemyID: UUID?)
    /// Dice are animating.
    case rolling(PendingRoll)
    /// An effect has just been applied and the fight screen is playing its feedback. Nothing else
    /// happens until the screen calls `continueAfterResolution(id:)` (game.md §7.6).
    case resolving(beat: ResolutionBeat, id: UUID)
    case victory
    case defeat
}

enum ResolutionBeat: Equatable {
    case roll
    case effect
}

/// Who did something / had something done to them, for the combat log.
enum CombatActor: Hashable {
    case hero(String)
    case enemy(UUID)
    case party
}

/// One line in the fight's symbol-based log (game.md §7.6). `text` is the plain-language version
/// for the info sheet and accessibility, never shown on the battlefield.
struct CombatLogEntry: Identifiable {
    enum Kind { case damage, heal, block, armor, mana, strength, correct, wrong, stun, buff, debuff }
    var id: UUID = UUID()
    var kind: Kind
    var actor: CombatActor?
    var target: CombatActor?
    /// The skill / move / item icon that caused this.
    var icon: String
    var dice: [Int] = []
    /// The skill's / move's own flat part (buffs, gear and relics are in `modifiers`).
    var flat: Int = 0
    /// How many of `dice` (the last ones) are bonus dice.
    var bonusDice: Int = 0
    /// Every buff, debuff and block that changed the number, in calculation order.
    var modifiers: [RollModifier] = []
    /// Magic damage (ignores block / armor).
    var isMagic = false
    /// The applied result (after modifiers / capping).
    var amount: Int = 0
    var rounds: Int?
    var text: String
}
