import Foundation
import Testing
@testable import StudyRPG

/// Shop (game.md §10), campfire (§11) and events (§12), driven through the real `RunState`.
@MainActor
@Suite("Shop")
struct ShopTests {
    init() { Fixtures.isolateUserData() }

    @Test("Stock: relics the party doesn't own and gear it can wear, in the balance.json ranges")
    func stockRules() throws {
        let content = try Fixtures.content()
        let shopConfig = content.balance.shop
        let owned = try #require(content.relics.first)
        let run = try RunState.fixture(content).resumed { $0.relicIDs = [owned.id] }
        let classIDs = Set(run.heroes.map(\.classDef.id))
        let unowned = content.relics.count - 1
        let wearable = content.gear.filter { $0.classId == nil || classIDs.contains($0.classId!) }.count

        for node in run.map.nodes {
            let relics = run.shopRelics(for: node.id), gear = run.shopGear(for: node.id)
            #expect(!relics.contains { $0.id == owned.id }, "shop sells a relic the party owns")
            #expect(relics.count >= min(shopConfig.relicsMin, unowned) && relics.count <= shopConfig.relicsMax)
            #expect(gear.count >= min(shopConfig.gearMin, wearable) && gear.count <= shopConfig.gearMax)
            #expect(gear.allSatisfy { $0.classId == nil || classIDs.contains($0.classId!) })
        }
    }

    @Test("The skill scroll costs skillScrollCost, opens a skill offer and sells once per shop")
    func skillScroll() throws {
        let content = try Fixtures.content()
        let cost = content.balance.shop.skillScrollCost
        let run = try RunState.fixture(content).resumed { $0.gold = cost * 2 }
        let shop = try run.node(.shop)
        #expect(run.canLearnSkills)

        #expect(run.buySkillScroll(at: shop.id))
        #expect(run.gold == cost)
        let offer = try #require(run.pendingSkillOffer)
        #expect(!offer.choices.isEmpty)
        #expect(run.isScrollSold(at: shop.id))
        run.skipSkillOffer()
        #expect(!run.buySkillScroll(at: shop.id), "one scroll per shop")
        #expect(try run.resumed().isScrollSold(at: shop.id))

        let poor = try RunState.fixture(content).resumed { $0.gold = cost - 1 }
        #expect(!poor.buySkillScroll(at: try poor.node(.shop).id))
        #expect(poor.pendingSkillOffer == nil)
    }

    @Test("Haggle: right = −haggleDiscount (min 1), wrong = +haggleSurcharge, none = base price")
    func prices() throws {
        let content = try Fixtures.content()
        let config = content.balance.shop
        let run = RunState.fixture(content)
        for base in [1, 7, 15, 30, 100] {
            #expect(run.price(base, haggleWon: nil) == base)
            #expect(run.price(base, haggleWon: true) == max(1, Int((Double(base) * (1 - config.haggleDiscount)).rounded())))
            #expect(run.price(base, haggleWon: false) == Int((Double(base) * (1 + config.haggleSurcharge)).rounded()))
            #expect(run.price(base, haggleWon: true) >= 1)
        }
    }

    @Test("You can haggle once per shop, and the result survives a resume")
    func haggleOnce() throws {
        let run = RunState.fixture(try Fixtures.content())
        let shop = try run.node(.shop)
        #expect(run.haggleResult(at: shop.id) == nil)
        run.recordHaggle(at: shop.id, won: true)
        run.recordHaggle(at: shop.id, won: false)
        #expect(run.haggleResult(at: shop.id) == true)
        #expect(try run.resumed().haggleResult(at: shop.id) == true)
    }

    @Test("Buying pays the (haggled) price; relics and gear sell once; a full bag blocks potions")
    func buying() throws {
        let content = try Fixtures.content()
        let run = try RunState.fixture(content).resumed { $0.gold = 1000 }
        let shop = try run.node(.shop)
        let potion = try #require(content.items.first)
        run.recordHaggle(at: shop.id, won: true)

        let gold = run.gold
        #expect(run.buyPotion(potion, at: shop.id))
        #expect(run.gold == gold - run.price(potion.cost, haggleWon: true))

        let relic = try #require(run.shopRelics(for: shop.id).first)
        #expect(run.buyRelic(relic, at: shop.id))
        #expect(run.relics.contains { $0.id == relic.id })
        #expect(!run.buyRelic(relic, at: shop.id), "sold out")

        let gear = try #require(run.shopGear(for: shop.id).first)
        #expect(run.buyGear(gear, at: shop.id))
        #expect(run.gearBag.contains(gear))
        #expect(!run.buyGear(gear, at: shop.id), "sold out")

        while !run.isBagFull { _ = run.buyPotion(potion, at: shop.id) }
        let before = run.gold
        #expect(!run.buyPotion(potion, at: shop.id))
        #expect(run.gold == before)
    }

    @Test("You can't buy what you can't afford")
    func cantAfford() throws {
        let content = try Fixtures.content()
        let run = try RunState.fixture(content).resumed { $0.gold = 0 }
        let shop = try run.node(.shop)
        #expect(!run.buyPotion(try #require(content.items.first), at: shop.id))
        if let relic = run.shopRelics(for: shop.id).first { #expect(!run.buyRelic(relic, at: shop.id)) }
        if let gear = run.shopGear(for: shop.id).first { #expect(!run.buyGear(gear, at: shop.id)) }
        #expect(run.gold == 0)
    }

    @Test("Leaving the shop finishes the place")
    func leave() throws {
        let run = RunState.fixture(try Fixtures.content())
        let shop = try run.node(.shop)
        run.leave(shop.id)
        #expect(run.visitedNodeIDs.contains(shop.id) && run.currentNodeID == shop.id)
    }
}

@MainActor
@Suite("Campfire")
struct CampfireTests {
    init() { Fixtures.isolateUserData() }

    @Test("Rest heals every hero restHeal, capped at max HP")
    func rest() throws {
        let content = try Fixtures.content()
        let base = RunState.fixture(content)
        let run = try base.resumed {
            $0.heroes[0].hp = 3
            $0.heroes[1].hp = base.heroes[1].maxHP - 1
        }
        let campfire = try run.node(.campfire)
        run.rest(at: campfire.id)
        #expect(run.heroes[0].hp == min(run.heroes[0].maxHP, 3 + content.balance.campfire.restHeal))
        #expect(run.heroes[1].hp == run.heroes[1].maxHP)
        #expect(run.visitedNodeIDs.contains(campfire.id))
    }

    @Test("Study upgrades one known skill for the rest of the run, uses up the campfire and is saved")
    func study() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let skill = try #require(run.heroes[0].upgradableSkills.first)
        let campfire = try run.node(.campfire)

        run.study(heroAt: 0, skillID: skill.id, at: campfire.id)
        #expect(run.visitedNodeIDs.contains(campfire.id))
        let learned = try #require(run.heroes[0].skill(id: skill.id))
        #expect(learned == skill.upgraded())
        #expect(learned.isUpgraded == true)
        #expect(!run.heroes[0].upgradableSkills.contains { $0.id == skill.id }, "a skill upgrades once")
        #expect(try run.resumed().heroes[0].skill(id: skill.id) == learned)

        // Fights use the upgraded skill.
        let (engine, _, _) = try #require(run.startFight(at: try run.node(.fight).id))
        #expect(engine.heroes[0].skill(id: skill.id) == learned)
    }

    @Test("Only known skills with an upgrade can be studied")
    func studyNeedsAKnownSkill() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let unknown = try #require(run.heroes[0].classDef.skills.first { !run.heroes[0].knownSkillIDs.contains($0.id) && $0.upgrade != nil })
        run.study(heroAt: 0, skillID: unknown.id, at: try run.node(.campfire).id)
        #expect(run.heroes[0].upgradedSkillIDs.isEmpty)
    }

    @Test("Train stacks trainDamageBonus permanently")
    func train() throws {
        let content = try Fixtures.content()
        let run = RunState.fixture(content)
        let campfires = run.map.nodes.filter { $0.type == .campfire }
        for node in campfires.prefix(2) { run.train(at: node.id) }
        #expect(run.trainedDamageBonus == min(2, campfires.count) * content.balance.campfire.trainDamageBonus)
        #expect(try run.resumed().trainedDamageBonus == run.trainedDamageBonus)
    }
}

@MainActor
@Suite("Events")
struct EventTests {
    init() { Fixtures.isolateUserData() }

    /// A run where `node` holds `event`, with low gold and one badly hurt hero.
    private func run(with event: EventDef, at node: Int, gold: Int = 3) throws -> RunState {
        let content = try Fixtures.content()
        let base = RunState.fixture(content)
        return try base.resumed {
            $0.events = [node: RunSnapshot.Event(eventID: event.id)]
            $0.gold = gold
            $0.heroes[0].hp = 2
            $0.heroes[1].hp = base.heroes[1].maxHP - 1
        }
    }

    @Test("Every event's reward and penalty does what game.md §12 says", arguments: [true, false])
    func outcomes(correct: Bool) throws {
        let content = try Fixtures.content()
        for event in content.events {
            let node = 0
            let run = try run(with: event, at: node)
            let outcome = correct ? event.reward : event.penalty
            let amount = outcome.amount ?? 0
            let hp = run.heroes.map(\.hp), maxHP = run.heroes.map(\.maxHP)
            let gold = run.gold, bag = run.inventory.count, relics = run.relics.count, gear = run.gearBag.count

            let applied = try #require(run.resolveEvent(at: node, correct: correct))
            let label = "\(event.id) \(correct ? "reward" : "penalty")"
            #expect(applied.type == outcome.type, "\(label)")
            switch outcome.type {
            case .gold:
                #expect(run.gold == gold + amount, "\(label)")
            case .potion:
                #expect(run.inventory.count == bag + 1, "\(label)")
            case .relic:
                #expect(run.relics.count == relics + 1, "\(label)")
            case .gear:
                #expect(run.gearBag.count == gear + 1, "\(label)")
            case .heal:
                #expect(run.heroes.map(\.hp) == zip(hp, maxHP).map { min($1, $0 + amount) }, "\(label)")
            case .maxHP:
                #expect(run.heroes.map(\.maxHP) == maxHP.map { $0 + amount }, "\(label)")
                #expect(run.heroes.map(\.hp) == hp.map { $0 + amount }, "\(label)")
            case .loseHP:
                #expect(run.heroes.map(\.hp) == hp.map { max(1, $0 - amount) }, "\(label): events can't kill")
            case .loseGold:
                #expect(run.gold == max(0, gold - amount), "\(label): gold never below 0")
            }
        }
    }

    @Test("An event can't be replayed: answering again or resuming keeps the first outcome")
    func noReplay() throws {
        let content = try Fixtures.content()
        let event = try #require(content.events.first { $0.reward.type == .gold })
        let run = try run(with: event, at: 0)
        let gold = run.gold
        _ = run.resolveEvent(at: 0, correct: true)
        _ = run.resolveEvent(at: 0, correct: true)
        _ = run.resolveEvent(at: 0, correct: false)
        #expect(run.gold == gold + (event.reward.amount ?? 0), "applied exactly once")
        let resumed = try run.resumed()
        #expect(resumed.eventResult(at: 0)?.correct == true)
        _ = resumed.resolveEvent(at: 0, correct: true)
        #expect(resumed.gold == run.gold)
    }

    @Test("A potion with a full bag, or a relic with all relics owned, becomes gold")
    func conversions() throws {
        let content = try Fixtures.content()
        if let event = content.events.first(where: { $0.reward.type == .potion }), let potion = content.items.first {
            let run = try run(with: event, at: 0).resumed {
                $0.inventoryIDs = Array(repeating: potion.id, count: content.balance.maxPotionsCarried)
            }
            let gold = run.gold
            let applied = try #require(run.resolveEvent(at: 0, correct: true))
            #expect(applied.convertedToGold)
            #expect(run.gold == gold + content.balance.fullBagGoldConversion)
        }
        if let event = content.events.first(where: { $0.reward.type == .relic }) {
            let run = try run(with: event, at: 0).resumed { $0.relicIDs = content.relics.map(\.id) }
            let gold = run.gold
            let applied = try #require(run.resolveEvent(at: 0, correct: true))
            #expect(applied.convertedToGold)
            #expect(run.gold == gold + content.balance.rewards.relicFallbackGold)
        }
    }

    @Test("Event heals and HP losses leave fallen heroes alone")
    func fallenHeroesUntouched() throws {
        let content = try Fixtures.content()
        let events = content.events.filter { [$0.reward.type, $0.penalty.type].contains(.heal) || [$0.reward.type, $0.penalty.type].contains(.loseHP) }
        for event in events {
            for correct in [true, false] {
                let run = try run(with: event, at: 0).resumed { $0.heroes[0].hp = 0 }
                _ = run.resolveEvent(at: 0, correct: correct)
                let type = (correct ? event.reward : event.penalty).type
                if type == .heal || type == .loseHP {
                    #expect(run.heroes[0].hp == 0, "\(event.id): a fallen hero was affected")
                }
            }
        }
    }
}
