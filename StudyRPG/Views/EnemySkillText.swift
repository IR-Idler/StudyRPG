import SwiftUI

// MARK: - Monster skills as symbols and plain text (game.md §7.3, §7.6, §16.1)
//
// Shared by the fight nameplate (next-move icon), the character info sheet and the Bestiary, so a
// monster's skills and rules read the same everywhere.

extension EnemySkillDef {
    /// The skill's meaning color: red damage, green healing, silver armor, yellow buffs, violet
    /// control on heroes — from its main effect (the roll if it has one).
    var tint: Color {
        switch (diceEffect ?? effects.first)?.type {
        case .damage: return Palette.damage
        case .heal: return Palette.health
        case .armor: return Palette.block
        case .damageBuff: return Palette.strength
        case .stun, .weaken, .vulnerable: return Palette.control
        case .none: return Palette.damage
        }
    }

    var dealsMagicDamage: Bool { diceEffect.map { $0.type == .damage && $0.isMagic } ?? false }

    /// e.g. "2d6+2 magic damage to each hero, ignores block · weaken −1 on each hero for 2 rounds".
    var plainDescription: String {
        effects.map { effect in
            let who = Self.targetText(target(of: effect))
            let amount = effect.amount ?? 0
            let rounds = effect.rounds ?? 0
            let dice = effect.dice.map(EnemySkillText.dice) ?? "–"
            switch effect.type {
            case .damage:
                return effect.isMagic
                    ? L("\(dice) magic damage to \(who), ignores block")
                    : L("\(dice) damage to \(who)")
            case .heal:
                return L("heals \(who) \(dice)")
            case .armor:
                return L("armor −\(amount) per hit on \(who) for \(rounds) rounds")
            case .damageBuff:
                return L("+\(amount) damage per hit for \(who) for \(rounds) rounds")
            case .stun:
                return amount == 1 ? L("stuns \(who): loses 1 turn") : L("stuns \(who): loses \(amount) turns")
            case .weaken:
                return L("weaken −\(amount) on \(who) for \(rounds) rounds")
            case .vulnerable:
                return L("vulnerable +\(amount) on \(who) for \(rounds) rounds")
            }
        }
        .joined(separator: " · ")
        .capitalizedFirst
    }

    /// Used as the object of every phrase above (German: accusative).
    static func targetText(_ target: EnemySkillTarget) -> String {
        switch target {
        case .heroes: return L("each hero")
        case .hero: return L("the most hurt hero")
        case .selfEnemy: return L("itself")
        case .ally: return L("the most hurt monster")
        case .allies: return L("every monster")
        }
    }
}

extension EnemyRuleDef {
    /// e.g. "When below 50% HP · once per fight".
    var plainDescription: String {
        var parts: [String] = []
        if let when {
            if let share = when.selfHPBelow { parts.append(L("below \(EnemySkillText.percent(share)) HP")) }
            if let share = when.allyHPBelow { parts.append(L("a monster below \(EnemySkillText.percent(share)) HP")) }
            if let share = when.heroHPBelow { parts.append(L("a hero below \(EnemySkillText.percent(share)) HP")) }
            if let count = when.minAlliesAlive { parts.append(L("\(count)+ monsters standing")) }
            if let count = when.maxAlliesAlive { parts.append(count == 1 ? L("alone") : L("at most \(count) monsters standing")) }
            if when.unlessActive == true { parts.append(L("not already active")) }
        }
        var text = parts.isEmpty ? L("Whenever it can") : L("When \(parts.joined(separator: ", "))")
        if let maxUses {
            text += " · " + (maxUses == 1 ? L("once per fight") : L("at most \(maxUses)× per fight"))
        }
        if let cooldown, cooldown > 0 {
            text += " · " + (cooldown == 1 ? L("then waits 1 move") : L("then waits \(cooldown) moves"))
        }
        return text
    }
}

enum EnemySkillText {
    static func dice(_ dice: DiceExpr) -> String {
        L("\(dice.count)d\(dice.dieSides)") + (dice.flat > 0 ? "+\(dice.flat)" : dice.flat < 0 ? "−\(abs(dice.flat))" : "")
    }

    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}

/// One monster skill as a row: dark medallion with its icon in its meaning color, name and what it
/// does (game.md §16.1 Bestiary, §7.6 info sheet).
struct EnemySkillRow: View {
    let skill: EnemySkillDef
    /// Small leading label: the pattern position ("1") or a rule marker.
    var leading: String? = nil
    var leadingIcon: String? = nil
    /// Extra line under the description (a rule's condition).
    var note: String? = nil
    var isNext = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Group {
                if let leadingIcon {
                    Image(systemName: leadingIcon).font(.system(size: 9, weight: .bold))
                } else {
                    Text(leading ?? "").font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(Palette.ink.opacity(0.45))
            .frame(width: 12, height: 22)

            Image(systemName: skill.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(skill.tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.ink.opacity(0.88)))
                .overlay {
                    if isNext { Circle().strokeBorder(Palette.ember, lineWidth: 1.5) }
                }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(skill.name)
                        .font(.serif(12, .bold))
                    if skill.dealsMagicDamage {
                        Image(systemName: "sparkles").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.control)
                    }
                    if isNext {
                        Text("Next")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.ember)
                    }
                }
                Text(skill.plainDescription)
                    .font(.readable(11))
                    .foregroundStyle(Palette.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .font(.readable(11).italic())
                        .foregroundStyle(Palette.ink.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A monster's whole move list: its pattern as numbered rows, then its rules (game.md §7.3).
struct EnemyMoveList: View {
    let enemy: EnemyDef
    /// Fight only: what it will do next (highlighted).
    var next: EnemyPlan? = nil
    /// Fight only: its position in the pattern.
    var moveIndex: Int = 0

    private func isNextPatternRow(_ index: Int) -> Bool {
        guard let next, next.ruleIndex == nil, !enemy.movePattern.isEmpty else { return false }
        return index == moveIndex % enemy.movePattern.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(enemy.movePattern.enumerated()), id: \.offset) { index, id in
                if let skill = enemy.skill(id: id) {
                    EnemySkillRow(skill: skill, leading: "\(index + 1)", isNext: isNextPatternRow(index))
                }
            }
            if !enemy.allRules.isEmpty {
                Label("Rules — checked first, in order", systemImage: "arrow.triangle.branch")
                    .font(.serif(11, .bold))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                    .padding(.top, 3)
                ForEach(Array(enemy.allRules.enumerated()), id: \.offset) { index, rule in
                    if let skill = enemy.skill(id: rule.skill) {
                        EnemySkillRow(skill: skill, leadingIcon: "arrow.turn.down.right", note: rule.plainDescription,
                                      isNext: next?.ruleIndex == index)
                    }
                }
            }
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
