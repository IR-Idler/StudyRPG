import SwiftUI

// MARK: - Glossary & Bestiary (game.md §16.1)
//
// Two menu screens listing everything in the content files. What the player has met in any run
// (`DiscoveryStore`) is revealed with art, stats and effects; the rest shows as a dark silhouette
// with "???", so there's something left to find.

/// Every skill, potion, piece of gear and relic.
struct GlossaryView: View {
    let content: GameContent
    @State private var found = Discoveries()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                CodexProgressStrip(entries: [
                    ("sparkles", found.skills, content.classes.flatMap(\.skills).map(\.id)),
                    ("flask.fill", found.potions, content.items.map(\.id)),
                    ("shield.lefthalf.filled", found.gear, content.gear.map(\.id)),
                    ("seal.fill", found.relics, content.relics.map(\.id)),
                ])

                ForEach(content.classes) { heroClass in
                    CodexSection(icon: "sparkles", title: L("\(heroClass.name) skills"),
                                 found: heroClass.skills.filter { found.skills.contains($0.id) }.count,
                                 total: heroClass.skills.count) {
                        ForEach(heroClass.skills) { skill in
                            CodexEntry(isFound: found.skills.contains(skill.id), name: skill.name,
                                       detail: skillDescription(skill)) {
                                SkillIcon(skill: skill, size: 38)
                            } symbols: {
                                HStack(spacing: 6) {
                                    if let cost = skill.cost {
                                        HStack(spacing: 1) {
                                            Image(systemName: "diamond.fill").font(.system(size: 8, weight: .bold))
                                            Text("\(cost)")
                                        }
                                        .foregroundStyle(Palette.mana)
                                    }
                                    if let cooldown = skill.cooldown {
                                        HStack(spacing: 1) {
                                            Image(systemName: "hourglass").font(.system(size: 8, weight: .bold))
                                            Text("\(cooldown)")
                                        }
                                        .foregroundStyle(Palette.block)
                                    }
                                    SkillEffectSummary(skill: skill)
                                }
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                        }
                    }
                }

                CodexSection(icon: "flask.fill", title: L("Potions"),
                             found: content.items.filter { found.potions.contains($0.id) }.count,
                             total: content.items.count) {
                    ForEach(content.items) { item in
                        CodexEntry(isFound: found.potions.contains(item.id), name: item.name,
                                   detail: potionDescription(item), cost: item.cost) {
                            SpriteView(spriteId: item.spriteId, kind: .consumable, size: 38)
                        } symbols: {
                            ItemEffectLabel(effect: item.effect)
                        }
                    }
                }

                CodexSection(icon: "shield.lefthalf.filled", title: L("Gear"),
                             found: content.gear.filter { found.gear.contains($0.id) }.count,
                             total: content.gear.count) {
                    ForEach(content.gear) { gear in
                        CodexEntry(isFound: found.gear.contains(gear.id), name: gear.name,
                                   detail: gearDetail(gear), cost: gear.cost) {
                            GearArt(gear: gear, size: 38)
                        } symbols: {
                            HStack(spacing: 6) {
                                Image(systemName: gear.slot.icon)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Palette.text.opacity(0.7))
                                GearEffectLabel(gear: gear)
                            }
                        }
                    }
                }

                CodexSection(icon: "seal.fill", title: L("Relics"),
                             found: content.relics.filter { found.relics.contains($0.id) }.count,
                             total: content.relics.count) {
                    ForEach(content.relics) { relic in
                        CodexEntry(isFound: found.relics.contains(relic.id), name: relic.name,
                                   detail: relicEffectDescription(relic.effect), cost: relic.cost) {
                            SpriteView(spriteId: relic.spriteId, kind: .relic, size: 38)
                        } symbols: {
                            RelicEffectLabel(effect: relic.effect)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DeskBackground())
        .navigationTitle("Glossary")
        .themedNavigationBar()
        .onAppear { found = DiscoveryStore.load() }
    }

    /// Slot, who can wear it, and what it does.
    private func gearDetail(_ gear: GearDef) -> String {
        let wearer = gear.classId.flatMap { content.classDef(id: $0)?.name }.map { L("\($0) only") } ?? L("Anyone")
        return ([gear.slot.title, wearer] + gear.effects.map(gearEffectDescription)).joined(separator: " · ")
    }

    private func potionDescription(_ item: ItemDef) -> String {
        switch item.effect.type {
        case .heal: return L("Heals one hero for \(item.fixedHealAmount) HP")
        case .bonusDice: return L("+\(item.effect.amount ?? 0) die on that hero's next damage or heal roll")
        case .resource: return L("+\(item.effect.amount ?? 0) mana")
        }
    }
}

/// Every monster: art, stats and moves once it has been met in a fight.
struct BestiaryView: View {
    let content: GameContent
    @State private var found = Discoveries()

    /// Normal monsters first, then elites, then bosses — in content order within a tier.
    private var enemies: [EnemyDef] {
        let order: [EnemyTier] = [.normal, .elite, .boss]
        return order.flatMap { tier in content.enemies.filter { $0.tier == tier } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                CodexProgressStrip(entries: [("pawprint.fill", found.enemies, content.enemies.map(\.id))])

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(enemies) { enemy in
                        BestiaryCard(enemy: enemy, isFound: found.enemies.contains(enemy.id))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DeskBackground())
        .navigationTitle("Bestiary")
        .themedNavigationBar()
        .onAppear { found = DiscoveryStore.load() }
    }
}

// MARK: - Pieces

/// Found / total per category, as symbols.
private struct CodexProgressStrip: View {
    let entries: [(icon: String, found: Set<String>, all: [String])]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                let count = entry.all.filter { entry.found.contains($0) }.count
                HStack(spacing: 4) {
                    Image(systemName: entry.icon).font(.system(size: 11, weight: .bold))
                    Text("\(count)/\(entry.all.count)")
                    if count == entry.all.count, !entry.all.isEmpty {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.moss)
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .parchmentRow()
    }
}

/// A parchment card with a title + found count over a grid of entries.
private struct CodexSection<Entries: View>: View {
    let icon: String
    let title: String
    let found: Int
    let total: Int
    @ViewBuilder var entries: Entries

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(icon: icon, text: title)
                Spacer()
                Text("\(found)/\(total)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.6))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .top)], spacing: 8) {
                entries
            }
        }
        .parchment(padding: 14)
    }
}

/// One glossary entry: art, name, symbols and a line of text — or a silhouette and "???".
private struct CodexEntry<Art: View, Symbols: View>: View {
    let isFound: Bool
    let name: String
    let detail: String
    var cost: Int? = nil
    @ViewBuilder var art: Art
    @ViewBuilder var symbols: Symbols

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            art
                .frame(width: 40, height: 40)
                .codexSilhouette(!isFound)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isFound ? name : "???")
                        .font(.readable(13, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if isFound, let cost {
                        HStack(spacing: 2) {
                            GoldCoin(size: 10)
                            Text("\(cost)")
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                    }
                }
                if isFound {
                    symbols
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.ink.opacity(0.88)))
                    Text(detail)
                        .font(.readable(11))
                        .foregroundStyle(Palette.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not found yet")
                        .font(.readable(11).italic())
                        .foregroundStyle(Palette.ink.opacity(0.45))
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(isFound ? 0.4 : 0.15)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ink.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isFound ? "\(name). \(detail)" : L("Undiscovered"))
    }
}

/// One monster: sprite, tier, stats and moves — or a silhouette until it has been met.
private struct BestiaryCard: View {
    let enemy: EnemyDef
    let isFound: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                SpriteView(spriteId: enemy.spriteId, kind: .enemy, targetHeight: 84)
                    .frame(width: 96, height: 88)
                    .codexSilhouette(!isFound)
                if isFound { tierBadge }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isFound ? enemy.name : "???")
                    .font(.serif(17, .bold))
                if isFound {
                    stats
                    EnemyMoveList(enemy: enemy)
                } else {
                    Text("Meet it in a fight to learn more.")
                        .font(.readable(12).italic())
                        .foregroundStyle(Palette.ink.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .parchment(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var tierBadge: some View {
        let icon = switch enemy.tier {
        case .normal: "pawprint.fill"
        case .elite: "crown"
        case .boss: "crown.fill"
        }
        let label = enemy.tier.title
        return Label(label, systemImage: icon)
            .font(.serif(11, .bold))
            .foregroundStyle(enemy.tier == .normal ? Palette.ink.opacity(0.6) : Color(red: 0.62, green: 0.48, blue: 0.12))
    }

    /// HP, attack, charge speed and gold, as symbols on an ink capsule.
    private var stats: some View {
        HStack(spacing: 10) {
            chip("heart.fill", "\(enemy.baseHP)", Palette.health)
            HStack(spacing: 2) {
                chip("burst.fill", diceText(enemy.attackDice), Palette.damage)
                if enemy.basicAttackIsMagic {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.control)
                }
            }
            chip("hourglass", "\(enemy.attackEvery)", Palette.block)
            HStack(spacing: 2) {
                GoldCoin(size: 11)
                Text("\(enemy.goldReward)").foregroundStyle(Palette.goldGlow)
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.ink.opacity(0.88)))
        .accessibilityLabel(L("\(enemy.baseHP) HP, attacks for \(diceText(enemy.attackDice)) every \(enemy.attackEvery) enemy turn(s), \(enemy.goldReward) gold"))
    }

    private func chip(_ icon: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(value)
        }
        .foregroundStyle(tint)
    }

    private func diceText(_ dice: DiceExpr) -> String {
        L("\(dice.count)d\(dice.dieSides)") + (dice.flat > 0 ? "+\(dice.flat)" : dice.flat < 0 ? "−\(abs(dice.flat))" : "")
    }
}

private extension View {
    /// An undiscovered entry: the art as a dark, faded silhouette with a question mark on top.
    func codexSilhouette(_ locked: Bool) -> some View {
        self
            .colorMultiply(locked ? .black : .white)
            .opacity(locked ? 0.55 : 1)
            .overlay {
                if locked {
                    Image(systemName: "questionmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Palette.parchment.opacity(0.9))
                }
            }
    }
}
