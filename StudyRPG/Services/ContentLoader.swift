import Foundation

/// A content-loading or validation failure, naming the offending file and field
/// so a bad hand edit to Content/*.json fails loudly instead of crashing deep
/// in unrelated game logic. See agents.md: "a malformed content file should fail
/// loudly and specifically."
struct ContentError: Error, CustomStringConvertible {
    let file: String
    let message: String

    var description: String { "Content error in \(file): \(message)" }
}

/// Parses `#RRGGBB` content colors into 0…1 RGB components.
nonisolated enum HexColor {
    static func parse(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

/// Loads and validates every file under Content/*.json into a single GameContent value.
/// Game code should only ever read content through this, never hard-code stats (agents.md).
enum ContentLoader {
    /// The most recently loaded content, for small display lookups.
    nonisolated(unsafe) private(set) static var loaded: GameContent?

    static func load(bundle: Bundle = .main) throws -> GameContent {
        let classesFile: ClassesFile = try decode("classes", from: bundle)
        let enemiesFile: EnemiesFile = try decode("enemies", from: bundle)
        let itemsFile: ItemsFile = try decode("items", from: bundle)
        let relicsFile: RelicsFile = try decode("relics", from: bundle)
        let encountersFile: EncountersFile = try decode("encounters", from: bundle)
        let balance: BalanceDef = try decode("balance", from: bundle)

        var content = GameContent(
            classes: classesFile.classes,
            enemies: enemiesFile.enemies,
            items: itemsFile.items,
            gear: itemsFile.gear ?? [],
            relics: relicsFile.relics,
            acts: encountersFile.acts,
            encounterPools: encountersFile.pools,
            themes: encountersFile.themes,
            events: encountersFile.events,
            balance: balance
        )

        try validate(content)
        content.starterDecks = try loadStarterDecks(bundle: bundle, minDeckSize: balance.flashcards.minDeckSize)
        loaded = content
        return content
    }

    // MARK: - Decoding

    private static func decode<T: Decodable>(_ name: String, from bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Content")
            ?? bundle.url(forResource: name, withExtension: "json") else {
            throw ContentError(file: "\(name).json", message: "file not found in bundle")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ContentError(file: "\(name).json", message: "could not read file: \(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            throw ContentError(file: "\(name).json", message: describeDecodingError(error))
        } catch {
            throw ContentError(file: "\(name).json", message: "could not decode: \(error.localizedDescription)")
        }
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "missing field \"\(key.stringValue)\" at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .typeMismatch(type, context):
            return "expected \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .valueNotFound(type, context):
            return "missing value of type \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .dataCorrupted(context):
            return "corrupted data at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return "unknown decoding error"
        }
    }

    // MARK: - Cross-file validation

    static func validate(_ content: GameContent) throws {
        try requireUniqueIDs(content.classes.map(\.id), file: "classes.json", kind: "class")
        try requireUniqueIDs(content.enemies.map(\.id), file: "enemies.json", kind: "enemy")
        try requireUniqueIDs(content.items.map(\.id), file: "items.json", kind: "item")
        try requireUniqueIDs(content.relics.map(\.id), file: "relics.json", kind: "relic")

        guard !content.acts.isEmpty else {
            throw ContentError(file: "encounters.json", message: "acts cannot be empty")
        }
        for act in content.acts {
            let actPools = content.encounterPools.filter { $0.act == act.id }
            let hasFight = actPools.contains { $0.nodeType == .fight && !$0.encounters.isEmpty }
            let hasElite = actPools.contains { $0.nodeType == .elite && !$0.encounters.isEmpty }
            let hasBoss = actPools.contains { $0.nodeType == .boss && !$0.encounters.isEmpty }
            guard hasFight && hasElite && hasBoss else {
                throw ContentError(file: "encounters.json", message: "act \"\(act.id)\" needs fight, elite and boss pools")
            }
        }
        for pool in content.encounterPools {
            guard content.acts.contains(where: { $0.id == pool.act }) else {
                throw ContentError(file: "encounters.json", message: "pool references unknown act \"\(pool.act)\"")
            }
        }

        let knownEnemyIDs = Set(content.enemies.map(\.id))
        for pool in content.encounterPools {
            for encounter in pool.encounters {
                for enemyId in encounter.enemyIds {
                    guard knownEnemyIDs.contains(enemyId) else {
                        throw ContentError(
                            file: "encounters.json",
                            message: "encounter for \(pool.nodeType.rawValue)/tier \(pool.depthTier) references unknown enemy id \"\(enemyId)\""
                        )
                    }
                }
                guard !encounter.enemyIds.isEmpty else {
                    throw ContentError(file: "encounters.json", message: "encounter for \(pool.nodeType.rawValue)/tier \(pool.depthTier) has no enemies")
                }
                guard encounter.enemyIds.count <= 3 else {
                    throw ContentError(file: "encounters.json", message: "encounter for \(pool.nodeType.rawValue)/tier \(pool.depthTier) has more than 3 enemies (see game.md §7.1)")
                }
            }
        }

        for enemy in content.enemies {
            guard enemy.attackEvery > 0 else {
                throw ContentError(file: "enemies.json", message: "enemy \"\(enemy.id)\" has non-positive attackEvery")
            }
            guard !enemy.movePattern.isEmpty else {
                throw ContentError(file: "enemies.json", message: "enemy \"\(enemy.id)\" has an empty movePattern")
            }
            if let hpDice = enemy.hpDice {
                guard hpDice.count >= 1 else {
                    throw ContentError(file: "enemies.json", message: "enemy \"\(enemy.id)\" hpDice count must be >= 1")
                }
                guard hpDice.dieSides >= 2 else {
                    throw ContentError(file: "enemies.json", message: "enemy \"\(enemy.id)\" hpDice dieSides must be >= 2")
                }
                guard hpDice.flat >= 0 else {
                    throw ContentError(file: "enemies.json", message: "enemy \"\(enemy.id)\" hpDice flat must be >= 0")
                }
            }
            guard DiceExpr.supportedSides.contains(enemy.attackDice.dieSides) else {
                throw ContentError(file: "enemies.json", message: "enemy \"\(enemy.id)\" attackDice has unsupported sides")
            }
            for skill in enemy.skills ?? [] {
                guard skill.id != EnemyDef.basicAttackID else {
                    throw ContentError(file: "enemies.json", message: "skill cannot use reserved basicAttackID")
                }
                for effect in skill.effects {
                    if effect.type == .damage && (skill.target(of: effect) == .selfEnemy || skill.target(of: effect) == .ally || skill.target(of: effect) == .allies) {
                        throw ContentError(file: "enemies.json", message: "enemy skill cannot damage self/allies")
                    }
                    if effect.type == .armor && (skill.target(of: effect) == .hero || skill.target(of: effect) == .heroes) {
                        throw ContentError(file: "enemies.json", message: "enemy skill cannot give armor to heroes")
                    }
                    let isTimed = effect.type == .armor || effect.type == .damageBuff || effect.type == .weaken || effect.type == .vulnerable
                    if isTimed && effect.rounds == nil {
                        throw ContentError(file: "enemies.json", message: "timed effect needs rounds")
                    }
                }
                let rollingEffects = skill.effects.filter { $0.dice != nil }
                guard rollingEffects.count <= 1 else {
                    throw ContentError(file: "enemies.json", message: "at most one rolling effect per skill")
                }
            }
            for move in enemy.movePattern {
                guard enemy.skill(id: move) != nil else {
                    throw ContentError(file: "enemies.json", message: "movePattern references unknown skill \"\(move)\"")
                }
            }
            for rule in enemy.allRules {
                guard enemy.skill(id: rule.skill) != nil else {
                    throw ContentError(file: "enemies.json", message: "rule references unknown skill \"\(rule.skill)\"")
                }
                if let when = rule.when {
                    if let selfHPBelow = when.selfHPBelow, selfHPBelow > 1.0 || selfHPBelow < 0.0 {
                        throw ContentError(file: "enemies.json", message: "selfHPBelow must be between 0 and 1")
                    }
                    if let allyHPBelow = when.allyHPBelow, allyHPBelow > 1.0 || allyHPBelow < 0.0 {
                        throw ContentError(file: "enemies.json", message: "allyHPBelow must be between 0 and 1")
                    }
                    if let heroHPBelow = when.heroHPBelow, heroHPBelow > 1.0 || heroHPBelow < 0.0 {
                        throw ContentError(file: "enemies.json", message: "heroHPBelow must be between 0 and 1")
                    }
                }
            }
        }

        let levels = content.balance.leveling.levels
        guard levels.first?.xp == 0 else {
            throw ContentError(file: "balance.json", message: "leveling.levels must start with level 1 at xp 0")
        }
        for (index, level) in levels.enumerated() {
            if index > 0, level.xp <= levels[index - 1].xp {
                throw ContentError(file: "balance.json", message: "thresholds must rise")
            }
        }

        // Hero dice (game.md §8 "Hero dice").
        let dice = content.balance.dice
        guard dice.startingFaces.count == DiceConfig.faceCount else {
            throw ContentError(file: "balance.json", message: "dice.startingFaces must have \(DiceConfig.faceCount) faces")
        }
        guard dice.maxFaceValue >= 1, dice.startingFaces.allSatisfy({ (1...dice.maxFaceValue).contains($0) }) else {
            throw ContentError(file: "balance.json", message: "dice.startingFaces must be between 1 and dice.maxFaceValue")
        }
        guard dice.offerCount >= 1 else {
            throw ContentError(file: "balance.json", message: "dice.offerCount must be at least 1")
        }
        guard Set(dice.stickers.map(\.id)).count == dice.stickers.count, Set(dice.upgrades.map(\.id)).count == dice.upgrades.count else {
            throw ContentError(file: "balance.json", message: "dice.stickers and dice.upgrades ids must be unique")
        }
        for sticker in dice.stickers {
            guard !sticker.symbol.isEmpty, sticker.amount > 0 else {
                throw ContentError(file: "balance.json", message: "dice sticker \"\(sticker.id)\" needs a symbol and an amount > 0")
            }
        }
        for upgrade in dice.upgrades {
            switch upgrade.type {
            case .raiseFace:
                guard (upgrade.amount ?? 0) > 0 else {
                    throw ContentError(file: "balance.json", message: "dice upgrade \"\(upgrade.id)\" needs an amount > 0")
                }
            case .sticker:
                guard dice.sticker(id: upgrade.sticker) != nil else {
                    throw ContentError(file: "balance.json", message: "dice upgrade \"\(upgrade.id)\" uses unknown sticker \"\(upgrade.sticker ?? "")\"")
                }
            }
        }

        for heroClass in content.classes {
            for starting in heroClass.startingSkills {
                guard heroClass.skill(id: starting) != nil else {
                    throw ContentError(file: "classes.json", message: "class \"\(heroClass.id)\" starts with unknown skill \"\(starting)\"")
                }
            }
            for skill in heroClass.skills {
                if let cost = skill.cost, heroClass.resource == nil {
                    throw ContentError(file: "classes.json", message: "class \"\(heroClass.id)\" skill \"\(skill.id)\" costs \(cost) but the class has no resource")
                }
                guard !skill.effects.isEmpty else {
                    throw ContentError(file: "classes.json", message: "class \"\(heroClass.id)\" skill \"\(skill.id)\" has no effects")
                }
                guard skill.actionPoints >= 1 else {
                    throw ContentError(file: "classes.json", message: "class \"\(heroClass.id)\" skill \"\(skill.id)\" needs actionPoints >= 1")
                }
                // Skill upgrades (game.md §5 "Skill upgrades"): the upgraded skill must be valid too.
                if let upgrade = skill.upgrade {
                    let where_ = "class \"\(heroClass.id)\" skill \"\(skill.id)\" upgrade"
                    guard upgrade.cost != nil || upgrade.cooldown != nil || upgrade.actionPoints != nil || upgrade.effects != nil else {
                        throw ContentError(file: "classes.json", message: "\(where_) changes nothing")
                    }
                    let upgraded = skill.upgraded()
                    if let cost = upgraded.cost, heroClass.resource == nil {
                        throw ContentError(file: "classes.json", message: "\(where_) costs \(cost) but the class has no resource")
                    }
                    guard !upgraded.effects.isEmpty, upgraded.actionPoints >= 1,
                          (upgrade.cost ?? 0) >= 0, (upgrade.cooldown ?? 0) >= 0 else {
                        throw ContentError(file: "classes.json", message: "\(where_) needs effects, actionPoints >= 1 and no negative cost or cooldown")
                    }
                }
            }
        }
    }

    private static func requireUniqueIDs(_ ids: [String], file: String, kind: String) throws {
        var seen = Set<String>()
        for id in ids {
            guard seen.insert(id).inserted else {
                throw ContentError(file: file, message: "duplicate \(kind) id \"\(id)\"")
            }
        }
    }

    // MARK: - Starter decks (game.md §4.5)

    private struct StarterDecksFile: Decodable {
        var decks: [DeckFile]
    }

    static func loadStarterDecks(bundle: Bundle = .main, minDeckSize: Int) throws -> [Deck] {
        let file: StarterDecksFile = try decode("starter_decks", from: bundle)
        return try starterDecks(from: file.decks, minDeckSize: minDeckSize)
    }

    static func starterDecks(from files: [DeckFile], minDeckSize: Int) throws -> [Deck] {
        let fileName = "starter_decks.json"
        try requireUniqueIDs(files.map(\.id), file: fileName, kind: "deck")
        return try files.map { deckFile in
            let where_ = "deck \"\(deckFile.id)\""
            guard deckFile.format == DeckFile.formatName, deckFile.version <= DeckFile.currentVersion else {
                throw ContentError(file: fileName, message: "\(where_) must be format \"\(DeckFile.formatName)\" version ≤ \(DeckFile.currentVersion)")
            }
            guard !deckFile.id.isEmpty, !deckFile.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ContentError(file: fileName, message: "\(where_) needs an id and a name")
            }
            if let color = deckFile.color, HexColor.parse(color) == nil {
                throw ContentError(file: fileName, message: "\(where_) color \"\(color)\" is not #RRGGBB")
            }
            try requireUniqueIDs(deckFile.cards.map(\.id), file: fileName, kind: "card (\(where_))")
            guard deckFile.cards.count >= minDeckSize else {
                throw ContentError(file: fileName, message: "\(where_) has \(deckFile.cards.count) cards; a run needs at least \(minDeckSize)")
            }
            // Bundled decks are content: their texts come in the current language (game.md §4.5, §13
            // "Localization"). Once added they are the player's own decks and don't change language.
            let text = { (english: String?) in english.map(Localization.shared.content) }
            let cards = try deckFile.cards.map { card -> Flashcard in
                func face(_ source: DeckFile.Face, _ label: String) throws -> CardFace {
                    guard source.image == nil else {
                        throw ContentError(file: fileName, message: "\(where_) card \"\(card.id)\" \(label) uses an image; bundled decks only support text, symbol and color")
                    }
                    if let color = source.color, HexColor.parse(color) == nil {
                        throw ContentError(file: fileName, message: "\(where_) card \"\(card.id)\" \(label) color \"\(color)\" is not #RRGGBB")
                    }
                    return CardFace(text: text(source.text), symbol: source.symbol, color: source.color)
                }
                let flashcard = Flashcard(
                    id: UUID.stable("\(deckFile.id)/\(card.id)"),
                    question: try face(card.question, "question"),
                    answer: try face(card.answer, "answer"),
                    wrongAnswers: try (card.wrongAnswers ?? []).enumerated().map { try face($0.element, "wrong answer \($0.offset + 1)") },
                    prompt: text(card.prompt),
                    hint: text(card.hint),
                    explanation: text(card.explanation),
                    reversible: card.reversible
                )
                if let issue = flashcard.validationIssues.first {
                    throw ContentError(file: fileName, message: "\(where_) card \"\(card.id)\": \(issue)")
                }
                return flashcard
            }
            return Deck(
                id: UUID.stable("deck/\(deckFile.id)"),
                name: Localization.shared.content(deckFile.name),
                cards: cards,
                subtitle: text(deckFile.subtitle),
                icon: deckFile.icon,
                color: deckFile.color,
                reverseCards: deckFile.reverseCards,
                sourceID: deckFile.id
            )
        }
    }
}
