import Testing
@testable import StudyRPG

/// The map guarantees from game.md §9, each checked on many seeded maps generated from the real
/// `balance.json → map` config. One test per rule (looping over the seeds) keeps test output
/// short; a failure names its seed so it can be reproduced.
@MainActor
@Suite("Map generator")
struct MapGeneratorTests {
    init() { Fixtures.isolateUserData() }

    static let seeds: [UInt64] = Array(1...400)

    /// Generates every seeded map and hands each to `check`.
    private func forEachMap(_ check: (GameMap, MapConfig, UInt64) throws -> Void) throws {
        let config = try Fixtures.content().balance.map
        for seed in Self.seeds {
            var rng = SeededRNG(seed: seed)
            try check(MapGenerator.generate(config: config, using: &rng), config, seed)
        }
    }

    @Test("Exactly one boss, alone in the final row")
    func singleBoss() throws {
        try forEachMap { map, config, seed in
            let bosses = map.nodes.filter { $0.type == .boss }
            #expect(bosses.count == 1, "seed \(seed)")
            #expect(bosses.first?.id == map.bossNodeID, "seed \(seed)")
            #expect(bosses.first?.row == config.rowCount, "seed \(seed)")
            #expect(map.nodes.filter { $0.row == config.rowCount }.count == 1, "seed \(seed)")
        }
    }

    @Test("Roads only go one row forward and lanes stay within maxLanes")
    func edgesAndLanes() throws {
        try forEachMap { map, config, seed in
            for node in map.nodes {
                #expect(node.column >= 0 && node.column < config.maxLanes, "seed \(seed)")
                for next in node.nextNodeIDs {
                    #expect(map.node(next)?.row == node.row + 1, "seed \(seed): road \(node.id)→\(next)")
                }
            }
        }
    }

    @Test("Every place is reachable from the start and leads to the boss")
    func reachability() throws {
        try forEachMap { map, _, seed in
            var reached = Set(map.nodes.filter { $0.row == 0 }.map(\.id))
            var frontier = Array(reached)
            while let id = frontier.popLast() {
                for next in map.node(id)?.nextNodeIDs ?? [] where reached.insert(next).inserted { frontier.append(next) }
            }
            #expect(reached.count == map.nodes.count, "seed \(seed): unreachable places")

            // Walk backwards from the boss.
            var leadsToBoss: Set<Int> = [map.bossNodeID]
            var changed = true
            while changed {
                changed = false
                for node in map.nodes where !leadsToBoss.contains(node.id) && node.nextNodeIDs.contains(where: leadsToBoss.contains) {
                    leadsToBoss.insert(node.id)
                    changed = true
                }
            }
            #expect(leadsToBoss.count == map.nodes.count, "seed \(seed): dead ends")
        }
    }

    @Test("Roads never cross")
    func noCrossings() throws {
        try forEachMap { map, _, seed in
            let roads = map.nodes.flatMap { node in node.nextNodeIDs.compactMap { map.node($0) }.map { (node, $0) } }
            for (a, b) in roads {
                for (c, d) in roads where a.row == c.row {
                    let crosses = (a.column < c.column && b.column > d.column) || (a.column > c.column && b.column < d.column)
                    #expect(!crosses, "seed \(seed): road \(a.id)→\(b.id) crosses \(c.id)→\(d.id)")
                }
            }
        }
    }

    @Test("The row before the boss is all campfires, and the row before that has none")
    func campfireRow() throws {
        try forEachMap { map, config, seed in
            guard config.campfireBeforeBoss else { return }
            let campfireRow = config.rowCount - 1
            #expect(map.nodes.filter { $0.row == campfireRow }.allSatisfy { $0.type == .campfire }, "seed \(seed)")
            #expect(!map.nodes.contains { $0.row == campfireRow - 1 && $0.type == .campfire }, "seed \(seed)")
        }
    }

    @Test("No shop or campfire before restMinProgress")
    func noEarlyRest() throws {
        try forEachMap { map, config, seed in
            let restMinRow = MapGenerator.restMinRow(config: config)
            for node in map.nodes where node.row < restMinRow {
                #expect(node.type != .shop && node.type != .campfire, "seed \(seed): \(node.type) in row \(node.row)")
            }
        }
    }

    @Test("At least one elite and one shop")
    func requiredPlaces() throws {
        try forEachMap { map, _, seed in
            #expect(map.nodes.contains { $0.type == .elite }, "seed \(seed)")
            #expect(map.nodes.contains { $0.type == .shop }, "seed \(seed)")
        }
    }

    @Test("Never two shops in a row")
    func noShopAfterShop() throws {
        try forEachMap { map, _, seed in
            for node in map.nodes where node.type == .shop {
                for next in node.nextNodeIDs {
                    #expect(map.node(next)?.type != .shop, "seed \(seed): shop \(node.id) → shop \(next)")
                }
            }
        }
    }

    @Test("More fights than every other kind of place together")
    func fightsAreTheMajority() throws {
        try forEachMap { map, _, seed in
            let fights = map.nodes.filter { $0.type == .fight }.count
            #expect(fights > map.nodes.count - fights, "seed \(seed): \(fights) fights of \(map.nodes.count) places")
        }
    }

    @Test("Every route passes a shop or campfire before the campfire row")
    func everyRouteRests() throws {
        try forEachMap { map, config, seed in
            let lastFreeRow = config.campfireBeforeBoss ? config.rowCount - 2 : config.rowCount - 1
            var memo: [Int: Bool] = [:]
            /// Whether some route from `node` to `lastFreeRow` avoids every shop and campfire.
            func restFreeRouteExists(_ node: MapNode) -> Bool {
                if let known = memo[node.id] { return known }
                let result: Bool
                if node.type == .shop || node.type == .campfire {
                    result = false
                } else if node.row == lastFreeRow {
                    result = true
                } else {
                    result = node.nextNodeIDs.compactMap { map.node($0) }.contains { restFreeRouteExists($0) }
                }
                memo[node.id] = result
                return result
            }
            for start in map.nodes where start.row == 0 {
                #expect(!restFreeRouteExists(start), "seed \(seed): a route from place \(start.id) never rests")
            }
        }
    }
}
