import SwiftUI

// MARK: - Hero dice views (game.md §8 "Hero dice", §5 "Levels")

/// The color a sticker is painted in — by what it does, matching the battlefield colors (§7.6).
enum StickerStyle {
    static func tint(_ type: StickerEffectType) -> Color {
        switch type {
        case .crit: return Palette.strength
        case .block: return Palette.block
        case .resource: return Palette.mana
        case .heal: return Palette.health
        }
    }

    /// What a sticker does, in one short line (offer cards, accessibility).
    static func description(_ sticker: StickerDef, resourceName: String?) -> String {
        switch sticker.type {
        case .crit: return L("Counts this die twice")
        case .block: return L("−\(sticker.amount) damage per hit until your next turn")
        case .resource: return L("+\(sticker.amount) \(resourceName ?? L("resource"))")
        case .heal: return L("Heals you \(sticker.amount) HP")
        }
    }
}

/// A sticker as a small ink medallion with its symbol.
struct StickerBadge: View {
    let sticker: StickerDef
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: sticker.symbol)
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(StickerStyle.tint(sticker.type))
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.ink))
            .overlay(Circle().strokeBorder(StickerStyle.tint(sticker.type), lineWidth: max(0.8, size * 0.08)))
            .accessibilityLabel(sticker.name)
    }
}

/// One face of a hero's die: a bone tile with its number and, if it has one, its sticker.
struct DieFaceTile: View {
    let face: DieFace
    let dice: DiceConfig
    var size: CGFloat = 18

    var body: some View {
        let sticker = dice.sticker(id: face.sticker)
        Text("\(face.value)")
            .font(.serif(size * 0.6, .heavy))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.2).fill(Palette.dieBone))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2).strokeBorder(Palette.ink.opacity(0.8), lineWidth: max(0.8, size * 0.05)))
            .overlay(alignment: .topTrailing) {
                if let sticker {
                    StickerBadge(sticker: sticker, size: size * 0.5)
                        .offset(x: size * 0.18, y: -size * 0.18)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sticker.map { L("\(face.value) with \($0.name)") } ?? "\(face.value)")
    }
}

/// All six faces of a hero's die in a row.
struct HeroDieStrip: View {
    let die: [DieFace]
    let dice: DiceConfig
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(Array(die.enumerated()), id: \.offset) { _, face in
                DieFaceTile(face: face, dice: dice, size: size)
            }
        }
        .padding(.top, size * 0.2)
        .padding(.trailing, size * 0.2)
    }
}

// MARK: - Level-up: shape your die

/// After a level-up: the hero picks one of the offered die upgrades, then the face it changes —
/// or skips (game.md §5 "Levels").
struct DieUpgradeView: View {
    @Bindable var run: RunState
    let offer: DieUpgradeOffer
    @State private var picked: DieUpgradeDef?

    private var dice: DiceConfig { run.content.balance.dice }
    private var heroIndex: Int? { run.heroes.firstIndex { $0.id == offer.heroID } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            if let heroIndex {
                let hero = run.heroes[heroIndex]
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: 54)
                            .frame(width: 44, height: 56)
                        Text("LEVEL UP")
                            .font(.serif(16, .heavy))
                            .foregroundStyle(Palette.gold)
                        DieGlyph(sides: DiceExpr.standardSides, tint: Palette.gold, size: 20)
                        Spacer()
                        Button {
                            Sound.play(.tap)
                            run.skipDieUpgrade()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 44)
                        }
                        .buttonStyle(QuestButtonStyle(kind: .secondary))
                        .accessibilityLabel("Skip")
                    }

                    if let picked {
                        faceStep(hero: hero, upgrade: picked)
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(offer.upgradeIDs, id: \.self) { id in
                                if let upgrade = dice.upgrade(id: id) {
                                    Button {
                                        Sound.play(.tap)
                                        withAnimation(.easeInOut(duration: 0.2)) { self.picked = upgrade }
                                    } label: {
                                        DieUpgradeCard(upgrade: upgrade, dice: dice, resourceName: hero.classDef.resource?.name)
                                    }
                                    .buttonStyle(.gamePlain)
                                }
                            }
                        }
                        HeroDieStrip(die: hero.die, dice: dice, size: 26)
                    }
                }
                .frame(maxWidth: 600)
                .parchment(padding: 18)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                MapPeekButton()
                SettingsGearButton(chipSize: 32)
            }
            .padding(.trailing, 16)
            .padding(.top, 10)
        }
    }

    /// Tap the face the upgrade goes on; faces it can't change are dimmed.
    private func faceStep(hero: HeroState, upgrade: DieUpgradeDef) -> some View {
        VStack(spacing: 12) {
            DieUpgradeCard(upgrade: upgrade, dice: dice, resourceName: hero.classDef.resource?.name, compact: true)
            HStack(spacing: 12) {
                ForEach(Array(hero.die.enumerated()), id: \.offset) { index, face in
                    let usable = dice.canApply(upgrade, to: face)
                    Button {
                        Sound.play(.skillLearn)
                        run.applyDieUpgrade(upgrade.id, toFace: index)
                    } label: {
                        VStack(spacing: 6) {
                            DieFaceTile(face: face, dice: dice, size: 44)
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.ink.opacity(0.5))
                            DieFaceTile(face: dice.applying(upgrade, to: face), dice: dice, size: 44)
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        .opacity(usable ? 1 : 0.3)
                    }
                    .buttonStyle(.gamePlain)
                    .disabled(!usable)
                    .accessibilityLabel(L("Face \(face.value)"))
                }
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { self.picked = nil }
            } label: {
                Image(systemName: "chevron.left").frame(width: 44)
            }
            .buttonStyle(QuestButtonStyle(kind: .secondary))
            .accessibilityLabel("Back")
        }
    }
}

/// An upgrade choice: raise a face, or a sticker with what it does.
private struct DieUpgradeCard: View {
    let upgrade: DieUpgradeDef
    let dice: DiceConfig
    let resourceName: String?
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            switch upgrade.type {
            case .raiseFace:
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up").font(.system(size: compact ? 16 : 24, weight: .heavy))
                    Text("+\(upgrade.amount ?? 0)").font(.serif(compact ? 20 : 28, .heavy))
                }
                .foregroundStyle(Palette.gold)
                .frame(height: compact ? 30 : 48)
                Text("Raise a face")
                    .font(.readable(compact ? 12 : 14, .bold))
                    .foregroundStyle(Palette.ink)
            case .sticker:
                if let sticker = dice.sticker(id: upgrade.sticker) {
                    StickerBadge(sticker: sticker, size: compact ? 30 : 48)
                    Text(sticker.name)
                        .font(.readable(compact ? 12 : 14, .bold))
                        .foregroundStyle(Palette.ink)
                    if !compact {
                        Text(StickerStyle.description(sticker, resourceName: resourceName))
                            .font(.readable(11, .semibold))
                            .foregroundStyle(Palette.ink.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(compact ? 8 : 12)
        .frame(width: compact ? 124 : 160, height: compact ? 84 : 140)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.gold, lineWidth: 1.5))
    }
}
