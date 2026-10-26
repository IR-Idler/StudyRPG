import Foundation
import Observation
import SwiftUI
import CryptoKit

// MARK: - MapGenerator (game.md §9)

/// Builds a branching map: several random walks from row 0 to the boss row are unioned into one
/// graph (this is what gives every node a route from the start and a route to the boss, for
/// free, with no separate reachability pass needed), then node types are assigned with weighted
/// randomness and guarantees are patched in afterward (game.md §9): a campfire row before the
/// boss, no shops/campfires before `restMinProgress`, a shop or campfire on every route, at
/// least one elite and one shop, never two shops in a row, and more fights than everything else.
enum MapGenerator {
    private struct Position: Hashable {
        var row: Int
        var lane: Int
    }

    static func generate(config: MapConfig, using rng: inout some RandomNumberGenerator) -> GameMap {
        let rowCount = config.rowCount
        let laneCount = config.maxLanes
        let bossPosition = Position(row: rowCount, lane: 0)

        var touched: Set<Position> = [bossPosition]
        var forwardEdges: [Position: Set<Position>] = [:]

        /// Whether a new road a → b (adjacent rows) would cross an existing one. Roads never
        /// cross, so the map always reads as clean branching paths (game.md §9).
        func crosses(_ a: Position, _ b: Position) -> Bool {
            for (from, tos) in forwardEdges where from.row == a.row {
                for to in tos where to.row == b.row {
                    if (from.lane < a.lane && to.lane > b.lane) || (from.lane > a.lane && to.lane < b.lane) { return true }
                }
            }
            return false
        }

        for _ in 0..<config.pathCount {
            var lane = Int.random(in: 0..<laneCount, using: &rng)
            touched.insert(Position(row: 0, lane: lane))
            for row in 0..<(rowCount - 1) {
                let from = Position(row: row, lane: lane)
                // Try the possible next lanes in random order; take the first that doesn't cross.
                let options = [-1, 0, 1].shuffled(using: &rng)
                    .map { min(laneCount - 1, max(0, lane + $0)) }
                let nextLane = options.first { !crosses(from, Position(row: row + 1, lane: $0)) } ?? lane
                let to = Position(row: row + 1, lane: nextLane)
                touched.insert(to)
                forwardEdges[from, default: []].insert(to)
                lane = nextLane
            }
            forwardEdges[Position(row: rowCount - 1, lane: lane), default: []].insert(bossPosition)
        }

        // Pad rows short of minLanes with extra nodes, but only where they can be wired in
        // without crossing a road.
        for row in 0..<rowCount {
            var lanesInRow = touched.filter { $0.row == row }.map(\.lane)
            var candidateLanes = Set(0..<laneCount).subtracting(lanesInRow).shuffled(using: &rng)
            while lanesInRow.count < config.minLanes, let newLane = candidateLanes.popLast() {
                let newPos = Position(row: row, lane: newLane)
                let nearest: (Int) -> [Position] = { r in
                    touched.filter { $0.row == r }.sorted { abs($0.lane - newLane) < abs($1.lane - newLane) }
                }
                let from = row > 0 ? nearest(row - 1).first { !crosses($0, newPos) } : nil
                let to = row < rowCount - 1 ? nearest(row + 1).first { !crosses(newPos, $0) } : bossPosition
                guard row == 0 || from != nil, let to else { continue }
                touched.insert(newPos)
                lanesInRow.append(newLane)
                if let from { forwardEdges[from, default: []].insert(newPos) }
                forwardEdges[newPos, default: []].insert(to)
            }
        }

        let sortedPositions = touched.sorted { ($0.row, $0.lane) < ($1.row, $1.lane) }
        var idByPosition: [Position: Int] = [:]
        for (index, pos) in sortedPositions.enumerated() {
            idByPosition[pos] = index
        }

        // Rows the random pass may fill: everything but the boss, and (with `campfireBeforeBoss`)
        // the campfire row right before it.
        let campfireRow = config.campfireBeforeBoss ? rowCount - 1 : nil
        let lastFreeRow = (campfireRow ?? rowCount) - 1
        let restMinRow = restMinRow(config: config)

        var types: [Position: MapNodeType] = [bossPosition: .boss]
        for pos in touched where pos != bossPosition {
            if pos.row == campfireRow {
                types[pos] = .campfire
            } else {
                types[pos] = weightedRandomType(row: pos.row, rowCount: rowCount, config: config, using: &rng)
            }
        }

        let freeRows = 0..<(lastFreeRow + 1)
        patchGuarantee(.elite, in: &types, touched: touched, rowRange: (rowCount / 3)..<(lastFreeRow + 1), allowedRows: freeRows, excluding: bossPosition, using: &rng)
        patchGuarantee(.shop, in: &types, touched: touched, rowRange: restMinRow..<(lastFreeRow + 1), allowedRows: freeRows, excluding: bossPosition, using: &rng)
        if campfireRow == nil {
            patchGuarantee(.campfire, in: &types, touched: touched, rowRange: max(restMinRow, rowCount * 2 / 3)..<rowCount, allowedRows: freeRows, excluding: bossPosition, using: &rng)
        }

        // Every route passes a shop or campfire before the end (game.md §9): while some route
        // from the start to the last free row has neither, one of its fights/events becomes one.
        var backEdges: [Position: Set<Position>] = [:]
        for (from, tos) in forwardEdges {
            for to in tos { backEdges[to, default: []].insert(from) }
        }
        /// A road leads straight from or to a shop (two shops in a row are never allowed).
        func touchesShop(_ pos: Position) -> Bool {
            ((forwardEdges[pos] ?? []).union(backEdges[pos] ?? [])).contains { types[$0] == .shop }
        }
        /// No campfire right before the campfire row (two rests in a row is a wasted pick).
        func campfireAllowed(_ pos: Position) -> Bool { campfireRow.map { pos.row < $0 - 1 } ?? true }

        // No two shops in a row (game.md §9): the later one of a shop → shop road becomes a
        // campfire (still a rest), or a fight where a campfire isn't allowed.
        for pos in sortedPositions where types[pos] == .shop && (backEdges[pos] ?? []).contains(where: { types[$0] == .shop }) {
            types[pos] = campfireAllowed(pos) ? .campfire : .fight
        }

        let isRest: (Position) -> Bool = { types[$0] == .shop || types[$0] == .campfire }
        while let route = restFreeRoute(touched: touched, edges: forwardEdges, lastRow: lastFreeRow, isRest: isRest) {
            let candidates = route.filter { $0.row >= restMinRow && (types[$0] == .fight || types[$0] == .event) }
            let fallback = route.filter { types[$0] == .fight || types[$0] == .event }
            let pool = candidates.isEmpty ? fallback : candidates
            // Prefer places where at least one kind of rest fits the rules above.
            let fitting = pool.filter { campfireAllowed($0) || !touchesShop($0) }
            guard let chosen = (fitting.isEmpty ? pool : fitting).randomElement(using: &rng) else { break }
            let shopOK = !touchesShop(chosen)
            types[chosen] = campfireAllowed(chosen) && (!shopOK || Bool.random(using: &rng)) ? .campfire : .shop
        }

        // More fights than every other kind of place together (game.md §9): events, then extra
        // elites, then shops and campfires become fights — never a guaranteed place, the boss or
        // the campfire row, and never a rest some route needs.
        func isSpecial(_ pos: Position) -> Bool { types[pos] != .fight }
        while touched.filter({ !isSpecial($0) }).count <= touched.filter(isSpecial).count {
            let free = touched.filter { $0 != bossPosition && $0.row != campfireRow }
            let counts = Dictionary(grouping: free.compactMap { types[$0] }, by: { $0 }).mapValues(\.count)
            func convertible(_ type: MapNodeType) -> [Position] {
                free.filter { types[$0] == type }.sorted { ($0.row, $0.lane) < ($1.row, $1.lane) }
            }
            var chosen: Position?
            // The map's last event stays, so every map keeps some variety.
            let events = counts[.event, default: 0] > 1 ? convertible(.event) : []
            if !events.isEmpty {
                chosen = events.randomElement(using: &rng)
            } else if counts[.elite, default: 0] > 1 {
                chosen = convertible(.elite).randomElement(using: &rng)
            } else {
                // A rest may only go if every route still rests without it (and one shop stays).
                let rests = (counts[.shop, default: 0] > 1 ? convertible(.shop) : []) + convertible(.campfire)
                chosen = rests.shuffled(using: &rng).first { pos in
                    let kept = types[pos]
                    types[pos] = .fight
                    let ok = restFreeRoute(touched: touched, edges: forwardEdges, lastRow: lastFreeRow, isRest: isRest) == nil
                    types[pos] = kept
                    return ok
                }
            }
            // Only when nothing else can go does the map's last event become a fight.
            guard let chosen = chosen ?? convertible(.event).first else { break }
            types[chosen] = .fight
        }

        let nodes: [MapNode] = sortedPositions.map { pos in
            let nextIDs = (forwardEdges[pos] ?? []).compactMap { idByPosition[$0] }
            return MapNode(id: idByPosition[pos]!, row: pos.row, column: pos.lane, type: types[pos] ?? .fight, nextNodeIDs: nextIDs)
        }

        return GameMap(nodes: nodes, bossNodeID: idByPosition[bossPosition]!)
    }

    /// Which `encounters.json` depth tier a row maps to — thirds of the non-boss rows.
    static func depthTier(forRow row: Int, rowCount: Int) -> Int {
        if row < rowCount / 3 { return 0 }
        if row < rowCount * 2 / 3 { return 1 }
        return 2
    }

    /// The first row where shops and campfires may appear (`map.restMinProgress`).
    static func restMinRow(config: MapConfig) -> Int {
        Int((config.restMinProgress * Double(max(1, config.rowCount - 1))).rounded(.up))
    }

    /// A route from any row-0 node to `lastRow` that passes no shop or campfire, if one exists.
    private static func restFreeRoute(touched: Set<Position>, edges: [Position: Set<Position>], lastRow: Int, isRest: (Position) -> Bool) -> [Position]? {
        var deadEnds = Set<Position>()
        func search(_ pos: Position) -> [Position]? {
            guard !isRest(pos), !deadEnds.contains(pos) else { return nil }
            if pos.row >= lastRow { return [pos] }
            for next in (edges[pos] ?? []).sorted(by: { $0.lane < $1.lane }) where next.row <= lastRow {
                if let rest = search(next) { return [pos] + rest }
            }
            deadEnds.insert(pos)
            return nil
        }
        for start in touched.filter({ $0.row == 0 }).sorted(by: { $0.lane < $1.lane }) {
            if let route = search(start) { return route }
        }
        return nil
    }

    private static func weightedRandomType(row: Int, rowCount: Int, config: MapConfig, using rng: inout some RandomNumberGenerator) -> MapNodeType {
        let progress = Double(row) / Double(max(1, rowCount - 1))
        let w = config.nodeWeights
        var weights: [(MapNodeType, Double)] = [(.fight, w.fight), (.event, w.event)]
        // No resting right at the start; no campfire right before the campfire row.
        if row >= restMinRow(config: config) {
            weights.append((.shop, w.shop))
            if !(config.campfireBeforeBoss && row == rowCount - 2) {
                weights.append((.campfire, w.campfire))
            }
        }
        if progress >= config.eliteMinProgress {
            weights.append((.elite, w.elite))
        }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return .fight }
        var roll = Double.random(in: 0..<total, using: &rng)
        for (type, weight) in weights {
            roll -= weight
            if roll <= 0 { return type }
        }
        return .fight
    }

    private static func patchGuarantee(
        _ type: MapNodeType,
        in types: inout [Position: MapNodeType],
        touched: Set<Position>,
        rowRange: Range<Int>,
        allowedRows: Range<Int>,
        excluding bossPosition: Position,
        using rng: inout some RandomNumberGenerator
    ) {
        guard !types.values.contains(type) else { return }
        // Never overwrite the only node of another guaranteed type (elite/shop/campfire).
        let guaranteed: Set<MapNodeType> = [.elite, .shop, .campfire]
        let snapshot = types
        let isSoleGuaranteed: (Position) -> Bool = { pos in
            guard let current = snapshot[pos], guaranteed.contains(current) else { return false }
            return snapshot.values.filter { $0 == current }.count == 1
        }
        let inRange = touched.filter { rowRange.contains($0.row) && $0 != bossPosition }
        let safe = inRange.filter { !isSoleGuaranteed($0) }
        // The fallback still never touches the boss or the campfire row before it.
        let fallback = touched.filter { allowedRows.contains($0.row) && $0 != bossPosition && !isSoleGuaranteed($0) }
        guard let chosen = (safe.isEmpty ? fallback : safe).randomElement(using: &rng) else { return }
        types[chosen] = type
    }
}
