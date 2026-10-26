import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Events (game.md §12)

struct EventView: View {
    @Bindable var run: RunState
    let nodeID: Int
    var onDone: () -> Void

    @State private var event: EventDef?
    @State private var quizCard: PresentedCard?
    @State private var result: (correct: Bool, applied: RunState.AppliedOutcome)?

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()

            VStack(spacing: 0) {
                RunHUD(run: run)

                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack {
                        // The scenery reaches the screen edges (under the notch); the card stays
                        // inside the safe area.
                        ThemePlaceholderPainting(theme: roadsideTheme)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea(edges: [.horizontal, .bottom])

                        // The party, standing by the road, looking at what they found.
                        HStack(alignment: .bottom, spacing: -10) {
                            ForEach(run.heroes) { hero in
                                SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: h * 0.36, breathes: false)
                                    .opacity(hero.isAlive ? 1 : 0.45)
                            }
                        }
                        .position(x: w * 0.13, y: h * 0.70)

                        if let event {
                            EventSceneView(event: event)
                                .frame(width: h * 0.72, height: h * 0.72)
                                .position(x: w * 0.38, y: h * 0.56)

                            eventCard(event)
                                .frame(width: min(330, w * 0.38))
                                .position(x: w * 0.77, y: h * 0.5)
                        } else {
                            // No events defined in content: nothing happens here.
                            continueButton.position(x: w * 0.5, y: h * 0.5)
                        }
                    }
                }
            }

            if let quizCard {
                FlashcardQuizHost(card: quizCard, flashcards: run.flashcards) { correct in
                    self.quizCard = nil
                    resolve(correct: correct)
                }
            }
        }
        .onAppear {
            run.enterNode(nodeID)
            event = run.event(for: nodeID)
            // Already answered before the app was closed: show what happened, no replay.
            if let saved = run.eventResult(at: nodeID) { result = saved }
        }
    }

    private func eventCard(_ event: EventDef) -> some View {
        VStack(spacing: 14) {
            Text(event.text)
                .font(.serif(15, .semibold))
                .multilineTextAlignment(.center)

            if let result {
                HStack(spacing: 10) {
                    Image(systemName: result.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(result.correct ? Palette.health : Palette.damage)
                    if result.applied.convertedToGold {
                        EventOutcomeLabel(type: .gold, amount: result.applied.amount)
                    } else {
                        EventOutcomeLabel(type: result.applied.type, amount: result.applied.amount,
                                          relic: result.applied.relic, potion: result.applied.potion, gear: result.applied.gear)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.ink.opacity(0.88)))
                .transition(.scale.combined(with: .opacity))

                continueButton
            } else {
                VStack(spacing: 8) {
                    outcomeRow(correct: true, outcome: event.reward)
                    outcomeRow(correct: false, outcome: event.penalty)
                }

                Button {
                    quizCard = run.flashcards.present()
                    if quizCard == nil { resolve(correct: false) }
                } label: {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 60)
                }
                .buttonStyle(QuestButtonStyle(kind: .primary))
                .accessibilityLabel("Answer a card")
            }
        }
        .parchment(padding: 16)
    }

    private var continueButton: some View {
        Button {
            run.leave(nodeID)
            onDone()
        } label: {
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 60)
        }
        .buttonStyle(QuestButtonStyle(kind: .primary))
    }

    private func outcomeRow(correct: Bool, outcome: EventOutcomeDef) -> some View {
        HStack(spacing: 8) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(correct ? Palette.health : Palette.damage)
            EventOutcomeLabel(type: outcome.type, amount: outcome.amount)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.ink.opacity(0.88)))
    }

    private func resolve(correct: Bool) {
        guard let applied = run.resolveEvent(at: nodeID, correct: correct) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            result = (correct, applied)
        }
    }
}
