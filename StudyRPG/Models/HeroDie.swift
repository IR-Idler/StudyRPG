import Foundation

// MARK: - Hero dice (game.md §8 "Hero dice", §5 "Levels")

/// One face of a hero's die: the number it adds and, optionally, the id of a sticker whose effect
/// triggers when the face lands (`balance.json → dice.stickers`). Enemy dice are plain faces.
struct DieFace: Codable, Hashable {
    var value: Int
    var sticker: String? = nil

    /// A plain die: faces 1…sides, no stickers.
    static func plain(sides: Int = DiceExpr.standardSides) -> [DieFace] {
        (1...max(1, sides)).map { DieFace(value: $0) }
    }
}

/// What a sticker does when its face lands on a hero's roll (game.md §8).
enum StickerEffectType: String, Codable {
    /// The face's number counts `amount` extra times (1 = doubled) — damage and healing rolls.
    case crit
    /// The roller gets −`amount` damage from every physical hit until their next party turn.
    case block
    /// The roller gains `amount` resource (only offered to classes that have one).
    case resource
    /// The roller heals `amount` HP.
    case heal
}

struct StickerDef: Codable, Hashable, Identifiable {
    var id: String
    @ContentText var name: String
    /// SF Symbol drawn on the face.
    var symbol: String
    var type: StickerEffectType
    var amount: Int
}

enum DieUpgradeType: String, Codable {
    /// +`amount` on the chosen face, capped at `dice.maxFaceValue`.
    case raiseFace
    /// Puts `sticker` on the chosen face (replacing any sticker it had).
    case sticker
}

/// One level-up choice (game.md §5 "Levels"): the player picks it, then the face it changes.
struct DieUpgradeDef: Codable, Hashable, Identifiable {
    var id: String
    var type: DieUpgradeType
    var amount: Int? = nil
    var sticker: String? = nil
}

/// `balance.json → dice`.
struct DiceConfig: Codable, Hashable {
    /// Every hero's die at the start of a run (always six faces — the tray draws a d6).
    var startingFaces: [Int]
    var maxFaceValue: Int
    /// How many upgrades a level-up offers.
    var offerCount: Int
    var stickers: [StickerDef]
    var upgrades: [DieUpgradeDef]

    static let faceCount = 6

    var startingDie: [DieFace] { startingFaces.map { DieFace(value: $0) } }

    func sticker(id: String?) -> StickerDef? {
        guard let id else { return nil }
        return stickers.first { $0.id == id }
    }

    func upgrade(id: String) -> DieUpgradeDef? {
        upgrades.first { $0.id == id }
    }

    /// Whether this upgrade would change this face.
    func canApply(_ upgrade: DieUpgradeDef, to face: DieFace) -> Bool {
        switch upgrade.type {
        case .raiseFace: return face.value < maxFaceValue
        case .sticker: return upgrade.sticker != nil && face.sticker != upgrade.sticker
        }
    }

    func applying(_ upgrade: DieUpgradeDef, to face: DieFace) -> DieFace {
        guard canApply(upgrade, to: face) else { return face }
        var face = face
        switch upgrade.type {
        case .raiseFace: face.value = min(maxFaceValue, face.value + (upgrade.amount ?? 0))
        case .sticker: face.sticker = upgrade.sticker
        }
        return face
    }

    /// The upgrades that make sense for this hero: at least one face can take them, and resource
    /// stickers only for classes that have a resource.
    func offerableUpgrades(for hero: HeroState) -> [DieUpgradeDef] {
        upgrades.filter { upgrade in
            if sticker(id: upgrade.sticker)?.type == .resource, hero.maxResource == 0 { return false }
            return hero.die.contains { canApply(upgrade, to: $0) }
        }
    }

    // MARK: Resolving a landed roll

    /// Extra points from crit stickers on these faces.
    func critBonus(_ faces: [DieFace]) -> Int {
        faces.reduce(0) { sum, face in
            guard let sticker = sticker(id: face.sticker), sticker.type == .crit else { return sum }
            return sum + face.value * sticker.amount
        }
    }

    /// The landed stickers with an effect on the roller (everything but crit), in face order.
    func rollerStickers(_ faces: [DieFace]) -> [StickerDef] {
        faces.compactMap { sticker(id: $0.sticker) }.filter { $0.type != .crit }
    }
}

/// After a level-up, one hero picks one of these die upgrades, then a face (or skips) — game.md §5.
struct DieUpgradeOffer: Codable, Hashable {
    var heroID: String
    var upgradeIDs: [String]
}
