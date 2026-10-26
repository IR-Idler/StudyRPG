import Foundation
import Testing
@testable import StudyRPG

/// Every skill effect type, mana, cooldowns, timed-effect expiry, relics, gear and enemy moves
/// (game.md §5-§7). Skills are found by what they do, so new or rebalanced skills are covered too.
@MainActor
@Suite("Skill effects, relics, gear and enemy moves")
struct SkillEffectTests {
    init() { Fixtures.isolateUserData() }

    // MARK: Helpers

    /// The first skill (and its class) matching `predicate`.
    private func skill(_ content: GameContent, _ what: String, where predicate: (SkillDef) -> Bool) throws -> (HeroClassDef, SkillDef) {
        for heroClass in content.classes {
            if let skill = heroClass.skills.first(where: predicate) { return (heroClass, skill) }
        }
        throw TestSkip(reason: "content has no skill that \(what)")
    }

    private struct TestSkip: Error { var reason: String }

    /// A fight where `lead` acts first. `hp` overrides starting HP by class id; heroes start with
    /// full resource unless `resource` overrides it.
    private func fight(_ content: GameContent, lead: String, enemies: [EnemyDef], hp: [String: Int] = [:],
                       resource: [String: Int] = [:], gear: [GearDef] = [], relics: [RelicDef] = []) -> CombatEngine {
        let ordered = content.classes.sorted { a, _ in a.id == lead }
        let heroes = ordered.map { heroClass -> HeroState in
            var hero = HeroState(classDef: heroClass, hp: hp[heroClass.id] ?? heroClass.maxHP,
                                 resource: resource[heroClass.id] ?? heroClass.resource?.max ?? 0)
            if heroClass.id == lead { hero.gear = gear }
            return hero
        }
        return CombatEngine(heroes: heroes, enemyDefs: enemies, balance: content.balance,
                            flashcards: FlashcardSession(decks: [], statsStore: CardStatsStore(), balance: content.balance),
                            relics: relics, rollEnemyHP: false)
    }

    /// The toughest enemy, with HP raised so long tests (2 action points per hero) never kill it.
    private func tank(_ content: GameContent) throws -> EnemyDef {
        var tank = try #require(content.enemies.max { $0.baseHP < $1.baseHP })
        tank.baseHP = 999
        return tank
    }

    private func attacker(_ content: GameContent) throws -> EnemyDef {
        var enemy = try #require(content.enemies
            .filter { $0.movePattern.first == EnemyDef.basicAttackID && !$0.basicAttackIsMagic }
            .min { $0.attackEvery < $1.attackEvery })
        enemy.rules = nil
        return enemy
    }

    private func amount(_ skill: SkillDef, _ type: SkillEffectType) -> Int {
        skill.effects.first { $0.type == type }?.amount ?? 0
    }

    private func rounds(_ skill: SkillDef, _ type: SkillEffectType) -> Int {
        skill.effects.first { $0.type == type }?.rounds ?? 0
    }

    /// Plays basic attacks (weak dice both ways) for `turns` hero turns.
    /// Plays `turns` whole hero turns: each spends the selected hero's action points on basic attacks.
    private func pass(_ engine: CombatEngine, turns: Int) throws {
        for _ in 0..<turns where engine.phase == .choosingAction {
            try finishTurn(engine, of: engine.activeHero.id)
        }
    }

    /// Spends what's left of this hero's action points this round on basic attacks (no-op once
    /// another hero is selected or the round has moved on).
    private func finishTurn(_ engine: CombatEngine, of heroID: String) throws {
        let round = engine.roundNumber
        for _ in 0..<10 where engine.phase == .choosingAction && engine.activeHero.id == heroID && engine.roundNumber == round {
            guard let attack = engine.basicAttack, engine.isSkillUsable(attack) else { return }
            engine.playTurn(attack, target: engine.livingEnemies.first, face: 1, enemyFace: 1)
        }
    }

    // MARK: Stun, weaken, vulnerable (game.md §7.3, §7.4)

    @Test("Stun: a stunned enemy visibly sleeps through its next turn")
    func stun() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "stuns") { $0.effects.contains { $0.type == .stun } && $0.cost == nil }
        let engine = fight(content, lead: heroClass.id, enemies: [try tank(content)])
        engine.playTurn(skill, target: engine.enemies[0], face: 1, enemyFace: 1)
        #expect(engine.enemies[0].stunTicks == amount(skill, .stun), "nothing wears off during the party's turn")
        let start = engine.log.count
        let hits = engine.playRound()
        #expect(hits.isEmpty, "a stunned enemy attacked")
        #expect(engine.enemies[0].chargeCounter == 0, "its charge didn't tick")
        #expect(engine.enemies[0].stunTicks == amount(skill, .stun) - 1)
        #expect(engine.log[start...].contains { $0.kind == .stun && $0.actor == .enemy(engine.enemies[0].id) }, "the skipped turn is shown")
    }

    @Test("Weaken: the weakened enemy's hits deal that much less")
    func weaken() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "weakens") { $0.effects.contains { $0.type == .weaken } }
        let engine = fight(content, lead: heroClass.id, enemies: [try attacker(content)])
        var hits = engine.playTurn(skill, target: engine.enemies[0], face: 1, enemyFace: 6)
        for _ in 0..<6 where hits.isEmpty && engine.phase == .choosingAction {
            hits = engine.playTurn(try #require(engine.basicAttack), target: engine.enemies[0], face: 1, enemyFace: 6)
        }
        try #require(!hits.isEmpty, "the enemy never attacked while weakened")
        for hit in hits {
            #expect(hit.dealt == max(0, hit.rolled - amount(skill, .weaken) - (hit.isMagic ? 0 : hit.block)))
        }
    }

    @Test("Vulnerable: the enemy takes that much more from every hit")
    func vulnerable() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "applies vulnerable") { $0.effects.contains { $0.type == .vulnerable } }
        let engine = fight(content, lead: heroClass.id, enemies: [try tank(content)])
        engine.playTurn(skill, target: engine.enemies[0], face: 1, enemyFace: 1)

        let attack = try #require(engine.basicAttack)
        let dice = try #require(attack.diceEffect?.dice)
        let total = 2 * dice.count + dice.flat + engine.rollBonus(for: attack, heroAt: engine.activeHeroIndex)
        let start = engine.log.count
        engine.playTurn(attack, target: engine.enemies[0], face: 2, enemyFace: 1)
        let hit = try #require(engine.log[start...].first { $0.kind == .damage && $0.target == .enemy(engine.enemies[0].id) })
        #expect(hit.amount == total + amount(skill, .vulnerable))
    }

    // MARK: Buffs, block and timed-effect expiry (game.md §7.4)

    @Test("Damage buffs add to damage rolls, then wear off after their rounds")
    func damageBuff() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "buffs damage") { $0.effects.contains { $0.type == .damageBuff } }
        let engine = fight(content, lead: heroClass.id, enemies: [try tank(content)])
        let attack = try #require(heroClass.skills.first { $0.diceEffect?.type == .damage })
        let before = engine.rollBonus(for: attack, heroAt: 0)

        let lead = engine.activeHero.id
        engine.playTurn(skill, target: engine.enemies[0], face: 1, enemyFace: 1)
        #expect(engine.rollBonus(for: attack, heroAt: 0) == before + amount(skill, .damageBuff))
        try finishTurn(engine, of: lead)

        // Cast in round 1; lasts `rounds` full rounds after it, gone after the next one.
        try pass(engine, turns: 2 * rounds(skill, .damageBuff) - 1)
        #expect(engine.rollBonus(for: attack, heroAt: 0) == before + amount(skill, .damageBuff), "wore off too early")
        try pass(engine, turns: 2)
        #expect(engine.rollBonus(for: attack, heroAt: 0) == before, "never wore off")
    }

    @Test("Party block lasts its rounds and can't be re-cast while active")
    func blockExpiry() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "blocks") { $0.effects.contains { $0.type == .block } }
        let engine = fight(content, lead: heroClass.id, enemies: [try tank(content)])
        let lead = engine.activeHero.id
        engine.playTurn(skill, face: 1, enemyFace: 1)
        #expect(engine.shieldWallBlock == amount(skill, .block))
        try finishTurn(engine, of: lead)

        try pass(engine, turns: 1)
        if skill.requiresInactive == "block" {
            #expect(engine.activeHero.classDef.id == heroClass.id)
            #expect(!engine.isSkillUsable(skill), "re-cast while still active")
        }
        try pass(engine, turns: 2 * rounds(skill, .block) - 2)
        #expect(engine.shieldWallBlock > 0, "wore off too early")
        try pass(engine, turns: 2)
        #expect(engine.shieldWallBlock == 0, "never wore off")
    }

    // MARK: Healing, area damage (game.md §5)

    @Test("Healing skills heal their targets by the roll, capped at max HP, never reviving")
    func heal() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "heals") { $0.diceEffect?.type == .heal }
        let other = try #require(content.classes.first { $0.id != heroClass.id })
        let engine = fight(content, lead: heroClass.id, enemies: [try tank(content)], hp: [heroClass.id: 5, other.id: 0])
        let dice = try #require(skill.diceEffect?.dice)
        let healed = 2 * dice.count + dice.flat + engine.rollBonus(for: skill, heroAt: 0)

        let start = engine.log.count
        engine.playTurn(skill, target: engine.enemies[0], face: 2, enemyFace: 1)

        // Read from the log: the enemies' turn may hit afterwards.
        let heals = engine.log[start...].filter { $0.kind == .heal && $0.actor == .hero(engine.heroes[0].id) }
        #expect(heals.first { $0.target == .hero(engine.heroes[0].id) }?.amount == min(engine.heroes[0].maxHP - 5, healed))
        #expect(!heals.contains { $0.target == .hero(engine.heroes[1].id) && $0.amount > 0 }, "healing revived a fallen hero")
        #expect(engine.heroes[1].hp == 0, "healing revived a fallen hero")
    }

    @Test("Area damage hits every living enemy with the same roll")
    func areaDamage() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "hits all enemies") { $0.target == .allEnemies && $0.diceEffect?.type == .damage }
        let enemy = try tank(content)
        let engine = fight(content, lead: heroClass.id, enemies: [enemy, enemy])
        let dice = try #require(skill.diceEffect?.dice)
        let total = 3 * dice.count + dice.flat + engine.rollBonus(for: skill, heroAt: 0)
        engine.playTurn(skill, face: 3, enemyFace: 1)
        #expect(engine.enemies.map(\.hp) == [enemy.baseHP - total, enemy.baseHP - total])
    }

    // MARK: Mana & cooldowns (game.md §5, §7.2)

    @Test("A skill's mana cost is paid on a right answer only, and blocks it when short")
    func manaCost() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "costs mana") {
            ($0.cost ?? 0) > 0 && !$0.effects.contains { $0.type == .resource } && $0.target != .ally
        }
        let max = try #require(heroClass.resource?.max)
        let cost = try #require(skill.cost)

        let paid = fight(content, lead: heroClass.id, enemies: [try tank(content)])
        paid.playTurn(skill, target: paid.enemies[0], face: 1, enemyFace: 1)
        #expect(paid.heroes[0].resource == max - cost)

        let fizzled = fight(content, lead: heroClass.id, enemies: [try tank(content)])
        fizzled.playTurn(skill, target: fizzled.enemies[0], correct: false, face: 1, enemyFace: 1)
        #expect(fizzled.heroes[0].resource == max, "a fizzled skill cost mana")

        let broke = fight(content, lead: heroClass.id, enemies: [try tank(content)], resource: [heroClass.id: cost - 1])
        #expect(!broke.isSkillUsable(skill))
    }

    @Test("Mana-gaining hits add mana every turn, capped at max, including the killing blow")
    func manaGain() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "gains mana on a hit") {
            $0.effects.contains { $0.type == .resource } && $0.diceEffect?.type == .damage && $0.cost == nil && ($0.cooldown ?? 0) == 0
        }
        let other = try #require(content.classes.first { $0.id != heroClass.id })
        let max = try #require(heroClass.resource?.max)
        let gain = amount(skill, .resource)
        let weakest = try #require(content.enemies.min { $0.baseHP < $1.baseHP })
        let engine = fight(content, lead: heroClass.id, enemies: [weakest], hp: [other.id: 0], resource: [heroClass.id: 0])
        var turns = 0
        while engine.phase == .choosingAction && turns < 40 {
            engine.playTurn(skill, target: engine.enemies[0], face: 6, enemyFace: 1)
            turns += 1
            if engine.phase == .choosingAction { #expect(engine.heroes[0].resource == min(max, turns * gain)) }
        }
        #expect(engine.phase == .victory)
        #expect(engine.heroes[0].resource == min(max, turns * gain), "the killing blow's mana was lost")
    }

    @Test("Cooldown N: unusable for the hero's next N turns; a fizzled skill doesn't go on cooldown")
    func cooldowns() throws {
        let content = try Fixtures.content()
        let (heroClass, skill) = try skill(content, "has a cooldown") { ($0.cooldown ?? 0) > 0 && $0.cost == nil && $0.target != .ally }
        let cooldown = try #require(skill.cooldown)

        let engine = fight(content, lead: heroClass.id, enemies: [try tank(content)])
        let lead = engine.activeHero.id
        engine.playTurn(skill, target: engine.enemies[0], face: 1, enemyFace: 1)
        try finishTurn(engine, of: lead)
        for ownTurn in 1...cooldown {
            try pass(engine, turns: 1)
            #expect(engine.activeHero.classDef.id == heroClass.id)
            #expect(!engine.isSkillUsable(skill), "usable on own turn \(ownTurn) of \(cooldown)")
            if ownTurn < cooldown { try pass(engine, turns: 1) }
        }
        try pass(engine, turns: 2)
        #expect(engine.isSkillUsable(skill), "still on cooldown after \(cooldown) turns")

        let fizzled = fight(content, lead: heroClass.id, enemies: [try tank(content)])
        fizzled.playTurn(skill, target: fizzled.enemies[0], correct: false, face: 1, enemyFace: 1)
        try finishTurn(fizzled, of: lead)
        try pass(fizzled, turns: 1)
        #expect(fizzled.isSkillUsable(skill), "a fizzled skill went on cooldown")
    }

    // MARK: Relics (game.md §6)

    @Test("Relics: damage reduction blocks every hero, roll bonus adds to every roll, max HP raises both heroes")
    func relics() throws {
        let content = try Fixtures.content()
        let engine = fight(content, lead: content.classes[0].id, enemies: [try tank(content)], relics: content.relics)
        let reduction = content.relics.filter { $0.effect.type == .damageReduction }.reduce(0) { $0 + $1.effect.amount }
        let bonus = content.relics.filter { $0.effect.type == .rollBonus }.reduce(0) { $0 + $1.effect.amount }
        for index in engine.heroes.indices {
            #expect(engine.damageReduction(forHeroAt: index) == reduction)
            for skill in engine.heroes[index].classDef.skills where skill.diceEffect != nil {
                #expect(engine.rollBonus(for: skill, heroAt: index) == bonus, "\(skill.id)")
            }
        }

        if let amulet = content.relics.first(where: { $0.effect.type == .maxHPBonus }) {
            let run = RunState.fixture(content)
            let maxHP = run.heroes.map(\.maxHP), hp = run.heroes.map(\.hp)
            run.gainRelic(amulet)
            #expect(run.heroes.map(\.maxHP) == maxHP.map { $0 + amulet.effect.amount })
            #expect(run.heroes.map(\.hp) == hp.map { $0 + amulet.effect.amount })
        }
    }

    // MARK: Gear in fights (game.md §6)

    @Test("Gear: start mana, first-roll dice (first roll only), heal bonus on heals only, damage bonus on the wearer only")
    func gearInFights() throws {
        let content = try Fixtures.content()
        func gear(_ type: GearEffectType) -> GearDef? { content.gear.first { $0.effects.contains { $0.type == type } } }
        func total(_ gear: GearDef, _ type: GearEffectType) -> Int { gear.effects.filter { $0.type == type }.reduce(0) { $0 + $1.amount } }

        if let crystal = gear(.startResource) {
            let wearer = try #require(content.classes.first { ($0.resource?.max ?? 0) > 0 && (crystal.classId == nil || crystal.classId == $0.id) })
            let engine = fight(content, lead: wearer.id, enemies: [try tank(content)], resource: [wearer.id: 0], gear: [crystal])
            #expect(engine.heroes[0].resource == min(wearer.resource?.max ?? 0, total(crystal, .startResource)))
        }

        if let stone = gear(.firstRollBonusDice) {
            let wearer = try #require(content.classes.first { stone.classId == nil || stone.classId == $0.id })
            let engine = fight(content, lead: wearer.id, enemies: [try tank(content)], gear: [stone])
            let attack = try #require(engine.basicAttack)
            let dice = try #require(attack.diceEffect?.dice?.count)
            #expect(engine.heroes[0].bonusDiceNextTurn == total(stone, .firstRollBonusDice))
            engine.selectSkill(attack)
            engine.selectTarget(engine.enemies[0].id)
            if case .awaitingAnswer(let id, let target) = engine.phase {
                engine.proceedAfterAnswer(skillID: id, targetEnemyID: target, correct: true)
            }
            if case .rolling(let roll) = engine.phase { #expect(roll.expr.count == dice + total(stone, .firstRollBonusDice)) }
            _ = engine.settle(face: 1, enemyFace: 1)
            #expect(engine.heroes[0].bonusDiceNextTurn == 0, "first-roll dice carried past the first roll")
        }

        if let charm = gear(.healBonus) {
            let (healer, heal) = try skill(content, "heals") { $0.diceEffect?.type == .heal }
            if charm.classId == nil || charm.classId == healer.id {
                let engine = fight(content, lead: healer.id, enemies: [try tank(content)], gear: [charm])
                #expect(engine.rollBonus(for: heal, heroAt: 0) == total(charm, .healBonus))
                if let attack = healer.skills.first(where: { $0.diceEffect?.type == .damage }) {
                    #expect(engine.rollBonus(for: attack, heroAt: 0) == 0, "heal bonus boosted damage")
                }
            }
        }

        if let weapon = gear(.damageBonus) {
            let wearer = try #require(content.classes.first { weapon.classId == nil || weapon.classId == $0.id })
            let engine = fight(content, lead: wearer.id, enemies: [try tank(content)], gear: [weapon])
            let mine = try #require(wearer.skills.first { $0.diceEffect?.type == .damage })
            let theirs = try #require(engine.heroes[1].classDef.skills.first { $0.diceEffect?.type == .damage })
            #expect(engine.rollBonus(for: mine, heroAt: 0) == total(weapon, .damageBonus))
            #expect(engine.rollBonus(for: theirs, heroAt: 1) == 0, "gear helped someone who isn't wearing it")
        }
    }

    // MARK: Enemy armor & heal moves (game.md §7.3)

    @Test("Enemy armor and heal skills: armor gives its amount, heals stay within the roll and max HP")
    func enemyArmorAndHeal() throws {
        let content = try Fixtures.content()
        func selfEffect(_ enemy: EnemyDef, _ type: EnemyEffectType) -> EnemyEffectDef? {
            enemy.patternSkills.lazy.compactMap { skill in skill.effects.first { $0.type == type && skill.target(of: $0) == .selfEnemy } }.first
        }
        var enemy = try #require(content.enemies.filter { selfEffect($0, .armor) != nil && selfEffect($0, .heal) != nil }
            .max { $0.baseHP < $1.baseHP }, "content has no enemy with self armor and heal moves")
        enemy.rules = nil
        let armorAmount = selfEffect(enemy, .armor)?.amount
        let healDice = selfEffect(enemy, .heal)?.dice
        let engine = fight(content, lead: content.classes[0].id, enemies: [enemy])
        var sawArmor = false, sawHeal = false
        for _ in 0..<60 where engine.phase == .choosingAction && !(sawArmor && sawHeal) {
            try pass(engine, turns: 1)
            if engine.enemies[0].armorAmount > 0 {
                #expect(engine.enemies[0].armorAmount == armorAmount)
                sawArmor = true
            }
            if let heal = engine.log.last(where: { $0.kind == .heal && $0.actor == .enemy(engine.enemies[0].id) }) {
                let dice = healDice ?? DiceExpr(count: 1, flat: 0)
                #expect(heal.amount <= dice.count + dice.flat, "healed more than the roll (all 1s)")
                #expect(engine.enemies[0].hp <= enemy.baseHP)
                sawHeal = true
            }
        }
        #expect(sawArmor && sawHeal, "armor or heal never happened")
    }
}
