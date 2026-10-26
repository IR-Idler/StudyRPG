import Foundation
import Testing
@testable import StudyRPG

/// Experience and hero levels (game.md §5 "Levels"): run fights pay XP, levels come from
/// `balance.json → leveling`, and every level gained offers a die upgrade.
@MainActor
@Suite("Experience and levels")
struct LevelTests {
    init() { Fixtures.isolateUserData() }

    private func win(_ engine: CombatEngine) throws {
        for _ in 0..<200 where engine.phase == .choosingAction {
            let target = try #require(engine.livingEnemies.first)
            engine.playTurn(try #require(engine.basicAttack), target: target, face: 6, enemyFace: 1)
        }
        #expect(engine.phase == .victory)
    }

    @Test("Winning a run fight gives every hero its enemies' XP, and the XP is saved")
    func fightsPayExperience() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let node = try run.node(.fight)
        let (engine, reward, _) = try #require(run.startFight(at: node.id))
        let expected = engine.enemies.reduce(0) { $0 + $1.def.xp }
        let before = run.heroes.map(\.xp)
        try win(engine)

        run.finishFight(at: node.id, engine: engine, reward: reward)

        #expect(run.heroes.map(\.xp) == before.map { $0 + expected })
        let resumed = try run.resumed()
        #expect(resumed.heroes.map(\.xp) == run.heroes.map(\.xp))
    }

    @Test("Reaching a level's XP raises the level, and every level gained offers a die upgrade")
    func levelsOfferDieUpgrades() throws {
        let content = try Fixtures.content()
        let levels = content.balance.leveling.levels
        try #require(levels.count >= 2, "balance.json has only one level")
        let leveling = content.balance.leveling

        #expect(leveling.level(forXP: 0) == 1)
        #expect(leveling.level(forXP: levels[1].xp - 1) == 1)
        #expect(leveling.level(forXP: levels[1].xp) == 2)
        #expect(leveling.level(forXP: levels.last!.xp + 10_000) == levels.count, "XP past the top level stays at the top")

        // Hero 0 is one XP short of level 2, so any won fight levels them up.
        let run = try RunState.fixture(content).resumed { $0.heroes[0].xp = levels[1].xp - 1 }
        let node = try run.node(.fight)
        let (engine, reward, _) = try #require(run.startFight(at: node.id))
        let before = run.heroes.map { leveling.level(forXP: $0.xp) }
        try win(engine)
        run.finishFight(at: node.id, engine: engine, reward: reward)

        let gained = zip(before, run.heroes).map { leveling.level(forXP: $1.xp) - $0 }
        #expect(gained[0] >= 1)
        #expect(run.pendingDieUpgrades.count == gained.reduce(0, +))
        let offer = try #require(run.pendingDieUpgrades.first)
        #expect(offer.heroID == run.heroes[0].id)
        #expect(!offer.upgradeIDs.isEmpty && offer.upgradeIDs.count <= content.balance.dice.offerCount)
        #expect(Set(offer.upgradeIDs).count == offer.upgradeIDs.count, "no upgrade offered twice")
        #expect(!run.isReachable(try #require(run.reachableNodeIDs.first)), "the map waits for the pick")

        // The offer survives a restart.
        #expect(try run.resumed().pendingDieUpgrades == run.pendingDieUpgrades)
    }

    @Test("In the first act, a fight-heavy route gets three level-ups before the boss; a fight-light route doesn't")
    func levelPacing() throws {
        let content = try Fixtures.content()
        let levels = content.balance.leveling.levels
        try #require(levels.count >= 4, "balance.json needs at least four levels")
        let threshold = levels[3].xp
        let config = content.balance.map
        /// The average XP of the encounters a node can roll.
        func expectedXP(_ node: MapNode) -> Double {
            guard node.type == .fight || node.type == .elite else { return 0 }
            let tier = MapGenerator.depthTier(forRow: node.row, rowCount: config.rowCount)
            let pools = content.encounterPools.filter { $0.act == content.acts[0].id && $0.nodeType == node.type && $0.depthTier == tier }
            let encounters = pools.flatMap(\.encounters)
            guard !encounters.isEmpty else { return 0 }
            let total = encounters.reduce(0.0) { sum, encounter in
                sum + Double(encounter.enemyIds.compactMap { content.enemyDef(id: $0)?.xp }.reduce(0, +))
            }
            return total / Double(encounters.count)
        }

        var heavy: [Double] = [], light: [Double] = []
        for seed in 1...200 as ClosedRange<UInt64> {
            var rng = SeededRNG(seed: seed)
            let map = MapGenerator.generate(config: config, using: &rng)
            // Best / worst expected XP over every route from the start to (not including) the boss.
            var best: [Int: Double] = [:], worst: [Int: Double] = [:]
            for node in map.nodes.sorted(by: { $0.row > $1.row }) where node.type != .boss {
                let next = node.nextNodeIDs.filter { $0 != map.bossNodeID }
                best[node.id] = expectedXP(node) + (next.compactMap { best[$0] }.max() ?? 0)
                worst[node.id] = expectedXP(node) + (next.compactMap { worst[$0] }.min() ?? 0)
            }
            let starts = map.nodes.filter { $0.row == 0 }.map(\.id)
            heavy.append(starts.compactMap { best[$0] }.max() ?? 0)
            light.append(starts.compactMap { worst[$0] }.min() ?? 0)
        }
        let heavyAverage = heavy.reduce(0, +) / Double(heavy.count)
        let lightAverage = light.reduce(0, +) / Double(light.count)
        #expect(heavyAverage >= Double(threshold), "fight-heavy routes average \(heavyAverage) XP, level 4 needs \(threshold)")
        #expect(lightAverage < Double(threshold), "fight-light routes average \(lightAverage) XP, level 4 needs \(threshold)")
    }

    @Test("Broken levels are rejected, blaming balance.json")
    func rejectsBrokenLevels() throws {
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
        #expect(error { $0.balance.leveling.levels[0].xp = 5 }?.file == "balance.json", "level 1 must start at 0 XP")
        #expect(error { $0.balance.leveling.levels.append(LevelDef(xp: 0)) }?.file == "balance.json", "thresholds must rise")
        #expect(error { $0.enemies[0].attackDice.sides = 7 }?.file == "enemies.json")
    }
}
