import Foundation
import Testing
@testable import StudyRPG

/// Hero dice (game.md §8 "Hero dice", §5 "Levels"): every hero rolls their own six faces, landed
/// stickers add their effect, and level-up upgrades change faces. Stickers and upgrades are picked
/// by what they do, never by id.
@MainActor
@Suite("Hero dice")
struct DiceFaceTests {
    init() { Fixtures.isolateUserData() }

    private func sticker(_ type: StickerEffectType, _ content: GameContent) throws -> StickerDef {
        try #require(content.balance.dice.stickers.first { $0.type == type }, "balance.json has no \(type) sticker")
    }

    /// A run fight whose hero `heroIndex` has `die` (set through the real save format).
    private func fight(_ content: GameContent, heroIndex: Int = 0, die: [DieFace], change: (inout RunSnapshot.Hero) -> Void = { _ in }) throws -> CombatEngine {
        let run = try RunState.fixture(content).resumed {
            $0.heroes[heroIndex].die = die
            change(&$0.heroes[heroIndex])
        }
        let node = try run.node(.fight)
        return try #require(run.startFight(at: node.id)).engine
    }

    /// The hero uses their basic attack and answers correctly; returns the hero's pending roll.
    private func heroRoll(_ engine: CombatEngine, heroIndex: Int = 0) throws -> PendingRoll {
        engine.selectHero(engine.heroes[heroIndex].id)
        engine.selectSkill(try #require(engine.basicAttack))
        engine.selectTarget(try #require(engine.livingEnemies.first).id)
        guard case .awaitingAnswer(let skillID, let target) = engine.phase else {
            throw TestFailure("not awaiting an answer")
        }
        engine.proceedAfterAnswer(skillID: skillID, targetEnemyID: target, correct: true)
        guard case .rolling(let roll) = engine.phase else { throw TestFailure("expected the hero's roll") }
        return roll
    }

    /// Lands every die of the roll on `face` and plays the beats after it, up to the next decision.
    private func land(_ engine: CombatEngine, _ roll: PendingRoll, on face: DieFace) {
        engine.applyRollSegment(0, rolled: Array(repeating: face, count: roll.expr.count))
        engine.finishRoll()
        while case .resolving(_, let id) = engine.phase { engine.continueAfterResolution(id: id) }
    }

    struct TestFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    @Test("A fresh hero's die is the starting die, and hero rolls throw it")
    func heroRollsThrowTheirDie() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        #expect(run.heroes.allSatisfy { $0.die == content.balance.dice.startingDie })
        #expect(content.balance.dice.startingDie.count == DiceConfig.faceCount)

        var custom = content.balance.dice.startingDie
        custom[0].value = content.balance.dice.maxFaceValue
        let engine = try fight(content, die: custom)
        let roll = try heroRoll(engine)
        #expect(roll.heroDie == custom)
        #expect(!roll.isEnemyRoll)
    }

    @Test("A crit sticker counts its face extra times, and the log shows it")
    func critCountsTheFaceAgain() throws {
        let content = try Fixtures.content()
        let crit = try sticker(.crit, content)
        let plain = DieFace(value: 4)
        let critFace = DieFace(value: 4, sticker: crit.id)
        let engine = try fight(content, die: Array(repeating: critFace, count: DiceConfig.faceCount))
        let roll = try heroRoll(engine)

        #expect(engine.segmentTotal(roll, rolled: [critFace]) == engine.segmentTotal(roll, rolled: [plain]) + 4 * crit.amount)
        let before = engine.log.count
        land(engine, roll, on: critFace)
        let hit = try #require(engine.log[before...].first { $0.kind == .damage })
        #expect(hit.modifiers.contains(RollModifier(kind: .crit, amount: 4 * crit.amount * roll.expr.count)))
    }

    @Test("Enemy dice never crit")
    func enemyRollsIgnoreStickers() throws {
        let content = try Fixtures.content()
        let crit = try sticker(.crit, content)
        let engine = try fight(content, die: content.balance.dice.startingDie)
        let enemyRoll = PendingRoll(expr: DiceExpr(count: 1, flat: 0), isEnemyRoll: true, purpose: .heroDamageAll)
        #expect(engine.segmentTotal(enemyRoll, rolled: [DieFace(value: 3, sticker: crit.id)]) == 3)
    }

    @Test("A guard sticker blocks physical hits on the roller until their next party turn")
    func guardBlocksUntilNextTurn() throws {
        let content = try Fixtures.content()
        let guardSticker = try sticker(.block, content)
        let face = DieFace(value: 1, sticker: guardSticker.id)
        let engine = try fight(content, die: Array(repeating: face, count: DiceConfig.faceCount))
        let blockBefore = engine.damageReduction(forHeroAt: 0)
        let roll = try heroRoll(engine)
        land(engine, roll, on: face)

        #expect(engine.heroes[0].stickerBlock == guardSticker.amount * roll.expr.count)
        #expect(engine.damageReduction(forHeroAt: 0) == blockBefore + guardSticker.amount * roll.expr.count)

        // Through the enemies' turn it still counts; the next party turn clears it.
        engine.endPartyTurn()
        let hits = engine.settle(face: 1, enemyFace: 1)
        for hit in hits where hit.heroID == engine.heroes[0].id && !hit.isMagic {
            #expect(hit.block >= guardSticker.amount * roll.expr.count)
        }
        if engine.isChoosing { #expect(engine.heroes[0].stickerBlock == 0) }
    }

    @Test("A heal sticker heals the roller")
    func healStickerHealsTheRoller() throws {
        let content = try Fixtures.content()
        let heal = try sticker(.heal, content)
        let face = DieFace(value: 1, sticker: heal.id)
        let engine = try fight(content, die: Array(repeating: face, count: DiceConfig.faceCount)) { $0.hp = 5 }
        let roll = try heroRoll(engine)
        let hpBefore = engine.heroes[0].hp
        land(engine, roll, on: face)
        #expect(engine.heroes[0].hp == min(engine.heroes[0].maxHP, hpBefore + heal.amount * roll.expr.count))
    }

    @Test("A resource sticker gives the roller resource; heroes without a resource are never offered it")
    func resourceSticker() throws {
        let content = try Fixtures.content()
        let resource = try sticker(.resource, content)
        let casterIndex = try #require(content.classes.firstIndex { $0.resource != nil })
        func manaGained(_ face: DieFace) throws -> Int {
            let engine = try fight(content, heroIndex: casterIndex, die: Array(repeating: face, count: DiceConfig.faceCount)) { $0.resource = 0 }
            let roll = try heroRoll(engine, heroIndex: casterIndex)
            land(engine, roll, on: face)
            return engine.heroes[casterIndex].resource
        }
        let plain = try manaGained(DieFace(value: 1))
        let sparked = try manaGained(DieFace(value: 1, sticker: resource.id))
        let max = try #require(content.classes[casterIndex].resource?.max)
        #expect(sparked == min(max, plain + resource.amount))

        let run = RunState.fixture(content)
        let dice = content.balance.dice
        for hero in run.heroes {
            let offersResource = dice.offerableUpgrades(for: hero).contains { dice.sticker(id: $0.sticker)?.type == .resource }
            #expect(offersResource == (hero.maxResource > 0), "\(hero.id)")
        }
    }

    @Test("Upgrades raise a face up to the cap or put a sticker on it")
    func upgradesChangeFaces() throws {
        let dice = try Fixtures.content().balance.dice
        let raise = try #require(dice.upgrades.first { $0.type == .raiseFace })
        let stickerUpgrade = try #require(dice.upgrades.first { $0.type == .sticker })

        let low = DieFace(value: 1)
        #expect(dice.applying(raise, to: low).value == min(dice.maxFaceValue, 1 + (raise.amount ?? 0)))
        let top = DieFace(value: dice.maxFaceValue)
        #expect(!dice.canApply(raise, to: top))
        #expect(dice.applying(raise, to: DieFace(value: dice.maxFaceValue - 1)).value == dice.maxFaceValue)

        let stickered = dice.applying(stickerUpgrade, to: low)
        #expect(stickered.sticker == stickerUpgrade.sticker && stickered.value == low.value)
        #expect(!dice.canApply(stickerUpgrade, to: stickered), "the same sticker twice changes nothing")
    }

    @Test("Picking a die upgrade changes that face, clears the offer and is saved")
    func applyingAnOffer() throws {
        let content = try Fixtures.content()
        let levels = content.balance.leveling.levels
        try #require(levels.count >= 2)
        let start = try RunState.fixture(content).resumed { $0.heroes[0].xp = levels[1].xp - 1 }
        let node = try start.node(.fight)
        let (engine, reward, _) = try #require(start.startFight(at: node.id))
        for _ in 0..<200 where engine.phase == .choosingAction {
            engine.playTurn(try #require(engine.basicAttack), target: try #require(engine.livingEnemies.first), face: 6, enemyFace: 1)
        }
        start.finishFight(at: node.id, engine: engine, reward: reward)
        let offer = try #require(start.pendingDieUpgrades.first)
        let heroIndex = try #require(start.heroes.firstIndex { $0.id == offer.heroID })
        let dice = content.balance.dice
        let upgradeID = try #require(offer.upgradeIDs.first)
        let upgrade = try #require(dice.upgrade(id: upgradeID))
        let faceIndex = try #require(start.heroes[heroIndex].die.firstIndex { dice.canApply(upgrade, to: $0) })
        let expected = dice.applying(upgrade, to: start.heroes[heroIndex].die[faceIndex])
        let pending = start.pendingDieUpgrades.count

        start.applyDieUpgrade(upgrade.id, toFace: faceIndex)
        #expect(start.heroes[heroIndex].die[faceIndex] == expected)
        #expect(start.pendingDieUpgrades.count == pending - 1)
        #expect(try start.resumed().heroes[heroIndex].die == start.heroes[heroIndex].die)
    }

    @Test("A save from before hero dice loads with the starting die")
    func oldSavesGetTheStartingDie() throws {
        let content = try Fixtures.content()
        let run = try RunState.fixture(content).resumed { snapshot in
            for index in snapshot.heroes.indices { snapshot.heroes[index].die = nil }
            snapshot.pendingDieUpgrades = nil
        }
        #expect(run.heroes.allSatisfy { $0.die == content.balance.dice.startingDie })
        #expect(run.pendingDieUpgrades.isEmpty)
    }

    @Test("Broken dice content is rejected, blaming balance.json")
    func rejectsBrokenDice() throws {
        let content = try Fixtures.content()
        func error(_ change: (inout GameContent) -> Void) -> ContentError? {
            var broken = content
            change(&broken)
            do {
                try ContentLoader.validate(broken)
                return nil
            } catch let error as ContentError {
                return error
            } catch {
                return nil
            }
        }
        #expect(error { $0.balance.dice.startingFaces.removeLast() }?.file == "balance.json", "six faces")
        #expect(error { $0.balance.dice.startingFaces[0] = 0 }?.file == "balance.json", "faces are 1…max")
        #expect(error { $0.balance.dice.offerCount = 0 }?.file == "balance.json")
        #expect(error { $0.balance.dice.upgrades.append(DieUpgradeDef(id: "broken", type: .sticker, sticker: "nope")) }?.file == "balance.json",
                "unknown sticker")
        #expect(error { $0.balance.dice.upgrades.append(DieUpgradeDef(id: "broken", type: .raiseFace, amount: 0)) }?.file == "balance.json")
    }
}
