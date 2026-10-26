import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Run end recap (game.md §3)

struct RunEndView: View {
    let run: RunState
    var onExit: () -> Void

    var body: some View {
        ZStack {
            SceneryBackground()
            VStack(spacing: 18) {
                Text(run.isComplete ? "VICTORY" : "DEFEAT")
                    .font(.serif(34, .bold))
                    .foregroundStyle(run.isComplete ? Palette.goldGlow : Palette.crimson)
                    .shadow(color: run.isComplete ? Palette.goldGlow : Palette.crimson, radius: 10)

                HStack(spacing: 14) {
                    RewardChip {
                        Image(systemName: "burst.fill").font(.system(size: 20)).foregroundStyle(Palette.damage)
                    } label: {
                        Text("\(run.stats.fightsWon)")
                    }
                    RewardChip {
                        GoldCoin(size: 20)
                    } label: {
                        Text("\(run.stats.goldEarned)")
                    }
                    RewardChip {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.health)
                    } label: {
                        Text("\(run.stats.cardsCorrect)/\(run.stats.cardsAnswered)")
                    }
                    if !run.relics.isEmpty {
                        RewardChip {
                            RelicTray(relics: run.relics, size: 22)
                        } label: {
                            Text("\(run.relics.count)")
                        }
                    }
                }

                Button(action: onExit) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 60)
                }
                .buttonStyle(QuestButtonStyle(kind: .primary))
                .accessibilityLabel("Back to menu")
            }
            .parchment()
        }
        .overlay(alignment: .topTrailing) {
            SettingsGearButton(chipSize: 32)
                .padding(.trailing, 16)
                .padding(.top, 10)
        }
    }
}

// MARK: - Run history (game.md §3)

/// Every finished run, newest first: a summary strip on top, then one row per run as symbols.
/// Tap a row to see its decks, skills and gear.
struct RunHistoryView: View {
    @State private var records: [RunRecord] = []
    @State private var expandedID: UUID?

    private var content: GameContent? { ContentLoader.loaded }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if records.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "scroll").font(.system(size: 30)).foregroundStyle(Palette.ink.opacity(0.5))
                        Text("No finished runs yet.").font(.readable(14))
                    }
                    .frame(maxWidth: .infinity)
                    .parchment()
                } else {
                    summary
                    ForEach(records) { record in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedID = expandedID == record.id ? nil : record.id
                            }
                        } label: {
                            row(record)
                        }
                        .buttonStyle(.gamePlain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DeskBackground())
        .navigationTitle("History")
        .themedNavigationBar()
        .onAppear { records = RunHistoryStore.load() }
    }

    // MARK: Summary

    private var summary: some View {
        let wins = records.filter { $0.outcome == .victory }.count
        let answered = records.reduce(0) { $0 + $1.cardsAnswered }
        let correct = records.reduce(0) { $0 + $1.cardsCorrect }
        let bestDepth = records.map(\.rowsReached).max() ?? 0
        let total = records.first?.totalRows ?? 0
        return HStack(spacing: 18) {
            stat("flag.checkered", "\(records.count)", Palette.ink)
            stat("crown.fill", "\(wins)", Color(red: 0.62, green: 0.48, blue: 0.12))
            stat("map.fill", "\(bestDepth)/\(total)", Palette.ink)
            stat("burst.fill", "\(records.reduce(0) { $0 + $1.fightsWon })", Palette.crimson)
            if answered > 0 {
                stat("checkmark.circle.fill", "\(Int((Double(correct) / Double(answered) * 100).rounded()))%", Palette.moss)
            }
            Spacer(minLength: 0)
        }
        .parchmentRow()
    }

    // MARK: One run

    private func row(_ record: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                outcomeBadge(record.outcome)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.endedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.readable(12, .bold))
                    if let duration = record.duration {
                        HStack(spacing: 3) {
                            Image(systemName: "clock").font(.system(size: 9, weight: .bold))
                            Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes], width: .narrow))
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                    }
                }
                .frame(width: 120, alignment: .leading)

                HStack(spacing: 6) {
                    ForEach(record.heroes, id: \.classID) { hero in
                        VStack(spacing: 2) {
                            SpriteView(spriteId: hero.spriteID, kind: .hero, targetHeight: 28)
                                .frame(width: 26, height: 30)
                                .saturation(hero.hp > 0 ? 1 : 0)
                            HPBarView(current: hero.hp, max: max(1, hero.maxHP), width: 28, height: 4)
                        }
                    }
                }

                // How far along the map the party got.
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Image(systemName: "map.fill").font(.system(size: 9, weight: .bold))
                        Text("\(record.rowsReached)/\(record.totalRows)")
                    }
                    ProgressView(value: Double(record.rowsReached), total: Double(max(1, record.totalRows)))
                        .tint(record.outcome == .victory ? Palette.gold : Palette.ink.opacity(0.55))
                        .frame(width: 60)
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))

                stat("burst.fill", "\(record.fightsWon)", Palette.crimson)
                if record.elitesWon > 0 {
                    stat("crown", "\(record.elitesWon)", Color(red: 0.62, green: 0.48, blue: 0.12))
                }
                HStack(spacing: 3) {
                    GoldCoin(size: 13)
                    Text("\(record.goldEarned)")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                stat("checkmark.circle.fill", accuracyText(record), Palette.moss)

                Spacer(minLength: 0)

                RelicTray(relics: record.relicIDs.compactMap { content?.relicDef(id: $0) }, size: 22)

                if !record.defeatedBy.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.crimson)
                        ForEach(Array(record.defeatedBy.enumerated()), id: \.offset) { _, enemyID in
                            if let enemy = content?.enemyDef(id: enemyID) {
                                SpriteView(spriteId: enemy.spriteId, kind: .enemy, size: 22)
                            }
                        }
                    }
                    .accessibilityLabel("Defeated by \(record.defeatedBy.compactMap { content?.enemyDef(id: $0)?.name }.joined(separator: ", "))")
                }

                Image(systemName: expandedID == record.id ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.ink.opacity(0.4))
            }

            if expandedID == record.id {
                details(record)
                    .transition(.opacity)
            }
        }
        .parchmentRow()
        .contentShape(Rectangle())
    }

    private func details(_ record: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Palette.ink.opacity(0.2))
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 11, weight: .bold))
                Text(record.deckNames.joined(separator: ", ")).font(.readable(12))
                Spacer(minLength: 8)
                if record.goldSpent > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "cart.fill").font(.system(size: 10, weight: .bold))
                        Text("−\(record.goldSpent)")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
            ForEach(record.heroes, id: \.classID) { hero in
                HStack(spacing: 8) {
                    SpriteView(spriteId: hero.spriteID, kind: .hero, targetHeight: 22)
                        .frame(width: 22, height: 24)
                    Text("\(hero.hp)/\(hero.maxHP)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                        .frame(width: 44, alignment: .leading)
                    // Every skill the hero knew at the end.
                    HStack(spacing: 4) {
                        ForEach(hero.skillIDs, id: \.self) { skillID in
                            if let skill = content?.classDef(id: hero.classID)?.skill(id: skillID) {
                                SkillIcon(skill: skill, size: 24)
                                    .accessibilityElement()
                                    .accessibilityLabel(skill.name)
                            }
                        }
                    }
                    ForEach(hero.gearIDs, id: \.self) { gearID in
                        if let gear = content?.gearDef(id: gearID) {
                            GearArt(gear: gear, size: 22).accessibilityLabel(gear.name)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Pieces

    private func outcomeBadge(_ outcome: RunRecord.Outcome) -> some View {
        let label: LocalizedStringKey = switch outcome {
        case .victory: "Victory"
        case .defeat: "Defeat"
        case .abandoned: "Abandoned"
        }
        let (icon, tint): (String, Color) = switch outcome {
        case .victory: ("crown.fill", Color(red: 0.62, green: 0.48, blue: 0.12))
        case .defeat: ("xmark.shield.fill", Palette.crimson)
        case .abandoned: ("flag.slash.fill", Palette.ink.opacity(0.5))
        }
        return Image(systemName: icon)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint.opacity(0.15)))
            .accessibilityLabel(label)
    }

    private func accuracyText(_ record: RunRecord) -> String {
        guard let accuracy = record.accuracy else { return "–" }
        return "\(record.cardsCorrect)/\(record.cardsAnswered) · \(Int((accuracy * 100).rounded()))%"
    }

    private func stat(_ icon: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            Text(value).foregroundStyle(Palette.ink)
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
    }
}
