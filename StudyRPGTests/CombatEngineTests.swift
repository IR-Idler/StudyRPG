import Foundation
import Testing
@testable import StudyRPG

/// Combat rules (game.md §7), driven through the real `CombatEngine` with fixed dice faces.
/// Enemies and skills are picked by behavior, so rebalancing the content doesn't break these.
@MainActor
@Suite("Combat engine")
struct CombatEngineTests {
    init() { Fixtures.isolateUserData() }

    // MARK: Picking content by behavior

    /// An enemy whose first move is its basic attack, of the requested damage type. Its rules are
    /// dropped so only the pattern plays.
    private func attacker(_ content: GameContent, magic: Bool) throws -> EnemyDef {
        var enemy = try #require(content.enemies
            .filter { $0.movePattern.first == EnemyDef.basicAttackID && $0.basicAttackIsMagic == magic }
            .min { $0.attackEvery < $1.attackEvery },
            "content has no \(magic ? "magic" : "physical") attacker")
        enemy.rules = nil
        return enemy
    }

    /// Damage the active hero's roll with `skill` totals when every die shows `face`.
    private func rolledTotal(_ engine: CombatEngine, _ skill: SkillDef, face: Int) throws -> Int {
        let dice = try #require(skill.diceEffect?.dice)
        return face * (dice.count + engine.activeHero.bonusDiceNextTurn) + dice.flat
            + engine.rollBonus(for: skill, heroAt: engine.activeHeroIndex)
    }

    /// The damage the active hero dealt during the last turn, from the combat log.
    private func heroDamageEntries(_ engine: CombatEngine, since start: Int) -> [CombatLogEntry] {
        engine.log[start...].filter {
            if case .hero = $0.actor, $0.kind == .damage { return true }
            return false
        }
    }

    // MARK: Hero damage (game.md §7.4)

    @Test("A hero's hit deals exactly dice + flat + bonuses to an unarmored enemy")
    func heroDamageEqualsRoll() throws {
        let content = try Fixtures.content()
        let tank = try #require(content.enemies.max { $0.baseHP < $1.baseHP })
        let engine = CombatEngine.fixture(content, enemies: [tank])
        let skill = try #require(engine.basicAttack)
        let expected = try rolledTotal(engine, skill, face: 3)

        engine.playTurn(skill, target: engine.enemies[0], face: 3, enemyFace: 1)

        #expect(engine.enemies[0].hp == tank.baseHP - expected)
    }

    @Test("Enemy armor reduces physical hits; magic hits ignore it")
    func magicIgnoresEnemyArmor() throws {
        let content = try Fixtures.content()
        let armored = try #require(content.enemies
            .filter { $0.patternSkills.contains { skill in skill.effects.contains { $0.type == .armor && skill.target(of: $0) == .selfEnemy } } }
            .max { $0.baseHP < $1.baseHP }, "content has no enemy with a self-armor move")
        let engine = CombatEngine.fixture(content, enemies: [armored])
        var sawMagic = false, sawPhysical = false

        for _ in 0..<40 where engine.phase == .choosingAction {
            let skill = try #require(engine.basicAttack)
            let armor = engine.enemies[0].armorAmount
            let total = try rolledTotal(engine, skill, face: 2)
            let start = engine.log.count
            engine.playTurn(skill, target: engine.enemies[0], face: 2, enemyFace: 1)
            guard armor > 0, let hit = heroDamageEntries(engine, since: start).first else { continue }
            if skill.dealsMagicDamage {
                #expect(hit.amount == total, "magic must ignore armor")
                sawMagic = true
            } else {
                #expect(hit.amount == max(0, total - armor), "physical must lose the armor")
                sawPhysical = true
            }
            if sawMagic && sawPhysical { break }
        }
        #expect(sawPhysical, "never saw a physical hit on armor")
        if content.classes.contains(where: { $0.skills.contains(where: \.dealsMagicDamage) }) {
            #expect(sawMagic, "never saw a magic hit on armor")
        }
    }

    // MARK: Party block (game.md §7.4)

    /// Plays turns (raising the party block whenever possible) until the first scheduled enemy hit.
    private func firstScheduledHits(against enemy: EnemyDef, content: GameContent) throws -> [EnemyHit] {
        let engine = CombatEngine.fixture(content, enemies: [enemy])
        for _ in 0..<20 where engine.phase == .choosingAction {
            let block = engine.activeHero.classDef.skills.first {
                $0.effects.contains { $0.type == .block } && engine.isSkillUsable($0)
            }
            let skill = try #require(block ?? engine.basicAttack)
            let hits = engine.playTurn(skill, target: engine.enemies[0], face: 1, enemyFace: 6)
            if !hits.isEmpty { return hits }
        }
        Issue.record("\(enemy.id) never attacked")
        return []
    }

    @Test("Party block reduces each physical enemy hit")
    func blockReducesPhysical() throws {
        let content = try Fixtures.content()
        let hits = try firstScheduledHits(against: attacker(content, magic: false), content: content)
        for hit in hits {
            #expect(hit.block > 0, "test setup: block should be up for this hit")
            #expect(!hit.isMagic)
            #expect(hit.dealt == max(0, hit.rolled - hit.block))
        }
    }

    @Test("Magic enemy hits ignore party block")
    func magicIgnoresBlock() throws {
        let content = try Fixtures.content()
        let hits = try firstScheduledHits(against: attacker(content, magic: true), content: content)
        for hit in hits {
            #expect(hit.block > 0, "test setup: block should be up for this hit")
            #expect(hit.isMagic)
            #expect(hit.dealt == hit.rolled)
        }
    }

    // MARK: Enemy charge & scheduled attacks (game.md §7.3)

    @Test("A scheduled attack hits every living hero with a separate roll", arguments: [false, true])
    func scheduledAttackHitsBothHeroes(fastMode: Bool) throws {
        let content = try Fixtures.content()
        let enemy = try attacker(content, magic: false)
        let engine = CombatEngine.fixture(content, enemies: [enemy], fastMode: fastMode)
        var hits: [EnemyHit] = []
        for round in 1...enemy.attackEvery {
            hits = engine.playRound()
            if round < enemy.attackEvery {
                #expect(hits.isEmpty, "attacked before its charge was full")
                #expect(engine.enemies[0].chargeCounter == round)
            }
        }
        #expect(Set(hits.map(\.heroID)) == Set(engine.heroes.map(\.id)))
        #expect(hits.count == engine.heroes.count)
        // Normal mode: one throw per hero. Fast mode: one throw for all, applied one after another.
        #expect(Set(hits.map(\.rollID)).count == (fastMode ? 1 : engine.heroes.count))
        #expect(engine.enemies[0].chargeCounter == 0, "charge resets after the move")
    }

    // MARK: Wrong answers (game.md §7.2)

    @Test("A wrong answer fizzles: the strongest enemy hits only the answering hero, with capped dice")
    func wrongAnswerCounterattack() throws {
        let content = try Fixtures.content()
        let candidates = content.enemies
        let weak = try #require(candidates.min { $0.attackDice.count * 7 + $0.attackDice.flat * 2 < $1.attackDice.count * 7 + $1.attackDice.flat * 2 })
        let strong = try #require(candidates.max { $0.attackDice.count * 7 + $0.attackDice.flat * 2 < $1.attackDice.count * 7 + $1.attackDice.flat * 2 })
        let engine = CombatEngine.fixture(content, enemies: [weak, strong])
        let answering = engine.activeHero.id
        let bystander = try #require(engine.heroes.first { $0.id != answering })
        let hpBefore = engine.enemies.map(\.hp)
        let strongest = try #require(engine.enemies.max { $0.threat < $1.threat })

        let skill = try #require(engine.basicAttack)
        let pointsBefore = engine.activeHero.actionPoints
        let spent = skill.actionPoints
        engine.selectSkill(skill)
        engine.selectTarget(engine.enemies[0].id)
        guard case .awaitingAnswer(let skillID, let targetID) = engine.phase else {
            Issue.record("not awaiting an answer: \(engine.phase)")
            return
        }
        engine.proceedAfterAnswer(skillID: skillID, targetEnemyID: targetID, correct: false)

        guard case .rolling(let counter) = engine.phase else {
            Issue.record("expected the counterattack roll, got \(engine.phase)")
            return
        }
        #expect(counter.isEnemyRoll)
        #expect(counter.expr.count <= max(1, content.balance.combat.wrongAnswerMaxDice))
        #expect(counter.segments.count == 1)
        if case .enemyAttack(let enemyID, let heroID, _) = counter.segments.first {
            #expect(enemyID == strongest.id, "the strongest enemy strikes back")
            #expect(heroID == answering, "only the answering hero is hit")
        }

        let hits = engine.settle(face: 1, enemyFace: 6, counterFirst: true)
        #expect(hits.filter(\.isCounter).count == min(content.balance.combat.wrongAnswerCounterattacks, 2))
        #expect(engine.heroes.first { $0.id == bystander.id }?.hp == bystander.hp)
        #expect(engine.enemies.map(\.hp) == hpBefore, "the skill fizzled, so no enemy took damage")
        #expect(engine.enemies.allSatisfy { $0.chargeCounter == 0 }, "a counterattack doesn't touch the charges")
        #expect(!engine.isEnemyTurn && engine.phase == .choosingAction, "the party's turn goes on")
        #expect(engine.heroes.first { $0.id == answering }?.actionPoints == pointsBefore - spent, "the fizzled skill still used its action points")
    }

    // MARK: Potions (game.md §6, §7.2)

    @Test("Drinking a potion costs the giver its action points; another hero can drink it")
    func potionsCostActionPoints() throws {
        let content = try Fixtures.content()
        let potion = try #require(content.items.first { $0.effect.type == .bonusDice && ($0.effect.amount ?? 0) > 0 })
        let enemy = try attacker(content, magic: false)
        let engine = CombatEngine(heroClasses: content.classes, enemyDefs: [enemy], balance: content.balance,
                                  decks: [], statsStore: CardStatsStore(), inventory: [potion])
        let giver = engine.activeHeroIndex
        let drinker = try #require(engine.heroes.indices.first { $0 != giver })
        let apBefore = engine.heroes[giver].actionPoints

        engine.usePotion(potion, targetHeroID: engine.heroes[drinker].id)
        _ = engine.settle(face: 1, enemyFace: 1)

        #expect(engine.inventory.isEmpty)
        #expect(engine.heroes[giver].actionPoints == apBefore - potion.actionPoints)
        #expect(engine.heroes[drinker].bonusDiceNextTurn == potion.effect.amount)
        #expect(engine.enemies[0].chargeCounter == 0, "still the party's turn")
        #expect(!engine.isEnemyTurn)

        // The bonus dice are spent by the drinker's next roll.
        engine.selectHero(engine.heroes[drinker].id)
        let skill = try #require(engine.basicAttack)
        let baseDice = try #require(skill.diceEffect?.dice?.count)
        engine.selectSkill(skill)
        engine.selectTarget(engine.enemies[0].id)
        guard case .awaitingAnswer(let skillID, let targetID) = engine.phase else { return }
        engine.proceedAfterAnswer(skillID: skillID, targetEnemyID: targetID, correct: true)
        guard case .rolling(let roll) = engine.phase else {
            Issue.record("expected the hero's roll")
            return
        }
        #expect(roll.expr.count == baseDice + (potion.effect.amount ?? 0))
    }

    @Test("A hero without action points can't act, drink or be selected; the next one is selected")
    func noActionPointsNoActions() throws {
        let content = try Fixtures.content()
        let potion = try #require(content.items.first { $0.actionPoints > 0 && $0.effect.type == .bonusDice })
        let tank = try #require(content.enemies.max { $0.baseHP < $1.baseHP })
        let engine = CombatEngine(heroClasses: content.classes, enemyDefs: [tank], balance: content.balance,
                                  decks: [], statsStore: CardStatsStore(), inventory: [potion])
        let first = engine.activeHero.id
        for _ in 0..<content.balance.combat.actionPointsPerTurn {
            engine.playTurn(try #require(engine.basicAttack), face: 1, enemyFace: 1)
        }
        #expect(engine.heroes.first { $0.id == first }?.actionPoints == 0)
        #expect(engine.activeHero.id != first, "the next hero with action points is selected")
        engine.selectHero(first)
        #expect(engine.activeHero.id != first, "a hero without action points can't be selected")
        #expect(engine.inventory.count == 1)
    }

    @Test("A skill costing more action points than the hero has left can't be used")
    func bigSkillsNeedTheirPoints() throws {
        let content = try Fixtures.content()
        let tank = try #require(content.enemies.max { $0.baseHP < $1.baseHP })
        let engine = CombatEngine.fixture(content, enemies: [tank])
        let max = engine.maxActionPoints(heroAt: engine.activeHeroIndex)
        let big = try #require(engine.activeHero.classDef.skills.first { $0.actionPoints == max && max > 1 && $0.cost == nil },
                               "needs a free skill costing every action point")
        #expect(engine.isSkillUsable(big))
        engine.playTurn(try #require(engine.basicAttack), face: 1, enemyFace: 1)
        #expect(engine.activeHero.actionPoints == max - 1)
        #expect(!engine.isSkillUsable(big))
    }

    // MARK: Victory (game.md §7.5)

    @Test("Killing every enemy wins the fight and pays their gold")
    func victoryPaysGold() throws {
        let content = try Fixtures.content()
        let enemy = try #require(content.enemies.min { $0.baseHP < $1.baseHP })
        let engine = CombatEngine.fixture(content, enemies: [enemy])
        for _ in 0..<40 where engine.phase == .choosingAction {
            engine.playTurn(try #require(engine.basicAttack), target: engine.enemies[0], face: 6, enemyFace: 1)
        }
        #expect(engine.phase == .victory)
        #expect(engine.goldReward == enemy.goldReward)
    }

    // MARK: Turn structure (game.md §7.2)

    @Test("A round: the heroes act in any order until their points are spent, then every enemy acts")
    func partyThenEnemies() throws {
        let content = try Fixtures.content()
        var tank = try #require(content.enemies.filter { $0.movePattern.first == EnemyDef.basicAttackID }.max { $0.baseHP < $1.baseHP })
        tank.rules = nil
        let engine = CombatEngine.fixture(content, enemies: [tank, tank])
        let perTurn = content.balance.combat.actionPointsPerTurn

        #expect(engine.roundNumber == 1)
        #expect(!engine.isEnemyTurn)
        #expect(engine.heroes.allSatisfy { $0.actionPoints == perTurn })

        // The second hero goes first — the order is the player's choice.
        let second = engine.heroes[1].id
        engine.selectHero(second)
        #expect(engine.activeHero.id == second)

        var heroActions = 0
        var hits: [EnemyHit] = []
        while engine.roundNumber == 1, let attack = engine.basicAttack, engine.phase == .choosingAction {
            #expect(engine.enemies.allSatisfy { $0.chargeCounter == 0 }, "enemies waited for the whole party")
            if heroActions == 0 { #expect(engine.activeHero.id == second) }
            hits += engine.playTurn(attack, face: 1, enemyFace: 1)
            heroActions += 1
        }
        #expect(heroActions == perTurn * engine.heroes.count, "every hero spent every point")
        // Every enemy that acts every enemy turn hit both heroes.
        let everyTurn = engine.enemies.filter { $0.def.attackEvery == 1 }
        #expect(hits.count == everyTurn.count * engine.heroes.count)
        // Round 2: points back, the party's turn again, starting with the first hero.
        #expect(engine.roundNumber == 2)
        #expect(!engine.isEnemyTurn)
        #expect(engine.heroes.allSatisfy { $0.actionPoints == perTurn })
        #expect(engine.activeHeroIndex == 0)
    }

    @Test("Ending the turn early skips to the enemies; unspent points are lost")
    func endTurnEarly() throws {
        let content = try Fixtures.content()
        let tank = try #require(content.enemies.max { $0.baseHP < $1.baseHP })
        let engine = CombatEngine.fixture(content, enemies: [tank])
        engine.endPartyTurn()
        #expect(engine.heroes.allSatisfy { $0.actionPoints == 0 } || engine.roundNumber == 2)
        _ = engine.settle(face: 1, enemyFace: 1)
        #expect(engine.roundNumber == 2)
        #expect(engine.phase == .choosingAction)
    }

    @Test("Every skill takes two taps: the skill, then a target — even party, self and all-enemy skills")
    func twoTapsAlways() throws {
        let content = try Fixtures.content()
        let tank = try #require(content.enemies.max { $0.baseHP < $1.baseHP })
        for heroClass in content.classes {
            for skill in heroClass.skills {
                // The skill's class acts first, with only that skill equipped and full resource.
                let heroes = content.classes.sorted { a, _ in a.id == heroClass.id }.map { cls -> HeroState in
                    var hero = HeroState(classDef: cls, hp: cls.maxHP, resource: cls.resource?.max ?? 0)
                    if cls.id == heroClass.id { hero.loadoutSkillIDs = [skill.id] }
                    return hero
                }
                let engine = CombatEngine(heroes: heroes, enemyDefs: [tank, tank], balance: content.balance,
                                          flashcards: FlashcardSession(decks: [], statsStore: CardStatsStore(), balance: content.balance))
                guard engine.isSkillUsable(skill) else { continue }
                engine.selectSkill(skill)
                switch skill.target {
                case .enemy, .allEnemies:
                    #expect(engine.phase == .choosingTarget(skillID: skill.id), "\(skill.id)")
                    #expect(engine.armedSkillHitsGroup == (skill.target == .allEnemies))
                    engine.selectTarget(engine.enemies[1].id)
                    #expect(engine.phase == .awaitingAnswer(skillID: skill.id, targetEnemyID: skill.target == .enemy ? engine.enemies[1].id : nil), "\(skill.id)")
                case .ally, .party, .selfHero:
                    #expect(engine.phase == .choosingAlly(skillID: skill.id), "\(skill.id)")
                    #expect(engine.armedSkillHitsGroup == (skill.target == .party))
                    let other = try #require(engine.heroes.first { $0.id != engine.activeHero.id })
                    #expect(engine.isValidTarget(heroID: other.id) == (skill.target != .selfHero), "\(skill.id)")
                    engine.selectAlly(engine.activeHero.id)
                    #expect(engine.phase == .awaitingAnswer(skillID: skill.id, targetEnemyID: nil), "\(skill.id)")
                }
            }
        }
    }

    // MARK: Hit dice (D&D-style randomized monster HP)

    @Test("Monster HP rolls according to hpDice when rollEnemyHP is true")
    func monsterHitDiceRolling() throws {
        let content = try Fixtures.content()
        let goblin = try #require(content.enemyDef(id: "goblin"))
        let dice = try #require(goblin.hpDice)
        let minHP = dice.count * 1 + dice.flat
        let maxHP = dice.count * dice.dieSides + dice.flat

        var sawDifferent = false
        var firstHP: Int? = nil

        for _ in 0..<30 {
            let engine = CombatEngine(
                heroClasses: Array(content.classes.prefix(2)),
                enemyDefs: [goblin],
                balance: content.balance,
                decks: [],
                statsStore: CardStatsStore(),
                rollEnemyHP: true
            )
            let enemy = engine.enemies[0]
            #expect(enemy.hp >= minHP && enemy.hp <= maxHP)
            #expect(enemy.maxHP == enemy.hp)
            if let first = firstHP {
                if first != enemy.hp { sawDifferent = true }
            } else {
                firstHP = enemy.hp
            }
        }
        #expect(sawDifferent, "Expected rolled HP to vary across 30 runs")
    }

    @Test("Monster HP equals baseHP when rollEnemyHP is false")
    func monsterDeterministicHPWhenDisabled() throws {
        let content = try Fixtures.content()
        let goblin = try #require(content.enemyDef(id: "goblin"))
        let engine = CombatEngine.fixture(content, enemies: [goblin])
        let enemy = engine.enemies[0]
        #expect(enemy.hp == goblin.baseHP)
        #expect(enemy.maxHP == goblin.baseHP)
    }

    @Test("DiceExpr.roll stays within bounds")
    func diceExprRollBounds() {
        let dice = DiceExpr(count: 3, flat: 4, sides: 6)
        for _ in 0..<100 {
            let roll = dice.roll()
            #expect(roll >= 7 && roll <= 22)
        }
    }
}
