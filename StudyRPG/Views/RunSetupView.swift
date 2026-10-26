import SwiftUI

// MARK: - Run setup (game.md §3)

/// Pick exactly two heroes of different classes and at least one deck, then start a run.
/// Party on the left, decks on the right, the start button bottom-right where the thumb is.
struct RunSetupView: View {
    @Environment(DeckStore.self) private var deckStore
    let content: GameContent
    var onStart: (_ heroes: [HeroClassDef], _ decks: [Deck]) -> Void

    @State private var selectedClassIDs: [String] = []
    @State private var selectedDeckIDs: Set<UUID> = []

    private var usableDecks: [Deck] {
        deckStore.decks.filter { $0.cards.count >= content.balance.flashcards.minDeckSize }
    }

    private var canStart: Bool { selectedClassIDs.count == 2 && !selectedDeckIDs.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // Party: tap to toggle, exactly two.
            VStack(alignment: .leading, spacing: 10) {
                SectionHeaderLabel(text: "Party")
                HStack(spacing: 12) {
                    ForEach(content.classes) { heroClass in
                        HeroPickCard(heroClass: heroClass, selected: selectedClassIDs.contains(heroClass.id)) {
                            Sound.play(.tap)
                            toggle(heroClass)
                        }
                    }
                }
                Text("Two heroes of different classes share every flashcard you answer.")
                    .font(.serif(11))
                    .italic()
                    .foregroundStyle(Palette.text.opacity(0.75))
                    .shadow(color: .black, radius: 3)
                    .frame(maxWidth: 260, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeaderLabel(text: "Decks")
                DeckPickerList(
                    decks: usableDecks,
                    minDeckSize: content.balance.flashcards.minDeckSize,
                    selection: $selectedDeckIDs
                )
                HStack(spacing: 12) {
                    Text(statusText)
                        .font(.serif(12, .semibold))
                        .foregroundStyle(canStart ? Palette.text.opacity(0.85) : Palette.ember)
                        .shadow(color: .black, radius: 3)
                    Spacer()
                    Button {
                        let heroes = selectedClassIDs.compactMap { content.classDef(id: $0) }
                        let decks = deckStore.decks.filter { selectedDeckIDs.contains($0.id) }
                        LastDeckSelection.save(selectedDeckIDs)
                        onStart(heroes, decks)
                    } label: {
                        Label("Begin", systemImage: "play.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(QuestButtonStyle(kind: .primary))
                    .disabled(!canStart)
                    .accessibilityLabel("Start run")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(SceneryBackground())
        .themedNavigationBar()
        .onAppear {
            if selectedClassIDs.isEmpty {
                selectedClassIDs = Array(content.classes.prefix(2).map(\.id))
            }
            // The last run's decks start selected (every usable deck the first time).
            if selectedDeckIDs.isEmpty {
                selectedDeckIDs = LastDeckSelection.initialSelection(usable: usableDecks)
            }
        }
    }

    private var statusText: String {
        if selectedClassIDs.count != 2 { return L("Pick two heroes") }
        if usableDecks.isEmpty { return L("Add a deck with \(content.balance.flashcards.minDeckSize)+ cards first") }
        if selectedDeckIDs.isEmpty { return L("Pick at least one deck") }
        let cards = usableDecks.filter { selectedDeckIDs.contains($0.id) }.reduce(0) { $0 + $1.cards.count }
        return L("\(cards) cards in the pool")
    }

    /// Exactly two different classes (game.md §3): tapping a third replaces the oldest pick.
    private func toggle(_ heroClass: HeroClassDef) {
        if let index = selectedClassIDs.firstIndex(of: heroClass.id) {
            selectedClassIDs.remove(at: index)
        } else {
            selectedClassIDs.append(heroClass.id)
            if selectedClassIDs.count > 2 { selectedClassIDs.removeFirst() }
        }
    }
}

/// A hero class as a dark gilded card: portrait on a small island, name, HP and mana.
private struct HeroPickCard: View {
    let heroClass: HeroClassDef
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    if selected {
                        Ellipse()
                            .fill(RadialGradient(colors: [Palette.goldGlow.opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 60))
                            .frame(width: 120, height: 110)
                    }
                    SpriteView(spriteId: heroClass.spriteId, kind: .hero, targetHeight: 96)
                }
                .frame(height: 104)
                Text(heroClass.name).font(.serif(14, .bold))
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                        Text("\(heroClass.maxHP)")
                    }
                    .foregroundStyle(Palette.health)
                    if let res = heroClass.resource {
                        HStack(spacing: 2) {
                            Image(systemName: "diamond.fill")
                            Text("\(res.max)")
                        }
                        .foregroundStyle(Palette.mana)
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Palette.text)
            .padding(10)
            .frame(width: 124)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.panel.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Palette.goldGlow : Palette.gold.opacity(0.25), lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Palette.goldGlow : Palette.text.opacity(0.35))
                    .padding(7)
            }
            .opacity(selected ? 1 : 0.65)
            .animation(.easeOut(duration: 0.15), value: selected)
        }
        .buttonStyle(.gamePlain)
        .accessibilityLabel(heroClass.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Selectable deck rows on one parchment card, shared by run setup and Test Fight.
struct DeckPickerList: View {
    let decks: [Deck]
    let minDeckSize: Int
    @Binding var selection: Set<UUID>

    var body: some View {
        VStack(spacing: 0) {
            if decks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                    Text("No deck has \(minDeckSize)+ cards yet. Add one in Decks.")
                        .font(.readable(13))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(decks.enumerated()), id: \.element.id) { index, deck in
                            if index > 0 {
                                Rectangle().fill(Palette.ink.opacity(0.1)).frame(height: 1).padding(.leading, 48)
                            }
                            row(deck)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.parchment))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.ink.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    private func row(_ deck: Deck) -> some View {
        let isSelected = selection.contains(deck.id)
        return Button {
            Sound.play(.tap)
            if isSelected { selection.remove(deck.id) } else { selection.insert(deck.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: deck.icon ?? "rectangle.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(deck.color.map { Color(hex: $0) } ?? Palette.gold)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.ink.opacity(0.85)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(deck.name).font(.readable(14, .semibold))
                    if let subtitle = deck.subtitle {
                        Text(subtitle)
                            .font(.readable(11))
                            .foregroundStyle(Palette.ink.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 6)
                if deck.includesReverse {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.ink.opacity(0.45))
                }
                Text("\(deck.cards.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color(red: 0.30, green: 0.48, blue: 0.26) : Palette.ink.opacity(0.3))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gamePlain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
