import Foundation
import Testing
@testable import StudyRPG

// Shared helpers for the StudyRPG test suites. Tests read the real `Content/*.json` and pick
// skills/enemies by what they do (target, effect types, damage type), never by hard-coded IDs or
// stats, so rebalancing the content sheets doesn't break them — only breaking a rule does.

/// Deterministic random numbers, so a failing randomized test can be reproduced from its seed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Fixtures {
    /// A throwaway folder all user data (decks, card stats, answer log, saved run, run history)
    /// goes to during tests, so they can never touch the player's real data.
    nonisolated(unsafe) private static let sandbox: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyRPGTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDataLocation.directory = dir
        return dir
    }()

    /// Call before touching any store. Every suite does this in `init()`.
    static func isolateUserData() { _ = sandbox }

    @MainActor static func content() throws -> GameContent {
        isolateUserData()
        return try ContentLoader.load()
    }

    /// A deck of `count` simple text cards with distinct answers.
    static func deck(_ count: Int, name: String = "Fixture") -> Deck {
        Deck(name: name, cards: (0..<count).map {
            Flashcard(question: CardFace(text: "Q\($0)"), answer: CardFace(text: "A\($0)"))
        })
    }
}

/// One enemy hit on a hero, as measured while driving a fight.
struct EnemyHit {
    var heroID: String
    var enemyID: UUID
    /// Dice faces + flat, before weaken/block.
    var rolled: Int
    /// Block the engine reported for that hero at the moment of the hit.
    var block: Int
    var isMagic: Bool
    var isCounter: Bool
    var dealt: Int
    /// Which throw it came from (Fast mode batches several hits into one throw).
    var rollID: UUID
}

@MainActor
extension CombatEngine {
    /// A fresh fight between the content's heroes and the given enemies, with no decks (tests
    /// answer through `proceedAfterAnswer` directly).
    static func fixture(_ content: GameContent, enemies: [EnemyDef], fastMode: Bool = false) -> CombatEngine {
        let engine = CombatEngine(heroClasses: content.classes, enemyDefs: enemies, balance: content.balance,
                                  decks: [], statsStore: CardStatsStore(), rollEnemyHP: false)
        engine.fastMode = fastMode
        return engine
    }

    /// The selected hero uses `skill` (two taps: the skill, then `target` — or, for a skill on
    /// heroes, the hero themself; a group skill accepts any member): answers `correct`, then
    /// settles every roll and beat until the next decision (or the end of the fight). When that
    /// was the party's last action point, this includes the whole enemies' turn. Hero dice show
    /// `face`, enemy dice `enemyFace` (defaults to `face`).
    @discardableResult
    func playTurn(_ skill: SkillDef, target: EnemyInstance? = nil, correct: Bool = true, face: Int = 1, enemyFace: Int? = nil) -> [EnemyHit] {
        selectSkill(skill)
        if case .choosingTarget = phase, let enemy = target ?? livingEnemies.first { selectTarget(enemy.id) }
        if case .choosingAlly = phase { selectAlly(activeHero.id) }
        guard case .awaitingAnswer(let skillID, let targetID) = phase else { return [] }
        proceedAfterAnswer(skillID: skillID, targetEnemyID: targetID, correct: correct)
        return settle(face: face, enemyFace: enemyFace ?? face, counterFirst: !correct)
    }

    /// Settles rolls and resolution beats until the engine waits for the player again.
    func settle(face: Int, enemyFace: Int, counterFirst: Bool = false) -> [EnemyHit] {
        var hits: [EnemyHit] = []
        var isFirstEnemyRoll = counterFirst
        for _ in 0..<500 {
            switch phase {
            case .rolling(let pending):
                let faces = Array(repeating: pending.isEnemyRoll ? enemyFace : face, count: pending.expr.count)
                for (index, segment) in pending.segments.enumerated() {
                    if case .enemyAttack(let enemyID, let heroID, _) = segment,
                       let heroIndex = heroes.firstIndex(where: { $0.id == heroID }) {
                        let before = heroes[heroIndex].hp
                        let block = damageReduction(forHeroAt: heroIndex)
                        applyRollSegment(index, faces: faces)
                        hits.append(EnemyHit(heroID: heroID, enemyID: enemyID,
                                             rolled: faces.reduce(0, +) + pending.expr.flat, block: block,
                                             isMagic: pending.isMagic, isCounter: isFirstEnemyRoll,
                                             dealt: before - heroes[heroIndex].hp, rollID: pending.id))
                    } else {
                        applyRollSegment(index, faces: faces)
                    }
                }
                if pending.isEnemyRoll { isFirstEnemyRoll = false }
                finishRoll()
            case .resolving(_, let id):
                continueAfterResolution(id: id)
            default:
                return hits
            }
        }
        Issue.record("Fight did not reach a decision point within 500 steps")
        return hits
    }

    /// Plays basic attacks (ending the turn when there's no usable one) until the enemies' turn
    /// has run once; returns its hits.
    @discardableResult
    func playRound(target: EnemyInstance? = nil, face: Int = 1, enemyFace: Int = 1) -> [EnemyHit] {
        let round = roundNumber
        var hits: [EnemyHit] = []
        for _ in 0..<10 where roundNumber == round && phase == .choosingAction {
            if let attack = basicAttack, isSkillUsable(attack) {
                let alive = target.flatMap { t in livingEnemies.first { $0.id == t.id } }
                hits += playTurn(attack, target: alive, face: face, enemyFace: enemyFace)
            } else {
                endPartyTurn()
                hits += settle(face: face, enemyFace: enemyFace)
            }
        }
        return hits
    }

    /// The active hero's plain attack: single enemy, damage only, no cost or cooldown.
    var basicAttack: SkillDef? {
        activeHero.classDef.skills.first {
            $0.target == .enemy && $0.effects.map(\.type) == [.damage] && $0.cost == nil && ($0.cooldown ?? 0) == 0
        } ?? activeHero.classDef.skills.first {
            $0.target == .enemy && $0.diceEffect?.type == .damage && $0.cost == nil && ($0.cooldown ?? 0) == 0
        }
    }
}

// MARK: - Runs

@MainActor
extension RunState {
    /// A fresh run with the content's heroes and one usable deck.
    static func fixture(_ content: GameContent) -> RunState {
        RunState(content: content, heroClasses: content.classes, decks: [Fixtures.deck(6)], statsStore: CardStatsStore())
    }

    /// This run's save, edited by `change`, loaded back as a new `RunState` — how tests set up
    /// exact situations (a hurt hero, a full bag, a specific event) through the real save format.
    func resumed(_ change: (inout RunSnapshot) -> Void = { _ in }) throws -> RunState {
        var snapshot = self.snapshot
        change(&snapshot)
        return try #require(RunState(snapshot: snapshot, content: content, decks: flashcards.decks, statsStore: CardStatsStore()))
    }

    /// The first map node of a type (the generator guarantees elites, shops and campfires).
    func node(_ type: MapNodeType) throws -> MapNode {
        try #require(map.nodes.first { $0.type == type }, "map has no \(type)")
    }
}
