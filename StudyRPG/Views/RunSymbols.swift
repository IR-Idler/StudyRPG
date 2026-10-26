import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Shared run symbols (game.md §17: symbols + semantic colors, minimal text)

struct GoldCoin: View {
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Palette.glow, Palette.gold], center: .topLeading, startRadius: 1, endRadius: size))
            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.35), lineWidth: max(1, size * 0.08)))
            .overlay(
                Circle().strokeBorder(Palette.glow.opacity(0.9), lineWidth: max(0.8, size * 0.06))
                    .padding(size * 0.2)
            )
            .frame(width: size, height: size)
    }
}

/// An icon over a small symbolic label, in a dark capsule — one reward / price / outcome.
struct RewardChip<Icon: View, Label: View>: View {
    @ViewBuilder var icon: Icon
    @ViewBuilder var label: Label

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                icon
            }
            .frame(width: 30, height: 30)

            ZStack {
                label
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(height: 16)
        }
        .frame(minWidth: 64, minHeight: 52)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.ink.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.gold.opacity(0.55), lineWidth: 1.2))
        .foregroundStyle(Palette.text)
    }
}

/// What a potion does, as colored symbols.
struct ItemEffectLabel: View {
    let effect: ItemEffectDef

    var body: some View {
        HStack(spacing: 2) {
            switch effect.type {
            case .heal:
                Text("+\(effect.dice?.flat ?? effect.amount ?? 0)")
                Image(systemName: "heart.fill").font(.system(size: 9, weight: .bold))
            case .bonusDice:
                Text("+\(effect.amount ?? 0)")
                Image(systemName: "die.face.5.fill").font(.system(size: 10, weight: .bold))
            case .resource:
                Text("+\(effect.amount ?? 0)")
                Image(systemName: "diamond.fill").font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(tint)
        .font(.system(size: 12, weight: .bold, design: .rounded))
    }

    private var tint: Color {
        switch effect.type {
        case .heal: return Palette.health
        case .bonusDice: return Palette.strength
        case .resource: return Palette.mana
        }
    }
}

/// What a relic does, as colored symbols.
struct RelicEffectLabel: View {
    let effect: RelicEffectDef

    var body: some View {
        HStack(spacing: 2) {
            switch effect.type {
            case .damageReduction:
                Image(systemName: "shield.fill").font(.system(size: 9, weight: .bold))
                Text("\(effect.amount)")
            case .rollBonus:
                Image(systemName: "die.face.5.fill").font(.system(size: 10, weight: .bold))
                Text("+\(effect.amount)")
            case .maxHPBonus:
                Text("+\(effect.amount)")
                Image(systemName: "heart.fill").font(.system(size: 9, weight: .bold))
                Image(systemName: "arrow.up").font(.system(size: 8, weight: .heavy))
            }
        }
        .foregroundStyle(tint)
        .font(.system(size: 12, weight: .bold, design: .rounded))
    }

    private var tint: Color {
        switch effect.type {
        case .damageReduction: return Palette.block
        case .rollBonus: return Palette.strength
        case .maxHPBonus: return Palette.health
        }
    }
}

/// What an event outcome does, as colored symbols.
struct EventOutcomeLabel: View {
    let type: EventOutcomeType
    var amount: Int?
    var relic: RelicDef? = nil
    var potion: ItemDef? = nil
    var gear: GearDef? = nil

    var body: some View {
        HStack(spacing: 3) {
            switch type {
            case .gear:
                if let gear {
                    GearArt(gear: gear, size: 22)
                    GearEffectLabel(gear: gear)
                } else {
                    Image(systemName: "shippingbox.fill").foregroundStyle(Palette.goldGlow)
                }
            case .gold:
                Text("+\(amount ?? 0)").foregroundStyle(Palette.goldGlow)
                GoldCoin(size: 13)
            case .loseGold:
                Text("−\(amount ?? 0)").foregroundStyle(Palette.damage)
                GoldCoin(size: 13)
            case .potion:
                if let potion {
                    SpriteView(spriteId: potion.spriteId, kind: .consumable, size: 22)
                } else {
                    Image(systemName: "flask.fill").foregroundStyle(Palette.text)
                }
            case .relic:
                if let relic {
                    SpriteView(spriteId: relic.spriteId, kind: .relic, size: 22)
                    RelicEffectLabel(effect: relic.effect)
                } else {
                    Image(systemName: "seal.fill").foregroundStyle(Palette.goldGlow)
                }
            case .heal:
                Text("+\(amount ?? 0)").foregroundStyle(Palette.health)
                Image(systemName: "heart.fill").foregroundStyle(Palette.health)
                Image(systemName: "person.2.fill").font(.system(size: 9)).foregroundStyle(Palette.health)
            case .maxHP:
                Text("+\(amount ?? 0)").foregroundStyle(Palette.health)
                Image(systemName: "heart.fill").foregroundStyle(Palette.health)
                Image(systemName: "arrow.up").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.health)
            case .loseHP:
                Text("−\(amount ?? 0)").foregroundStyle(Palette.damage)
                Image(systemName: "heart.slash.fill").foregroundStyle(Palette.damage)
                Image(systemName: "person.2.fill").font(.system(size: 9)).foregroundStyle(Palette.damage)
            }
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
    }
}

/// The run's relics as small medallions.
struct RelicTray: View {
    let relics: [RelicDef]
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 5) {
            ForEach(relics) { relic in
                SpriteView(spriteId: relic.spriteId, kind: .relic, size: size * 0.8)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .overlay(Circle().strokeBorder(Palette.gold.opacity(0.55), lineWidth: 1))
                    .accessibilityLabel(relic.name)
            }
        }
    }
}

/// Which tab of `PartyInventorySheet` should open initially.
enum PartyInspectorSelection: Identifiable, Hashable {
    case hero(Int)
    case inventory

    var id: String {
        switch self {
        case .hero(let index): return "hero-\(index)"
        case .inventory: return "inventory"
        }
    }
}

/// Party HP/mana, training dice, potions, relics and gold — the run's status line.
/// Tapping a hero opens their page in `PartyInventorySheet`; the bag, relics or gold open the bag.
extension EnvironmentValues {
    /// Set by the run map for everything it covers (fight, shop, campfire, event, skill offer):
    /// shows the map for a look without leaving the screen (game.md §9 "Looking at the map").
    @Entry var openRunMap: (() -> Void)? = nil
}

/// The round "look at the map" chip, shown wherever `openRunMap` is available.
struct MapPeekButton: View {
    @Environment(\.openRunMap) private var openRunMap
    var size: CGFloat = 32

    var body: some View {
        if let openRunMap {
            Button {
                Sound.play(.tap)
                openRunMap()
            } label: {
                Image(systemName: "map.fill")
            }
            .buttonStyle(ChromeIconButtonStyle(size: size))
            .accessibilityLabel("Look at the map")
        }
    }
}

struct RunHUD: View {
    @Bindable var run: RunState
    var onAbandon: (() -> Void)? = nil
    @State private var inspectorSelection: PartyInspectorSelection?
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 12) {
            if let onAbandon {
                hudButton("flag.slash.fill", label: "Abandon run", action: onAbandon)
            }
            MapPeekButton()

            ForEach(Array(run.heroes.enumerated()), id: \.element.id) { index, hero in
                Button {
                    inspectorSelection = .hero(index)
                } label: {
                    HStack(spacing: 5) {
                        SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: 28)
                            .frame(width: 24, height: 30)
                            .opacity(hero.isAlive ? 1 : 0.35)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 3) {
                                HPBarView(current: hero.hp, max: hero.maxHP, width: 46, height: 5)
                                Text("\(hero.hp)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(Palette.health)
                            }
                            HStack(spacing: 3) {
                                // Level + progress to the next one (game.md §5 "Levels").
                                LevelBadge(level: run.leveling.level(forXP: hero.xp), size: 11)
                                ExperienceBar(xp: hero.xp, leveling: run.leveling, width: 30, height: 3)
                                if let res = hero.classDef.resource {
                                    ManaDiamonds(filled: hero.resource, total: res.max, size: 6)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.32)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.gold.opacity(0.28), lineWidth: 0.8))
                }
                .buttonStyle(.gamePlain)
                .accessibilityLabel("\(hero.classDef.name) details")
            }

            if run.trainedDamageBonus > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text("+\(run.trainedDamageBonus)")
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.strength)
                .accessibilityLabel("Training: +\(run.trainedDamageBonus) on every damage roll")
            }

            Spacer(minLength: 6)

            Button {
                inspectorSelection = .inventory
            } label: {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(Array(run.inventory.enumerated()), id: \.offset) { _, item in
                            SpriteView(spriteId: item.spriteId, kind: .consumable, size: 20)
                        }
                        ForEach(0..<max(0, run.content.balance.maxPotionsCarried - run.inventory.count), id: \.self) { _ in
                            Circle()
                                .strokeBorder(Palette.text.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .frame(width: 18, height: 18)
                        }
                    }
                    if !run.gearBag.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "shippingbox.fill").font(.system(size: 11, weight: .bold))
                            Text("\(run.gearBag.count)").font(.system(size: 11, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(Palette.goldGlow)
                    }
                    RelicTray(relics: run.relics, size: 24)
                    HStack(spacing: 4) {
                        GoldCoin(size: 15)
                        Text("\(run.gold)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.goldGlow)
                            .contentTransition(.numericText())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.gamePlain)
            .accessibilityLabel("Open bag")

            hudButton("gearshape.fill", label: "Settings") { showSettings = true }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        // The HUD's strip reaches the screen edges; its buttons stay inside the safe area.
        .background(Palette.night.opacity(0.88).ignoresSafeArea(edges: [.horizontal, .top]))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.gold.opacity(0.35)).frame(height: 1).ignoresSafeArea(edges: .horizontal)
        }
        .animation(.easeOut(duration: 0.3), value: run.gold)
        .sheet(item: $inspectorSelection) { initial in
            PartyInventorySheet(run: run, initialSelection: initial)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func hudButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.text.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.6)))
                .overlay(Circle().strokeBorder(Palette.gold.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.gamePlain)
        .accessibilityLabel(label)
    }
}

// MARK: - Levels (game.md §5 "Levels")

/// A hero's level as a small gold-rimmed shield with the number.
struct LevelBadge: View {
    let level: Int
    var size: CGFloat = 15

    var body: some View {
        Text("\(level)")
            .font(.system(size: size * 0.62, weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [Palette.goldGlow, Palette.gold], startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.55), lineWidth: 0.8))
            .accessibilityLabel("Level \(level)")
    }
}

/// Progress from the current level to the next, in experience purple-gold. Full at the top level.
struct ExperienceBar: View {
    let xp: Int
    let leveling: LevelingConfig
    var width: CGFloat = 46
    var height: CGFloat = 4

    var body: some View {
        let bounds = leveling.bounds(forXP: xp)
        let fraction: CGFloat = bounds.next.map { next in
            CGFloat(xp - bounds.current) / CGFloat(max(1, next - bounds.current))
        } ?? 1
        ZStack(alignment: .leading) {
            Capsule().fill(Color.black.opacity(0.55))
            Capsule()
                .fill(LinearGradient(colors: [Palette.goldGlow, Palette.gold], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(0, min(1, fraction)) * width)
        }
        .frame(width: width, height: height)
        .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.4), lineWidth: 0.5))
        .accessibilityLabel(bounds.next.map { L("\(xp) of \($0) experience") } ?? L("\(xp) experience, top level"))
    }
}

/// A die of `sides` sides as a glyph: the SF die face for a d6, an inked octahedron for a d8.
struct DieGlyph: View {
    let sides: Int
    var tint: Color = Palette.damage
    var size: CGFloat = 11

    var body: some View {
        if sides == DiceExpr.standardSides {
            Image(systemName: "die.face.5.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(tint)
        } else {
            OctahedronGlyph()
                .fill(tint)
                .overlay(OctahedronGlyph(edgesOnly: true).stroke(Color.black.opacity(0.55), lineWidth: max(0.6, size * 0.07)))
                .frame(width: size * 0.92, height: size * 1.08)
                .accessibilityLabel("\(sides)-sided die")
        }
    }
}

/// The 2D silhouette of a d8: a tall diamond with its equator and a front edge.
struct OctahedronGlyph: Shape {
    var edgesOnly = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY), bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.midY), right = CGPoint(x: rect.maxX, y: rect.midY)
        let front = CGPoint(x: rect.midX + rect.width * 0.08, y: rect.midY + rect.height * 0.04)
        if edgesOnly {
            path.move(to: left); path.addLine(to: front); path.addLine(to: right)
            path.move(to: top); path.addLine(to: front); path.addLine(to: bottom)
        } else {
            path.move(to: top)
            path.addLine(to: right)
            path.addLine(to: bottom)
            path.addLine(to: left)
            path.closeSubpath()
        }
        return path
    }
}
