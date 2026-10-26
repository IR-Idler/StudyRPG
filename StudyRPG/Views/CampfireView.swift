import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Campfire (game.md §11)

struct CampfireView: View {
    @Bindable var run: RunState
    let nodeID: Int
    var onDone: () -> Void

    @State private var showParty = false
    @State private var showStudy = false

    private var canStudy: Bool { run.heroes.contains { !$0.upgradableSkills.isEmpty } }

    private var config: CampfireConfig { run.content.balance.campfire }

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            VStack(spacing: 0) {
                RunHUD(run: run)
                ZStack {
                    // The scene reaches the screen edges; the choices stay inside the safe area.
                    CampfireSceneView(heroes: run.heroes)
                        .ignoresSafeArea(edges: [.horizontal, .bottom])

                    HStack {
                        choice(icon: "bed.double.fill", accessibility: "Rest") {
                            HStack(spacing: 3) {
                                Text("+\(config.restHeal)")
                                Image(systemName: "heart.fill")
                                Image(systemName: "person.2.fill").font(.system(size: 12))
                            }
                            .foregroundStyle(Palette.health)
                        } action: {
                            Sound.play(.heal)
                            run.rest(at: nodeID)
                            onDone()
                        }
                        Spacer()
                        if canStudy {
                            // Study: upgrade one skill for the rest of the run (game.md §11).
                            choice(icon: "book.fill", accessibility: "Study") {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                    Image(systemName: "arrow.up")
                                }
                                .foregroundStyle(Palette.goldGlow)
                            } action: {
                                Sound.play(.tap)
                                showStudy = true
                            }
                            .padding(.trailing, 12)
                        }
                        choice(icon: "figure.strengthtraining.traditional", accessibility: "Train") {
                            HStack(spacing: 3) {
                                // +damage on every damage roll, for the rest of the run.
                                Text("+\(config.trainDamageBonus)")
                                Image(systemName: "arrow.up.circle.fill")
                                Image(systemName: "person.2.fill").font(.system(size: 12))
                            }
                            .foregroundStyle(Palette.strength)
                        } action: {
                            Sound.play(.buff)
                            run.train(at: nodeID)
                            onDone()
                        }
                    }
                    .padding(.horizontal, 28)

                    // Swapping skills and gear is free and doesn't use up the campfire.
                    Button {
                        showParty = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Image(systemName: "arrow.left.arrow.right")
                            Image(systemName: "shield.lefthalf.filled")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 110)
                    }
                    .buttonStyle(QuestButtonStyle(kind: .primary))
                    .accessibilityLabel("Change skills and gear")
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 14)
                }
            }

            if showStudy {
                StudyPickerView(run: run, nodeID: nodeID, onDone: onDone) { showStudy = false }
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showParty) {
            PartyInventorySheet(run: run, initialSelection: .hero(0))
        }
        // The fire crackles while you sit at it (game.md §19).
        .onAppear { Sound.startLoop(.campfire) }
        .onDisappear { Sound.stopLoop() }
    }

    private func choice<Label: View>(icon: String, accessibility: LocalizedStringKey, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.goldGlow)
                label()
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .frame(width: 130, height: 108)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.panel.opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.gold, lineWidth: 1.5))
            .shadow(color: Palette.gold.opacity(0.3), radius: 8)
        }
        .buttonStyle(.gamePlain)
        .accessibilityLabel(accessibility)
    }
}
