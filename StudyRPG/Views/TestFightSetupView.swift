import SwiftUI

// MARK: - Standalone Test Fight entry point (developer harness, game.md §7)

/// Pick any encounter (as portrait tiles, each listed once) and decks, then fight it outside a
/// run. Every usable deck starts selected.
struct TestFightSetupView: View {
    @Environment(DeckStore.self) private var deckStore
    @Environment(CardStatsStore.self) private var statsStore
    let content: GameContent

    @State private var selectedKey: String?
    @State private var selectedDeckIDs: Set<UUID> = []
    @State private var engine: CombatEngine?
    @State private var isFighting = false

    /// One entry per distinct encounter (the same roster can appear in several depth pools).
    private struct Option: Identifiable {
        let id: String
        let encounter: EncounterDef
        let nodeType: MapNodeType
    }

    private var options: [Option] {
        var seen = Set<String>()
        var result: [Option] = []
        for pool in content.encounterPools {
            for encounter in pool.encounters {
                let key = encounter.enemyIds.joined(separator: "+") + "@" + encounter.theme
                if seen.insert(key).inserted {
                    result.append(Option(id: key, encounter: encounter, nodeType: pool.nodeType))
                }
            }
        }
        return result
    }

    private var selectedOption: Option? { options.first { $0.id == selectedKey } }

    private var usableDecks: [Deck] {
        deckStore.decks.filter { $0.cards.count >= content.balance.flashcards.minDeckSize }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeaderLabel(text: "Encounter")
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                        ForEach(options) { option in
                            EncounterTile(
                                enemies: option.encounter.enemyIds.compactMap { content.enemyDef(id: $0) },
                                nodeType: option.nodeType,
                                selected: option.id == selectedKey
                            ) {
                                Sound.play(.tap)
                                selectedKey = option.id
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                SectionHeaderLabel(text: "Decks")
                DeckPickerList(decks: usableDecks, minDeckSize: content.balance.flashcards.minDeckSize, selection: $selectedDeckIDs)
                Text("Test fights carry one of each potion; no relics, gear or training.")
                    .font(.serif(11))
                    .italic()
                    .foregroundStyle(Palette.text.opacity(0.75))
                    .shadow(color: .black, radius: 3)
                Spacer(minLength: 0)
                Button {
                    start()
                } label: {
                    Label("Fight", systemImage: "burst.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuestButtonStyle(kind: .primary))
                .disabled(selectedOption == nil || selectedDeckIDs.isEmpty)
            }
            .frame(width: 270)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(SceneryBackground())
        .themedNavigationBar()
        .onAppear {
            if selectedDeckIDs.isEmpty { selectedDeckIDs = Set(usableDecks.map(\.id)) }
            if selectedKey == nil { selectedKey = options.first?.id }
        }
        .navigationDestination(isPresented: $isFighting) {
            if let engine {
                FightView(
                    engine: engine,
                    theme: selectedOption.flatMap { content.theme(id: $0.encounter.theme) },
                    onComplete: { _ in isFighting = false },
                    onAbandon: { isFighting = false }
                )
            }
        }
    }

    private func start() {
        guard let selectedOption else { return }
        let enemyDefs = selectedOption.encounter.enemyIds.compactMap { content.enemyDef(id: $0) }
        let decks = deckStore.decks.filter { selectedDeckIDs.contains($0.id) }
        engine = CombatEngine(
            heroClasses: content.classes,
            enemyDefs: enemyDefs,
            balance: content.balance,
            decks: decks,
            statsStore: statsStore,
            inventory: content.items
        )
        isFighting = true
    }
}

/// An encounter as a dark tile: the enemies' portraits, their names and a tier mark.
private struct EncounterTile: View {
    let enemies: [EnemyDef]
    let nodeType: MapNodeType
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(enemies.enumerated()), id: \.offset) { _, enemy in
                        SpriteView(spriteId: enemy.spriteId, kind: .enemy, targetHeight: enemies.count > 2 ? 40 : 50)
                            .frame(maxWidth: 52)
                    }
                    Spacer(minLength: 4)
                    if let mark = tierMark {
                        Image(systemName: mark.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(mark.tint)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(height: 52)
                Text(names)
                    .font(.serif(12, .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(alignment: .bottom) {
                // A sliver of floor under the portraits.
                Ellipse()
                    .fill(RadialGradient(colors: [Palette.gold.opacity(selected ? 0.25 : 0.12), .clear], center: .center, startRadius: 2, endRadius: 80))
                    .frame(height: 40)
                    .offset(y: -18)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.panel.opacity(selected ? 0.95 : 0.82)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Palette.goldGlow : Palette.gold.opacity(0.25), lineWidth: selected ? 2 : 1))
            .shadow(color: selected ? Palette.gold.opacity(0.35) : .clear, radius: 8)
        }
        .buttonStyle(.gamePlain)
        .accessibilityLabel(names)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// "Goblin ×2 + Wolf" rather than repeating names.
    private var names: String {
        var counts: [(String, Int)] = []
        for enemy in enemies {
            if let index = counts.firstIndex(where: { $0.0 == enemy.name }) {
                counts[index].1 += 1
            } else {
                counts.append((enemy.name, 1))
            }
        }
        return counts.map { $0.1 > 1 ? "\($0.0) ×\($0.1)" : $0.0 }.joined(separator: " + ")
    }

    private var tierMark: (icon: String, tint: Color)? {
        switch nodeType {
        case .elite: return ("seal.fill", Palette.ember)
        case .boss: return ("crown.fill", Palette.goldGlow)
        default: return nil
        }
    }
}
