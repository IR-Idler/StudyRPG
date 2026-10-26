import Testing
@testable import StudyRPG

/// The content sheets (`Content/*.json`) load, cross-reference correctly, and broken content fails
/// loudly naming the file (game.md §13, agents.md).
@MainActor
@Suite("Content files")
struct ContentTests {
    init() { Fixtures.isolateUserData() }

    @Test("All content files load and pass validation")
    func loads() throws {
        let content = try Fixtures.content()
        #expect(!content.classes.isEmpty)
        #expect(!content.enemies.isEmpty)
        #expect(!content.encounterPools.isEmpty)
    }

    @Test("Every encounter's enemies exist")
    func encounterReferences() throws {
        let content = try Fixtures.content()
        for pool in content.encounterPools {
            for encounter in pool.encounters {
                for id in encounter.enemyIds {
                    #expect(content.enemyDef(id: id) != nil, "encounters.json: unknown enemy \(id)")
                }
            }
        }
    }

    @Test("Every map fight type has encounters for every depth tier it can appear in")
    func encounterPoolsCoverTheMap() throws {
        let content = try Fixtures.content()
        let config = content.balance.map
        let tiers = Set((0..<config.rowCount).map { MapGenerator.depthTier(forRow: $0, rowCount: config.rowCount) })
        for type in [MapNodeType.fight, .elite] {
            for tier in tiers {
                #expect(content.encounterPools.contains { $0.nodeType == type && $0.depthTier == tier && !$0.encounters.isEmpty },
                        "no \(type.rawValue) encounters for depth tier \(tier)")
            }
        }
        #expect(content.encounterPools.contains { $0.nodeType == .boss && !$0.encounters.isEmpty } )
    }

    @Test("An encounter naming a missing enemy is rejected, blaming encounters.json")
    func rejectsUnknownEnemy() throws {
        var content = try Fixtures.content()
        content.encounterPools[0].encounters[0].enemyIds = ["no_such_enemy"]
        #expect(validationError(content)?.file == "encounters.json")
    }

    @Test("An enemy with no moves is rejected, blaming enemies.json")
    func rejectsEmptyMovePattern() throws {
        var content = try Fixtures.content()
        content.enemies[0].movePattern = []
        #expect(validationError(content)?.file == "enemies.json")
    }

    @Test("Broken monster skills, patterns and rules are rejected, blaming enemies.json")
    func rejectsBrokenMonsterSkills() throws {
        let content = try Fixtures.content()
        let strike = EnemySkillDef(id: "t_strike", name: "T", icon: "star", target: .heroes,
                                   effects: [EnemyEffectDef(type: .damage, dice: DiceExpr(count: 1, flat: 0))])
        var cases: [(String, (inout EnemyDef) -> Void)] = []
        cases.append(("unknown pattern skill", { $0.movePattern = ["no_such_skill"] }))
        cases.append(("unknown rule skill", { $0.rules = [EnemyRuleDef(skill: "no_such_skill")] }))
        cases.append(("reserved id", { var s = strike; s.id = EnemyDef.basicAttackID; $0.skills = [s] }))
        cases.append(("damage on a monster", { var s = strike; s.target = .selfEnemy; $0.skills = [s]; $0.movePattern = [s.id] }))
        cases.append(("armor on a hero", { var s = strike; s.effects = [EnemyEffectDef(type: .armor, amount: 1, rounds: 1)]; $0.skills = [s] }))
        cases.append(("two rolls", { var s = strike; s.effects += s.effects; $0.skills = [s] }))
        cases.append(("timed effect without rounds", { var s = strike; s.effects = [EnemyEffectDef(type: .weaken, amount: 1)]; $0.skills = [s] }))
        cases.append(("HP share above 1", { $0.rules = [EnemyRuleDef(skill: EnemyDef.basicAttackID, when: EnemyRuleConditions(selfHPBelow: 1.5))] }))
        for (name, change) in cases {
            var broken = content
            change(&broken.enemies[0])
            #expect(validationError(broken)?.file == "enemies.json", "\(name) was accepted")
        }
    }

    @Test("Broken monster hit dice are rejected, blaming enemies.json")
    func rejectsBrokenHitDice() throws {
        let content = try Fixtures.content()
        var brokenCount = content
        brokenCount.enemies[0].hpDice = DiceExpr(count: 0, flat: 2, sides: 6)
        #expect(validationError(brokenCount)?.file == "enemies.json")

        var brokenSides = content
        brokenSides.enemies[0].hpDice = DiceExpr(count: 1, flat: 2, sides: 1)
        #expect(validationError(brokenSides)?.file == "enemies.json")

        var brokenFlat = content
        brokenFlat.enemies[0].hpDice = DiceExpr(count: 1, flat: -1, sides: 6)
        #expect(validationError(brokenFlat)?.file == "enemies.json")
    }

    @Test("Every monster has a move to play at the start of a fight")
    func everyMonsterHasAMove() throws {
        let content = try Fixtures.content()
        for enemy in content.enemies {
            let engine = CombatEngine.fixture(content, enemies: [enemy])
            #expect(engine.plannedMove(for: engine.enemies[0]) != nil, "\(enemy.id) has nothing to do")
        }
    }

    @Test("A class starting with an unknown skill is rejected, blaming classes.json")
    func rejectsUnknownStartingSkill() throws {
        var content = try Fixtures.content()
        content.classes[0].startingSkills = ["no_such_skill"]
        #expect(validationError(content)?.file == "classes.json")
    }

    @Test("Broken skill upgrades are rejected, blaming classes.json")
    func rejectsBrokenUpgrades() throws {
        let content = try Fixtures.content()
        let resourceless = try #require(content.classes.firstIndex { $0.resource == nil })
        var costly = content
        costly.classes[resourceless].skills[0].upgrade = SkillUpgradeDef(cost: 2)
        #expect(validationError(costly)?.file == "classes.json", "a mana cost on a class without mana")
        var empty = content
        empty.classes[0].skills[0].upgrade = SkillUpgradeDef()
        #expect(validationError(empty)?.file == "classes.json", "an upgrade that changes nothing")
        var noPoints = content
        noPoints.classes[0].skills[0].upgrade = SkillUpgradeDef(actionPoints: 0)
        #expect(validationError(noPoints)?.file == "classes.json")
    }

    @Test("Every skill can be upgraded, and the upgrade changes it")
    func everySkillUpgrades() throws {
        for skill in try Fixtures.content().classes.flatMap(\.skills) {
            #expect(skill.upgrade != nil, "\(skill.id) has no upgrade")
            var upgraded = skill.upgraded()
            upgraded.isUpgraded = nil
            upgraded.upgrade = skill.upgrade
            #expect(upgraded != skill, "\(skill.id)'s upgrade changes nothing")
        }
    }

    @Test("Every skill has a painted element; without one it's derived from its main effect")
    func skillArtElements() throws {
        let content = try Fixtures.content()
        let skills = content.classes.flatMap(\.skills)
        for skill in skills {
            var bare = skill
            bare.element = nil
            let main = bare.diceEffect ?? bare.effects.first
            let derived = bare.artElement
            switch main?.type {
            case .damage: #expect(derived == (main?.isMagic == true ? .arcane : .steel), "\(skill.id)")
            case .heal: #expect(derived == .nature, "\(skill.id)")
            case .block: #expect(derived == .guard, "\(skill.id)")
            case .damageBuff: #expect(derived == .war, "\(skill.id)")
            case .stun, .weaken, .vulnerable: #expect(derived == .shadow, "\(skill.id)")
            case .resource, .none: #expect(derived == .mana, "\(skill.id)")
            }
            // An authored element always wins over the derived one.
            for element in SkillElement.allCases {
                bare.element = element
                #expect(bare.artElement == element)
            }
        }
    }

    @Test("Every skill names a painted motif that the emblem can draw")
    func skillArtMotifs() throws {
        let content = try Fixtures.content()
        for skill in content.classes.flatMap(\.skills) {
            #expect(SkillMotif.canDraw(skill.art), "\(skill.id): art \(skill.art ?? "nil")")
        }
        #expect(!SkillMotif.canDraw(nil))
        #expect(!SkillMotif.canDraw("no_such_motif"))
    }

    private func validationError(_ content: GameContent) -> ContentError? {
        do {
            try ContentLoader.validate(content)
            return nil
        } catch let error as ContentError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
    }
}
