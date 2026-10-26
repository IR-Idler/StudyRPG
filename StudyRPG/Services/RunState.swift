import Foundation
import Observation
import SwiftUI
import CryptoKit

// MARK: - RunState (game.md §3, §9-12)

/// One run: the map, where the party is on it, and everything carried between nodes — hero HP /
/// mana / skills / gear, gold, potions, relics, the gear bag, campfire training — plus the recap
/// tallies. Anything random that a node offers (fight rewards, shop stock, the event and its
/// outcome, skill offers) is rolled once and saved immediately, so closing the app can never
/// re-roll or replay it (game.md §3).
@Observable
final class RunState: Identifiable {
    let id = UUID()
    let content: GameContent
    /// The current act's map; replaced by a new one when the act's boss falls (game.md §16).
    private(set) var map: GameMap
    /// Index into `content.acts` (game.md §16).
    private(set) var actIndex: Int
    let flashcards: FlashcardSession
    private(set) var currentNodeID: Int?
    private(set) var visitedNodeIDs: Set<Int>
    private(set) var heroes: [HeroState]
    private(set) var gold: Int
    private(set) var inventory: [ItemDef]
    private(set) var relics: [RelicDef]
    /// Gear the party carries but nobody wears (game.md §6).
    private(set) var gearBag: [GearDef]
    /// Campfire "Train" stacks: +damage on every hero damage roll (game.md §11).
    private(set) var trainedDamageBonus: Int
    private(set) var stats: RunStats
    private(set) var isComplete = false
    private(set) var isFailed = false
    /// A won fight's skill offer waiting for the player's pick (game.md §5).
    private(set) var pendingSkillOffer: SkillOffer?
    /// Level-up die upgrades waiting for the player's pick, first one shown first (game.md §5 "Levels").
    private(set) var pendingDieUpgrades: [DieUpgradeOffer] = []

    private var encounterCache: [Int: EncounterDef]
    private var rewardCache: [Int: RunSnapshot.Reward]
    private var shopCache: [Int: RunSnapshot.Shop]
    private var eventCache: [Int: RunSnapshot.Event]
    /// When the run began (nil for runs saved before the run history existed).
    @ObservationIgnored private let startedAt: Date?
    /// Answers from earlier app sessions of this run (the session counter restarts at 0 on resume).
    @ObservationIgnored private let baseCardsAnswered: Int
    @ObservationIgnored private let baseCardsCorrect: Int

    private var balance: BalanceDef { content.balance }

    /// A brand-new run (game.md §3): fresh heroes, starting gold, empty bag, new map.
    init(content: GameContent, heroClasses: [HeroClassDef], decks: [Deck], statsStore: CardStatsStore) {
        var rng = SystemRandomNumberGenerator()
        self.content = content
        self.map = MapGenerator.generate(config: content.balance.map, using: &rng)
        self.actIndex = 0
        self.flashcards = FlashcardSession(decks: decks, statsStore: statsStore, balance: content.balance)
        self.visitedNodeIDs = []
        self.heroes = heroClasses.map { classDef in
            var hero = HeroState(classDef: classDef, hp: classDef.maxHP, resource: classDef.resource?.start ?? 0)
            hero.die = content.balance.dice.startingDie
            return hero
        }
        self.gold = content.balance.startingGold
        self.inventory = []
        self.relics = []
        self.gearBag = []
        self.trainedDamageBonus = 0
        self.stats = RunStats()
        self.encounterCache = [:]
        self.rewardCache = [:]
        self.shopCache = [:]
        self.eventCache = [:]
        self.startedAt = Date()
        self.baseCardsAnswered = 0
        self.baseCardsCorrect = 0
        flashcards.runID = id
        DiscoveryStore.record(heroes.flatMap(\.knownSkillIDs), in: \.skills)
        save()
    }

    /// Resumes a saved run. Returns nil if the save references content that no longer exists.
    init?(snapshot: RunSnapshot, content: GameContent, decks: [Deck], statsStore: CardStatsStore) {
        let maxEquipped = content.balance.skills.maxEquipped
        var heroes: [HeroState] = []
        for saved in snapshot.heroes {
            guard let classDef = content.classDef(id: saved.classID) else { return nil }
            var hero = HeroState(classDef: classDef, hp: saved.hp, resource: saved.resource)
            hero.bonusMaxHP = saved.bonusMaxHP
            hero.xp = saved.xp ?? 0
            let known = (saved.knownSkillIDs ?? classDef.startingSkills).filter { classDef.skill(id: $0) != nil }
            hero.knownSkillIDs = known.isEmpty ? classDef.startingSkills : known
            let loadout = (saved.loadoutSkillIDs ?? hero.knownSkillIDs).filter { hero.knownSkillIDs.contains($0) }
            hero.loadoutSkillIDs = Array((loadout.isEmpty ? classDef.startingSkills : loadout).prefix(maxEquipped))
            hero.gear = (saved.gearIDs ?? []).compactMap { content.gearDef(id: $0) }
            // A save from before hero dice (or with a broken die) gets the starting die.
            let dice = content.balance.dice
            if let die = saved.die, die.count == DiceConfig.faceCount,
               die.allSatisfy({ $0.sticker == nil || dice.sticker(id: $0.sticker) != nil }) {
                hero.die = die
            } else {
                hero.die = dice.startingDie
            }
            let upgradable = Set(hero.upgradableSkills.map(\.id))
            hero.upgradedSkillIDs = (saved.upgradedSkillIDs ?? []).filter { upgradable.contains($0) }
            heroes.append(hero)
        }
        self.content = content
        self.map = snapshot.map
        self.actIndex = min(max(0, snapshot.actIndex ?? 0), max(0, content.acts.count - 1))
        self.flashcards = FlashcardSession(decks: decks, statsStore: statsStore, balance: content.balance)
        self.currentNodeID = snapshot.currentNodeID
        self.visitedNodeIDs = snapshot.visitedNodeIDs
        self.heroes = heroes
        self.gold = snapshot.gold
        self.inventory = snapshot.inventoryIDs.compactMap { content.itemDef(id: $0) }
        self.relics = snapshot.relicIDs.compactMap { content.relicDef(id: $0) }
        self.gearBag = (snapshot.gearBagIDs ?? []).compactMap { content.gearDef(id: $0) }
        // Old saves stored training as bonus dice (1 per Train): each stack becomes +damage.
        self.trainedDamageBonus = snapshot.trainedDamageBonus ?? snapshot.trainedBonusDice * content.balance.campfire.trainDamageBonus
        self.stats = snapshot.stats
        self.baseCardsAnswered = snapshot.stats.cardsAnswered
        self.baseCardsCorrect = snapshot.stats.cardsCorrect
        self.encounterCache = snapshot.encounters
        self.rewardCache = snapshot.rewards ?? [:]
        self.shopCache = snapshot.shops ?? [:]
        self.eventCache = snapshot.events ?? [:]
        self.pendingSkillOffer = snapshot.pendingSkillOffer
        self.pendingDieUpgrades = (snapshot.pendingDieUpgrades ?? []).filter { offer in
            heroes.contains { $0.id == offer.heroID }
        }
        self.startedAt = snapshot.startedAt
        flashcards.runID = id
        // Runs saved before discoveries existed still reveal what the party already has.
        DiscoveryStore.record(heroes.flatMap(\.knownSkillIDs), in: \.skills)
        DiscoveryStore.record(inventory.map(\.id), in: \.potions)
        DiscoveryStore.record(relics.map(\.id), in: \.relics)
        DiscoveryStore.record((gearBag + heroes.flatMap(\.gear)).map(\.id), in: \.gear)
    }

    var isOver: Bool { isComplete || isFailed }

    // MARK: Acts (game.md §16)

    /// The act the party is in now.
    var act: ActDef { content.acts[min(actIndex, content.acts.count - 1)] }
    var isLastAct: Bool { actIndex >= content.acts.count - 1 }

    /// The act's boss fell and another act follows: a fresh map for it. Everything the party
    /// carries stays; only the map and what its places had rolled are new.
    private func startNextAct() {
        var rng = SystemRandomNumberGenerator()
        actIndex += 1
        map = MapGenerator.generate(config: balance.map, using: &rng)
        currentNodeID = nil
        visitedNodeIDs = []
        encounterCache = [:]
        rewardCache = [:]
        shopCache = [:]
        eventCache = [:]
        pendingSkillOffer = nil
        save()
    }

    /// Cards answered right this run, out of all answered (for the recap).
    var cardAccuracy: (correct: Int, answered: Int) { (stats.cardsCorrect, stats.cardsAnswered) }

    // MARK: Map navigation

    var reachableNodeIDs: [Int] { map.reachableNodeIDs(from: currentNodeID) }
    func isReachable(_ nodeID: Int) -> Bool {
        !isOver && pendingSkillOffer == nil && pendingDieUpgrades.isEmpty && reachableNodeIDs.contains(nodeID)
    }

    /// Marks a node done and moves the party onto it.
    private func complete(_ nodeID: Int) {
        visitedNodeIDs.insert(nodeID)
        currentNodeID = nodeID
        syncFlashcardStats()
        if isOver {
            RunStore.delete()
        } else {
            save()
        }
    }

    /// Tells the answer log where the next answers happen (game.md §4.2 run context).
    func enterNode(_ nodeID: Int) {
        flashcards.nodeDepth = map.node(nodeID)?.row
    }

    // MARK: Fights (game.md §7)

    /// The encounter (enemies + theme) a fight/elite/boss node uses — rolled once and saved.
    func encounter(for nodeID: Int) -> EncounterDef? {
        if let cached = encounterCache[nodeID] { return cached }
        guard let node = map.node(nodeID) else { return nil }
        let tier = MapGenerator.depthTier(forRow: node.row, rowCount: balance.map.rowCount)
        let pools = content.encounterPools.filter { $0.act == act.id }
        let pool = pools.first { $0.nodeType == node.type && $0.depthTier == tier }
            ?? pools.first { $0.nodeType == node.type }
        guard let encounter = pool?.encounters.randomElement() else { return nil }
        encounterCache[nodeID] = encounter
        save()
        return encounter
    }

    /// The victory reward of a fight node — rolled once and saved (game.md §7.5).
    func reward(for nodeID: Int) -> NodeReward? {
        if let saved = rewardCache[nodeID] { return resolve(saved) }
        guard let node = map.node(nodeID), let encounter = encounter(for: nodeID) else { return nil }
        let enemyDefs = encounter.enemyIds.compactMap { content.enemyDef(id: $0) }
        var saved = RunSnapshot.Reward(gold: enemyDefs.reduce(0) { $0 + $1.goldReward })
        let isBig = node.type == .elite || node.type == .boss
        if node.type == .elite {
            if let relic = randomUnownedRelics(count: 1).first {
                saved.relicID = relic.id
            } else {
                saved.gold += balance.rewards.relicFallbackGold
            }
        }
        if isBig, Double.random(in: 0..<1) < balance.rewards.bonusPotionChance {
            saved.potionID = content.items.randomElement()?.id
        }
        if Double.random(in: 0..<1) < (isBig ? balance.rewards.eliteGearChance : balance.rewards.fightGearChance) {
            saved.gearID = randomGear()?.id
        }
        // Only elites teach a skill (game.md §5); normal fights and the boss don't.
        if node.type == .elite {
            saved.skillOffer = makeSkillOffer()
        }
        rewardCache[nodeID] = saved
        save()
        return resolve(saved)
    }

    private func resolve(_ saved: RunSnapshot.Reward) -> NodeReward {
        NodeReward(
            gold: saved.gold,
            relic: saved.relicID.flatMap { content.relicDef(id: $0) },
            potion: saved.potionID.flatMap { content.itemDef(id: $0) },
            gear: saved.gearID.flatMap { content.gearDef(id: $0) },
            skillOffer: saved.skillOffer
        )
    }

    /// Builds the fight for a node plus its pre-rolled victory reward. Campfire training is
    /// applied as +damage on every hero damage roll.
    func startFight(at nodeID: Int) -> (engine: CombatEngine, reward: NodeReward, theme: FightThemeDef?)? {
        guard let encounter = encounter(for: nodeID), let reward = reward(for: nodeID) else { return nil }
        let enemyDefs = encounter.enemyIds.compactMap { content.enemyDef(id: $0) }
        guard !enemyDefs.isEmpty else { return nil }
        enterNode(nodeID)
        DiscoveryStore.record(enemyDefs.map(\.id), in: \.enemies)

        var fightHeroes = heroes
        for index in fightHeroes.indices {
            fightHeroes[index].trainingDamageBonus = trainedDamageBonus
        }
        let engine = CombatEngine(
            heroes: fightHeroes,
            enemyDefs: enemyDefs,
            balance: balance,
            flashcards: flashcards,
            relics: relics,
            inventory: inventory
        )
        return (engine, reward, content.theme(id: encounter.theme))
    }

    /// Folds a finished fight back into the run: HP/mana, drunk potions, and — on victory — the reward.
    func finishFight(at nodeID: Int, engine: CombatEngine, reward: NodeReward) {
        heroes = zip(heroes, engine.heroes).map { runHero, fightHero in
            var hero = runHero
            hero.hp = fightHero.hp
            hero.resource = fightHero.resource
            return hero
        }
        inventory = engine.inventory
        switch engine.phase {
        case .victory:
            // Fallen heroes get back up at half their max HP after a won fight.
            for index in heroes.indices where !heroes[index].isAlive {
                heroes[index].hp = max(1, heroes[index].maxHP / 2)
            }
            stats.fightsWon += 1
            // Every hero gains the fight's experience, fallen or not (game.md §5 "Levels").
            let xp = Self.experience(for: engine)
            for index in heroes.indices {
                let before = leveling.level(forXP: heroes[index].xp)
                heroes[index].xp += xp
                // Every level gained offers a die upgrade (game.md §5 "Levels").
                for _ in before..<leveling.level(forXP: heroes[index].xp) {
                    if let offer = makeDieUpgradeOffer(heroAt: index) { pendingDieUpgrades.append(offer) }
                }
            }
            if map.node(nodeID)?.type == .elite { stats.elitesWon = (stats.elitesWon ?? 0) + 1 }
            addGold(reward.gold)
            if let relic = reward.relic { gainRelic(relic) }
            if let potion = reward.potion { gainPotion(potion) }
            if let gear = reward.gear { gearBag.append(gear) }
            discover(relic: reward.relic, potion: reward.potion, gear: reward.gear)
            if let offer = reward.skillOffer, nodeID != map.bossNodeID {
                DiscoveryStore.record(offer.allSkillIDs, in: \.skills)
            }
            if nodeID == map.bossNodeID {
                // The last act's boss wins the run; an earlier one leads to the next act.
                if isLastAct { isComplete = true }
            } else {
                pendingSkillOffer = reward.skillOffer
            }
        case .defeat:
            isFailed = true
        default:
            return
        }
        rewardCache[nodeID] = nil
        let advancesAct = engine.phase == .victory && nodeID == map.bossNodeID && !isLastAct
        complete(nodeID)
        if advancesAct { startNextAct() }
        if isOver {
            recordHistory(isComplete ? .victory : .defeat, defeatedBy: isFailed ? (encounterCache[nodeID]?.enemyIds ?? []) : [])
        }
    }

    // MARK: Levels (game.md §5 "Levels")

    /// What winning this fight is worth to each hero: the sum of its enemies' `xp`.
    static func experience(for engine: CombatEngine) -> Int {
        engine.enemies.reduce(0) { $0 + $1.def.xp }
    }

    var leveling: LevelingConfig { content.balance.leveling }

    /// `dice.offerCount` random upgrades that fit this hero's die.
    private func makeDieUpgradeOffer(heroAt index: Int) -> DieUpgradeOffer? {
        let options = balance.dice.offerableUpgrades(for: heroes[index])
        guard !options.isEmpty else { return nil }
        return DieUpgradeOffer(heroID: heroes[index].id,
                               upgradeIDs: options.shuffled().prefix(balance.dice.offerCount).map(\.id))
    }

    /// Applies one upgrade of the first pending offer to one face of that hero's die.
    func applyDieUpgrade(_ upgradeID: String, toFace faceIndex: Int) {
        guard let offer = pendingDieUpgrades.first, offer.upgradeIDs.contains(upgradeID),
              let upgrade = balance.dice.upgrade(id: upgradeID),
              let index = heroes.firstIndex(where: { $0.id == offer.heroID }),
              heroes[index].die.indices.contains(faceIndex),
              balance.dice.canApply(upgrade, to: heroes[index].die[faceIndex]) else { return }
        heroes[index].die[faceIndex] = balance.dice.applying(upgrade, to: heroes[index].die[faceIndex])
        pendingDieUpgrades.removeFirst()
        save()
    }

    func skipDieUpgrade() {
        guard !pendingDieUpgrades.isEmpty else { return }
        pendingDieUpgrades.removeFirst()
        save()
    }

    // MARK: Skills (game.md §5)

    /// For every hero who doesn't know their whole class yet: up to `skills.offerCount` of the
    /// skills they don't know. nil if nobody can learn anything.
    private func makeSkillOffer() -> SkillOffer? {
        var choices: [String: [String]] = [:]
        for hero in heroes {
            let unknown = hero.classDef.skills.map(\.id).filter { !hero.knownSkillIDs.contains($0) }
            guard !unknown.isEmpty else { continue }
            choices[hero.id] = Array(unknown.shuffled().prefix(balance.skills.offerCount))
        }
        return choices.isEmpty ? nil : SkillOffer(choices: choices)
    }

    /// Whether any hero still has a skill to learn (a scroll would offer something).
    var canLearnSkills: Bool {
        heroes.contains { hero in hero.classDef.skills.contains { !hero.knownSkillIDs.contains($0.id) } }
    }

    var maxEquippedSkills: Int { balance.skills.maxEquipped }

    /// Learns one skill from the pending offer. With a full loadout, `replacing` names the equipped
    /// skill it swaps out (nil = learn it but keep the loadout as is).
    func learnSkill(_ skillID: String, heroID: String, replacing: String?) {
        guard let offer = pendingSkillOffer, offer.choices[heroID]?.contains(skillID) == true,
              let index = heroes.firstIndex(where: { $0.id == heroID }) else { return }
        if !heroes[index].knownSkillIDs.contains(skillID) {
            heroes[index].knownSkillIDs.append(skillID)
        }
        if heroes[index].loadoutSkillIDs.count < maxEquippedSkills {
            heroes[index].loadoutSkillIDs.append(skillID)
        } else if let replacing, let slot = heroes[index].loadoutSkillIDs.firstIndex(of: replacing) {
            heroes[index].loadoutSkillIDs[slot] = skillID
        }
        pendingSkillOffer = nil
        save()
    }

    func skipSkillOffer() {
        pendingSkillOffer = nil
        save()
    }

    /// Equips or unequips a known skill outside of fights (1…maxEquipped equipped).
    func toggleLoadout(heroAt index: Int, skillID: String) {
        guard heroes.indices.contains(index), heroes[index].knownSkillIDs.contains(skillID) else { return }
        if let slot = heroes[index].loadoutSkillIDs.firstIndex(of: skillID) {
            guard heroes[index].loadoutSkillIDs.count > 1 else { return }
            heroes[index].loadoutSkillIDs.remove(at: slot)
        } else {
            guard heroes[index].loadoutSkillIDs.count < maxEquippedSkills else { return }
            heroes[index].loadoutSkillIDs.append(skillID)
        }
        save()
    }

    // MARK: Gear (game.md §6)

    func canWear(_ gear: GearDef, heroAt index: Int) -> Bool {
        heroes.indices.contains(index) && (gear.classId == nil || gear.classId == heroes[index].classDef.id)
    }

    /// Moves gear from the bag onto a hero; whatever was in that slot goes back to the bag.
    func equip(_ gear: GearDef, heroAt index: Int) {
        guard canWear(gear, heroAt: index), let bagSlot = gearBag.firstIndex(of: gear) else { return }
        gearBag.remove(at: bagSlot)
        if let worn = heroes[index].gear(in: gear.slot) {
            heroes[index].gear.removeAll { $0 == worn }
            gearBag.append(worn)
        }
        heroes[index].gear.append(gear)
        clampHP(heroAt: index)
        save()
    }

    func unequip(_ slot: GearSlot, heroAt index: Int) {
        guard heroes.indices.contains(index), let worn = heroes[index].gear(in: slot) else { return }
        heroes[index].gear.removeAll { $0 == worn }
        gearBag.append(worn)
        clampHP(heroAt: index)
        save()
    }

    private func clampHP(heroAt index: Int) {
        heroes[index].hp = min(heroes[index].hp, heroes[index].maxHP)
    }

    /// A random piece of gear at least one party member can wear.
    private func randomGear() -> GearDef? {
        let classIDs = Set(heroes.map(\.classDef.id))
        return content.gear.filter { $0.classId == nil || classIDs.contains($0.classId!) }.randomElement()
    }

    // MARK: Gains & losses

    private func addGold(_ amount: Int) {
        gold += amount
        stats.goldEarned += amount
    }

    /// Adds a potion; a full bag converts it to gold instead (game.md §6). Returns false if converted.
    @discardableResult
    func gainPotion(_ item: ItemDef) -> Bool {
        if inventory.count >= balance.maxPotionsCarried {
            addGold(balance.fullBagGoldConversion)
            return false
        }
        inventory.append(item)
        return true
    }

    func gainRelic(_ relic: RelicDef) {
        guard !relics.contains(where: { $0.id == relic.id }) else { return }
        relics.append(relic)
        if relic.effect.type == .maxHPBonus {
            raiseMaxHP(by: relic.effect.amount)
        }
    }

    private func raiseMaxHP(by amount: Int) {
        for index in heroes.indices {
            heroes[index].bonusMaxHP += amount
            if heroes[index].isAlive { heroes[index].hp += amount }
        }
    }

    func randomUnownedRelics(count: Int) -> [RelicDef] {
        let owned = Set(relics.map(\.id))
        return Array(content.relics.filter { !owned.contains($0.id) }.shuffled().prefix(count))
    }

    // MARK: Shop (game.md §10)

    /// This shop node's stock and haggle state, rolled once per node and saved.
    func shop(for nodeID: Int) -> RunSnapshot.Shop {
        if let cached = shopCache[nodeID] { return cached }
        let relicCount = Int.random(in: balance.shop.relicsMin...balance.shop.relicsMax)
        let gearCount = Int.random(in: balance.shop.gearMin...balance.shop.gearMax)
        let classIDs = Set(heroes.map(\.classDef.id))
        let gearStock = content.gear.filter { $0.classId == nil || classIDs.contains($0.classId!) }.shuffled().prefix(gearCount)
        let shop = RunSnapshot.Shop(relicIDs: randomUnownedRelics(count: relicCount).map(\.id), gearIDs: gearStock.map(\.id))
        shopCache[nodeID] = shop
        // Every potion is always on the shelf; relics and gear as rolled.
        DiscoveryStore.record(content.items.map(\.id), in: \.potions)
        DiscoveryStore.record(shop.relicIDs, in: \.relics)
        DiscoveryStore.record(shop.gearIDs, in: \.gear)
        save()
        return shop
    }

    func shopRelics(for nodeID: Int) -> [RelicDef] { shop(for: nodeID).relicIDs.compactMap { content.relicDef(id: $0) } }
    func shopGear(for nodeID: Int) -> [GearDef] { shop(for: nodeID).gearIDs.compactMap { content.gearDef(id: $0) } }
    func isSold(_ id: String, at nodeID: Int) -> Bool { shop(for: nodeID).soldIDs.contains(id) }
    /// nil = not haggled yet; true = won (discount), false = lost (surcharge).
    func haggleResult(at nodeID: Int) -> Bool? { shop(for: nodeID).haggleWon }
    func hasHaggled(at nodeID: Int) -> Bool { shop(for: nodeID).haggled }

    func recordHaggle(at nodeID: Int, won: Bool) {
        var state = shop(for: nodeID)
        guard !state.haggled else { return }
        state.haggled = true
        state.haggleWon = won
        shopCache[nodeID] = state
        save()
    }

    private func markSold(_ id: String, at nodeID: Int) {
        var state = shop(for: nodeID)
        state.soldIDs.append(id)
        shopCache[nodeID] = state
    }

    /// Price after this visit's haggle: nil = no haggle, true = won (discount), false = lost (surcharge).
    func price(_ base: Int, haggleWon: Bool?) -> Int {
        switch haggleWon {
        case .none: return base
        case .some(true): return max(1, Int((Double(base) * (1 - balance.shop.haggleDiscount)).rounded()))
        case .some(false): return Int((Double(base) * (1 + balance.shop.haggleSurcharge)).rounded())
        }
    }

    func price(_ base: Int, at nodeID: Int) -> Int { price(base, haggleWon: haggleResult(at: nodeID)) }

    var isBagFull: Bool { inventory.count >= balance.maxPotionsCarried }

    /// Whether a consumable item in `inventory` can be used right now outside combat.
    func canUsePotionOutsideCombat(_ item: ItemDef, onHeroIndex heroIndex: Int) -> Bool {
        guard heroes.indices.contains(heroIndex), heroes[heroIndex].isAlive else { return false }
        switch item.effect.type {
        case .heal:
            return heroes[heroIndex].hp < heroes[heroIndex].maxHP
        case .resource:
            let maxRes = heroes[heroIndex].maxResource
            return maxRes > 0 && heroes[heroIndex].resource < maxRes
        case .bonusDice:
            return false
        }
    }

    /// Uses the potion at `inventoryIndex` on `heroIndex` outside combat (e.g. a Health Potion from the bag).
    @discardableResult
    func usePotionOutsideCombat(at inventoryIndex: Int, onHeroIndex heroIndex: Int) -> Bool {
        guard inventory.indices.contains(inventoryIndex) else { return false }
        let item = inventory[inventoryIndex]
        guard canUsePotionOutsideCombat(item, onHeroIndex: heroIndex) else { return false }
        switch item.effect.type {
        case .heal:
            heroes[heroIndex].hp = min(heroes[heroIndex].maxHP, heroes[heroIndex].hp + item.fixedHealAmount)
        case .resource:
            let amount = item.effect.amount ?? 0
            heroes[heroIndex].resource = min(heroes[heroIndex].maxResource, heroes[heroIndex].resource + amount)
        case .bonusDice:
            return false
        }
        inventory.remove(at: inventoryIndex)
        save()
        return true
    }

    func buyPotion(_ item: ItemDef, at nodeID: Int) -> Bool {
        let cost = price(item.cost, at: nodeID)
        guard gold >= cost, !isBagFull else { return false }
        gold -= cost
        stats.goldSpent = (stats.goldSpent ?? 0) + cost
        inventory.append(item)
        save()
        return true
    }

    func buyRelic(_ relic: RelicDef, at nodeID: Int) -> Bool {
        let cost = price(relic.cost, at: nodeID)
        guard gold >= cost, !isSold(relic.id, at: nodeID), !relics.contains(where: { $0.id == relic.id }) else { return false }
        gold -= cost
        stats.goldSpent = (stats.goldSpent ?? 0) + cost
        gainRelic(relic)
        markSold(relic.id, at: nodeID)
        save()
        return true
    }

    func buyGear(_ gear: GearDef, at nodeID: Int) -> Bool {
        let cost = price(gear.cost, at: nodeID)
        guard gold >= cost, !isSold(gear.id, at: nodeID) else { return false }
        gold -= cost
        stats.goldSpent = (stats.goldSpent ?? 0) + cost
        gearBag.append(gear)
        markSold(gear.id, at: nodeID)
        save()
        return true
    }

    func isScrollSold(at nodeID: Int) -> Bool { shop(for: nodeID).scrollSold == true }

    /// Buys the shop's skill scroll: a skill offer opens right away (game.md §10).
    func buySkillScroll(at nodeID: Int) -> Bool {
        let cost = price(balance.shop.skillScrollCost, at: nodeID)
        guard gold >= cost, !isScrollSold(at: nodeID), pendingSkillOffer == nil, let offer = makeSkillOffer() else { return false }
        gold -= cost
        stats.goldSpent = (stats.goldSpent ?? 0) + cost
        pendingSkillOffer = offer
        DiscoveryStore.record(offer.allSkillIDs, in: \.skills)
        var state = shop(for: nodeID)
        state.scrollSold = true
        shopCache[nodeID] = state
        save()
        return true
    }

    func leave(_ nodeID: Int) {
        shopCache[nodeID] = nil
        eventCache[nodeID] = nil
        complete(nodeID)
    }

    // MARK: Campfire (game.md §11)

    /// Rest: every hero heals `campfire.restHeal`.
    func rest(at nodeID: Int) {
        for index in heroes.indices {
            heroes[index].hp = min(heroes[index].maxHP, heroes[index].hp + balance.campfire.restHeal)
        }
        complete(nodeID)
    }

    /// Train: +`campfire.trainDamageBonus` on every hero damage roll for the rest of the run.
    func train(at nodeID: Int) {
        trainedDamageBonus += balance.campfire.trainDamageBonus
        complete(nodeID)
    }

    /// Study: one hero's known skill becomes its upgraded version for the rest of the run
    /// (game.md §5 "Skill upgrades", §11).
    func study(heroAt index: Int, skillID: String, at nodeID: Int) {
        guard heroes.indices.contains(index), heroes[index].upgradableSkills.contains(where: { $0.id == skillID }) else { return }
        heroes[index].upgradedSkillIDs.append(skillID)
        complete(nodeID)
    }

    // MARK: Events (game.md §12)

    /// What an event outcome actually did, for the result screen.
    struct AppliedOutcome {
        var type: EventOutcomeType
        var amount: Int
        var relic: RelicDef?
        var potion: ItemDef?
        var gear: GearDef?
        /// A potion or relic that couldn't be given and became gold instead.
        var convertedToGold = false
    }

    /// The event at this node — rolled once and saved.
    func event(for nodeID: Int) -> EventDef? {
        if let cached = eventCache[nodeID] { return content.event(id: cached.eventID) }
        guard let event = content.events.randomElement() else { return nil }
        eventCache[nodeID] = RunSnapshot.Event(eventID: event.id)
        save()
        return event
    }

    /// The outcome already decided at this node (after resuming the app), if any.
    func eventResult(at nodeID: Int) -> (correct: Bool, applied: AppliedOutcome)? {
        guard let saved = eventCache[nodeID]?.outcome else { return nil }
        return (saved.correct, AppliedOutcome(
            type: saved.type,
            amount: saved.amount,
            relic: saved.relicID.flatMap { content.relicDef(id: $0) },
            potion: saved.potionID.flatMap { content.itemDef(id: $0) },
            gear: saved.gearID.flatMap { content.gearDef(id: $0) },
            convertedToGold: saved.convertedToGold
        ))
    }

    /// Applies the event's reward (right) or penalty (wrong) — exactly once per node.
    func resolveEvent(at nodeID: Int, correct: Bool) -> AppliedOutcome? {
        if let done = eventResult(at: nodeID) { return done.applied }
        guard let event = event(for: nodeID) else { return nil }
        let applied = applyEvent(correct ? event.reward : event.penalty)
        discover(relic: applied.relic, potion: applied.potion, gear: applied.gear)
        eventCache[nodeID]?.outcome = RunSnapshot.Event.Outcome(
            correct: correct, type: applied.type, amount: applied.amount,
            relicID: applied.relic?.id, potionID: applied.potion?.id, gearID: applied.gear?.id,
            convertedToGold: applied.convertedToGold
        )
        save()
        return applied
    }

    private func applyEvent(_ outcome: EventOutcomeDef) -> AppliedOutcome {
        let amount = outcome.amount ?? 0
        var applied = AppliedOutcome(type: outcome.type, amount: amount)
        switch outcome.type {
        case .gold:
            addGold(amount)
        case .potion:
            if let item = content.items.randomElement() {
                applied.potion = item
                if !gainPotion(item) {
                    applied.convertedToGold = true
                    applied.amount = balance.fullBagGoldConversion
                }
            }
        case .relic:
            if let relic = randomUnownedRelics(count: 1).first {
                applied.relic = relic
                gainRelic(relic)
            } else {
                applied.convertedToGold = true
                applied.amount = balance.rewards.relicFallbackGold
                addGold(applied.amount)
            }
        case .gear:
            if let gear = randomGear() {
                applied.gear = gear
                gearBag.append(gear)
            }
        case .heal:
            for index in heroes.indices where heroes[index].isAlive {
                heroes[index].hp = min(heroes[index].maxHP, heroes[index].hp + amount)
            }
        case .maxHP:
            raiseMaxHP(by: amount)
        case .loseHP:
            for index in heroes.indices where heroes[index].isAlive {
                heroes[index].hp = max(1, heroes[index].hp - amount)
            }
        case .loseGold:
            applied.amount = min(gold, amount)
            gold -= applied.amount
        }
        return applied
    }

    // MARK: Discoveries (game.md §16.1)

    /// Marks found things for the Glossary.
    private func discover(relic: RelicDef?, potion: ItemDef?, gear: GearDef?) {
        if let relic { DiscoveryStore.record([relic.id], in: \.relics) }
        if let potion { DiscoveryStore.record([potion.id], in: \.potions) }
        if let gear { DiscoveryStore.record([gear.id], in: \.gear) }
    }

    // MARK: Persistence

    private func syncFlashcardStats() {
        stats.cardsAnswered = baseCardsAnswered + flashcards.answered
        stats.cardsCorrect = baseCardsCorrect + flashcards.correct
    }

    var snapshot: RunSnapshot {
        RunSnapshot(
            map: map,
            currentNodeID: currentNodeID,
            visitedNodeIDs: visitedNodeIDs,
            heroes: heroes.map {
                RunSnapshot.Hero(
                    classID: $0.classDef.id,
                    hp: $0.hp,
                    resource: $0.resource,
                    bonusMaxHP: $0.bonusMaxHP,
                    xp: $0.xp,
                    knownSkillIDs: $0.knownSkillIDs,
                    loadoutSkillIDs: $0.loadoutSkillIDs,
                    gearIDs: $0.gear.map(\.id),
                    die: $0.die,
                    upgradedSkillIDs: $0.upgradedSkillIDs
                )
            },
            gold: gold,
            inventoryIDs: inventory.map(\.id),
            relicIDs: relics.map(\.id),
            trainedBonusDice: 0,
            deckIDs: flashcards.decks.map(\.id),
            encounters: encounterCache,
            stats: stats,
            gearBagIDs: gearBag.map(\.id),
            rewards: rewardCache,
            shops: shopCache,
            events: eventCache,
            pendingSkillOffer: pendingSkillOffer,
            skillOfferCount: nil,
            pendingDieUpgrades: pendingDieUpgrades,
            startedAt: startedAt,
            trainedDamageBonus: trainedDamageBonus,
            actIndex: actIndex
        )
    }

    func save() {
        guard !isOver else { return }
        syncFlashcardStats()
        RunStore.save(snapshot)
    }

    /// Permadeath: abandoning throws the run away (game.md §3).
    func abandon() {
        guard !isOver else { return }
        isFailed = true
        RunStore.delete()
        recordHistory(.abandoned, defeatedBy: [])
    }

    /// Writes this run into the permanent run history (game.md §3) — exactly once, when it ends.
    @ObservationIgnored private var historyRecorded = false

    private func recordHistory(_ outcome: RunRecord.Outcome, defeatedBy: [String]) {
        guard !historyRecorded else { return }
        historyRecorded = true
        syncFlashcardStats()
        let rowsReached = visitedNodeIDs.compactMap { map.node($0)?.row }.max().map { $0 + 1 } ?? 0
        RunHistoryStore.append(RunRecord(
            id: id,
            startedAt: startedAt,
            endedAt: Date(),
            outcome: outcome,
            heroes: heroes.map {
                RunRecord.Hero(classID: $0.classDef.id, name: $0.classDef.$name, spriteID: $0.classDef.spriteId,
                               hp: $0.hp, maxHP: $0.maxHP, skillIDs: $0.knownSkillIDs, gearIDs: $0.gear.map(\.id))
            },
            deckNames: flashcards.decks.map(\.name),
            rowsReached: rowsReached,
            totalRows: balance.map.rowCount + 1,
            fightsWon: stats.fightsWon,
            elitesWon: stats.elitesWon ?? 0,
            goldEarned: stats.goldEarned,
            goldSpent: stats.goldSpent ?? 0,
            cardsAnswered: stats.cardsAnswered,
            cardsCorrect: stats.cardsCorrect,
            relicIDs: relics.map(\.id),
            defeatedBy: defeatedBy
        ))
    }
}
