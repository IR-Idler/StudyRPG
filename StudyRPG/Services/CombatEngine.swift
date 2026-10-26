import Foundation
import Observation
import SwiftUI
import CryptoKit

// MARK: - CombatEngine (game.md §7)

/// A real turn state machine for one fight. Owned by the fight screen; not persisted.
///
/// Everything happens strictly one step at a time (game.md §7.6): every applied effect enters a
/// `.resolving` beat, and the engine only moves on when the fight screen has finished showing it
/// and calls `continueAfterResolution(id:)`.
@Observable
final class CombatEngine {
    private(set) var heroes: [HeroState]
    private(set) var enemies: [EnemyInstance]
    /// The hero the player has selected (tap a hero's sprite to switch, game.md §7.2). Exactly 2
    /// heroes, same as the rest of this project (party setup assumes 2 classes).
    private(set) var activeHeroIndex: Int = 0
    /// `true` while the enemies take their turn, `false` during the party's turn (game.md §7.2).
    private(set) var isEnemyTurn = false
    private(set) var phase: CombatPhase = .choosingAction
    private(set) var log: [CombatLogEntry] = []
    private(set) var currentPresentedCard: PresentedCard?
    private(set) var goldReward: Int = 0
    /// The party-wide Shield Wall buff (Iron Shield is separate: `relicDamageReduction`).
    private(set) var shieldWall: TimedStatus?
    /// The enemy currently doing something (attack roll, heal, armor), so the fight screen can
    /// always show who is acting (game.md §7.6). `nil` while the heroes are acting.
    private(set) var actingEnemyID: UUID?

    /// Potions the party carries into this fight; drinking one removes it (game.md §6).
    private(set) var inventory: [ItemDef]
    /// Run relics, applied passively (game.md §6, §7.4).
    let relics: [RelicDef]
    let flashcards: FlashcardSession
    private let combatConfig: CombatConfig
    /// Hero dice: stickers and their effects (game.md §8 "Hero dice").
    let dice: DiceConfig
    /// The roller-side stickers (guard, spark, vigor) of the hero roll that just landed; they
    /// play in the beat after the roll, with the skill's other effects.
    private var landedStickers: [StickerDef] = []
    /// Settings → Fast mode (game.md §7.6): an enemy's attack on both heroes is thrown as one batch.
    @ObservationIgnored var fastMode = false

    /// 1-indexed round counter; a round is the party's turn followed by the enemies' turn.
    private(set) var roundNumber: Int = 1
    /// The hero picked for an ally-targeted skill.
    private var allyTargetID: String?
    /// Cooldowns started this round (`heroID|skillID`): they don't tick at the end of this round.
    private var cooldownsSetThisRound: Set<String> = []

    /// Everything the enemies do, as one strictly sequential queue (game.md §7.3).
    private enum EnemyStep {
        /// A wrong-answer counterattack: the basic attack on the answering hero, with capped dice.
        case counter(enemyID: UUID, heroID: String)
        /// A charged enemy starts its move: picks the skill (rules, then pattern) and its targets
        /// now, so it reacts to everything that happened before it (game.md §7.3).
        case act(enemyID: UUID)
        /// One damage roll of a skill on one hero. A skill on every hero is one of these per hero.
        case damage(enemyID: UUID, skillID: String, heroID: String)
        /// One heal roll applied to every listed enemy.
        case heal(enemyID: UUID, skillID: String, targetIDs: [UUID])
        /// The skill's non-rolling effects, each on the targets picked when the move started.
        case effects(enemyID: UUID, skillID: String, targets: [EnemySkillTarget: [CombatActor]])
        /// Empties an enemy's charge pips (and advances its pattern unless a rule picked the move)
        /// once its move has fully played, so the pips stay full while it acts.
        case finishCharge(enemyID: UUID, advancesPattern: Bool)
        /// One enemy's slot in the enemies' turn: a stunned enemy sleeps through it, otherwise its
        /// charge ticks and, once full, it plays its move (game.md §7.3).
        case enemyTurn(enemyID: UUID)
    }
    private var enemyQueue: [EnemyStep] = []

    /// What happens when the current resolution beat is continued.
    private enum Continuation {
        /// A hero's roll just resolved; its non-dice effects (e.g. Bolt's +1 mana, a stun) get
        /// their own beat after it.
        case heroSkill(skillID: String, postRollEffects: [SkillEffectDef], targetEnemyID: UUID?)
        case heroActionDone
        case enemyQueue
        /// The party's turn has been set up (stunned heroes shown); the player can act.
        case partyTurnReady
    }
    private var continuation: Continuation?

    /// Fresh heroes at full HP/starting resource and no relics — used by standalone Test Fight.
    convenience init(heroClasses: [HeroClassDef], enemyDefs: [EnemyDef], balance: BalanceDef, decks: [Deck], statsStore: CardStatsStore, inventory: [ItemDef] = [], rollEnemyHP: Bool = true) {
        let heroes = heroClasses.map { classDef in
            var hero = HeroState(classDef: classDef, hp: classDef.maxHP, resource: classDef.resource?.start ?? 0)
            hero.die = balance.dice.startingDie
            return hero
        }
        self.init(
            heroes: heroes,
            enemyDefs: enemyDefs,
            balance: balance,
            flashcards: FlashcardSession(decks: decks, statsStore: statsStore, balance: balance),
            inventory: inventory,
            rollEnemyHP: rollEnemyHP
        )
    }

    /// Existing hero state (HP/resource/skills/gear carried over) — used for run fights.
    init(heroes: [HeroState], enemyDefs: [EnemyDef], balance: BalanceDef, flashcards: FlashcardSession, relics: [RelicDef] = [], inventory: [ItemDef] = [], rollEnemyHP: Bool = true) {
        // Fight-start gear effects (game.md §6): extra starting resource and first-roll dice.
        self.heroes = heroes.map { hero in
            var hero = hero
            hero.cooldowns = [:]
            hero.damageBuffs = []
            hero.stunTurns = 0
            hero.weakens = []
            hero.vulnerables = []
            hero.stickerBlock = 0
            hero.hp = min(hero.hp, hero.maxHP)
            if hero.isAlive {
                hero.resource = min(hero.maxResource, hero.resource + hero.gearTotal(.startResource))
            }
            hero.bonusDiceNextTurn += hero.gearTotal(.firstRollBonusDice)
            return hero
        }
        self.enemies = enemyDefs.map { def in
            let hp = rollEnemyHP ? (def.hpDice.map { max(1, $0.roll()) } ?? def.baseHP) : def.baseHP
            return EnemyInstance(def: def, hp: hp, maxHPOverride: hp)
        }
        self.flashcards = flashcards
        self.relics = relics
        self.inventory = inventory
        self.combatConfig = balance.combat
        self.dice = balance.dice
        beginPartyTurn()
    }

    var activeHero: HeroState { heroes[activeHeroIndex] }

    // MARK: Action points (game.md §7.2)

    /// Action points this hero gets every party turn (`combat.actionPointsPerTurn`; later things
    /// that raise it add here).
    func maxActionPoints(heroAt index: Int) -> Int { combatConfig.actionPointsPerTurn }

    /// Hero dice always have six faces; level-ups change the faces, not the size (game.md §8).
    func dieSides(heroAt index: Int) -> Int { DiceExpr.standardSides }

    /// A living hero with action points left this party turn.
    func canAct(heroAt index: Int) -> Bool {
        heroes.indices.contains(index) && heroes[index].isAlive && heroes[index].actionPoints > 0
    }
    /// Nothing is playing: the fight waits for the player to pick a skill / target (or it's over).
    var isAwaitingPlayer: Bool {
        switch phase {
        case .choosingAction, .choosingTarget, .choosingAlly, .victory, .defeat: return true
        case .awaitingAnswer, .rolling, .resolving: return false
        }
    }
    var livingEnemies: [EnemyInstance] { enemies.filter(\.isAlive) }
    var shieldWallRoundsRemaining: Int { shieldWall?.rounds ?? 0 }
    /// Block from an active Shield Wall only (what the party shield shows).
    var shieldWallBlock: Int { shieldWall?.amount ?? 0 }
    /// Permanent block from relics (Iron Shield).
    var relicDamageReduction: Int { relics.filter { $0.effect.type == .damageReduction }.reduce(0) { $0 + $1.effect.amount } }
    /// Added to every hero damage/heal roll (Lucky Ring).
    var relicRollBonus: Int { relics.filter { $0.effect.type == .rollBonus }.reduce(0) { $0 + $1.effect.amount } }
    /// Party-wide reduction on each hit (Shield Wall + Iron Shield).
    var damageReduction: Int { shieldWallBlock + relicDamageReduction }

    /// Everything subtracted from a normal hit on this hero: party block, the hero's own gear and
    /// landed guard stickers.
    func damageReduction(forHeroAt index: Int) -> Int {
        damageReduction + heroes[index].gearTotal(.block) + heroes[index].stickerBlock
    }

    /// The flat bonus a skill's roll gets right now: Lucky Ring, the hero's gear and damage buffs.
    func rollBonus(for skill: SkillDef, heroAt index: Int) -> Int {
        rollBonuses(for: skill, heroAt: index).reduce(0) { $0 + $1.amount }
    }

    /// The same bonus split by source, for the combat log (game.md §7.6).
    func rollBonuses(for skill: SkillDef, heroAt index: Int) -> [RollModifier] {
        guard let effect = skill.diceEffect else { return [] }
        let hero = heroes[index]
        let gear = effect.type == .damage
            ? hero.gearTotal(.damageBonus, skillId: skill.id)
            : hero.gearTotal(.healBonus, skillId: skill.id)
        var parts = [
            RollModifier(kind: .relic, amount: relicRollBonus),
            RollModifier(kind: .gear, amount: gear)
        ]
        if effect.type == .damage {
            parts.append(RollModifier(kind: .training, amount: hero.trainingDamageBonus))
            parts.append(RollModifier(kind: .damageBuff, amount: hero.damageBuff))
            // A monster's Weaken (game.md §7.3).
            parts.append(RollModifier(kind: .weaken, amount: -hero.weakenAmount))
        }
        return parts.filter { $0.amount != 0 }
    }

    /// Whether a skill is currently selectable: resource cost, cooldown and `requiresInactive`.
    func isSkillUsable(_ skill: SkillDef) -> Bool {
        guard !isEnemyTurn, activeHero.isAlive, activeHero.actionPoints >= skill.actionPoints else { return false }
        if let cost = skill.cost, activeHero.resource < cost { return false }
        if (activeHero.cooldowns[skill.id] ?? 0) > 0 { return false }
        if skill.requiresInactive == "block", shieldWall != nil { return false }
        return true
    }

    // MARK: Potions — free, no flashcard, no turn cost (game.md §7.2 step 1)

    /// Whether the selected hero can give this potion to this hero now: it's the party's turn, the
    /// giver has the action points, and it would do anything (dead heroes can't drink).
    func canUsePotion(_ item: ItemDef, onHeroID heroID: String) -> Bool {
        guard isChoosing, activeHero.isAlive, activeHero.actionPoints >= item.actionPoints,
              let hero = heroes.first(where: { $0.id == heroID }), hero.isAlive else { return false }
        switch item.effect.type {
        case .heal: return hero.hp < hero.maxHP
        case .bonusDice: return true
        case .resource: return hero.maxResource > 0 && hero.resource < hero.maxResource
        }
    }

    func usePotion(_ item: ItemDef, targetHeroID: String) {
        guard canUsePotion(item, onHeroID: targetHeroID),
              let slot = inventory.firstIndex(where: { $0.id == item.id }),
              let index = heroes.firstIndex(where: { $0.id == targetHeroID }) else { return }
        inventory.remove(at: slot)
        heroes[activeHeroIndex].actionPoints -= item.actionPoints
        phase = .choosingAction
        let name = heroes[index].classDef.name
        switch item.effect.type {
        case .heal:
            let healed = applyHeal(toHeroAt: index, amount: item.fixedHealAmount)
            log.append(CombatLogEntry(kind: .heal, actor: .hero(heroes[index].id), icon: "flask.fill", amount: healed,
                                      text: L("\(name) drinks \(item.name) and heals \(healed) HP.")))
        case .bonusDice:
            let amount = item.effect.amount ?? 0
            heroes[index].bonusDiceNextTurn += amount
            log.append(CombatLogEntry(kind: .strength, actor: .hero(heroes[index].id), icon: "flask.fill", amount: amount,
                                      text: L("\(name) drinks \(item.name): +\(amount) die on the next roll.")))
        case .resource:
            let gained = applyResource(toHeroAt: index, amount: item.effect.amount ?? 0)
            log.append(CombatLogEntry(kind: .mana, actor: .hero(heroes[index].id), icon: "flask.fill", amount: gained,
                                      text: L("\(name) drinks \(item.name) and regains \(gained) \(heroes[index].classDef.resource?.name ?? L("resource")).")))
        }
        // Its own beat, so the glow and number read before anything else (e.g. the enemies' turn).
        beginBeat(.effect, then: .heroActionDone)
    }

    // MARK: Turn flow (game.md §7.2)

    /// The party's turn, waiting for the player (nothing armed, or a skill armed).
    var isChoosing: Bool {
        switch phase {
        case .choosingAction, .choosingTarget, .choosingAlly: return !isEnemyTurn
        default: return false
        }
    }

    /// The skill currently armed (waiting for its target tap), if any.
    var armedSkill: SkillDef? {
        switch phase {
        case .choosingTarget(let id), .choosingAlly(let id): return activeHero.skill(id: id)
        default: return nil
        }
    }

    /// The armed skill lands on every target at once (all enemies / the whole party): the stage
    /// marks the whole group instead of one arrow each (game.md §7.6).
    var armedSkillHitsGroup: Bool {
        guard let skill = armedSkill else { return false }
        return skill.target == .allEnemies || skill.target == .party
    }

    /// Who tapping can confirm the armed skill on.
    func isValidTarget(enemyID: UUID) -> Bool {
        guard case .choosingTarget = phase else { return false }
        return enemies.first { $0.id == enemyID }?.isAlive == true
    }

    func isValidTarget(heroID: String) -> Bool {
        guard case .choosingAlly = phase, let skill = armedSkill,
              let hero = heroes.first(where: { $0.id == heroID }), hero.isAlive else { return false }
        return skill.target == .selfHero ? heroID == activeHero.id : true
    }

    /// Tapping a hero's sprite: confirms an armed ally/party/self skill on them, otherwise selects
    /// them as the hero who acts next (any order, game.md §7.2).
    func tapHero(_ heroID: String) {
        if isValidTarget(heroID: heroID) {
            selectAlly(heroID)
        } else {
            selectHero(heroID)
        }
    }

    func selectHero(_ heroID: String) {
        guard isChoosing, let index = heroes.firstIndex(where: { $0.id == heroID }), canAct(heroAt: index) else { return }
        activeHeroIndex = index
        allyTargetID = nil
        phase = .choosingAction
    }

    /// Every skill takes two taps — the skill, then its target — even when the target is obvious.
    func selectSkill(_ skill: SkillDef) {
        switch phase {
        case .choosingTarget(let armedSkillID), .choosingAlly(let armedSkillID):
            // Tapping the armed skill again disarms it; tapping another skill switches to it.
            phase = .choosingAction
            if armedSkillID == skill.id { return }
        default:
            break
        }
        guard phase == .choosingAction, isSkillUsable(skill) else { return }
        allyTargetID = nil
        switch skill.target {
        case .enemy, .allEnemies:
            phase = .choosingTarget(skillID: skill.id)
        case .ally, .party, .selfHero:
            phase = .choosingAlly(skillID: skill.id)
        }
    }

    func selectTarget(_ enemyID: UUID) {
        guard case .choosingTarget(let skillID) = phase, isValidTarget(enemyID: enemyID) else { return }
        let hitsAll = activeHero.skill(id: skillID)?.target == .allEnemies
        phase = .awaitingAnswer(skillID: skillID, targetEnemyID: hitsAll ? nil : enemyID)
    }

    func selectAlly(_ heroID: String) {
        guard case .choosingAlly(let skillID) = phase, isValidTarget(heroID: heroID) else { return }
        allyTargetID = heroID
        phase = .awaitingAnswer(skillID: skillID, targetEnemyID: nil)
    }

    /// Ends the party's turn early (unspent action points are lost).
    func endPartyTurn() {
        guard isChoosing else { return }
        for index in heroes.indices { heroes[index].actionPoints = 0 }
        phase = .choosingAction
        beginEnemyTurn()
    }

    func cancelTargeting() {
        switch phase {
        case .choosingTarget, .choosingAlly: phase = .choosingAction
        default: break
        }
    }

    // MARK: Flashcards (game.md §4)

    func presentCard() -> PresentedCard? {
        let presented = flashcards.present()
        currentPresentedCard = presented
        return presented
    }

    @discardableResult
    func recordAnswer(chosenOptionIndex: Int?, responseMs: Int) -> Bool {
        guard currentPresentedCard != nil else { return false }
        var skillID: String?
        var enemy: EnemyDef?
        if case .awaitingAnswer(let id, let targetEnemyID) = phase {
            skillID = id
            enemy = (enemies.first { $0.id == targetEnemyID } ?? livingEnemies.max { $0.threat < $1.threat })?.def
        }
        return flashcards.record(chosenOptionIndex: chosenOptionIndex, responseMs: responseMs, skillID: skillID, enemy: enemy)
    }

    /// No card could be drawn (no usable deck): the skill is cancelled instead of freezing the fight.
    func cancelAwaitingAnswer() {
        guard case .awaitingAnswer = phase else { return }
        currentPresentedCard = nil
        phase = .choosingAction
    }

    func proceedAfterAnswer(skillID: String, targetEnemyID: UUID?, correct: Bool) {
        guard case .awaitingAnswer = phase else { return }
        currentPresentedCard = nil
        // The action is spent either way: a fizzled skill still used the hero's action points.
        heroes[activeHeroIndex].actionPoints -= activeHero.skill(id: skillID)?.actionPoints ?? 0
        let icon = activeHero.skill(id: skillID)?.icon ?? "questionmark"
        log.append(CombatLogEntry(
            kind: correct ? .correct : .wrong,
            actor: .hero(activeHero.id),
            target: targetEnemyID.map { .enemy($0) },
            icon: icon,
            text: correct ? L("\(activeHero.classDef.name) answers correctly.") : L("\(activeHero.classDef.name) answers wrong — the skill fizzles.")
        ))
        if correct {
            resolveSkill(skillID: skillID, targetEnemyID: targetEnemyID)
        } else {
            beginWrongAnswerCounterattack()
        }
    }

    func submitAnswer(chosenOptionIndex: Int?, responseMs: Int) {
        guard case .awaitingAnswer(let skillID, let targetEnemyID) = phase else { return }
        let correct = recordAnswer(chosenOptionIndex: chosenOptionIndex, responseMs: responseMs)
        proceedAfterAnswer(skillID: skillID, targetEnemyID: targetEnemyID, correct: correct)
    }

    // MARK: Correct answer — resolve the skill (game.md §7.2 step 4)

    private func resolveSkill(skillID: String, targetEnemyID: UUID?) {
        guard let skill = activeHero.skill(id: skillID) else { return }
        if let cost = skill.cost {
            heroes[activeHeroIndex].resource -= cost
        }
        if let cooldown = skill.cooldown, cooldown > 0 {
            heroes[activeHeroIndex].cooldowns[skill.id] = cooldown
            cooldownsSetThisRound.insert("\(activeHero.id)|\(skill.id)")
        }
        let otherEffects = skill.effects.filter { !$0.type.rolls }

        guard let diceEffect = skill.diceEffect, var expr = diceEffect.dice else {
            // No roll (e.g. Shield Wall, Frost Nova): applied at once, shown in its own beat.
            applyInstantEffects(otherEffects, skill: skill, targetEnemyID: targetEnemyID)
            beginBeat(.effect, then: .heroActionDone)
            return
        }

        // Bonus dice (Strength Potion, gear) are only consumed by an actual roll.
        let baseFlat = expr.flat
        let bonuses = rollBonuses(for: skill, heroAt: activeHeroIndex)
        let bonusDice = heroes[activeHeroIndex].bonusDiceNextTurn
        expr.flat += bonuses.reduce(0) { $0 + $1.amount }
        expr.count += bonusDice
        heroes[activeHeroIndex].bonusDiceNextTurn = 0
        let purpose: RollPurpose
        if diceEffect.type == .heal {
            switch skill.target {
            case .ally: purpose = .heroHeal(targetHeroID: allyTargetID ?? activeHero.id)
            case .selfHero: purpose = .heroHeal(targetHeroID: activeHero.id)
            default: purpose = .heroHeal(targetHeroID: nil)
            }
        } else {
            purpose = skill.target == .allEnemies ? .heroDamageAll : .heroDamage(targetEnemyID: targetEnemyID)
        }
        continuation = .heroSkill(skillID: skill.id, postRollEffects: otherEffects, targetEnemyID: targetEnemyID)
        phase = .rolling(PendingRoll(
            expr: expr, sides: dieSides(heroAt: activeHeroIndex), heroDie: heroes[activeHeroIndex].die, isEnemyRoll: false, purpose: purpose, skillID: skillID,
            baseFlat: baseFlat, bonuses: bonuses, bonusDice: bonusDice, isMagic: skill.dealsMagicDamage
        ))
    }

    /// The heroes a hero-side effect lands on.
    private func heroTargets(for skill: SkillDef) -> [Int] {
        switch skill.target {
        case .party: return heroes.indices.filter { heroes[$0].isAlive }
        case .ally: return heroes.indices.filter { heroes[$0].id == (allyTargetID ?? activeHero.id) && heroes[$0].isAlive }
        default: return [activeHeroIndex]
        }
    }

    /// The living enemies an enemy-side effect lands on.
    private func enemyTargets(for skill: SkillDef, targetEnemyID: UUID?) -> [Int] {
        if skill.target == .allEnemies { return enemies.indices.filter { enemies[$0].isAlive } }
        return enemies.indices.filter { enemies[$0].id == targetEnemyID && enemies[$0].isAlive }
    }

    /// Non-dice skill effects: resource, party block, stun, buffs and debuffs.
    private func applyInstantEffects(_ effects: [SkillEffectDef], skill: SkillDef, targetEnemyID: UUID?) {
        let hero = activeHero
        for effect in effects {
            let amount = effect.amount ?? 0
            let rounds = effect.rounds ?? 0
            switch effect.type {
            case .damage, .heal:
                continue
            case .resource:
                let gained = applyResource(toHeroAt: activeHeroIndex, amount: amount)
                log.append(CombatLogEntry(kind: .mana, actor: .hero(hero.id), icon: skill.icon, amount: gained,
                                          text: L("\(hero.classDef.name) gains \(gained) \(hero.classDef.resource?.name ?? L("resource")).")))
            case .block:
                shieldWall = TimedStatus(amount: amount, rounds: rounds)
                log.append(CombatLogEntry(kind: .block, actor: .hero(hero.id), target: .party, icon: skill.icon,
                                          amount: amount, rounds: rounds,
                                          text: L("The party takes \(amount) less damage per hit for \(rounds) rounds.")))
            case .stun:
                for index in enemyTargets(for: skill, targetEnemyID: targetEnemyID) {
                    enemies[index].stunTicks += amount
                    log.append(CombatLogEntry(kind: .stun, actor: .hero(hero.id), target: .enemy(enemies[index].id), icon: skill.icon,
                                              amount: amount, text: L("\(enemies[index].def.name) is stunned and skips its next \(amount) turn(s).")))
                }
            case .weaken, .vulnerable:
                for index in enemyTargets(for: skill, targetEnemyID: targetEnemyID) {
                    let status = TimedStatus(amount: amount, rounds: rounds)
                    let name = enemies[index].def.name
                    if effect.type == .weaken {
                        enemies[index].weakens.append(status)
                    } else {
                        enemies[index].vulnerables.append(status)
                    }
                    log.append(CombatLogEntry(kind: .debuff, actor: .hero(hero.id), target: .enemy(enemies[index].id), icon: skill.icon,
                                              amount: amount, rounds: rounds,
                                              text: effect.type == .weaken
                                                ? L("\(name) deals \(amount) less damage per hit for \(rounds) rounds.")
                                                : L("\(name) takes \(amount) more damage per hit for \(rounds) rounds.")))
                }
            case .damageBuff:
                for index in heroTargets(for: skill) {
                    heroes[index].damageBuffs.append(TimedStatus(amount: amount, rounds: rounds))
                    log.append(CombatLogEntry(kind: .buff, actor: .hero(hero.id), target: .hero(heroes[index].id), icon: skill.icon,
                                              amount: amount, rounds: rounds,
                                              text: L("\(heroes[index].classDef.name) deals \(amount) more damage for \(rounds) rounds.")))
                }
            }
        }
    }

    /// After a hero's action: the same hero goes on if they have action points left, otherwise
    /// the next hero who does is selected; when nobody can act, the enemies take their turn.
    private func finishHeroAction() {
        if checkVictoryOrDefeat() { return }
        allyTargetID = nil
        if canAct(heroAt: activeHeroIndex) {
            phase = .choosingAction
        } else if let next = heroes.indices.first(where: canAct(heroAt:)) {
            activeHeroIndex = next
            phase = .choosingAction
        } else {
            beginEnemyTurn()
        }
    }

    // MARK: Turn structure — party turn, then enemies' turn = one round (game.md §7.2)

    /// Every living hero gets their action points; a stunned hero loses this turn instead (one
    /// stun point used up, shown in its own beat).
    private func beginPartyTurn() {
        isEnemyTurn = false
        actingEnemyID = nil
        let before = log.count
        for index in heroes.indices {
            heroes[index].actionPoints = heroes[index].isAlive ? maxActionPoints(heroAt: index) : 0
            // Guard stickers last until the hero's next party turn (game.md §8).
            heroes[index].stickerBlock = 0
            if heroes[index].isAlive && heroes[index].isStunned {
                heroes[index].stunTurns -= 1
                heroes[index].actionPoints = 0
                let hero = heroes[index]
                log.append(CombatLogEntry(kind: .stun, actor: .hero(hero.id), target: .hero(hero.id), icon: "moon.zzz.fill", amount: 1,
                                          text: L("\(hero.classDef.name) is stunned and loses this turn.")))
            }
        }
        if log.count > before {
            beginBeat(.effect, then: .partyTurnReady)
        } else {
            partyTurnReady()
        }
    }

    /// Each party turn starts with the first hero (in party order) who can act selected.
    private func partyTurnReady() {
        if let next = heroes.indices.first(where: canAct(heroAt:)) {
            activeHeroIndex = next
            phase = .choosingAction
        } else {
            beginEnemyTurn()
        }
    }

    /// Every living enemy, in roster order, gets one slot (game.md §7.3).
    private func beginEnemyTurn() {
        isEnemyTurn = true
        enemyQueue = enemies.filter(\.isAlive).map { .enemyTurn(enemyID: $0.id) }
        processEnemyQueue()
    }

    // MARK: Wrong answer — the skill fizzles, the strongest enemy strikes (game.md §7.2 step 5)

    private func beginWrongAnswerCounterattack() {
        // Charge counters are left alone; only un-stunned enemies can strike back.
        let strikers = enemies.filter { $0.isAlive && !$0.isStunned }
            .sorted { ($0.threat, $0.hp) > ($1.threat, $1.hp) }
            .prefix(combatConfig.wrongAnswerCounterattacks)
        enemyQueue = strikers.map { .counter(enemyID: $0.id, heroID: activeHero.id) }
        processEnemyQueue()
    }

    // MARK: Enemy charge & scheduled moves (game.md §7.3), independently per enemy

    private func processEnemyQueue() {
        if checkVictoryOrDefeat() { return }
        guard !enemyQueue.isEmpty else {
            actingEnemyID = nil
            if isEnemyTurn {
                endRound()
            } else {
                // A wrong-answer counterattack during the party's turn has played.
                finishHeroAction()
            }
            return
        }

        switch enemyQueue.removeFirst() {
        case .enemyTurn(let enemyID):
            guard let index = enemies.firstIndex(where: { $0.id == enemyID }), enemies[index].isAlive else {
                processEnemyQueue()
                return
            }
            if enemies[index].stunTicks > 0 {
                // Stunned: it sleeps through this turn, visibly (game.md §7.3).
                enemies[index].stunTicks -= 1
                actingEnemyID = enemyID
                let enemy = enemies[index]
                log.append(CombatLogEntry(kind: .stun, actor: .enemy(enemy.id), target: .enemy(enemy.id), icon: "moon.zzz.fill", amount: 1,
                                          text: L("\(enemy.def.name) is stunned and skips its turn.")))
                beginBeat(.effect, then: .enemyQueue)
                return
            }
            enemies[index].chargeCounter += 1
            if enemies[index].chargeCounter >= enemies[index].def.attackEvery {
                enemyQueue.insert(.act(enemyID: enemyID), at: 0)
            }
            processEnemyQueue()

        case .act(let enemyID):
            if let index = enemies.firstIndex(where: { $0.id == enemyID }), enemies[index].isAlive {
                enemyQueue.insert(contentsOf: startMove(forEnemyAt: index), at: 0)
            }
            processEnemyQueue()

        case .counter(let enemyID, let heroID):
            guard let enemy = enemies.first(where: { $0.id == enemyID }), enemy.isAlive,
                  heroes.first(where: { $0.id == heroID })?.isAlive == true else {
                processEnemyQueue()
                return
            }
            let attack = enemy.def.basicAttack
            var expr = enemy.def.attackDice
            expr.count = min(expr.count, max(1, combatConfig.wrongAnswerMaxDice))
            beginEnemyRoll(enemyID: enemyID, skill: attack, expr: expr,
                           purposes: [.enemyAttack(enemyID: enemyID, targetHeroID: heroID, skillID: attack.id)])

        case .damage(let enemyID, let skillID, let heroID):
            guard let enemy = enemies.first(where: { $0.id == enemyID }), enemy.isAlive,
                  let skill = enemy.def.skill(id: skillID), let dice = skill.diceEffect?.dice,
                  heroes.first(where: { $0.id == heroID })?.isAlive == true else {
                processEnemyQueue()
                return
            }
            var purposes: [RollPurpose] = [.enemyAttack(enemyID: enemyID, targetHeroID: heroID, skillID: skillID)]
            if fastMode {
                // Fast mode: the same skill's following hits on other heroes join this throw.
                while case .damage(let nextEnemy, let nextSkill, let nextHero)? = enemyQueue.first,
                      nextEnemy == enemyID, nextSkill == skillID {
                    enemyQueue.removeFirst()
                    if heroes.first(where: { $0.id == nextHero })?.isAlive == true {
                        purposes.append(.enemyAttack(enemyID: enemyID, targetHeroID: nextHero, skillID: skillID))
                    }
                }
            }
            beginEnemyRoll(enemyID: enemyID, skill: skill, expr: dice, purposes: purposes)

        case .heal(let enemyID, let skillID, let targetIDs):
            guard let enemy = enemies.first(where: { $0.id == enemyID }), enemy.isAlive,
                  let skill = enemy.def.skill(id: skillID), let dice = skill.diceEffect?.dice else {
                processEnemyQueue()
                return
            }
            beginEnemyRoll(enemyID: enemyID, skill: skill, expr: dice,
                           purposes: [.enemyHeal(enemyID: enemyID, skillID: skillID, targetEnemyIDs: targetIDs)])

        case .effects(let enemyID, let skillID, let targets):
            guard let enemy = enemies.first(where: { $0.id == enemyID }), enemy.isAlive,
                  let skill = enemy.def.skill(id: skillID) else {
                processEnemyQueue()
                return
            }
            actingEnemyID = enemyID
            let before = log.count
            applyEnemyInstantEffects(skill, caster: enemy, targets: targets)
            if log.count > before {
                beginBeat(.effect, then: .enemyQueue)
            } else {
                processEnemyQueue()
            }

        case .finishCharge(let enemyID, let advancesPattern):
            if let index = enemies.firstIndex(where: { $0.id == enemyID }) {
                enemies[index].chargeCounter = 0
                enemies[index].actingPlan = nil
                if advancesPattern { enemies[index].moveIndex += 1 }
            }
            processEnemyQueue()
        }
    }

    private func beginEnemyRoll(enemyID: UUID, skill: EnemySkillDef, expr: DiceExpr, purposes: [RollPurpose]) {
        actingEnemyID = enemyID
        continuation = .enemyQueue
        phase = .rolling(PendingRoll(
            expr: expr,
            sides: expr.dieSides,
            isEnemyRoll: true,
            purpose: purposes[0],
            skillID: skill.id,
            baseFlat: expr.flat,
            isMagic: skill.diceEffect?.type == .damage && skill.diceEffect?.isMagic == true,
            batch: purposes.count > 1 ? purposes : []
        ))
    }

    /// What the fight screen shows as this enemy's next move: the skill it's playing right now, or
    /// what it would pick if its charge filled now (game.md §7.3, §7.6).
    func plannedMove(for enemy: EnemyInstance) -> EnemyPlan? {
        enemy.actingPlan ?? EnemyBrain.plan(for: enemy, enemies: enemies, heroes: heroes)
    }

    func enemySkill(enemyID: UUID, skillID: String) -> EnemySkillDef? {
        enemies.first { $0.id == enemyID }?.def.skill(id: skillID)
    }

    /// Picks the enemy's move (rules, then pattern) and its targets, does the rule bookkeeping and
    /// returns the steps that play it: its roll(s), then its other effects, then the charge reset.
    private func startMove(forEnemyAt index: Int) -> [EnemyStep] {
        let enemy = enemies[index]
        guard let plan = EnemyBrain.plan(for: enemy, enemies: enemies, heroes: heroes) else {
            return [.finishCharge(enemyID: enemy.id, advancesPattern: true)]
        }
        // Rule cooldowns count this move; then the rule that fired (if any) starts its own.
        for (rule, left) in enemy.ruleCooldowns {
            enemies[index].ruleCooldowns[rule] = left > 1 ? left - 1 : nil
        }
        if let ruleIndex = plan.ruleIndex {
            enemies[index].ruleUses[ruleIndex, default: 0] += 1
            if let cooldown = enemy.def.allRules[ruleIndex].cooldown, cooldown > 0 {
                enemies[index].ruleCooldowns[ruleIndex] = cooldown
            }
        }
        enemies[index].actingPlan = plan

        let skill = plan.skill
        var targets: [EnemySkillTarget: [CombatActor]] = [:]
        for target in Set(skill.effects.map(skill.target(of:))) {
            targets[target] = target.isHeroSide
                ? EnemyBrain.heroTargets(target, heroes: heroes).map { .hero(heroes[$0].id) }
                : EnemyBrain.enemyTargets(target, caster: enemy, enemies: enemies).map { .enemy(enemies[$0].id) }
        }

        var steps: [EnemyStep] = []
        if let rolling = skill.diceEffect {
            let actors = targets[skill.target(of: rolling)] ?? []
            if rolling.type == .damage {
                for case .hero(let heroID) in actors {
                    steps.append(.damage(enemyID: enemy.id, skillID: skill.id, heroID: heroID))
                }
            } else {
                let ids = actors.compactMap { actor -> UUID? in
                    if case .enemy(let id) = actor { return id }
                    return nil
                }
                if !ids.isEmpty { steps.append(.heal(enemyID: enemy.id, skillID: skill.id, targetIDs: ids)) }
            }
        }
        if skill.effects.contains(where: { !$0.type.rolls }) {
            steps.append(.effects(enemyID: enemy.id, skillID: skill.id, targets: targets))
        }
        return steps + [.finishCharge(enemyID: enemy.id, advancesPattern: plan.ruleIndex == nil)]
    }

    /// A monster skill's non-dice effects: armor and damage buffs on monsters; stun, weaken and
    /// vulnerable on heroes (game.md §7.3).
    private func applyEnemyInstantEffects(_ skill: EnemySkillDef, caster: EnemyInstance, targets: [EnemySkillTarget: [CombatActor]]) {
        let name = caster.def.name
        for effect in skill.effects where !effect.type.rolls {
            let amount = effect.amount ?? 0
            let rounds = effect.rounds ?? 0
            for actor in targets[skill.target(of: effect)] ?? [] {
                switch actor {
                case .hero(let heroID):
                    guard let index = heroes.firstIndex(where: { $0.id == heroID }), heroes[index].isAlive else { continue }
                    let heroName = heroes[index].classDef.name
                    switch effect.type {
                    case .stun:
                        heroes[index].stunTurns += amount
                        log.append(CombatLogEntry(kind: .stun, actor: .enemy(caster.id), target: actor, icon: skill.icon, amount: amount,
                                                  text: L("\(name) stuns \(heroName): they lose their next \(amount) turn(s).")))
                    case .weaken:
                        heroes[index].weakens.append(TimedStatus(amount: amount, rounds: rounds))
                        log.append(CombatLogEntry(kind: .debuff, actor: .enemy(caster.id), target: actor, icon: skill.icon,
                                                  amount: amount, rounds: rounds,
                                                  text: L("\(heroName) deals \(amount) less damage for \(rounds) rounds.")))
                    case .vulnerable:
                        heroes[index].vulnerables.append(TimedStatus(amount: amount, rounds: rounds))
                        log.append(CombatLogEntry(kind: .debuff, actor: .enemy(caster.id), target: actor, icon: skill.icon,
                                                  amount: amount, rounds: rounds,
                                                  text: L("\(heroName) takes \(amount) more damage per hit for \(rounds) rounds.")))
                    case .damage, .heal, .armor, .damageBuff:
                        continue
                    }
                case .enemy(let enemyID):
                    guard let index = enemies.firstIndex(where: { $0.id == enemyID }), enemies[index].isAlive else { continue }
                    let targetName = enemies[index].def.name
                    switch effect.type {
                    case .armor:
                        enemies[index].armor = TimedStatus(amount: amount, rounds: rounds)
                        log.append(CombatLogEntry(kind: .armor, actor: .enemy(caster.id), target: actor, icon: skill.icon,
                                                  amount: amount, rounds: rounds,
                                                  text: L("\(targetName) raises its armor: −\(amount) damage per hit for \(rounds) rounds.")))
                    case .damageBuff:
                        enemies[index].damageBuffs.append(TimedStatus(amount: amount, rounds: rounds))
                        log.append(CombatLogEntry(kind: .buff, actor: .enemy(caster.id), target: actor, icon: skill.icon,
                                                  amount: amount, rounds: rounds,
                                                  text: L("\(targetName) deals \(amount) more damage per hit for \(rounds) rounds.")))
                    case .damage, .heal, .stun, .weaken, .vulnerable:
                        continue
                    }
                case .party:
                    continue
                }
            }
        }
    }

    // MARK: Dice settlement — the only place a roll's number turns into an effect (game.md §8)

    /// Applies one segment of the current roll (a batched fast-mode throw has one per hero). The
    /// fight screen calls this once per segment, at that segment's impact, then `finishRoll()`.
    func applyRollSegment(_ segmentIndex: Int, faces: [Int]) {
        applyRollSegment(segmentIndex, rolled: faces.map { DieFace(value: $0) })
    }

    /// The number a landed segment adds up to: its faces, the flat part and — on hero rolls —
    /// crit stickers (game.md §8 "Hero dice"). The roll banner shows exactly this.
    func segmentTotal(_ pending: PendingRoll, rolled: [DieFace]) -> Int {
        rolled.reduce(0) { $0 + $1.value } + pending.expr.flat + (pending.isEnemyRoll ? 0 : dice.critBonus(rolled))
    }

    /// Applies one segment from the faces as they landed, stickers included.
    func applyRollSegment(_ segmentIndex: Int, rolled: [DieFace]) {
        guard case .rolling(var pending) = phase, pending.segments.indices.contains(segmentIndex) else { return }
        let faces = rolled.map(\.value)
        let total = segmentTotal(pending, rolled: rolled)
        if !pending.isEnemyRoll {
            let crit = dice.critBonus(rolled)
            if crit > 0 { pending.bonuses.append(RollModifier(kind: .crit, amount: crit)) }
            landedStickers = dice.rollerStickers(rolled)
        }
        let hero = activeHero
        let skillIcon = pending.skillID.flatMap { hero.skill(id: $0)?.icon } ?? "burst.fill"

        switch pending.segments[segmentIndex] {
        case .heroDamage(let targetEnemyID):
            if let index = enemies.firstIndex(where: { $0.id == targetEnemyID }) {
                damageEnemy(at: index, total: total, faces: faces, pending: pending, icon: skillIcon)
            }

        case .heroDamageAll:
            for index in enemies.indices where enemies[index].isAlive {
                damageEnemy(at: index, total: total, faces: faces, pending: pending, icon: skillIcon)
            }

        case .heroHeal(let targetHeroID):
            for index in heroes.indices where heroes[index].isAlive && (targetHeroID == nil || heroes[index].id == targetHeroID) {
                let healed = applyHeal(toHeroAt: index, amount: total)
                log.append(CombatLogEntry(kind: .heal, actor: .hero(hero.id), target: .hero(heroes[index].id), icon: skillIcon,
                                          dice: faces, flat: pending.baseFlat, bonusDice: pending.bonusDice,
                                          modifiers: pending.bonuses, amount: healed,
                                          text: L("\(heroes[index].classDef.name) heals \(healed) HP.")))
            }

        case .enemyAttack(let enemyID, let targetHeroID, let skillID):
            if let index = heroes.firstIndex(where: { $0.id == targetHeroID }),
               let enemy = enemies.first(where: { $0.id == enemyID }) {
                // Buffs, weaken and vulnerable always apply; magic ignores every kind of block (game.md §7.4).
                let isMagic = pending.isMagic
                let block = damageReduction(forHeroAt: index)
                let vulnerable = heroes[index].vulnerableAmount
                var modifiers: [RollModifier] = []
                if enemy.damageBuff > 0 { modifiers.append(RollModifier(kind: .damageBuff, amount: enemy.damageBuff)) }
                if enemy.weakenAmount > 0 { modifiers.append(RollModifier(kind: .weaken, amount: -enemy.weakenAmount)) }
                if vulnerable > 0 { modifiers.append(RollModifier(kind: .vulnerable, amount: vulnerable)) }
                if block > 0 { modifiers.append(RollModifier(kind: isMagic ? .ignoredBlock : .block, amount: -block)) }
                let dealt = max(0, total + enemy.damageBuff - enemy.weakenAmount + vulnerable - (isMagic ? 0 : block))
                heroes[index].hp = max(0, heroes[index].hp - dealt)
                log.append(CombatLogEntry(kind: .damage, actor: .enemy(enemyID), target: .hero(targetHeroID),
                                          icon: enemy.def.skill(id: skillID)?.icon ?? "burst.fill",
                                          dice: faces, flat: pending.expr.flat, modifiers: modifiers, isMagic: isMagic, amount: dealt,
                                          text: isMagic
                                              ? L("\(enemy.def.name) deals \(dealt) magic damage to \(heroes[index].classDef.name).")
                                              : L("\(enemy.def.name) deals \(dealt) damage to \(heroes[index].classDef.name).")))
            }

        case .enemyHeal(let enemyID, let skillID, let targetIDs):
            let icon = enemySkill(enemyID: enemyID, skillID: skillID)?.icon ?? "cross.case.fill"
            for index in enemies.indices where enemies[index].isAlive && targetIDs.contains(enemies[index].id) {
                let before = enemies[index].hp
                enemies[index].hp = min(enemies[index].maxHP, enemies[index].hp + total)
                let healed = enemies[index].hp - before
                log.append(CombatLogEntry(kind: .heal, actor: .enemy(enemyID), target: .enemy(enemies[index].id), icon: icon,
                                          dice: faces, flat: pending.expr.flat, amount: healed,
                                          text: L("\(enemies[index].def.name) heals \(healed) HP.")))
            }
        }
    }

    /// Ends the current roll once every segment has been applied and shown.
    func finishRoll() {
        guard case .rolling = phase else { return }
        beginBeat(.roll, then: continuation)
    }

    /// Applies a whole roll at once (all segments), then finishes it.
    func diceSettled(faces: [Int]) {
        diceSettled(rolled: faces.map { DieFace(value: $0) })
    }

    func diceSettled(rolled: [DieFace]) {
        guard case .rolling(let pending) = phase else { return }
        let per = pending.expr.count
        for index in pending.segments.indices {
            let start = min(rolled.count, index * per)
            let end = min(rolled.count, start + per)
            applyRollSegment(index, rolled: Array(rolled[start..<end]))
        }
        finishRoll()
    }

    /// `roll + vulnerable − armor` (magic ignores armor), logged with every part of the sum.
    private func damageEnemy(at index: Int, total: Int, faces: [Int], pending: PendingRoll, icon: String) {
        let armor = enemies[index].armorAmount
        let extra = enemies[index].vulnerableAmount
        var modifiers = pending.bonuses
        if extra > 0 { modifiers.append(RollModifier(kind: .vulnerable, amount: extra)) }
        if armor > 0 { modifiers.append(RollModifier(kind: pending.isMagic ? .ignoredBlock : .armor, amount: -armor)) }
        let dealt = max(0, total + extra - (pending.isMagic ? 0 : armor))
        enemies[index].hp = max(0, enemies[index].hp - dealt)
        log.append(CombatLogEntry(kind: .damage, actor: .hero(activeHero.id), target: .enemy(enemies[index].id), icon: icon,
                                  dice: faces, flat: pending.baseFlat, bonusDice: pending.bonusDice, modifiers: modifiers,
                                  isMagic: pending.isMagic, amount: dealt,
                                  text: pending.isMagic
                                      ? L("\(activeHero.classDef.name) deals \(dealt) magic damage to \(enemies[index].def.name).")
                                      : L("\(activeHero.classDef.name) deals \(dealt) damage to \(enemies[index].def.name).")))
    }

    // MARK: Sequencing (game.md §7.6)

    private func beginBeat(_ beat: ResolutionBeat, then next: Continuation?) {
        continuation = next
        phase = .resolving(beat: beat, id: UUID())
    }

    /// Called by the fight screen once it has finished presenting the current beat.
    func continueAfterResolution(id: UUID) {
        guard case .resolving(_, let currentID) = phase, currentID == id else { return }
        let next = continuation
        continuation = nil
        // A skill's non-dice effects always land — even when its roll just won the fight — so
        // mana is never silently lost on a killing blow.
        if case .heroSkill(let skillID, let postRollEffects, let targetEnemyID) = next,
           let skill = activeHero.skill(id: skillID) {
            let before = log.count
            applyLandedStickers()
            applyInstantEffects(postRollEffects, skill: skill, targetEnemyID: targetEnemyID)
            if log.count > before {
                beginBeat(.effect, then: .heroActionDone)
                return
            }
        }
        if checkVictoryOrDefeat() { return }
        switch next {
        case .heroSkill, .heroActionDone:
            finishHeroAction()
        case .partyTurnReady:
            partyTurnReady()
        case .enemyQueue, .none:
            processEnemyQueue()
        }
    }

    // MARK: Applying effects

    /// The landed guard / spark / vigor stickers of the last hero roll, on the roller (game.md §8).
    private func applyLandedStickers() {
        let stickers = landedStickers
        landedStickers = []
        let index = activeHeroIndex
        let name = heroes[index].classDef.name
        for sticker in stickers {
            let actor = CombatActor.hero(heroes[index].id)
            switch sticker.type {
            case .crit:
                continue
            case .block:
                heroes[index].stickerBlock += sticker.amount
                log.append(CombatLogEntry(kind: .block, actor: actor, target: actor, icon: sticker.symbol, amount: sticker.amount,
                                          text: L("\(name) takes \(sticker.amount) less damage per hit until their next turn.")))
            case .resource:
                let gained = applyResource(toHeroAt: index, amount: sticker.amount)
                guard gained > 0 else { continue }
                log.append(CombatLogEntry(kind: .mana, actor: actor, icon: sticker.symbol, amount: gained,
                                          text: L("\(name) gains \(gained) \(heroes[index].classDef.resource?.name ?? L("resource")).")))
            case .heal:
                let healed = applyHeal(toHeroAt: index, amount: sticker.amount)
                guard healed > 0 else { continue }
                log.append(CombatLogEntry(kind: .heal, actor: actor, target: actor, icon: sticker.symbol, amount: healed,
                                          text: L("\(name) heals \(healed) HP.")))
            }
        }
    }

    @discardableResult
    private func applyHeal(toHeroAt index: Int, amount: Int) -> Int {
        guard heroes[index].isAlive else { return 0 }
        let before = heroes[index].hp
        heroes[index].hp = min(heroes[index].maxHP, heroes[index].hp + amount)
        return heroes[index].hp - before
    }

    private func applyResource(toHeroAt index: Int, amount: Int) -> Int {
        let before = heroes[index].resource
        heroes[index].resource = min(heroes[index].maxResource, heroes[index].resource + amount)
        return heroes[index].resource - before
    }

    // MARK: Turn end (game.md §7.5 and the round-decay rule)

    private func checkVictoryOrDefeat() -> Bool {
        if enemies.allSatisfy({ !$0.isAlive }) {
            goldReward = enemies.reduce(0) { $0 + $1.def.goldReward }
            actingEnemyID = nil
            phase = .victory
            return true
        }
        if heroes.allSatisfy({ !$0.isAlive }) {
            actingEnemyID = nil
            phase = .defeat
            return true
        }
        return false
    }

    /// The enemies' turn is over: timed effects wear down, cooldowns tick (except those started
    /// this round), and the next round's party turn begins (game.md §7.4).
    private func endRound() {
        for index in heroes.indices {
            for (skillID, turns) in heroes[index].cooldowns where !cooldownsSetThisRound.contains("\(heroes[index].id)|\(skillID)") {
                heroes[index].cooldowns[skillID] = turns > 1 ? turns - 1 : nil
            }
        }
        cooldownsSetThisRound = []
        tickTimedEffects()
        roundNumber += 1
        beginPartyTurn()
    }

    private func tickTimedEffects() {
        if var wall = shieldWall { shieldWall = wall.tick() ? wall : nil }
        for index in enemies.indices {
            if var armor = enemies[index].armor { enemies[index].armor = armor.tick() ? armor : nil }
            enemies[index].weakens = enemies[index].weakens.compactMap { status in var s = status; return s.tick() ? s : nil }
            enemies[index].vulnerables = enemies[index].vulnerables.compactMap { status in var s = status; return s.tick() ? s : nil }
            enemies[index].damageBuffs = enemies[index].damageBuffs.compactMap { status in var s = status; return s.tick() ? s : nil }
        }
        for index in heroes.indices {
            heroes[index].damageBuffs = heroes[index].damageBuffs.compactMap { status in var s = status; return s.tick() ? s : nil }
            heroes[index].weakens = heroes[index].weakens.compactMap { status in var s = status; return s.tick() ? s : nil }
            heroes[index].vulnerables = heroes[index].vulnerables.compactMap { status in var s = status; return s.tick() ? s : nil }
        }
    }
}

extension ItemDef {
    /// Potions heal a fixed amount — never a hidden roll (game.md §8).
    var fixedHealAmount: Int { effect.dice?.flat ?? effect.amount ?? 0 }
}
