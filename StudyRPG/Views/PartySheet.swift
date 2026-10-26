import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Party & bag sheet (game.md §5, §6, §9)

/// The party screen outside fights. One page per hero — portrait and vitals on the left, the three
/// gear slots (plus wearable gear from the bag) in the middle, and the equipped / known skills on
/// the right — and one Bag page with potions, gear, relics and gold. Everything is editable here:
/// tap gear to wear or take off, tap a skill to equip or unequip it.
///
/// The fight's party button opens this same sheet (game.md §9): with `fight` set it shows the
/// fight's live HP / mana / potions and is read-only (gear and skills change outside fights).
/// `run` is nil only for the Test Fight harness.
struct PartyInventorySheet: View {
    var run: RunState?
    var fight: CombatEngine? = nil
    var initialSelection: PartyInspectorSelection

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PartyInspectorSelection

    init(run: RunState?, fight: CombatEngine? = nil, initialSelection: PartyInspectorSelection) {
        self.run = run
        self.fight = fight
        self.initialSelection = initialSelection
        self._selectedTab = State(initialValue: initialSelection)
    }

    // One data source for both cases: the fight's live state wins over the run's pre-fight state.
    private var isEditable: Bool { fight == nil && run != nil }
    private var heroes: [HeroState] { fight?.heroes ?? run?.heroes ?? [] }
    private var inventory: [ItemDef] { fight?.inventory ?? run?.inventory ?? [] }
    private var relics: [RelicDef] { fight?.relics ?? run?.relics ?? [] }
    private var gearBag: [GearDef] { run?.gearBag ?? [] }
    private var gold: Int { run?.gold ?? 0 }
    private var maxEquipped: Int { run?.maxEquippedSkills ?? ContentLoader.loaded?.balance.skills.maxEquipped ?? 4 }
    private var maxPotions: Int { run?.content.balance.maxPotionsCarried ?? ContentLoader.loaded?.balance.maxPotionsCarried ?? 3 }
    private var trainedDamageBonus: Int { run?.trainedDamageBonus ?? 0 }
    private var leveling: LevelingConfig? { run?.leveling ?? ContentLoader.loaded?.balance.leveling }
    private var cardAccuracy: (correct: Int, answered: Int) {
        guard let run else {
            let session = fight?.flashcards
            return (session?.correct ?? 0, session?.answered ?? 0)
        }
        return run.cardAccuracy
    }

    var body: some View {
        sheetContent.gameSheetFrame()
    }

    @ViewBuilder private var sheetContent: some View {
        VStack(spacing: 0) {
            tabBar
            Group {
                switch selectedTab {
                case .hero(let index) where heroes.indices.contains(index):
                    heroPage(index)
                default:
                    bagPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SceneryBackground())
        .presentationBackground(Palette.night)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(heroes.enumerated()), id: \.element.id) { index, hero in
                tabButton(.hero(index)) {
                    SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: 26)
                        .frame(width: 22, height: 28)
                    Text(hero.classDef.name).font(.readable(13, .bold))
                }
            }
            tabButton(.inventory) {
                Image(systemName: "bag.fill").font(.system(size: 14, weight: .bold))
                Text("Bag").font(.readable(13, .bold))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.gold)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .buttonStyle(.gamePlain)
            .accessibilityLabel("Close")
            .macKeyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.night.opacity(0.95))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.gold.opacity(0.35)).frame(height: 1) }
    }

    private func tabButton<Label: View>(_ tab: PartyInspectorSelection, @ViewBuilder label: () -> Label) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) { label() }
                .foregroundStyle(isSelected ? Palette.ink : Palette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? Palette.gold : Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Palette.gold.opacity(isSelected ? 0 : 0.4), lineWidth: 1))
        }
        .buttonStyle(.gamePlain)
    }

    // MARK: Hero page

    private func heroPage(_ index: Int) -> some View {
        let hero = heroes[index]
        return HStack(alignment: .top, spacing: 12) {
            // Portrait & vitals
            VStack(spacing: 8) {
                SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: 110)
                    .frame(height: 116)
                    .saturation(hero.isAlive ? 1 : 0)
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").foregroundStyle(Palette.health)
                    HPBarView(current: hero.hp, max: hero.maxHP, width: 90, height: 7)
                    Text("\(hero.hp)/\(hero.maxHP)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                }
                if let res = hero.classDef.resource {
                    ManaDiamonds(filled: hero.resource, total: res.max, size: 9)
                }
                if let leveling {
                    // Level and progress to the next (game.md §5 "Levels").
                    let bounds = leveling.bounds(forXP: hero.xp)
                    HStack(spacing: 5) {
                        LevelBadge(level: leveling.level(forXP: hero.xp), size: 17)
                        ExperienceBar(xp: hero.xp, leveling: leveling, width: 70, height: 6)
                        Text(bounds.next.map { "\(hero.xp)/\($0)" } ?? "\(hero.xp)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.7))
                    }
                }
                if let dice = fight?.dice ?? run?.content.balance.dice ?? ContentLoader.loaded?.balance.dice {
                    // The hero's six die faces (game.md §8 "Hero dice").
                    HeroDieStrip(die: hero.die, dice: dice, size: 20)
                }
                PassiveChips(hero: hero, relics: relics, trainedDamageBonus: trainedDamageBonus)
                if fight != nil {
                    // Fight-only: what's active right now (buffs, block, bonus dice, cooldowns are
                    // on the skill buttons).
                    StatusEffectRow(effects: fight.map { heroStatusEffects(engine: $0, index: index) } ?? [])
                }
            }
            .frame(width: 180)
            .parchment(padding: 12)

            // Gear
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(icon: "shield.lefthalf.filled", text: "Gear")
                ForEach(GearSlot.allCases) { slot in
                    GearSlotRow(slot: slot, gear: hero.gear(in: slot), canUnequip: isEditable) {
                        run?.unequip(slot, heroAt: index)
                    }
                }
                let wearable = isEditable ? gearBag.filter { run?.canWear($0, heroAt: index) == true } : []
                if !wearable.isEmpty {
                    SectionTitle(icon: "shippingbox.fill", text: "From the bag")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(wearable.enumerated()), id: \.offset) { _, gear in
                                Button { run?.equip(gear, heroAt: index) } label: {
                                    GearTile(gear: gear)
                                }
                                .buttonStyle(.gamePlain)
                                .accessibilityLabel("Wear \(gear.name)")
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 250)
            .frame(maxHeight: .infinity, alignment: .top)
            .parchment(padding: 12)

            // Skills
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(icon: "sparkles", text: "Skills")
                    Spacer()
                    Text("\(hero.loadoutSkillIDs.count)/\(maxEquipped)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(hero.knownSkills) { skill in
                            let isEquipped = hero.loadoutSkillIDs.contains(skill.id)
                            Button { run?.toggleLoadout(heroAt: index, skillID: skill.id) } label: {
                                SkillRow(skill: skill, isEquipped: isEquipped, cooldownLeft: hero.cooldowns[skill.id])
                            }
                            .buttonStyle(.gamePlain)
                            .disabled(!isEditable)
                            .accessibilityLabel(isEquipped ? "Unequip \(skill.name)" : "Equip \(skill.name)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .parchment(padding: 12)
        }
        .padding(14)
    }

    // MARK: Bag page

    private var bagPage: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        GoldCoin(size: 18)
                        Text("\(gold)").font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    statChip("checkmark.seal.fill", "\(run?.stats.fightsWon ?? 0)", Palette.ink)
                    statChip("rectangle.stack.fill", "\(cardAccuracy.correct)/\(cardAccuracy.answered)", Palette.ink)
                }
                .foregroundStyle(Palette.ink)

                SectionTitle(icon: "flask.fill", text: "Potions \(inventory.count)/\(maxPotions)")
                if inventory.isEmpty {
                    emptyNote
                }
                ForEach(Array(inventory.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        SpriteView(spriteId: item.spriteId, kind: .consumable, size: 30)
                        Text(item.name).font(.readable(13, .bold)).foregroundStyle(Palette.ink)
                        ItemEffectLabel(effect: item.effect)
                        Spacer()
                        // In a fight, potions are drunk from the console's potion tray.
                        let targets = isEditable ? heroes.indices.filter { run?.canUsePotionOutsideCombat(item, onHeroIndex: $0) == true } : []
                        if !targets.isEmpty {
                            Menu {
                                ForEach(targets, id: \.self) { heroIndex in
                                    Button(heroes[heroIndex].classDef.name) {
                                        run?.usePotionOutsideCombat(at: index, onHeroIndex: heroIndex)
                                    }
                                }
                            } label: {
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 44, height: 30)
                            }
                            .buttonStyle(QuestButtonStyle(kind: .secondary))
                            .accessibilityLabel("Drink \(item.name)")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .parchment(padding: 12)

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(icon: "shippingbox.fill", text: "Gear")
                if gearBag.isEmpty {
                    emptyNote
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(Array(gearBag.enumerated()), id: \.offset) { _, gear in
                            HStack(spacing: 8) {
                                GearTile(gear: gear, compact: true)
                                Spacer()
                                ForEach(Array(heroes.enumerated()), id: \.element.id) { heroIndex, hero in
                                    if isEditable, run?.canWear(gear, heroAt: heroIndex) == true {
                                        Button { run?.equip(gear, heroAt: heroIndex) } label: {
                                            SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: 26)
                                                .frame(width: 34, height: 30)
                                        }
                                        .buttonStyle(QuestButtonStyle(kind: .secondary))
                                        .accessibilityLabel("Give \(gear.name) to \(hero.classDef.name)")
                                    }
                                }
                            }
                        }
                    }
                }

                SectionTitle(icon: "seal.fill", text: "Relics")
                if relics.isEmpty {
                    emptyNote
                }
                ForEach(relics) { relic in
                    HStack(spacing: 10) {
                        SpriteView(spriteId: relic.spriteId, kind: .relic, size: 28)
                        Text(relic.name).font(.readable(13, .bold)).foregroundStyle(Palette.ink)
                        Spacer()
                        RelicEffectLabel(effect: relic.effect)
                    }
                    .accessibilityHint(relicEffectDescription(relic.effect))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .parchment(padding: 12)
        }
        .padding(14)
    }

    private var emptyNote: some View {
        Image(systemName: "minus")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Palette.ink.opacity(0.3))
            .accessibilityLabel("Empty")
    }

    private func statChip(_ icon: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint.opacity(0.8))
    }
}

/// Small ink header with an icon, used on parchment cards.
struct SectionTitle: View {
    let icon: String
    let text: Text

    init(icon: String, text: LocalizedStringKey) {
        self.icon = icon
        self.text = Text(text)
    }

    /// Already-localized text (built with `L`), shown as is. Disfavored so literals still localize.
    @_disfavoredOverload
    init(icon: String, text: String) {
        self.icon = icon
        self.text = Text(verbatim: text)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            text.font(.readable(13, .bold))
        }
        .foregroundStyle(Palette.ink.opacity(0.85))
    }
}

/// A hero's always-on bonuses as symbol chips: training, relics and worn gear.
private struct PassiveChips: View {
    let hero: HeroState
    let relics: [RelicDef]
    let trainedDamageBonus: Int

    var body: some View {
        let block = hero.gearTotal(.block) + relics.filter { $0.effect.type == .damageReduction }.reduce(0) { $0 + $1.effect.amount }
        let damage = trainedDamageBonus + hero.gearTotal(.damageBonus) + relics.filter { $0.effect.type == .rollBonus }.reduce(0) { $0 + $1.effect.amount }
        let firstDice = hero.gearTotal(.firstRollBonusDice)
        HStack(spacing: 8) {
            if block > 0 { chip("shield.fill", "\(block)", Palette.block) }
            if damage > 0 { chip("arrow.up.circle.fill", "+\(damage)", Palette.strength) }
            if firstDice > 0 { chip("die.face.5.fill", "+\(firstDice)", Palette.strength) }
            if hero.gearTotal(.startResource) > 0 { chip("diamond.fill", "+\(hero.gearTotal(.startResource))", Palette.mana) }
            if hero.gearTotal(.healBonus) > 0 { chip("cross.case.fill", "+\(hero.gearTotal(.healBonus))", Palette.health) }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
    }

    private func chip(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.ink.opacity(0.85)))
    }
}

/// Gear art: `item_<spriteId>` if it exists, else its painted `ItemArt`, else the slot's symbol on a parchment badge.
struct GearArt: View {
    let gear: GearDef
    var size: CGFloat = 34

    var body: some View {
        if let image = ArtCache.thumbnail("item_\(gear.spriteId)", height: size) {
            Image(platformImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else if ItemArt.canDraw(gear.spriteId) {
            ItemArtView(spriteId: gear.spriteId)
                .frame(width: size, height: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(RadialGradient(colors: [Palette.parchment, Palette.parchmentShade], center: .center, startRadius: 2, endRadius: size))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(Palette.gold.opacity(0.8), lineWidth: 1.5))
                Image(systemName: gear.slot.icon)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Palette.ink.opacity(0.8))
            }
            .frame(width: size, height: size)
        }
    }
}

/// What a piece of gear does, as colored symbols.
struct GearEffectLabel: View {
    let gear: GearDef

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(gear.effects.enumerated()), id: \.offset) { _, effect in
                HStack(spacing: 2) {
                    switch effect.type {
                    case .maxHP:
                        Text("+\(effect.amount)")
                        Image(systemName: "heart.fill").font(.system(size: 9, weight: .bold))
                        Image(systemName: "arrow.up").font(.system(size: 8, weight: .heavy))
                    case .damageBonus:
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 9, weight: .bold))
                        Text("+\(effect.amount)")
                    case .healBonus:
                        Image(systemName: "cross.case.fill").font(.system(size: 9, weight: .bold))
                        Text("+\(effect.amount)")
                    case .startResource:
                        Text("+\(effect.amount)")
                        Image(systemName: "diamond.fill").font(.system(size: 8, weight: .bold))
                    case .block:
                        Image(systemName: "shield.fill").font(.system(size: 9, weight: .bold))
                        Text("\(effect.amount)")
                    case .firstRollBonusDice:
                        Text("+\(effect.amount)")
                        Image(systemName: "die.face.5.fill").font(.system(size: 10, weight: .bold))
                    }
                    if let skillId = effect.skillId {
                        Image(systemName: skillIcon(skillId)).font(.system(size: 9, weight: .bold)).opacity(0.75)
                    }
                }
                .foregroundStyle(tint(effect.type))
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .accessibilityLabel(gear.effects.map(gearEffectDescription).joined(separator: ". "))
    }

    private func skillIcon(_ id: String) -> String {
        ContentLoader.loaded?.classes.lazy.compactMap { $0.skill(id: id) }.first?.icon ?? "sparkles"
    }

    private func tint(_ type: GearEffectType) -> Color {
        switch type {
        case .maxHP, .healBonus: return Palette.health
        case .damageBonus, .firstRollBonusDice: return Palette.strength
        case .startResource: return Palette.mana
        case .block: return Palette.block
        }
    }
}

/// One piece of gear: art, name and effects.
struct GearTile: View {
    let gear: GearDef
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            GearArt(gear: gear, size: compact ? 30 : 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(gear.name).font(.readable(12, .bold)).foregroundStyle(Palette.ink).lineLimit(1)
                GearEffectLabel(gear: gear)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Palette.ink.opacity(0.85)))
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.ink.opacity(0.2), lineWidth: 1))
    }
}

/// One gear slot on a hero page: empty (dashed) or worn gear with a take-off button.
private struct GearSlotRow: View {
    let slot: GearSlot
    let gear: GearDef?
    var canUnequip = true
    let onUnequip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: slot.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.ink.opacity(0.45))
                .frame(width: 18)
            if let gear {
                GearTile(gear: gear, compact: true)
                Spacer(minLength: 0)
                if canUnequip {
                    Button(action: onUnequip) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 26)
                    }
                    .buttonStyle(QuestButtonStyle(kind: .secondary))
                    .accessibilityLabel("Take off \(gear.name)")
                }
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Palette.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: 44)
                    .overlay(Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.ink.opacity(0.25)))
                    .accessibilityLabel("Empty \(slot.title) slot")
            }
        }
    }
}

/// A skill on the hero page / skill reward screen: icon, name, cost, cooldown and its effects.
struct SkillRow: View {
    let skill: SkillDef
    var isEquipped = false
    /// In a fight: own turns until it can be used again.
    var cooldownLeft: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            SkillIcon(skill: skill, size: 32)
                .saturation(isEquipped ? 1 : 0.55)
                .opacity(isEquipped ? 1 : 0.8)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.displayName).font(.readable(13, .bold)).foregroundStyle(Palette.ink)
                    if let cost = skill.cost {
                        HStack(spacing: 1) {
                            Image(systemName: "diamond.fill").font(.system(size: 8, weight: .bold))
                            Text("\(cost)").font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Palette.mana)
                    }
                    if let cooldown = cooldownLeft ?? skill.cooldown {
                        HStack(spacing: 1) {
                            Image(systemName: "hourglass").font(.system(size: 8, weight: .bold))
                            Text("\(cooldown)").font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(cooldownLeft != nil ? Palette.crimson : Palette.ink.opacity(0.55))
                    }
                }
                SkillEffectSummary(skill: skill)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.ink.opacity(0.88)))
            }
            Spacer(minLength: 0)
            Image(systemName: isEquipped ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isEquipped ? Palette.moss : Palette.ink.opacity(0.3))
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 10).fill(isEquipped ? Palette.gold.opacity(0.2) : Color.white.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isEquipped ? Palette.gold : Palette.ink.opacity(0.15), lineWidth: isEquipped ? 1.5 : 1))
        .accessibilityHint(skillDescription(skill))
    }
}

/// Plain-language skill text, for accessibility and the fight info sheet.
func skillDescription(_ skill: SkillDef) -> String {
    let target: String = switch skill.target {
    case .enemy: L("One enemy")
    case .allEnemies: L("All enemies")
    case .party: L("Both heroes")
    case .ally: L("One hero")
    case .selfHero: L("Self")
    }
    var parts = [target] + skill.effects.map(skillEffectDescription)
    if let cooldown = skill.cooldown { parts.append(L("Recharges for \(cooldown) turns")) }
    if skill.requiresInactive == "block" { parts.append(L("Only when no Shield Wall is up")) }
    return parts.joined(separator: " · ")
}

func skillEffectDescription(_ effect: SkillEffectDef) -> String {
    let dice = effect.dice.map { L("\($0.count)d6") + ($0.flat > 0 ? "+\($0.flat)" : "") } ?? ""
    let amount = effect.amount ?? 0
    let rounds = effect.rounds ?? 0
    switch effect.type {
    case .damage:
        return effect.isMagic
            ? L("Deal \(dice) magic damage (ignores armor)")
            : L("Deal \(dice) damage")
    case .heal: return L("Heal \(dice)")
    case .block: return L("Block \(amount) per hit for \(rounds) rounds")
    case .resource: return L("+\(amount) mana")
    case .stun: return L("Stun: skips \(amount) turn(s)")
    case .damageBuff: return L("+\(amount) damage for \(rounds) rounds")
    case .weaken: return L("Weaken: −\(amount) damage dealt for \(rounds) rounds")
    case .vulnerable: return L("Vulnerable: +\(amount) damage taken for \(rounds) rounds")
    }
}

func gearEffectDescription(_ effect: GearEffectDef) -> String {
    let skillName = effect.skillId.flatMap { id in ContentLoader.loaded?.classes.lazy.compactMap { $0.skill(id: id) }.first?.name }
    let only = skillName.map { " " + L("(\($0) only)") } ?? ""
    switch effect.type {
    case .maxHP: return L("+\(effect.amount) max HP")
    case .damageBonus: return L("+\(effect.amount) damage") + only
    case .healBonus: return L("+\(effect.amount) healing") + only
    case .startResource: return L("Start fights with +\(effect.amount) mana")
    case .block: return L("−\(effect.amount) damage from every hit")
    case .firstRollBonusDice: return L("+\(effect.amount) die on the first roll of each fight")
    }
}

func relicEffectDescription(_ effect: RelicEffectDef) -> String {
    switch effect.type {
    case .damageReduction:
        return L("Reduces all incoming enemy attack damage by \(effect.amount).")
    case .rollBonus:
        return L("Adds +\(effect.amount) to every damage and healing dice roll.")
    case .maxHPBonus:
        return L("Increases each hero's maximum HP by +\(effect.amount).")
    }
}

/// Dims the screen and shows one flashcard; reports right/wrong once answered (outside combat:
/// shop haggle, events).
struct FlashcardQuizHost: View {
    let card: PresentedCard
    let flashcards: FlashcardSession
    let onResult: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            FlashcardQuizOverlay(card: card) { chosenIndex, responseMs in
                onResult(flashcards.record(chosenOptionIndex: chosenIndex, responseMs: responseMs))
            }
        }
        .transition(.opacity)
    }
}
