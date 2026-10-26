import Foundation
import Testing
@testable import StudyRPG

/// Monster skills and rules (game.md §7.3). The monsters here are a real content enemy with its
/// skills, pattern and rules replaced by test-only ones that act every enemy turn, so the
/// rules are tested without depending on any id or stat in enemies.json.
@MainActor
@Suite("Monster skills")
struct EnemySkillTests {
    init() { Fixtures.isolateUserData() }

    // MARK: Building test monsters

    /// A skill whose `icon` is its id, so the combat log tells which one was played.
    private func skill(_ id: String, _ target: EnemySkillTarget, _ effects: EnemyEffectDef...) -> EnemySkillDef {
        EnemySkillDef(id: id, name: id, icon: id, target: target, effects: effects)
    }

    private func armor(_ amount: Int = 1, rounds: Int = 2) -> EnemyEffectDef {
        EnemyEffectDef(type: .armor, amount: amount, rounds: rounds)
    }

    private func monster(_ content: GameContent, skills: [EnemySkillDef], pattern: [String],
                         rules: [EnemyRuleDef] = [], attackEvery: Int = 1) throws -> EnemyDef {
        var enemy = try #require(content.enemies.max { $0.baseHP < $1.baseHP })
        enemy.id = "test-monster-\(UUID().uuidString)"
        enemy.skills = skills
        enemy.movePattern = pattern
        enemy.rules = rules
        enemy.attackEvery = attackEvery
        enemy.attackDice = DiceExpr(count: 1, flat: 0)
        return enemy
    }

    /// Plays one round (every hero's basic attack on the first living enemy, then the enemies'
    /// turn) and returns the ids of the skills enemies played during it, from the log.
    @discardableResult
    private func turn(_ engine: CombatEngine, face: Int = 1) throws -> [String] {
        let start = engine.log.count
        engine.playRound(face: face, enemyFace: 1)
        var played: [String] = []
        for entry in engine.log[start...] {
            if case .enemy = entry.actor, played.last != entry.icon { played.append(entry.icon) }
        }
        return played
    }

    // MARK: Pattern and rules

    @Test("With no rule firing, the pattern plays in order and loops")
    func patternLoops() throws {
        let content = try Fixtures.content()
        let a = skill("a", .selfEnemy, armor()), b = skill("b", .selfEnemy, armor(2))
        let engine = CombatEngine.fixture(content, enemies: [try monster(content, skills: [a, b], pattern: ["a", "b"])])
        var played: [String] = []
        for _ in 0..<4 { played += try turn(engine) }
        #expect(played == ["a", "b", "a", "b"])
    }

    @Test("A rule replaces the pattern's move without advancing it")
    func ruleOverridesPattern() throws {
        let content = try Fixtures.content()
        let guardUp = skill("guard", .selfEnemy, armor())
        let mend = skill("mend", .selfEnemy, EnemyEffectDef(type: .heal, dice: DiceExpr(count: 1, flat: 0)))
        let enemy = try monster(content, skills: [guardUp, mend], pattern: ["guard", EnemyDef.basicAttackID],
                                rules: [EnemyRuleDef(skill: "mend", when: EnemyRuleConditions(selfHPBelow: 0.999), maxUses: 1)])
        let engine = CombatEngine.fixture(content, enemies: [enemy])

        // The hero's hit hurts it before it acts, so the rule fires instead of "guard".
        #expect(try turn(engine, face: 6) == ["mend"])
        #expect(engine.enemies[0].moveIndex == 0, "a rule move must not advance the pattern")
        #expect(try turn(engine) == ["guard"], "the pattern resumes where it was")
    }

    @Test("Rule cooldown and maxUses limit how often a rule fires")
    func ruleLimits() throws {
        let content = try Fixtures.content()
        let a = skill("a", .selfEnemy, armor()), r = skill("r", .selfEnemy, armor(2))
        let cooling = CombatEngine.fixture(content, enemies: [
            try monster(content, skills: [a, r], pattern: ["a"], rules: [EnemyRuleDef(skill: "r", cooldown: 1)])
        ])
        var played: [String] = []
        for _ in 0..<4 { played += try turn(cooling) }
        #expect(played == ["r", "a", "r", "a"])

        let limited = CombatEngine.fixture(content, enemies: [
            try monster(content, skills: [a, r], pattern: ["a"], rules: [EnemyRuleDef(skill: "r", maxUses: 2)])
        ])
        played = []
        for _ in 0..<4 { played += try turn(limited) }
        #expect(played == ["r", "r", "a", "a"])
    }

    @Test("Ally-count and unlessActive conditions; the first rule that holds wins")
    func ruleConditions() throws {
        let content = try Fixtures.content()
        let a = skill("a", .selfEnemy, armor())
        let rally = skill("rally", .allies, EnemyEffectDef(type: .damageBuff, amount: 1, rounds: 3))
        let lone = skill("lone", .selfEnemy, armor(3))
        let rules = [
            EnemyRuleDef(skill: "lone", when: EnemyRuleConditions(maxAlliesAlive: 1)),
            EnemyRuleDef(skill: "rally", when: EnemyRuleConditions(minAlliesAlive: 2, unlessActive: true))
        ]
        let caster = try monster(content, skills: [a, rally, lone], pattern: ["a"], rules: rules)
        let idle = try monster(content, skills: [a], pattern: ["a"], attackEvery: 99)

        let pair = CombatEngine.fixture(content, enemies: [caster, idle])
        #expect(try turn(pair) == ["rally"])
        #expect(pair.enemies.allSatisfy { $0.damageBuff > 0 }, "an allies buff reaches every monster")
        #expect(try turn(pair) == ["a"], "unlessActive: the buff is still up, so the pattern plays")

        let alone = CombatEngine.fixture(content, enemies: [caster])
        #expect(try turn(alone) == ["lone"])
    }

    @Test("The nameplate's next move is exactly the move the monster plays")
    func telegraphMatchesAction() throws {
        let content = try Fixtures.content()
        let a = skill("a", .selfEnemy, armor()), b = skill("b", .heroes, EnemyEffectDef(type: .weaken, amount: 1, rounds: 1))
        let mend = skill("mend", .selfEnemy, EnemyEffectDef(type: .heal, dice: DiceExpr(count: 1, flat: 0)))
        let enemy = try monster(content, skills: [a, b, mend], pattern: ["a", "b", EnemyDef.basicAttackID],
                                rules: [EnemyRuleDef(skill: "mend", when: EnemyRuleConditions(selfHPBelow: 0.9), cooldown: 2)])
        let engine = CombatEngine.fixture(content, enemies: [enemy])
        for turnIndex in 0..<10 where engine.phase == .choosingAction {
            if turnIndex < 3 {
                // Hurt it first, so the rule's HP condition comes into play.
                try turn(engine, face: 6)
                continue
            }
            // Every hero answers wrong: that leaves the monster's HP alone, so nothing changes its
            // plan between the nameplate and its move at the end of the round.
            let round = engine.roundNumber
            var planned: String?
            var start = engine.log.count
            while engine.roundNumber == round, engine.phase == .choosingAction {
                let attack = try #require(engine.basicAttack)
                engine.selectSkill(attack)
                if case .choosingTarget = engine.phase { engine.selectTarget(engine.enemies[0].id) }
                guard case .awaitingAnswer(let id, let target) = engine.phase else { break }
                planned = engine.plannedMove(for: engine.enemies[0])?.skill.icon
                start = engine.log.count
                engine.proceedAfterAnswer(skillID: id, targetEnemyID: target, correct: false)
                _ = engine.settle(face: 1, enemyFace: 1, counterFirst: true)
            }
            // The last counterattack comes first; the scheduled move is the last thing it does.
            let moves = engine.log[start...].filter { $0.actor == .enemy(engine.enemies[0].id) }.map(\.icon)
            #expect(moves.last == planned, "planned \(planned ?? "nothing") but played \(moves)")
        }
        #expect(engine.enemies[0].ruleUses[0] ?? 0 > 0, "the rule never fired")
    }

    // MARK: Effects on heroes and monsters

    @Test("A stunned hero loses their next turn, and nobody ever acts while stunned")
    func heroStun() throws {
        let content = try Fixtures.content()
        let daze = skill("daze", .hero, EnemyEffectDef(type: .stun, amount: 1))
        let a = skill("a", .selfEnemy, armor())
        let engine = CombatEngine.fixture(content, enemies: [try monster(content, skills: [daze, a], pattern: ["daze", "a", "a", "a"])])
        // Round 1: the monster dazes a hero at the end, in the enemies' turn.
        try turn(engine)
        let dazeHit = try #require(engine.log.last { $0.kind == .stun && $0.icon == "daze" }, "daze stunned nobody")
        guard case .hero(let stunnedID)? = dazeHit.target else {
            Issue.record("daze didn't land on a hero")
            return
        }
        // Round 2: the stunned hero loses this party turn (shown in the log) and can't be selected.
        #expect(engine.log.contains { $0.kind == .stun && $0.actor == .hero(stunnedID) }, "the lost turn isn't shown")
        let stunned = try #require(engine.heroes.first { $0.id == stunnedID })
        #expect(stunned.actionPoints == 0)
        #expect(engine.activeHero.id != stunnedID, "a stunned hero got to act")
        engine.selectHero(stunnedID)
        #expect(engine.activeHero.id != stunnedID, "a stunned hero could be selected")
        // Round 3: back to normal.
        try turn(engine)
        #expect(engine.heroes.first { $0.id == stunnedID }?.actionPoints == content.balance.combat.actionPointsPerTurn)
    }

    @Test("Monster weaken lowers the hero's damage rolls")
    func heroWeaken() throws {
        let content = try Fixtures.content()
        let curse = skill("curse", .heroes, EnemyEffectDef(type: .weaken, amount: 2, rounds: 3))
        let engine = CombatEngine.fixture(content, enemies: [try monster(content, skills: [curse], pattern: ["curse"])])
        let hero = engine.activeHeroIndex
        let attack = try #require(engine.basicAttack)
        let before = engine.rollBonus(for: attack, heroAt: hero)
        try turn(engine)
        #expect(engine.rollBonus(for: attack, heroAt: hero) == before - 2)
    }

    @Test("Monster damage buff and hero vulnerable both add to every hit; per-effect targets work")
    func buffAndVulnerable() throws {
        let content = try Fixtures.content()
        let roar = skill("roar", .heroes,
                         EnemyEffectDef(type: .vulnerable, amount: 1, rounds: 3),
                         EnemyEffectDef(type: .damageBuff, amount: 2, rounds: 3, target: .selfEnemy))
        let engine = CombatEngine.fixture(content, enemies: [try monster(content, skills: [roar], pattern: ["roar", EnemyDef.basicAttackID])])
        try turn(engine)
        #expect(engine.enemies[0].damageBuff == 2)
        #expect(engine.heroes.allSatisfy { $0.vulnerableAmount == 1 })
        let hits = engine.playRound(face: 1, enemyFace: 6)
        #expect(!hits.isEmpty)
        for hit in hits {
            #expect(hit.dealt == max(0, hit.rolled + 2 + 1 - (hit.isMagic ? 0 : hit.block)))
        }
    }

    @Test("An ally heal goes to the most hurt monster")
    func allyHeal() throws {
        let content = try Fixtures.content()
        let a = skill("a", .selfEnemy, armor())
        let brew = skill("brew", .ally, EnemyEffectDef(type: .heal, dice: DiceExpr(count: 1, flat: 0)))
        let healer = try monster(content, skills: [brew], pattern: ["brew"], attackEvery: 2)
        let other = try monster(content, skills: [a], pattern: ["a"], attackEvery: 99)
        let engine = CombatEngine.fixture(content, enemies: [healer, other])
        let hurt = engine.enemies[1].id
        // Two rounds with one small hit each on the second monster; the healer acts at the end of
        // the second.
        for _ in 0..<2 {
            engine.playTurn(try #require(engine.basicAttack), target: engine.enemies[1], face: 1, enemyFace: 1)
            engine.endPartyTurn()
            engine.settle(face: 1, enemyFace: 1)
        }
        let heal = try #require(engine.log.last { $0.kind == .heal && $0.actor == .enemy(engine.enemies[0].id) })
        #expect(heal.target == .enemy(hurt))
    }
}
