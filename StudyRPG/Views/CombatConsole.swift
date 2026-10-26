import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Polished Bottom Tactical Console

struct FullWidthBottomConsoleView: View {
    @Bindable var engine: CombatEngine
    var onSelectSkill: (SkillDef) -> Void
    /// Drink a potion on a hero (by id).
    var onUsePotion: (ItemDef, String) -> Void
    /// End the party's turn early (unspent action points are lost).
    var onEndTurn: () -> Void = {}

    private var activeHero: HeroState {
        engine.heroes[engine.activeHeroIndex]
    }

    /// The bag grouped by potion kind, in first-seen order, with how many of each are carried.
    private var potionStacks: [(item: ItemDef, count: Int)] {
        var order: [String] = []
        var stacks: [String: (item: ItemDef, count: Int)] = [:]
        for item in engine.inventory {
            if let existing = stacks[item.id] {
                stacks[item.id] = (existing.item, existing.count + 1)
            } else {
                stacks[item.id] = (item, 1)
                order.append(item.id)
            }
        }
        return order.compactMap { stacks[$0] }
    }

    private var armedSkillID: String? {
        switch engine.phase {
        case .choosingTarget(let skillID), .choosingAlly(let skillID): return skillID
        default: return nil
        }
    }

    /// Skills and potions only respond during the party's turn, while the player is choosing.
    private var canAct: Bool { engine.isChoosing }

    var body: some View {
        VStack(spacing: 0) {
            // Gilded Top Edge Accent
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Palette.gold.opacity(0.15), Palette.gold, Palette.gold.opacity(0.15)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)

            HStack(spacing: 10) {
                // MARK: Left: Active Hero Medallion Portrait
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(red: 0.22, green: 0.20, blue: 0.18), Color(red: 0.08, green: 0.07, blue: 0.06)],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 26
                                )
                            )
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle().strokeBorder(Palette.gold, lineWidth: 2)
                            )
                            .shadow(color: Palette.gold.opacity(0.35), radius: 6)

                        SpriteView(spriteId: activeHero.classDef.spriteId, kind: .hero, targetHeight: 42)
                            .offset(y: 2)
                            .id(activeHero.id)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Palette.health)
                            HPBarView(current: activeHero.hp, max: activeHero.maxHP, width: 50, height: 5)
                            Text("\(activeHero.hp)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.health)
                        }

                        // Action points left this turn + ending the party's turn early.
                        HStack(spacing: 6) {
                            ActionPointPips(filled: activeHero.actionPoints,
                                            total: engine.maxActionPoints(heroAt: engine.activeHeroIndex), size: 10)
                            Button(action: onEndTurn) {
                                HStack(spacing: 3) {
                                    Image(systemName: "forward.end.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("End turn")
                                        .font(.serif(9, .bold))
                                }
                                .foregroundStyle(canAct ? Palette.goldGlow : Palette.textDim)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.black.opacity(0.55)))
                                .overlay(Capsule().strokeBorder(Palette.gold.opacity(canAct ? 0.6 : 0.2), lineWidth: 1))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.gamePlain)
                            .disabled(!canAct)
                            .accessibilityLabel("End the party's turn")
                        }

                        // Consumable belt
                        if !potionStacks.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(potionStacks, id: \.item.id) { stack in
                                    let item = stack.item
                                    // Pick who drinks it; heroes it can't help are left out.
                                    Menu {
                                        ForEach(engine.heroes) { hero in
                                            if engine.canUsePotion(item, onHeroID: hero.id) {
                                                Button(hero.classDef.name) { onUsePotion(item, hero.id) }
                                            }
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(Color.black.opacity(0.55))
                                                .frame(width: 28, height: 28)
                                                .overlay(
                                                    Circle().strokeBorder(potionTint(item).opacity(0.6), lineWidth: 1)
                                                )
                                            SpriteView(spriteId: item.spriteId, kind: .consumable, size: 18)
                                        }
                                        .overlay(alignment: .topLeading) {
                                            ActionPointCostBadge(cost: item.actionPoints, size: 11)
                                                .offset(x: -3, y: -3)
                                        }
                                        .overlay(alignment: .bottomTrailing) {
                                            if stack.count > 1 {
                                                Text("\(stack.count)")
                                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                                    .foregroundStyle(Palette.ink)
                                                    .padding(.horizontal, 3)
                                                    .background(Capsule().fill(Palette.goldGlow))
                                                    .offset(x: 3, y: 3)
                                            }
                                        }
                                        .contentShape(Circle())
                                    }
                                    .menuStyle(.button)
                                    .buttonStyle(.gamePlain)
                                    .disabled(!engine.heroes.contains { engine.canUsePotion(item, onHeroID: $0.id) } || !canAct)
                                    .opacity(engine.heroes.contains { engine.canUsePotion(item, onHeroID: $0.id) } && canAct ? 1 : 0.45)
                                    .accessibilityLabel(item.name)
                                }
                            }
                        }
                    }
                }
                // Fixed width, so switching heroes (different HP digits, mana, potions) never
                // moves the skill grid or the log (game.md §7.6).
                .frame(width: 176, alignment: .leading)

                // MARK: Center: fixed 4-slot (2×2) skill grid so the console never shifts height.
                // Equipped skills occupy slots in loadout order; remaining slots render as empty.
                LazyVGrid(
                    columns: [GridItem(.flexible(minimum: 120, maximum: 190), spacing: 6),
                              GridItem(.flexible(minimum: 120, maximum: 190), spacing: 6)],
                    spacing: 5
                ) {
                    ForEach(0..<4, id: \.self) { slot in
                        if slot < activeHero.loadout.count {
                            let skill = activeHero.loadout[slot]
                            TacticalSkillCard(
                                skill: skill,
                                isUsable: canAct && engine.isSkillUsable(skill),
                                isArmed: armedSkillID == skill.id,
                                bonusDice: activeHero.bonusDiceNextTurn,
                                rollBonus: engine.rollBonus(for: skill, heroAt: engine.activeHeroIndex),
                                cooldown: activeHero.cooldowns[skill.id] ?? 0,
                                dieSides: engine.dieSides(heroAt: engine.activeHeroIndex)
                            ) {
                                onSelectSkill(skill)
                            }
                        } else {
                            EmptySkillSlotCard(slotIndex: slot)
                        }
                    }
                }
                // Takes all the room between the fixed side columns, the same for every hero.
                .frame(maxWidth: .infinity)

                // MARK: Right: what happened, as symbols.
                CombatLogView(engine: engine)
                    .frame(width: 196, height: 66)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.11, blue: 0.10),
                        Color(red: 0.07, green: 0.06, blue: 0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func potionTint(_ item: ItemDef) -> Color {
        switch item.effect.type {
        case .heal: return Palette.health
        case .bonusDice: return Palette.strength
        case .resource: return Palette.mana
        }
    }
}

// MARK: - Tactical Skill Card (Embossed Stone & Gilded Fantasy Card)

struct TacticalSkillCard: View {
    let skill: SkillDef
    let isUsable: Bool
    var isArmed: Bool = false
    /// Strength-potion dice waiting on the hero; shown as extra yellow dice on rolling skills.
    var bonusDice: Int = 0
    /// Relic/gear/buff bonus added to the roll; shown as a yellow `+N` on rolling skills.
    var rollBonus: Int = 0
    /// Own turns until it can be used again (0 = ready).
    var cooldown: Int = 0
    /// The hero's die (grows with their level).
    var dieSides: Int = DiceExpr.standardSides
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // One compact line: icon · name · effects · cost / recharge.
            HStack(spacing: 6) {
                // Painted emblem; desaturated and dimmed while the skill can't be used.
                SkillIcon(skill: skill, size: 28)
                    .saturation(isUsable ? 1 : 0.15)
                    .opacity(isUsable ? 1 : 0.6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.displayName)
                        .font(.serif(10, .bold))
                        .foregroundStyle(isUsable ? Palette.text : Palette.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    SkillEffectSummary(skill: skill, bonusDice: bonusDice, rollBonus: rollBonus, dieSides: dieSides)
                        .opacity(isUsable ? 1 : 0.5)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Recharging lives on the button itself (not under the hero): hourglass + turns
                // in place of the cost. The action-point cost always shows.
                ActionPointCostBadge(cost: skill.actionPoints)
                if cooldown > 0 {
                    HStack(spacing: 1) {
                        Image(systemName: "hourglass").font(.system(size: 8, weight: .bold))
                        Text("\(cooldown)").font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.block))
                    .accessibilityLabel("Recharging: ready in \(cooldown) turns")
                } else if let cost = skill.cost {
                    HStack(spacing: 2) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 7, weight: .bold))
                        Text("\(cost)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Palette.mana)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .modifier(SkillCardFrame(isUsable: isUsable, isArmed: isArmed))
        }
        .buttonStyle(.gamePlain)
        // Custom dimming above already communicates "unusable"; `.disabled` would dim the whole
        // card a second time and make the label nearly illegible.
        .allowsHitTesting(isUsable)
    }
}

/// The skill card's surface: an embossed dark card.
private struct SkillCardFrame: ViewModifier {
    let isUsable: Bool
    let isArmed: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: isUsable
                                ? [Color(red: 0.22, green: 0.19, blue: 0.16), Color(red: 0.14, green: 0.12, blue: 0.10)]
                                : [Color(red: 0.12, green: 0.11, blue: 0.10), Color(red: 0.08, green: 0.07, blue: 0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isArmed ? Palette.damage : (isUsable ? Palette.gold : Palette.ink.opacity(0.3)),
                        lineWidth: isArmed ? 2.5 : (isUsable ? 1.5 : 1)
                    )
            )
            .shadow(color: isArmed ? Palette.damage.opacity(0.7) : (isUsable ? Palette.gold.opacity(0.25) : .clear), radius: isArmed ? 8 : 4)
            .scaleEffect(isArmed ? 1.05 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isArmed)
    }
}

/// What a skill does, as colored symbols read straight from its JSON effects: red dice = damage,
/// green dice = healing (with a party icon when it hits both heroes), blue diamond = mana, silver
/// shield = block with its rounds.
struct SkillEffectSummary: View {
    let skill: SkillDef
    var bonusDice: Int = 0
    var rollBonus: Int = 0
    /// The die the hero rolls: d6, or bigger once they level up (game.md §5 "Levels").
    var dieSides: Int = DiceExpr.standardSides

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(skill.effects.enumerated()), id: \.offset) { _, effect in
                effectView(effect)
            }
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
    }

    @ViewBuilder
    private func effectView(_ effect: SkillEffectDef) -> some View {
        switch effect.type {
        case .damage:
            if let dice = effect.dice {
                HStack(spacing: 3) {
                    DiceGlyphs(dice: dice, tint: Palette.damage, bonusDice: bonusDice, rollBonus: rollBonus, sides: dieSides)
                    // Magic damage ignores armor (game.md §7.4).
                    if effect.isMagic {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.control)
                            .accessibilityLabel("Magic")
                    }
                    targetGlyph(Palette.damage)
                }
            }
        case .heal:
            if let dice = effect.dice {
                HStack(spacing: 3) {
                    DiceGlyphs(dice: dice, tint: Palette.health, bonusDice: bonusDice, rollBonus: rollBonus, sides: dieSides)
                    targetGlyph(Palette.health)
                }
            }
        case .stun:
            HStack(spacing: 2) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 9, weight: .bold))
                Text("\(effect.amount ?? 0)")
                targetGlyph(Palette.control)
            }
            .foregroundStyle(Palette.control)
        case .damageBuff:
            timedGlyph(icon: "arrow.up.circle.fill", sign: "+", effect: effect, tint: Palette.strength)
        case .weaken:
            timedGlyph(icon: "arrow.down.circle.fill", sign: "−", effect: effect, tint: Palette.control)
        case .vulnerable:
            timedGlyph(icon: "scope", sign: "+", effect: effect, tint: Palette.control)
        case .resource:
            HStack(spacing: 1) {
                Text("+\(effect.amount ?? 0)")
                Image(systemName: "diamond.fill")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Palette.mana)
        case .block:
            HStack(spacing: 2) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("\(effect.amount ?? 0)")
                if let rounds = effect.rounds {
                    Image(systemName: "hourglass")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.leading, 2)
                    Text("\(rounds)")
                }
            }
            .foregroundStyle(Palette.block)
        }
    }

    /// Who it lands on, when that isn't obvious: every enemy, both heroes, one ally, or yourself.
    @ViewBuilder
    private func targetGlyph(_ tint: Color) -> some View {
        let icon: String? = switch skill.target {
        case .allEnemies: "person.3.fill"
        case .party: "person.2.fill"
        case .ally: "person.fill.questionmark"
        case .selfHero: "person.crop.circle"
        case .enemy: nil
        }
        if let icon {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
        }
    }

    private func timedGlyph(icon: String, sign: String, effect: SkillEffectDef, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text("\(sign)\(effect.amount ?? 0)")
            if let rounds = effect.rounds {
                Image(systemName: "hourglass").font(.system(size: 8, weight: .bold)).padding(.leading, 1)
                Text("\(rounds)")
            }
            targetGlyph(tint)
        }
        .foregroundStyle(tint)
    }
}

/// `count` dice icons in the effect's color, extra bonus dice in strength yellow, then `+flat`.
struct DiceGlyphs: View {
    let dice: DiceExpr
    let tint: Color
    var bonusDice: Int = 0
    var rollBonus: Int = 0
    /// d6 shows the die face symbol, a d8 the octahedron glyph.
    var sides: Int = DiceExpr.standardSides

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<dice.count, id: \.self) { _ in
                DieGlyph(sides: sides, tint: tint)
            }
            ForEach(0..<max(0, bonusDice), id: \.self) { _ in
                DieGlyph(sides: sides, tint: Palette.strength)
            }
            if dice.flat != 0 {
                Text(dice.flat > 0 ? "+\(dice.flat)" : "\(dice.flat)")
                    .foregroundStyle(tint)
                    .padding(.leading, 1)
            }
            if rollBonus != 0 {
                Text("+\(rollBonus)")
                    .foregroundStyle(Palette.strength)
                    .padding(.leading, 1)
            }
        }
        .font(.system(size: 11, weight: .bold))
    }
}

/// Recessed empty slot shown for any unequipped slot in the 4-slot skill grid, keeping the
/// console layout fixed regardless of how many skills the active hero currently knows.
struct EmptySkillSlotCard: View {
    let slotIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Palette.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 22, height: 22)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.22))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.ink.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Empty skill slot")
    }
}

// MARK: - Combat log (game.md §7.6)

/// Running, symbol-only record of everything that happened: who acted, on whom, the dice, every
/// modifier, and the result — newest at the bottom.
struct CombatLogView: View {
    let engine: CombatEngine

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(engine.log.suffix(40)) { entry in
                        CombatLogRow(entry: entry, engine: engine)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            .onChange(of: engine.log.count) {
                guard let last = engine.log.last?.id else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.gold.opacity(0.3), lineWidth: 1)
        }
        .overlay {
            // An empty log at the start of a fight reads as broken; show a faint quill instead.
            if engine.log.isEmpty {
                Image(systemName: "scroll")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.gold.opacity(0.25))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(engine.log.suffix(3).map(\.text).joined(separator: " "))
    }
}

private struct CombatLogRow: View {
    let entry: CombatLogEntry
    let engine: CombatEngine

    private var tint: Color { Palette.combatColor(entry.kind) }

    var body: some View {
        HStack(spacing: 3) {
            portrait(entry.actor)
            Image(systemName: entry.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Palette.goldGlow.opacity(0.85))

            switch entry.kind {
            case .correct:
                portrait(entry.target)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
            case .wrong:
                Image(systemName: "xmark.circle.fill").foregroundStyle(tint)
            default:
                if let target = entry.target, target != entry.actor {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Palette.textDim)
                    portrait(target)
                }
                if !entry.dice.isEmpty {
                    Image(systemName: "die.face.5.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.textDim)
                    diceSum
                    // Every buff / debuff / block that changed the number, as a symbol + amount.
                    ForEach(Array(entry.modifiers.enumerated()), id: \.offset) { _, modifier in
                        modifierView(modifier)
                    }
                    Text("=").foregroundStyle(Palette.textDim)
                }
                result
                if entry.isMagic {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.control)
                }
            }
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .lineLimit(1)
        .fixedSize()
    }

    /// `3+4` with bonus dice in strength yellow, then the skill's own `+flat`.
    private var diceSum: some View {
        let normalCount = max(0, entry.dice.count - entry.bonusDice)
        let normal = entry.dice.prefix(normalCount).map(String.init).joined(separator: "+")
        let bonus = entry.dice.suffix(entry.dice.count - normalCount).map(String.init).joined(separator: "+")
        return HStack(spacing: 0) {
            Text(normal).foregroundStyle(Palette.text.opacity(0.85))
            if !bonus.isEmpty {
                Text(normal.isEmpty ? bonus : "+" + bonus).foregroundStyle(Palette.strength)
            }
            if entry.flat != 0 {
                Text(entry.flat > 0 ? "+\(entry.flat)" : "\(entry.flat)").foregroundStyle(Palette.text.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private func modifierView(_ modifier: RollModifier) -> some View {
        let sign = modifier.amount >= 0 ? "+" : "−"
        let value = "\(sign)\(abs(modifier.amount))"
        HStack(spacing: 1) {
            switch modifier.kind {
            case .damageBuff:
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 8, weight: .bold))
                Text(value)
            case .gear:
                Image(systemName: "hammer.fill").font(.system(size: 7, weight: .bold))
                Text(value)
            case .relic:
                Image(systemName: "seal.fill").font(.system(size: 7, weight: .bold))
                Text(value)
            case .training:
                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 8, weight: .bold))
                Text(value)
            case .vulnerable:
                Image(systemName: "scope").font(.system(size: 8, weight: .bold))
                Text(value)
            case .weaken:
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 8, weight: .bold))
                Text(value)
            case .armor, .block:
                Image(systemName: "shield.fill").font(.system(size: 8, weight: .bold))
                Text(value)
            case .ignoredBlock:
                // Magic went straight through this block: shown, but crossed out.
                Image(systemName: "shield.slash.fill").font(.system(size: 8, weight: .bold))
                Text(value).strikethrough()
            case .crit:
                Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
                Text(value)
            }
        }
        .foregroundStyle(modifierTint(modifier.kind))
    }

    private func modifierTint(_ kind: RollModifier.Kind) -> Color {
        switch kind {
        case .damageBuff, .gear, .relic, .training: return entry.kind == .heal ? Palette.health : Palette.strength
        case .vulnerable, .weaken: return Palette.control
        case .armor, .block: return Palette.block
        case .ignoredBlock: return Palette.block.opacity(0.45)
        case .crit: return Palette.strength
        }
    }

    @ViewBuilder
    private var result: some View {
        switch entry.kind {
        case .damage:
            Text("−\(entry.amount)").foregroundStyle(entry.amount > 0 ? tint : Palette.block)
        case .heal:
            Text("+\(entry.amount)").foregroundStyle(tint)
        case .mana:
            HStack(spacing: 1) {
                Text("+\(entry.amount)")
                Image(systemName: "diamond.fill").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(tint)
        case .strength:
            HStack(spacing: 1) {
                Text("+\(entry.amount)")
                Image(systemName: "die.face.5.fill").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(tint)
        case .block, .armor:
            HStack(spacing: 2) {
                Image(systemName: "shield.fill").font(.system(size: 8, weight: .bold))
                Text("\(entry.amount)")
                if let rounds = entry.rounds {
                    Image(systemName: "hourglass").font(.system(size: 7, weight: .bold))
                    Text("\(rounds)")
                }
            }
            .foregroundStyle(tint)
        case .stun:
            HStack(spacing: 1) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 8, weight: .bold))
                Text("\(entry.amount)")
            }
            .foregroundStyle(tint)
        case .buff, .debuff:
            HStack(spacing: 2) {
                Image(systemName: entry.kind == .buff ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("\(entry.amount)")
                if let rounds = entry.rounds {
                    Image(systemName: "hourglass").font(.system(size: 7, weight: .bold))
                    Text("\(rounds)")
                }
            }
            .foregroundStyle(tint)
        case .correct, .wrong:
            EmptyView()
        }
    }

    @ViewBuilder
    private func portrait(_ actor: CombatActor?) -> some View {
        switch actor {
        case .hero(let id):
            if let hero = engine.heroes.first(where: { $0.id == id }) {
                SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, size: 14)
            }
        case .enemy(let id):
            if let enemy = engine.enemies.first(where: { $0.id == id }) {
                SpriteView(spriteId: enemy.def.spriteId, kind: .enemy, size: 14)
            }
        case .party:
            Image(systemName: "person.2.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.text.opacity(0.8))
        case .none:
            EmptyView()
        }
    }
}
