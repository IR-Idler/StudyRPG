import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Flashcard Quiz Overlay with Timed Feedback

struct FlashcardQuizOverlay: View {
    var card: PresentedCard
    /// Chosen option index and the real response time in ms (logged to the answer history, game.md §4.2).
    var onAnswer: (Int?, Int) -> Void

    @State private var selectedIndex: Int? = nil
    @State private var hasAnswered = false
    @State private var shownAt = Date()
    @State private var showHint = false
    /// Waiting for the player to tap Continue (teaching moment after an answer).
    @State private var waitingForContinue = false
    @State private var pendingAnswer: (index: Int?, ms: Int)?
    /// Card pictures, decoded once per card instead of on every redraw.
    @State private var images: [String: PlatformImage] = [:]
    @Environment(GameSettings.self) private var settings

    /// Right/wrong marks: moss/crimson.
    private var good: Color { Palette.health }
    private var bad: Color { Palette.damage }
    /// Answer-letter ring: a circle.
    private var badgeShape: AnyShape {
        AnyShape(Circle())
    }

    private var allOptionsArePictures: Bool {
        !card.options.isEmpty && card.options.allSatisfy { $0.face.isPictureOnly }
    }

    private var nonEmptyPrompt: String? {
        guard let p = card.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else { return nil }
        return p
    }

    private var nonEmptyHint: String? {
        guard let h = card.hint?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty else { return nil }
        return h
    }

    private var nonEmptyExplanation: String? {
        guard let e = card.explanation?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty else { return nil }
        return e
    }

    var body: some View {
        // Short cards sit at their natural size; tall ones (pictures + hint + explanation on a
        // landscape phone) scroll instead of being cut off.
        ViewThatFits(in: .vertical) {
            content
            // Indicator shown so an overflowing card visibly has more below.
            ScrollView(.vertical, showsIndicators: true) { content }
        }
        .modifier(QuizCardFrame())
        .frame(maxWidth: 480)
        .padding(.vertical, 6)
        .onAppear { reset() }
        .onChange(of: card.cardID) { _, _ in reset() }
    }

    private func reset() {
        Sound.play(.cardFlip)
        shownAt = Date()
        showHint = false
        selectedIndex = nil
        hasAnswered = false
        waitingForContinue = false
        pendingAnswer = nil
        var loaded: [String: PlatformImage] = [:]
        for face in [card.question] + card.options.map(\.face) {
            if let id = face.imageID, loaded[id] == nil, let image = CardImageStore.load(id) {
                loaded[id] = image
            }
        }
        images = loaded
    }

    private var content: some View {
        VStack(spacing: 10) {
            if nonEmptyPrompt != nil || nonEmptyHint != nil || card.isReversed {
                HStack(spacing: 8) {
                    if let prompt = nonEmptyPrompt {
                        Text(prompt)
                            .font(.readable(14, .semibold))
                            .foregroundStyle(Palette.ink.opacity(0.68))
                    } else if card.isReversed {
                        // Reverse cards have no authored prompt; say what's being asked.
                        Label("Which one matches?", systemImage: "arrow.left.arrow.right")
                            .font(.readable(14, .semibold))
                            .foregroundStyle(Palette.ink.opacity(0.68))
                    }
                    Spacer(minLength: 4)
                    if nonEmptyHint != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showHint.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showHint ? "lightbulb.fill" : "lightbulb")
                                    .font(.system(size: 13, weight: .bold))
                                Text(showHint ? "Hide Hint" : "Hint")
                                    .font(.readable(12, .semibold))
                            }
                            .foregroundStyle(Palette.ink.opacity(0.85))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Palette.gold.opacity(showHint ? 0.42 : 0.22)))
                            .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.75), lineWidth: 1))
                        }
                        .buttonStyle(.gamePlain)
                    }
                }
            }

            // Continue sits right of the question so it never has to be scrolled to.
            HStack(spacing: 10) {
                faceView(card.question, isQuestion: true)
                    .font(.readable(20, .bold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)

                // Always laid out (invisible until needed), so the options never jump down when
                // Continue appears after an answer.
                Button {
                    finish()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 30)
                }
                .buttonStyle(QuestButtonStyle(kind: .primary))
                .accessibilityLabel("Continue")
                // Return continues (Mac, game.md §15); only while Continue is showing.
                .macKeyboardShortcut(.defaultAction, isEnabled: waitingForContinue)
                .opacity(waitingForContinue ? 1 : 0)
                .scaleEffect(waitingForContinue ? 1 : 0.8)
                .allowsHitTesting(waitingForContinue)
                .accessibilityHidden(!waitingForContinue)
            }

            if showHint, let hint = nonEmptyHint {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.58, green: 0.42, blue: 0.08))
                    Text(hint)
                        .font(.readable(13))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Palette.gold.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.gold.opacity(0.55), lineWidth: 1))
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if allOptionsArePictures {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(card.options.enumerated()), id: \.offset) { index, option in
                        optionButton(index: index, option: option, isGridTile: true)
                    }
                }
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(card.options.enumerated()), id: \.offset) { index, option in
                        optionButton(index: index, option: option, isGridTile: false)
                    }
                }
            }

            noneOfTheseButton

            if hasAnswered, let explanation = nonEmptyExplanation {
                let wasRight = selectedIndex == card.correctOptionIndex
                HStack(spacing: 8) {
                    Image(systemName: wasRight ? "checkmark.seal.fill" : "info.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(wasRight ? good : bad)
                    Text(explanation)
                        .font(.readable(14, .semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill((wasRight ? good : bad).opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder((wasRight ? good : bad).opacity(0.45), lineWidth: 1)
                        )
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func optionButton(index: Int, option: PresentedOption, isGridTile: Bool) -> some View {
        let isSelected = selectedIndex == index
        let isCorrectChoice = card.correctOptionIndex == index
        let showResult = hasAnswered
        let optionSeed = index + 1

        Button {
            guard !hasAnswered else { return }
            handleSelect(index: index)
        } label: {
            if isGridTile {
                ZStack(alignment: .topLeading) {
                    faceView(option.face, isQuestion: false, isGridTile: true)
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)

                    HStack {
                        Text(optionBadge(index))
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(badgeColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult))
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(Palette.parchment.opacity(0.88))
                                    .overlay(
                                        badgeShape
                                            .stroke(badgeColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult), lineWidth: 1.5)
                                    )
                            )
                        Spacer()
                        if showResult {
                            if isCorrectChoice {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(good)
                            } else if isSelected {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(bad)
                            }
                        }
                    }
                    .padding(7)
                }
                .modifier(optionFrame(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult, seed: optionSeed))
            } else {
                HStack(spacing: 12) {
                    Text(optionBadge(index))
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundStyle(badgeColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult))
                        .frame(width: 24, height: 24)
                        .background(
                            badgeShape
                                .stroke(badgeColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult), lineWidth: 1.5)
                        )

                    faceView(option.face, isQuestion: false, isGridTile: false)
                        .font(.readable(16, .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    Group {
                        if showResult {
                            if isCorrectChoice {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(good)
                            } else if isSelected {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(bad)
                            }
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .modifier(optionFrame(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult, seed: optionSeed))
            }
        }
        .buttonStyle(.gamePlain)
        .macKeyboardShortcut(optionKey(index))
        .disabled(hasAnswered)
    }

    private func handleSelect(index: Int?) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedIndex = index
            hasAnswered = true
        }
        let responseMs = Int(Date().timeIntervalSince(shownAt) * 1000)
        pendingAnswer = (index, responseMs)
        let wasRight = index == card.correctOptionIndex
        Sound.play(wasRight ? .correct : .wrong)

        // Teaching moment (game.md §4.1): each kind of answer either waits for a tap on Continue
        // (Settings) or moves on by itself — a right answer immediately, a wrong one after a beat
        // so the correct option can be seen.
        let waits = wasRight ? settings.waitAfterRightAnswer : settings.waitAfterWrongAnswer
        if waits {
            withAnimation(.easeInOut(duration: 0.2)) { waitingForContinue = true }
        } else if wasRight {
            finish()
        } else {
            autoFinish(after: .milliseconds(1600))
        }
    }

    private func autoFinish(after delay: Duration) {
        let cardID = card.cardID
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard card.cardID == cardID else { return }
            finish()
        }
    }

    /// Hands the answer on exactly once.
    private func finish() {
        guard let answer = pendingAnswer else { return }
        pendingAnswer = nil
        waitingForContinue = false
        onAnswer(answer.index, answer.ms)
    }

    @ViewBuilder
    private var noneOfTheseButton: some View {
        let isSelected = hasAnswered && selectedIndex == nil
        let isCorrectChoice = card.correctOptionIndex == nil
        let showResult = hasAnswered
        let optionSeed = 9

        Button {
            guard !hasAnswered else { return }
            handleSelect(index: nil)
        } label: {
            HStack(spacing: 12) {
                Text(optionBadge(4))
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(badgeColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult))
                    .frame(width: 24, height: 24)
                    .background(
                        badgeShape
                            .stroke(badgeColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult), lineWidth: 1.5)
                    )

                Text("None of these")
                    .font(.readable(15, .semibold))
                    .italic()
                    .foregroundStyle(Palette.ink.opacity(0.85))
                    .frame(maxWidth: .infinity)

                Group {
                    if showResult {
                        if isCorrectChoice {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(good)
                        } else if isSelected {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(bad)
                        }
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .modifier(optionFrame(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult, seed: optionSeed))
        }
        .buttonStyle(.gamePlain)
        .macKeyboardShortcut(optionKey(4))
        .disabled(hasAnswered)
    }

    /// A–E on iOS; on Mac the number key that picks it (1–4, "None of these" 5 — game.md §15).
    private func optionBadge(_ index: Int) -> String {
        #if os(macOS)
        "\(index % 5 + 1)"
        #else
        ["A", "B", "C", "D", "E"][index % 5]
        #endif
    }

    /// The number key for option `index` (Mac).
    private func optionKey(_ index: Int) -> KeyboardShortcut {
        KeyboardShortcut(KeyEquivalent(Character("\(index % 5 + 1)")), modifiers: [])
    }

    private func badgeColor(isSelected: Bool, isCorrectChoice: Bool, showResult: Bool) -> Color {
        if showResult {
            if isCorrectChoice { return good }
            if isSelected { return bad }
        }
        return Palette.ink.opacity(0.6)
    }

    private func backgroundColor(isSelected: Bool, isCorrectChoice: Bool, showResult: Bool) -> Color {
        if showResult {
            if isCorrectChoice { return good.opacity(0.18) }
            if isSelected { return bad.opacity(0.16) }
        }
        return isSelected ? Palette.gold.opacity(0.20) : Color.white.opacity(0.55)
    }

    private func borderColor(isSelected: Bool, isCorrectChoice: Bool, showResult: Bool) -> Color {
        if showResult {
            if isCorrectChoice { return good }
            if isSelected { return bad }
        }
        return isSelected ? Palette.gold : Palette.ink.opacity(0.2)
    }

    private func optionFrame(isSelected: Bool, isCorrectChoice: Bool, showResult: Bool, seed: Int) -> OptionFrame {
        OptionFrame(
            fill: backgroundColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult),
            line: borderColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice, showResult: showResult),
            lineWidth: isSelected || (showResult && isCorrectChoice) ? 2 : 1
        )
    }

    @ViewBuilder
    private func faceView(_ face: CardFace, isQuestion: Bool, isGridTile: Bool = false) -> some View {
        VStack(spacing: 6) {
            if let imageID = face.imageID, let uiImage = images[imageID] ?? CardImageStore.load(imageID) {
                Image(platformImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: isQuestion ? 110 : (isGridTile ? 68 : 48))
            }
            if let symbol = face.symbol, !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: isQuestion ? 44 : (isGridTile ? 34 : 24), weight: .semibold))
                    .foregroundStyle(face.color.map { Color(hex: $0) } ?? Palette.ink)
                    .frame(height: isQuestion ? 54 : (isGridTile ? 44 : 30))
            } else if let color = face.color, !color.isEmpty {
                RoundedRectangle(cornerRadius: isQuestion ? 14 : 10, style: .continuous)
                    .fill(Color(hex: color))
                    .frame(
                        width: isQuestion ? 84 : (isGridTile ? 68 : 44),
                        height: isQuestion ? 60 : (isGridTile ? 48 : 30)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: isQuestion ? 14 : 10, style: .continuous)
                            .strokeBorder(Palette.ink.opacity(0.28), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            }
            if let text = face.text, !text.isEmpty {
                Text(text)
            }
        }
    }
}

/// One answer's box: a rounded box.
private struct OptionFrame: ViewModifier {
    let fill: Color
    let line: Color
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 10).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(line, lineWidth: lineWidth))
    }
}

/// The quiz card itself: a parchment card with a gold rim.
private struct QuizCardFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Palette.parchment, Palette.parchmentShade],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.65), radius: 18, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Palette.gold, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
