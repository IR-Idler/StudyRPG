import Foundation
import Testing
@testable import StudyRPG

/// Starting, saving, resuming and ending a run (game.md §3). All user data goes to the test
/// sandbox (`Fixtures.isolateUserData`), never the player's real save.
@MainActor
@Suite("Run: start, save, resume, end")
struct RunTests {
    init() { Fixtures.isolateUserData() }

    @Test("A new run starts with full heroes, starting gold, nothing carried, and is saved")
    func newRun() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        #expect(run.gold == content.balance.startingGold)
        #expect(run.heroes.allSatisfy { $0.hp == $0.maxHP })
        #expect(run.inventory.isEmpty && run.relics.isEmpty && run.gearBag.isEmpty)
        #expect(run.trainedDamageBonus == 0)
        #expect(RunStore.hasSavedRun)
    }

    @Test("Only the first row is reachable at the start")
    func startReachability() throws {
        let run = RunState.fixture(try Fixtures.content())
        let firstRow = Set(run.map.nodes.filter { $0.row == 0 }.map(\.id))
        #expect(Set(run.reachableNodeIDs) == firstRow)
        for node in run.map.nodes where node.row > 0 {
            #expect(!run.isReachable(node.id))
        }
    }

    @Test("Saving and resuming restores everything carried")
    func saveRoundTrip() throws {
        let content = try Fixtures.content()
        let run = try RunState.fixture(content).resumed { $0.gold = 500 }
        let shop = try run.node(.shop)
        let potion = try #require(content.items.min { $0.cost < $1.cost })
        #expect(run.buyPotion(potion, at: shop.id))
        run.leave(shop.id)
        run.train(at: try run.node(.campfire).id)

        let saved = try #require(RunStore.load())
        let resumed = try #require(RunState(snapshot: saved, content: content, decks: run.flashcards.decks, statsStore: CardStatsStore()))
        #expect(resumed.gold == run.gold)
        #expect(resumed.inventory.map(\.id) == run.inventory.map(\.id))
        #expect(resumed.trainedDamageBonus == run.trainedDamageBonus)
        #expect(resumed.visitedNodeIDs == run.visitedNodeIDs)
        #expect(resumed.currentNodeID == run.currentNodeID)
        #expect(resumed.map == run.map)
        #expect(resumed.heroes.map(\.hp) == run.heroes.map(\.hp))
        #expect(resumed.heroes.map(\.loadoutSkillIDs) == run.heroes.map(\.loadoutSkillIDs))
    }

    @Test("Everything a place rolls is rolled once: encounter, reward, shop stock and event survive a resume")
    func rolledOnce() throws {
        let run = RunState.fixture(try Fixtures.content())
        let elite = try run.node(.elite), shop = try run.node(.shop), other = try run.node(.fight)
        let encounter = try #require(run.encounter(for: elite.id))
        let reward = try #require(run.reward(for: elite.id))
        let stock = run.shop(for: shop.id)
        let event = try #require(run.event(for: other.id))
        for _ in 0..<5 { #expect(run.encounter(for: elite.id) == encounter) }

        let resumed = try run.resumed()
        #expect(resumed.encounter(for: elite.id) == encounter)
        let again = try #require(resumed.reward(for: elite.id))
        #expect(again.gold == reward.gold)
        #expect(again.relic?.id == reward.relic?.id)
        #expect(again.potion?.id == reward.potion?.id)
        #expect(again.gear?.id == reward.gear?.id)
        #expect(again.skillOffer == reward.skillOffer)
        #expect(resumed.shop(for: shop.id).relicIDs == stock.relicIDs)
        #expect(resumed.shop(for: shop.id).gearIDs == stock.gearIDs)
        #expect(resumed.event(for: other.id)?.id == event.id)
    }

    @Test("Abandoning is permadeath: the save is deleted and the run goes into the history")
    func abandon() throws {
        let run = RunState.fixture(try Fixtures.content())
        run.abandon()
        #expect(run.isOver)
        #expect(!RunStore.hasSavedRun)
        #expect(RunHistoryStore.load().first { $0.id == run.id }?.outcome == .abandoned)
        #expect(run.reachableNodeIDs.allSatisfy { !run.isReachable($0) })
    }
}

// MARK: - Fights inside a run (game.md §3, §7.5)

@MainActor
@Suite("Run: fights and rewards")
struct RunFightTests {
    init() { Fixtures.isolateUserData() }

    /// Plays the fight to the end with strong hero dice and weak enemy dice.
    private func win(_ engine: CombatEngine) throws {
        for _ in 0..<200 where engine.phase == .choosingAction {
            let target = try #require(engine.livingEnemies.first)
            engine.playTurn(try #require(engine.basicAttack), target: target, face: 6, enemyFace: 1)
        }
        #expect(engine.phase == .victory)
    }

    @Test("A fight's gold reward is the sum of its enemies' gold")
    func fightGold() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let node = try run.node(.fight)
        let enemies = try #require(run.encounter(for: node.id)).enemyIds.compactMap { content.enemyDef(id: $0) }
        #expect(run.reward(for: node.id)?.gold == enemies.reduce(0) { $0 + $1.goldReward })
    }

    @Test("Elites give an unowned relic, or fallback gold once every relic is owned")
    func eliteRelic() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let elite = try run.node(.elite)
        let relic = try #require(run.reward(for: elite.id)?.relic, "elite reward without a relic")
        #expect(!run.relics.contains { $0.id == relic.id })

        let richRun = try RunState.fixture(content).resumed { $0.relicIDs = content.relics.map(\.id) }
        let richElite = try richRun.node(.elite)
        let enemies = try #require(richRun.encounter(for: richElite.id)).enemyIds.compactMap { content.enemyDef(id: $0) }
        let reward = try #require(richRun.reward(for: richElite.id))
        #expect(reward.relic == nil)
        #expect(reward.gold == enemies.reduce(0) { $0 + $1.goldReward } + content.balance.rewards.relicFallbackGold)
    }

    @Test("Only elites offer skills: every hero who can learn gets up to offerCount unknown skills; fights and the boss offer none")
    func skillOffers() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let offer = try #require(run.reward(for: try run.node(.elite).id)?.skillOffer)
        #expect(Set(offer.choices.keys) == Set(run.heroes.map(\.id)), "both heroes can still learn at the start")
        for hero in run.heroes {
            let skills = try #require(offer.choices[hero.id])
            #expect(!skills.isEmpty && skills.count <= content.balance.skills.offerCount)
            #expect(Set(skills).count == skills.count)
            for id in skills {
                #expect(hero.classDef.skill(id: id) != nil)
                #expect(!hero.knownSkillIDs.contains(id), "offered a skill the hero already knows")
            }
        }
        for node in run.map.nodes where node.type == .fight {
            #expect(run.reward(for: node.id)?.skillOffer == nil)
        }
        #expect(run.reward(for: run.map.bossNodeID)?.skillOffer == nil)
    }

    @Test("A hero who knows their whole class isn't in the offer")
    func fullyLearnedHeroIsLeftOut() throws {
        let content = try Fixtures.content()
        let run = try RunState.fixture(content).resumed { snapshot in
            snapshot.heroes[0].knownSkillIDs = content.classDef(id: snapshot.heroes[0].classID)?.skills.map(\.id) ?? []
        }
        let offer = try #require(run.reward(for: try run.node(.elite).id)?.skillOffer)
        #expect(offer.choices[run.heroes[0].id] == nil)
        #expect(offer.choices[run.heroes[1].id] != nil)
    }

    @Test("A skill offer saved before the hero choice still loads")
    func legacySkillOfferDecodes() throws {
        let json = #"{"heroID":"warrior","skillIDs":["a","b"]}"#
        let offer = try JSONDecoder().decode(SkillOffer.self, from: Data(json.utf8))
        #expect(offer.choices == ["warrior": ["a", "b"]])
        let again = try JSONDecoder().decode(SkillOffer.self, from: JSONEncoder().encode(offer))
        #expect(again == offer)
    }

    @Test("Winning a fight pays the reward and gets a fallen hero back up at half max HP")
    func victoryFoldsBack() throws {
        let content = try Fixtures.content()
        let run = try RunState.fixture(content).resumed { $0.heroes[0].hp = 0 }
        let node = try run.node(.fight)
        let (engine, reward, _) = try #require(run.startFight(at: node.id))
        let gold = run.gold, bag = run.gearBag.count
        try win(engine)

        run.finishFight(at: node.id, engine: engine, reward: reward)

        #expect(run.heroes[0].hp == max(1, run.heroes[0].maxHP / 2))
        #expect(run.gold == gold + reward.gold)
        #expect(run.gearBag.count == bag + (reward.gear == nil ? 0 : 1))
        #expect(run.stats.fightsWon == 1)
        #expect(run.visitedNodeIDs.contains(node.id) && run.currentNodeID == node.id)
        #expect(run.pendingSkillOffer == reward.skillOffer)
    }

    @Test("Beating the last act's boss completes the run, deletes the save and records a victory")
    func bossVictory() throws {
        let content = try Fixtures.content()
        let run = try RunState.fixture(content).resumed { $0.actIndex = content.acts.count - 1 }
        let (engine, reward, _) = try #require(run.startFight(at: run.map.bossNodeID))
        try win(engine)
        run.finishFight(at: run.map.bossNodeID, engine: engine, reward: reward)
        #expect(run.isComplete)
        #expect(!RunStore.hasSavedRun)
        #expect(RunHistoryStore.load().first { $0.id == run.id }?.outcome == .victory)
    }

    @Test("Campfire training adds its bonus to every hero damage roll in later fights")
    func trainingCarriesIntoFights() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let fight = try run.node(.fight)
        let before = try #require(run.startFight(at: fight.id)).engine
        run.train(at: try run.node(.campfire).id)
        let after = try #require(run.startFight(at: fight.id)).engine
        for index in after.heroes.indices {
            let skill = try #require(after.heroes[index].classDef.skills.first { $0.diceEffect?.type == .damage })
            #expect(after.rollBonus(for: skill, heroAt: index) == before.rollBonus(for: skill, heroAt: index) + content.balance.campfire.trainDamageBonus)
        }
    }
}

// MARK: - Skill learning & loadout (game.md §5)

@MainActor
@Suite("Run: skill learning and loadout")
struct SkillLearningTests {
    init() { Fixtures.isolateUserData() }

    /// A run with a pending offer of the first hero's unknown skills.
    private func runWithOffer(fullLoadout: Bool = false) throws -> (RunState, SkillOffer) {
        let content = try Fixtures.content()
        let base = RunState.fixture(content)
        let hero = base.heroes[0]
        let unknown = hero.classDef.skills.map(\.id).filter { !hero.knownSkillIDs.contains($0) }
        try #require(unknown.count > content.balance.skills.maxEquipped, "class pool too small for this test")
        let other = base.heroes[1]
        let otherUnknown = other.classDef.skills.map(\.id).filter { !other.knownSkillIDs.contains($0) }
        let offer = SkillOffer(choices: [hero.id: [unknown[0]], other.id: Array(otherUnknown.prefix(1))])
        let run = try base.resumed { snapshot in
            snapshot.pendingSkillOffer = offer
            if fullLoadout {
                let filler = Array(unknown.dropFirst().prefix(content.balance.skills.maxEquipped))
                snapshot.heroes[0].knownSkillIDs = filler
                snapshot.heroes[0].loadoutSkillIDs = filler
            } else {
                snapshot.heroes[0].knownSkillIDs = [hero.knownSkillIDs[0]]
                snapshot.heroes[0].loadoutSkillIDs = [hero.knownSkillIDs[0]]
            }
        }
        return (run, offer)
    }

    @Test("Either hero in the offer can learn their own skill — not the other hero's")
    func pickTheHero() throws {
        let (run, offer) = try runWithOffer()
        let second = run.heroes[1]
        let theirs = try #require(offer.choices[second.id]?.first)
        let firstHeroSkill = try #require(offer.choices[run.heroes[0].id]?.first)
        run.learnSkill(firstHeroSkill, heroID: second.id, replacing: nil)
        #expect(run.pendingSkillOffer != nil, "another hero's skill can't be learned")
        run.learnSkill(theirs, heroID: second.id, replacing: nil)
        #expect(run.heroes[1].knownSkillIDs.contains(theirs))
        #expect(!run.heroes[0].knownSkillIDs.contains(firstHeroSkill))
        #expect(run.pendingSkillOffer == nil)
    }

    @Test("You can't travel while a skill offer is waiting")
    func offerBlocksTravel() throws {
        let (run, _) = try runWithOffer()
        #expect(run.reachableNodeIDs.allSatisfy { !run.isReachable($0) })
        run.skipSkillOffer()
        #expect(run.pendingSkillOffer == nil)
        #expect(run.reachableNodeIDs.contains { run.isReachable($0) })
    }

    @Test("With a free slot, a learned skill is equipped right away")
    func learnIntoFreeSlot() throws {
        let (run, offer) = try runWithOffer()
        let skill = try #require(offer.choices[run.heroes[0].id]?.first)
        run.learnSkill(skill, heroID: run.heroes[0].id, replacing: nil)
        #expect(run.heroes[0].knownSkillIDs.contains(skill))
        #expect(run.heroes[0].loadoutSkillIDs.contains(skill))
        #expect(run.pendingSkillOffer == nil)
    }

    @Test("With a full loadout, a learned skill replaces the chosen one or goes to the skill book")
    func learnIntoFullLoadout() throws {
        let max = try Fixtures.content().balance.skills.maxEquipped
        let (swapRun, offer) = try runWithOffer(fullLoadout: true)
        let skill = try #require(offer.choices[swapRun.heroes[0].id]?.first)
        let replaced = swapRun.heroes[0].loadoutSkillIDs[0]
        swapRun.learnSkill(skill, heroID: swapRun.heroes[0].id, replacing: replaced)
        #expect(swapRun.heroes[0].loadoutSkillIDs.contains(skill))
        #expect(!swapRun.heroes[0].loadoutSkillIDs.contains(replaced))
        #expect(swapRun.heroes[0].knownSkillIDs.contains(replaced), "a swapped-out skill stays known")
        #expect(swapRun.heroes[0].loadoutSkillIDs.count == max)

        let (keepRun, _) = try runWithOffer(fullLoadout: true)
        let loadout = keepRun.heroes[0].loadoutSkillIDs
        keepRun.learnSkill(skill, heroID: keepRun.heroes[0].id, replacing: nil)
        #expect(keepRun.heroes[0].knownSkillIDs.contains(skill))
        #expect(keepRun.heroes[0].loadoutSkillIDs == loadout)
    }

    @Test("The loadout stays between 1 and maxEquipped skills")
    func loadoutBounds() throws {
        let content = try Fixtures.content()
        let max = content.balance.skills.maxEquipped
        let pool = try RunState.fixture(content).heroes[0].classDef.skills.map(\.id)
        try #require(pool.count > max)
        let run = try RunState.fixture(content).resumed {
            $0.heroes[0].knownSkillIDs = pool
            $0.heroes[0].loadoutSkillIDs = [pool[0]]
        }
        run.toggleLoadout(heroAt: 0, skillID: pool[0])
        #expect(run.heroes[0].loadoutSkillIDs == [pool[0]], "can't unequip the last skill")
        for id in pool.dropFirst() { run.toggleLoadout(heroAt: 0, skillID: id) }
        #expect(run.heroes[0].loadoutSkillIDs.count == max, "can't equip more than maxEquipped")
    }
}

// MARK: - Gear & potions outside fights (game.md §6)

@MainActor
@Suite("Run: gear and potions")
struct GearAndPotionTests {
    init() { Fixtures.isolateUserData() }

    @Test("Wearing gear moves it out of the bag; the old piece in that slot goes back")
    func equipSwaps() throws {
        let content = try Fixtures.content()
        let hero = content.classes[0]
        let wearable = content.gear.filter { $0.classId == nil || $0.classId == hero.id }
        let slot = try #require(GearSlot.allCases.first { s in wearable.filter { $0.slot == s }.count >= 2 })
        let first = wearable.filter { $0.slot == slot }[0], second = wearable.filter { $0.slot == slot }[1]
        let run = try RunState.fixture(content).resumed { $0.gearBagIDs = [first.id, second.id] }

        run.equip(first, heroAt: 0)
        #expect(run.heroes[0].gear(in: slot) == first)
        #expect(run.gearBag == [second])
        run.equip(second, heroAt: 0)
        #expect(run.heroes[0].gear(in: slot) == second)
        #expect(run.gearBag == [first])
        run.unequip(slot, heroAt: 0)
        #expect(run.heroes[0].gear(in: slot) == nil)
        #expect(Set(run.gearBag) == [first, second])
    }

    @Test("Class gear can only be worn by that class")
    func classLockedGear() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let locked = try #require(content.gear.first { $0.classId != nil })
        for index in run.heroes.indices {
            #expect(run.canWear(locked, heroAt: index) == (run.heroes[index].classDef.id == locked.classId))
        }
    }

    @Test("Max-HP gear raises max HP; taking it off caps HP again")
    func maxHPGear() throws {
        let content = try Fixtures.content()
        let gear = try #require(content.gear.first { g in g.classId == nil && g.effects.contains { $0.type == .maxHP } })
        let bonus = gear.effects.filter { $0.type == .maxHP }.reduce(0) { $0 + $1.amount }
        let run = try RunState.fixture(content).resumed { $0.gearBagIDs = [gear.id] }
        let baseMax = run.heroes[0].maxHP

        run.equip(gear, heroAt: 0)
        #expect(run.heroes[0].maxHP == baseMax + bonus)
        let healed = try run.resumed { $0.heroes[0].hp = baseMax + bonus }
        healed.unequip(gear.slot, heroAt: 0)
        #expect(healed.heroes[0].hp == baseMax)
    }

    @Test("Block gear only protects the hero wearing it")
    func blockGearIsPersonal() throws {
        let content = try Fixtures.content()
        let gear = try #require(content.gear.first { g in g.classId == nil && g.effects.contains { $0.type == .block } })
        let block = gear.effects.filter { $0.type == .block }.reduce(0) { $0 + $1.amount }
        let run = try RunState.fixture(content).resumed { $0.gearBagIDs = [gear.id] }
        run.equip(gear, heroAt: 0)
        let engine = try #require(run.startFight(at: try run.node(.fight).id)).engine
        #expect(engine.damageReduction(forHeroAt: 0) == engine.damageReduction + block)
        #expect(engine.damageReduction(forHeroAt: 1) == engine.damageReduction)
    }

    @Test("A healing potion outside a fight heals a hurt, living hero and is used up")
    func healPotionOutsideFight() throws {
        let content = try Fixtures.content()
        let potion = try #require(content.items.first { $0.effect.type == .heal })
        let run = try RunState.fixture(content).resumed {
            $0.inventoryIDs = [potion.id, potion.id]
            $0.heroes[0].hp = 3
            $0.heroes[1].hp = 0
        }
        #expect(!run.canUsePotionOutsideCombat(potion, onHeroIndex: 1), "the fallen can't drink")
        #expect(run.usePotionOutsideCombat(at: 0, onHeroIndex: 0))
        #expect(run.heroes[0].hp == min(run.heroes[0].maxHP, 3 + potion.fixedHealAmount))
        #expect(run.inventory.count == 1)

        let full = try RunState.fixture(content).resumed { $0.inventoryIDs = [potion.id] }
        #expect(!full.canUsePotionOutsideCombat(potion, onHeroIndex: 0), "no drinking at full HP")
    }

    @Test("Bonus-dice potions can only be drunk in a fight")
    func bonusDicePotionOnlyInFights() throws {
        let content = try Fixtures.content()
        let potion = try #require(content.items.first { $0.effect.type == .bonusDice })
        let run = try RunState.fixture(content).resumed { $0.inventoryIDs = [potion.id] }
        #expect(!run.canUsePotionOutsideCombat(potion, onHeroIndex: 0))
    }

    @Test("A potion found with a full bag becomes gold")
    func fullBagConvertsToGold() throws {
        let content = try Fixtures.content()
        let potion = try #require(content.items.first)
        let run = try RunState.fixture(content).resumed {
            $0.inventoryIDs = Array(repeating: potion.id, count: content.balance.maxPotionsCarried)
        }
        let gold = run.gold
        #expect(!run.gainPotion(potion))
        #expect(run.inventory.count == content.balance.maxPotionsCarried)
        #expect(run.gold == gold + content.balance.fullBagGoldConversion)
    }
}
