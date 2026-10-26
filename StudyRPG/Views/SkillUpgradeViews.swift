import SwiftUI

// MARK: - Campfire Study: upgrade one skill (game.md §5 "Skill upgrades", §11)

/// Every known skill either hero can still upgrade, shown before → after. Tapping one studies it
/// (uses up the campfire); the back button returns to the campfire's choices.
struct StudyPickerView: View {
    @Bindable var run: RunState
    let nodeID: Int
    var onDone: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        Sound.play(.tap)
                        onCancel()
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 44)
                    }
                    .buttonStyle(QuestButtonStyle(kind: .secondary))
                    .accessibilityLabel("Back")
                    Image(systemName: "book.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.gold)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Palette.gold)
                    Spacer()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(run.heroes.enumerated()), id: \.offset) { index, hero in
                            if !hero.upgradableSkills.isEmpty {
                                HStack(alignment: .top, spacing: 10) {
                                    SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: 44)
                                        .frame(width: 38, height: 46)
                                    VStack(spacing: 6) {
                                        ForEach(hero.upgradableSkills) { skill in
                                            Button {
                                                Sound.play(.skillLearn)
                                                run.study(heroAt: index, skillID: skill.id, at: nodeID)
                                                onDone()
                                            } label: {
                                                SkillUpgradeRow(skill: skill)
                                            }
                                            .buttonStyle(.gamePlain)
                                            .accessibilityLabel("Upgrade \(skill.name)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 560, maxHeight: 320)
            .parchment(padding: 16)
        }
    }
}

/// One skill's upgrade: its emblem and name, then the base version → the upgraded version.
struct SkillUpgradeRow: View {
    let skill: SkillDef

    var body: some View {
        HStack(spacing: 8) {
            SkillIcon(skill: skill, size: 32)
            Text(skill.name)
                .font(.readable(13, .bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            SkillSpecChip(skill: skill)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Palette.gold)
            SkillSpecChip(skill: skill.upgraded())
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.gold.opacity(0.7), lineWidth: 1))
    }
}

/// What a skill does and costs, on a dark chip: effects, action points, mana and cooldown.
private struct SkillSpecChip: View {
    let skill: SkillDef

    var body: some View {
        HStack(spacing: 5) {
            SkillEffectSummary(skill: skill)
            ActionPointCostBadge(cost: skill.actionPoints)
            if let cost = skill.cost {
                HStack(spacing: 1) {
                    Image(systemName: "diamond.fill").font(.system(size: 7, weight: .bold))
                    Text("\(cost)")
                }
                .foregroundStyle(Palette.mana)
            }
            if let cooldown = skill.cooldown {
                HStack(spacing: 1) {
                    Image(systemName: "hourglass").font(.system(size: 7, weight: .bold))
                    Text("\(cooldown)")
                }
                .foregroundStyle(Palette.block)
            }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.ink.opacity(0.88)))
    }
}
