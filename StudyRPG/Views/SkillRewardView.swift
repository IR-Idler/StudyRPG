import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Skill reward (game.md §5)

/// A skill offer (elite victory or shop scroll): pick which hero learns — skipped when only one
/// hero can — then one of up to three new skills, or skip. With a full loadout the player then
/// picks which equipped skill it replaces — or keeps it in the skill book only.
struct SkillRewardView: View {
    @Bindable var run: RunState
    let offer: SkillOffer
    @State private var chosenHeroID: String?
    @State private var picked: SkillDef?

    /// The heroes in the offer, in party order.
    private var offeredHeroes: [HeroState] { run.heroes.filter { offer.choices[$0.id] != nil } }
    private var heroID: String? { chosenHeroID ?? (offeredHeroes.count == 1 ? offeredHeroes.first?.id : nil) }
    private var heroIndex: Int? { heroID.flatMap { id in run.heroes.firstIndex { $0.id == id } } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    if let heroIndex {
                        SpriteView(spriteId: run.heroes[heroIndex].classDef.spriteId, kind: .hero, targetHeight: 54)
                            .frame(width: 44, height: 56)
                    }
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.gold)
                    Spacer()
                    Button {
                        Sound.play(.tap)
                        run.skipSkillOffer()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 44)
                    }
                    .buttonStyle(QuestButtonStyle(kind: .secondary))
                    .accessibilityLabel("Skip")
                }

                if let heroIndex {
                    let hero = run.heroes[heroIndex]
                    if let picked {
                        replaceStep(hero: hero, picked: picked)
                    } else {
                        skillStep(hero: hero)
                    }
                } else {
                    heroStep
                }
            }
            .frame(maxWidth: 600)
            .parchment(padding: 18)
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

    /// Who learns: each hero with a preview of the skills they'd be offered.
    private var heroStep: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(offeredHeroes) { hero in
                Button {
                    Sound.play(.tap)
                    withAnimation(.easeInOut(duration: 0.2)) { chosenHeroID = hero.id }
                } label: {
                    VStack(spacing: 8) {
                        SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: 70)
                            .frame(width: 70, height: 74)
                        Text(hero.classDef.name)
                            .font(.readable(14, .bold))
                            .foregroundStyle(Palette.ink)
                        HStack(spacing: 4) {
                            ForEach(offer.choices[hero.id] ?? [], id: \.self) { id in
                                if let skill = hero.classDef.skill(id: id) {
                                    SkillIcon(skill: skill, size: 30)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(width: 180)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.gold, lineWidth: 1.5))
                }
                .buttonStyle(.gamePlain)
                .accessibilityLabel(hero.classDef.name)
            }
        }
    }

    private func skillStep(hero: HeroState) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(offer.choices[hero.id] ?? [], id: \.self) { id in
                    if let skill = hero.classDef.skill(id: id) {
                        Button {
                            if hero.loadoutSkillIDs.count < run.maxEquippedSkills {
                                Sound.play(.skillLearn)
                                run.learnSkill(skill.id, heroID: hero.id, replacing: nil)
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) { self.picked = skill }
                            }
                        } label: {
                            SkillOfferCard(skill: skill)
                        }
                        .buttonStyle(.gamePlain)
                        .accessibilityLabel("Learn \(skill.name)")
                        .accessibilityHint(skillDescription(skill))
                    }
                }
            }
            if offeredHeroes.count > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { chosenHeroID = nil }
                } label: {
                    Image(systemName: "chevron.left").frame(width: 44)
                }
                .buttonStyle(QuestButtonStyle(kind: .secondary))
                .accessibilityLabel("Back")
            }
        }
    }

    /// Full loadout: tap the equipped skill to swap out, or keep the new one in the book only.
    private func replaceStep(hero: HeroState, picked: SkillDef) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                SkillOfferCard(skill: picked, compact: true)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.ink.opacity(0.6))
            }
            HStack(spacing: 8) {
                ForEach(hero.loadout) { equipped in
                    Button {
                        Sound.play(.skillLearn)
                        run.learnSkill(picked.id, heroID: hero.id, replacing: equipped.id)
                    } label: {
                        SkillOfferCard(skill: equipped, compact: true)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "arrow.uturn.down.circle.fill")
                                    .foregroundStyle(Palette.crimson)
                                    .offset(x: 6, y: -6)
                            }
                    }
                    .buttonStyle(.gamePlain)
                    .accessibilityLabel("Replace \(equipped.name)")
                }
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { self.picked = nil }
                } label: {
                    Image(systemName: "chevron.left").frame(width: 44)
                }
                .buttonStyle(QuestButtonStyle(kind: .secondary))
                .accessibilityLabel("Back")
                Button {
                    Sound.play(.skillLearn)
                    run.learnSkill(picked.id, heroID: hero.id, replacing: nil)
                } label: {
                    Image(systemName: "book.closed.fill").frame(width: 44)
                }
                .buttonStyle(QuestButtonStyle(kind: .secondary))
                .accessibilityLabel("Learn it, keep it unequipped")
            }
        }
    }
}

/// A big skill card: icon, name, cost / cooldown and its effects as symbols.
struct SkillOfferCard: View {
    let skill: SkillDef
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            SkillIcon(skill: skill, size: compact ? 40 : 64)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            Text(skill.displayName)
                .font(.readable(compact ? 12 : 14, .bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
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
                    .foregroundStyle(Palette.ink.opacity(0.6))
                }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .frame(height: 16)
            SkillEffectSummary(skill: skill)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(minHeight: 20)
                .background(Capsule().fill(Palette.ink.opacity(0.88)))
        }
        .padding(compact ? 8 : 12)
        .frame(width: compact ? 124 : 170, height: compact ? 118 : 158)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.gold, lineWidth: 1.5))
    }
}
