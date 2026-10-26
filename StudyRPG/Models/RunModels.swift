import Foundation

// MARK: - Map (game.md §9)
//
// Generated once per run and saved with it (`RunSnapshot`). Row 0 is the first
// real row after the start — the start itself isn't a materialized node, the player can pick any
// row-0 node immediately. The last row is always exactly one `.boss` node.

struct MapNode: Identifiable, Hashable, Codable {
    var id: Int
    var row: Int
    var column: Int
    var type: MapNodeType
    var nextNodeIDs: [Int]
}

struct GameMap: Hashable, Codable {
    var nodes: [MapNode]
    var bossNodeID: Int

    func node(_ id: Int) -> MapNode? {
        nodes.first { $0.id == id }
    }

    /// Nodes reachable right now: any row-0 node if nothing has been visited yet, else whatever
    /// the current node's `nextNodeIDs` point to.
    func reachableNodeIDs(from currentNodeID: Int?) -> [Int] {
        guard let currentNodeID, let current = node(currentNodeID) else {
            return nodes.filter { $0.row == 0 }.map(\.id)
        }
        return current.nextNodeIDs
    }
}

// MARK: - Run (game.md §3)

/// A skill offer (elite victory or a shop scroll, game.md §5): the player picks which hero
/// learns, then one of that hero's offered skills — or skips. Every hero who can still learn
/// something has their skills rolled up front, so switching heroes can't re-roll them.
struct SkillOffer: Codable, Hashable {
    /// Hero id → the skills offered to that hero.
    var choices: [String: [String]]

    init(choices: [String: [String]]) { self.choices = choices }

    /// Every skill in the offer, for discoveries.
    var allSkillIDs: [String] { choices.values.flatMap { $0 } }

    private enum CodingKeys: String, CodingKey { case choices, heroID, skillIDs }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let choices = try container.decodeIfPresent([String: [String]].self, forKey: .choices) {
            self.choices = choices
        } else {
            // Saves from before the hero choice: one hero, one list.
            let heroID = try container.decode(String.self, forKey: .heroID)
            choices = [heroID: try container.decode([String].self, forKey: .skillIDs)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(choices, forKey: .choices)
    }
}

/// What a fight/elite/boss node pays out on victory. Rolled once when the fight is first opened and
/// saved, so restarting the app can't re-roll it.
struct NodeReward: Hashable {
    var gold: Int
    var relic: RelicDef?
    var potion: ItemDef?
    var gear: GearDef?
    var skillOffer: SkillOffer?
}

/// Run-wide tallies for the end-of-run recap.
struct RunStats: Codable, Hashable {
    var fightsWon = 0
    var goldEarned = 0
    var cardsAnswered = 0
    var cardsCorrect = 0
    /// Optional so saves from before the run history still load.
    var elitesWon: Int? = nil
    var goldSpent: Int? = nil
}

/// One finished run in the permanent run history (game.md §3). Written once when a run ends —
/// victory, defeat or abandon — and never changed. Content is stored by id *and* display name, so
/// the history still reads right if content is renamed or removed later.
struct RunRecord: Codable, Hashable, Identifiable {
    enum Outcome: String, Codable {
        case victory, defeat, abandoned
    }

    struct Hero: Codable, Hashable {
        var classID: String
        var name: String
        var spriteID: String
        var hp: Int
        var maxHP: Int
        var skillIDs: [String]
        var gearIDs: [String]
    }

    var id: UUID
    var startedAt: Date?
    var endedAt: Date
    var outcome: Outcome
    var heroes: [Hero]
    var deckNames: [String]
    /// Map rows the party got through (the boss row counts) out of `totalRows`.
    var rowsReached: Int
    var totalRows: Int
    var fightsWon: Int
    var elitesWon: Int
    var goldEarned: Int
    var goldSpent: Int
    var cardsAnswered: Int
    var cardsCorrect: Int
    var relicIDs: [String]
    /// Enemy ids of the fight that ended the run (defeat only).
    var defeatedBy: [String]

    var accuracy: Double? { cardsAnswered > 0 ? Double(cardsCorrect) / Double(cardsAnswered) : nil }
    var duration: TimeInterval? { startedAt.map { endedAt.timeIntervalSince($0) } }
}

/// Everything needed to resume a run after the app is closed (game.md §3). Content (classes,
/// items, relics, gear, skills) is stored by id and re-resolved against `Content/*.json` on load.
/// Fields added after the first release are optional so older saves still load.
struct RunSnapshot: Codable {
    struct Hero: Codable {
        var classID: String
        var hp: Int
        var resource: Int
        var bonusMaxHP: Int
        var xp: Int? = nil
        var knownSkillIDs: [String]? = nil
        var loadoutSkillIDs: [String]? = nil
        var gearIDs: [String]? = nil
        /// The hero's die faces (game.md §8 "Hero dice"); nil in older saves = the starting die.
        var die: [DieFace]? = nil
        /// Skills upgraded at a campfire (game.md §5 "Skill upgrades").
        var upgradedSkillIDs: [String]? = nil
    }

    struct Reward: Codable {
        var gold: Int
        var relicID: String?
        var potionID: String?
        var gearID: String?
        var skillOffer: SkillOffer?
    }

    /// A shop's stock and haggle, so leaving the app can't re-roll or re-haggle it.
    struct Shop: Codable {
        var relicIDs: [String]
        var gearIDs: [String]
        var soldIDs: [String] = []
        var haggled = false
        var haggleWon: Bool?
        /// The shop's one skill scroll has been bought (game.md §10).
        var scrollSold: Bool? = nil
    }

    /// An event node: which event it is and, once answered, what happened (so it can't be replayed).
    struct Event: Codable {
        var eventID: String
        var outcome: Outcome?

        struct Outcome: Codable {
            var correct: Bool
            var type: EventOutcomeType
            var amount: Int
            var relicID: String?
            var potionID: String?
            var gearID: String?
            var convertedToGold: Bool
        }
    }

    var map: GameMap
    var currentNodeID: Int?
    var visitedNodeIDs: Set<Int>
    var heroes: [Hero]
    var gold: Int
    var inventoryIDs: [String]
    var relicIDs: [String]
    /// Legacy: training used to give bonus dice. Old saves' stacks convert to `trainedDamageBonus`.
    var trainedBonusDice: Int
    var deckIDs: [UUID]
    /// The encounter rolled for each fight node so far (enemies + theme).
    var encounters: [Int: EncounterDef]
    var stats: RunStats
    var gearBagIDs: [String]? = nil
    var rewards: [Int: Reward]? = nil
    var shops: [Int: Shop]? = nil
    var events: [Int: Event]? = nil
    var pendingSkillOffer: SkillOffer? = nil
    /// Legacy: offers used to alternate heroes; no longer written or read.
    var skillOfferCount: Int? = nil
    /// Level-up die upgrades still to pick, in order (game.md §5 "Levels").
    var pendingDieUpgrades: [DieUpgradeOffer]? = nil
    /// For the run history's duration.
    var startedAt: Date? = nil
    /// Campfire training: +damage on every damage roll (game.md §11).
    var trainedDamageBonus: Int? = nil
    /// Which act (`encounters.json → acts`) `map` belongs to (game.md §16); nil = the first.
    var actIndex: Int? = nil
}
