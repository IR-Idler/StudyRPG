import Foundation
import Testing
@testable import StudyRPG

/// Acts (game.md §16): a run plays every act in `encounters.json → acts` in order, each on its
/// own map with its own encounter pools; everything the party carries goes along.
@MainActor
@Suite("Acts")
struct ActTests {
    init() { Fixtures.isolateUserData() }

    private func win(_ engine: CombatEngine) throws {
        for _ in 0..<400 where engine.phase == .choosingAction {
            let target = try #require(engine.livingEnemies.first)
            engine.playTurn(try #require(engine.basicAttack), target: target, face: 6, enemyFace: 1)
        }
        #expect(engine.phase == .victory)
    }

    /// A run standing right before its act's boss (the boss is reachable).
    private func runBeforeBoss(_ content: GameContent, act: Int = 0) throws -> RunState {
        let base = RunState.fixture(content)
        let before = try #require(base.map.nodes.first { $0.nextNodeIDs.contains(base.map.bossNodeID) })
        return try base.resumed { snapshot in
            snapshot.actIndex = act
            snapshot.currentNodeID = before.id
            snapshot.visitedNodeIDs = [before.id]
        }
    }

    @Test("Fights use their own act's encounter pools")
    func encountersComeFromTheAct() throws {
        let content = try Fixtures.content()
        for (index, act) in content.acts.enumerated() {
            let actEnemies = Set(content.encounterPools.filter { $0.act == act.id }.flatMap(\.encounters).flatMap(\.enemyIds))
            let run = try RunState.fixture(content).resumed { $0.actIndex = index }
            for node in run.map.nodes where [.fight, .elite, .boss].contains(node.type) {
                let encounter = try #require(run.encounter(for: node.id), "no encounter for \(node.type) in act \(act.id)")
                #expect(Set(encounter.enemyIds).isSubset(of: actEnemies), "act \(act.id) fight used \(encounter.enemyIds)")
            }
        }
    }

    @Test("Beating an act's boss starts the next act on a fresh map; the party keeps everything")
    func bossLeadsToNextAct() throws {
        let content = try Fixtures.content()
        try #require(content.acts.count >= 2, "content has a single act")
        let run = try runBeforeBoss(content)
        let oldMap = run.map
        let (engine, reward, _) = try #require(run.startFight(at: run.map.bossNodeID))
        let xpGain = engine.enemies.reduce(0) { $0 + $1.def.xp }
        let xpBefore = run.heroes.map(\.xp)
        let goldBefore = run.gold
        try win(engine)

        run.finishFight(at: oldMap.bossNodeID, engine: engine, reward: reward)

        #expect(run.actIndex == 1)
        #expect(!run.isOver, "an act boss that isn't the last doesn't end the run")
        #expect(run.currentNodeID == nil && run.visitedNodeIDs.isEmpty, "the new map starts at its trailhead")
        #expect(run.map != oldMap)
        #expect(run.heroes.map(\.xp) == xpBefore.map { $0 + xpGain })
        let goldAfter = run.gold
        #expect(goldAfter == goldBefore + reward.gold)
        let allStanding = run.heroes.allSatisfy { $0.isAlive }
        #expect(allStanding)
        // The new act is what a saved run resumes into.
        let resumed = try run.resumed()
        #expect(resumed.actIndex == 1)
        #expect(resumed.map == run.map)
    }

    @Test("Only the last act's boss wins the run")
    func lastBossWins() throws {
        let content = try Fixtures.content()
        let run = try runBeforeBoss(content, act: content.acts.count - 1)
        let (engine, reward, _) = try #require(run.startFight(at: run.map.bossNodeID))
        try win(engine)
        run.finishFight(at: run.map.bossNodeID, engine: engine, reward: reward)
        #expect(run.isComplete)
    }

    @Test("Acts are validated: pools must name a known act, every act needs fights, elites and a boss")
    func rejectsBrokenActs() throws {
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
        #expect(error { $0.encounterPools[0].act = "nowhere" }?.file == "encounters.json")
        #expect(error { $0.acts.append(ActDef(id: "empty", name: "Empty", mapStyle: .hologram)) }?.file == "encounters.json")
        #expect(error { $0.acts = [] }?.file == "encounters.json")
    }
}
