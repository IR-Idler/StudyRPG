import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Character info sheet

/// Tap any hero or enemy to open this: full stats, abilities, and every active buff/debuff with
/// its magnitude, duration, effect and source.
struct CharacterInfoSheet: View {
    let engine: CombatEngine
    let target: InspectTarget

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch target {
        case .hero(let index):
            return engine.heroes[index].classDef.name
        case .enemy(let id):
            return engine.enemies.first(where: { $0.id == id })?.def.name ?? L("Enemy")
        }
    }

    var body: some View {
        sheetContent.gameSheetFrame()
    }

    @ViewBuilder private var sheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch target {
                    case .hero(let index):
                        heroContent(index)
                    case .enemy(let id):
                        if let enemy = engine.enemies.first(where: { $0.id == id }) {
                            enemyContent(enemy)
                        }
                    }
                }
                .padding(16)
            }
            .background(SceneryBackground())
            .navigationTitle(title)
            .themedNavigationBar(settings: false)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.gold)
                    }
                    .buttonStyle(.gamePlain)
                    .accessibilityLabel("Close")
                    .macKeyboardShortcut(.cancelAction)
                }
            }
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func heroContent(_ index: Int) -> some View {
        let hero = engine.heroes[index]

        header(
            spriteId: hero.classDef.spriteId,
            kind: .hero,
            name: hero.classDef.name,
            subtitle: hero.isAlive ? L("Hero") : L("Fallen")
        )

        VStack(spacing: 8) {
            statRow(icon: "heart.fill", label: L("Health"), value: "\(hero.hp) / \(hero.maxHP)", tint: Palette.health)
            if let res = hero.classDef.resource {
                statRow(icon: "diamond.fill", label: res.name, value: "\(hero.resource) / \(res.max)", tint: Palette.mana)
            }
        }
        .parchment(padding: 14)

        effectsCard(heroStatusEffects(engine: engine, index: index))

        equipmentCard(hero)

        abilitiesCard(
            title: L("Skills"),
            entries: hero.loadout.map { skill in
                AbilityEntry(icon: skill.icon, skill: skill, name: skill.displayName, cost: skill.cost, detail: skillDescription(skill))
            }
        )
    }

    /// Worn gear, read-only during a fight (change it on the map).
    private func equipmentCard(_ hero: HeroState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(icon: "shield.lefthalf.filled", text: "Gear")
            ForEach(GearSlot.allCases) { slot in
                HStack(spacing: 8) {
                    Image(systemName: slot.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.ink.opacity(0.45))
                        .frame(width: 18)
                    if let gear = hero.gear(in: slot) {
                        GearTile(gear: gear, compact: true)
                    } else {
                        Image(systemName: "minus").foregroundStyle(Palette.ink.opacity(0.3))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .parchment(padding: 14)
    }

    // MARK: Enemy

    @ViewBuilder
    private func enemyContent(_ enemy: EnemyInstance) -> some View {
        header(
            spriteId: enemy.def.spriteId,
            kind: .enemy,
            name: enemy.def.name,
            subtitle: enemy.def.tier.title
        )

        VStack(spacing: 8) {
            let hpText: String = {
                if let dice = enemy.def.hpDice {
                    return "\(enemy.hp) / \(enemy.maxHP) (\(diceText(dice)))"
                } else {
                    return "\(enemy.hp) / \(enemy.maxHP)"
                }
            }()
            statRow(icon: "heart.fill", label: L("Health"), value: hpText, tint: Palette.health)
            statRow(icon: enemy.def.basicAttackIsMagic ? "sparkles" : "die.face.5.fill",
                    label: enemy.def.basicAttackIsMagic ? L("Basic magic attack (ignores block)") : L("Basic attack"),
                    value: diceText(enemy.def.attackDice), tint: Palette.damage)
            statRow(icon: "hourglass", label: L("Acts every"), value: enemy.def.attackEvery == 1 ? L("1 enemy turn") : L("\(enemy.def.attackEvery) enemy turns"), tint: Palette.mist)
            statRow(icon: "circle.fill", label: L("Reward"), value: L("\(enemy.def.goldReward) gold"), tint: Palette.goldGlow)
            statRow(icon: "bolt.fill", label: L("Charge"), value: "\(enemy.chargeCounter) / \(enemy.def.attackEvery)", tint: Palette.ember)
        }
        .parchment(padding: 14)

        effectsCard(enemyStatusEffects(engine: engine, enemy: enemy))

        // Pattern + rules, with the move it will play next highlighted (game.md §7.3).
        VStack(alignment: .leading, spacing: 10) {
            Text("Moves")
                .font(.serif(14, .bold))
                .foregroundStyle(Palette.ink)
            EnemyMoveList(enemy: enemy.def, next: engine.plannedMove(for: enemy), moveIndex: enemy.moveIndex)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shared cards

    private func header(spriteId: String, kind: SpriteKind, name: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Palette.steel.opacity(0.35), Palette.panel],
                        center: .center, startRadius: 4, endRadius: 40))
                    .frame(width: 72, height: 72)
                    .overlay(Circle().strokeBorder(Palette.gold.opacity(0.6), lineWidth: 2))
                SpriteView(spriteId: spriteId, kind: kind, size: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.serif(22, .bold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.serif(12))
                    .foregroundStyle(Palette.ink.opacity(0.6))
            }
            Spacer()
        }
        .parchment(padding: 14)
    }

    private func statRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(label)
                .font(.serif(13))
                .foregroundStyle(Palette.ink.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
        }
    }

    private func effectsCard(_ effects: [StatusEffect]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Effects")
                .font(.serif(14, .bold))
                .foregroundStyle(Palette.ink)

            if effects.isEmpty {
                Text("No active buffs or debuffs.")
                    .font(.serif(12))
                    .foregroundStyle(Palette.ink.opacity(0.55))
            } else {
                ForEach(effects) { effect in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: effect.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(effect.tint)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(effect.name)
                                    .font(.serif(14, .bold))
                                if let value = effect.value {
                                    Text("\(value)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(effect.tint)
                                }
                                if let duration = effect.duration {
                                    HStack(spacing: 3) {
                                        Image(systemName: "hourglass")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("\(duration)")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(effect.tint)
                                }
                            }
                            Text(effect.detail)
                                .font(.serif(12))
                                .foregroundStyle(Palette.ink.opacity(0.72))
                            Text(effect.source)
                                .font(.serif(11).italic())
                                .foregroundStyle(Palette.ink.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                    }

                    if effect.id != effects.last?.id {
                        Divider().overlay(Palette.ink.opacity(0.15))
                    }
                }
            }
        }
        .parchment(padding: 14)
    }

    private struct AbilityEntry: Identifiable {
        let id = UUID()
        let icon: String
        /// Heroes' skills show their painted emblem; otherwise the plain symbol.
        var skill: SkillDef? = nil
        let name: String
        let cost: Int?
        let detail: String
    }

    private func abilitiesCard(title: String, entries: [AbilityEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.serif(14, .bold))
                .foregroundStyle(Palette.ink)

            if entries.isEmpty {
                Text("None")
                    .font(.serif(12))
                    .foregroundStyle(Palette.ink.opacity(0.55))
            }

            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if let skill = entry.skill {
                            SkillIcon(skill: skill, size: 28)
                        } else {
                            Image(systemName: entry.icon)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.gold.opacity(0.9))
                        }
                    }
                    .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.name)
                                .font(.serif(13, .bold))
                            if let cost = entry.cost {
                                HStack(spacing: 2) {
                                    Image(systemName: "diamond.fill")
                                        .font(.system(size: 8))
                                    Text("\(cost)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(Palette.mist)
                            }
                        }
                        if !entry.detail.isEmpty {
                            Text(entry.detail)
                                .font(.serif(12))
                                .foregroundStyle(Palette.ink.opacity(0.68))
                        }
                    }
                    Spacer(minLength: 0)
                }

                if entry.id != entries.last?.id {
                    Divider().overlay(Palette.ink.opacity(0.15))
                }
            }
        }
        .parchment(padding: 14)
    }

    // MARK: Text helpers

    private func diceText(_ dice: DiceExpr) -> String {
        var text = L("\(dice.count)d\(dice.dieSides)")
        if dice.flat > 0 {
            text += " + \(dice.flat)"
        } else if dice.flat < 0 {
            text += " − \(abs(dice.flat))"
        }
        return text
    }
}
