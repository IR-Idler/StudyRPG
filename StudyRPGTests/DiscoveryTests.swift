import Foundation
import Testing
@testable import StudyRPG

/// Glossary & Bestiary discovery (game.md §16.1): what a run shows the player is remembered
/// across runs in user data. Suites share one sandbox and run in parallel, so tests only check
/// that things become discovered, never that something is still undiscovered.
@MainActor
@Suite("Discoveries: glossary & bestiary")
struct DiscoveryTests {
    init() { Fixtures.isolateUserData() }

    @Test("Discoveries only grow, report what's new, and survive a save")
    func storeRoundTrip() throws {
        var discoveries = Discoveries()
        let first = discoveries.insert(["a", "b"], into: \.relics)
        let again = discoveries.insert(["a"], into: \.relics)
        #expect(first && !again)
        #expect(discoveries.relics == ["a", "b"])

        DiscoveryStore.record(["test-only-enemy"], in: \.enemies)
        #expect(DiscoveryStore.load().enemies.contains("test-only-enemy"))

        // Older files without a category still load.
        let partial = try JSONDecoder().decode(Discoveries.self, from: Data(#"{"skills":["x"]}"#.utf8))
        #expect(partial.skills == ["x"] && partial.enemies.isEmpty)
    }

    @Test("A new run reveals the heroes' starting skills")
    func startingSkills() throws {
        let run = RunState.fixture(try Fixtures.content())
        let found = DiscoveryStore.load().skills
        #expect(run.heroes.flatMap(\.knownSkillIDs).allSatisfy(found.contains))
    }

    @Test("Starting a fight reveals its monsters in the bestiary")
    func fightRevealsEnemies() throws {
        let run = RunState.fixture(try Fixtures.content())
        let node = try run.node(.elite)
        let encounter = try #require(run.encounter(for: node.id))
        _ = try #require(run.startFight(at: node.id))
        #expect(Set(encounter.enemyIds).isSubset(of: DiscoveryStore.load().enemies))
    }

    @Test("A shop reveals every potion and its relics and gear")
    func shopRevealsStock() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let stock = run.shop(for: try run.node(.shop).id)
        let found = DiscoveryStore.load()
        #expect(content.items.map(\.id).allSatisfy(found.potions.contains))
        #expect(stock.relicIDs.allSatisfy(found.relics.contains))
        #expect(stock.gearIDs.allSatisfy(found.gear.contains))
    }

    @Test("An event's relic, potion or gear is revealed")
    func eventRevealsFinds() throws {
        let content = try Fixtures.content()
        let findTypes: Set<EventOutcomeType> = [.relic, .potion, .gear]
        guard let event = content.events.first(where: { findTypes.contains($0.reward.type) }) else { return }
        let run = RunState.fixture(content)
        // Not every random map rolls an event, so the test makes a first-row place one.
        let node = try #require(run.map.nodes.first { $0.row == 0 })
        let resumed = try run.resumed { snapshot in
            if let index = snapshot.map.nodes.firstIndex(where: { $0.id == node.id }) { snapshot.map.nodes[index].type = .event }
            snapshot.events = [node.id: RunSnapshot.Event(eventID: event.id)]
        }
        let applied = try #require(resumed.resolveEvent(at: node.id, correct: true))
        let found = DiscoveryStore.load()
        if let relic = applied.relic { #expect(found.relics.contains(relic.id)) }
        if let potion = applied.potion { #expect(found.potions.contains(potion.id)) }
        if let gear = applied.gear { #expect(found.gear.contains(gear.id)) }
    }
}
