import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

#if DEBUG
// MARK: - Debug frame-rate HUD

/// Debug-only frame pacing monitor. A `CADisplayLink` ticks once per display refresh; whenever a
/// tick arrives late (the main thread missed a vsync) the skipped refreshes are counted as dropped
/// frames. Stats are published twice a second so the HUD itself costs next to nothing.
@MainActor @Observable
final class FrameRateMonitor {
    /// Frames actually delivered per second over the last sample window.
    private(set) var fps = 0
    /// Refresh rate the display link is targeting (60 on most iPhones, up to 120 on ProMotion).
    private(set) var targetFPS = 60
    /// Longest single frame in the last sample window, in milliseconds.
    private(set) var worstFrameMs = 0.0
    /// Dropped frames since launch (or the last reset).
    private(set) var droppedTotal = 0

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var windowStart: CFTimeInterval = 0
    @ObservationIgnored private var windowFrames = 0
    @ObservationIgnored private var windowWorst: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let proxy = DisplayLinkProxy(owner: self)
        #if os(macOS)
        // Mac display links come from the screen they follow.
        guard let link = NSScreen.main?.displayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:))) else { return }
        #else
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        #endif
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = 0
    }

    func reset() {
        droppedTotal = 0
        worstFrameMs = 0
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let budget = link.targetTimestamp - link.timestamp
        guard lastTimestamp > 0, budget > 0 else {
            lastTimestamp = now
            windowStart = now
            return
        }
        let delta = now - lastTimestamp
        lastTimestamp = now
        windowFrames += 1
        windowWorst = max(windowWorst, delta)
        // A frame that took ~2 budgets means one refresh was skipped, ~3 means two, etc.
        let missed = Int((delta / budget).rounded()) - 1
        if missed > 0 { droppedTotal += missed }

        let elapsed = now - windowStart
        if elapsed >= 0.5 {
            fps = Int((Double(windowFrames) / elapsed).rounded())
            targetFPS = Int((1 / budget).rounded())
            worstFrameMs = windowWorst * 1000
            windowStart = now
            windowFrames = 0
            windowWorst = 0
        }
    }

    /// `CADisplayLink` retains its target strongly; the proxy breaks that cycle.
    private final class DisplayLinkProxy: NSObject {
        weak var owner: FrameRateMonitor?
        init(owner: FrameRateMonitor) { self.owner = owner }
        @MainActor @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.tick(link)
        }
    }
}

/// Tiny always-on-top readout: fps (colored by health), worst frame time, total dropped frames.
/// Sits in the home-indicator strip and ignores touches. Compiled into Debug builds only.
struct FrameRateHUD: View {
    @State private var monitor = FrameRateMonitor()

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(healthColor)
                .frame(width: 7, height: 7)
            Text("\(monitor.fps)/\(monitor.targetFPS)")
            Text(String(format: "%.0fms", monitor.worstFrameMs))
                .foregroundStyle(monitor.worstFrameMs > 1000 / Double(max(monitor.targetFPS, 1)) * 1.5 ? Palette.ember : Palette.textDim)
            Image(systemName: "arrow.down.right")
                .foregroundStyle(Palette.textDim)
            Text("\(monitor.droppedTotal)")
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.6), in: Capsule())
        .onTapGesture { monitor.reset() }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var healthColor: Color {
        let ratio = Double(monitor.fps) / Double(max(monitor.targetFPS, 1))
        if ratio >= 0.95 { return Palette.moss }
        if ratio >= 0.8 { return Palette.gold }
        return Palette.ember
    }
}
#endif

/// Main menu (game.md §2): title and the party on the left, the menu plaques on the right
/// (Continue · New Run · Decks · History, each with a line of live info), settings as an icon
/// chip in the corner and the Test Fight harness as a small chip under the plaques.
struct ContentView: View {
    @Environment(DeckStore.self) private var deckStore
    @Environment(CardStatsStore.self) private var statsStore
    @Environment(GameMenuRouter.self) private var menuRouter
    @State private var content: GameContent?
    @State private var loadError: String?
    @State private var activeRun: RunState?
    @State private var hasSavedRun = RunStore.hasSavedRun
    @State private var savedRun: RunSnapshot?
    @State private var history: [RunRecord] = []
    @State private var discoveries = Discoveries()
    @State private var showSetup = false
    @State private var showSettings = false
    @State private var resumeFailed = false
    /// Decks opened from the Mac Game menu (the plaque uses its own link).
    @State private var showDecks = false
    /// The menu itself is on screen (nothing pushed over it) — Mac Game menu commands only work then.
    @State private var isMenuOnScreen = false

    var body: some View {
        NavigationStack {
            ZStack {
                SceneryBackground()
                // Warm pool of light under the party, so the left half isn't just sky.
                RadialGradient(colors: [Palette.glow.opacity(0.16), .clear], center: UnitPoint(x: 0.28, y: 0.78), startRadius: 10, endRadius: 320)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if let content {
                    HStack(alignment: .center, spacing: 28) {
                        MenuHeroShowcase(classes: Array(content.classes.prefix(2)))
                            .frame(maxWidth: .infinity)
                        menuColumn(content: content)
                            .frame(width: 300)
                    }
                    .padding(.horizontal, 36)
                    .frame(maxWidth: 980)
                } else if let loadError {
                    VStack(spacing: 8) {
                        Text("Content failed to load").font(.serif(17, .semibold)).foregroundStyle(Palette.ember)
                        Text(loadError).font(.serif(12)).multilineTextAlignment(.center)
                    }
                    .parchment()
                    .padding(40)
                } else {
                    ProgressView().tint(Palette.gold)
                }
            }
            .onAppear { isMenuOnScreen = true }
            .onDisappear { isMenuOnScreen = false }
            // Center on the whole screen, not the area below the (empty, always-present)
            // navigation bar — otherwise the menu sits visibly low.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeAreaOnIOS(.container, edges: .vertical)
            .overlay(alignment: .topTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(ChromeIconButtonStyle(size: 40))
                .accessibilityLabel("Settings")
                .padding(.trailing, 20)
                .padding(.top, 14)
                // Measured from the screen's top edge, not below the (empty) navigation bar —
                // otherwise it lands on the first menu plaque. Mac: below the title bar.
                .ignoresSafeAreaOnIOS(.container, edges: .top)
            }
            .themedNavigationBar(settings: false)
            .navigationDestination(isPresented: $showSetup) {
                if let content {
                    RunSetupView(content: content) { heroes, decks in
                        if hasSavedRun { RunStore.delete() }
                        activeRun = RunState(content: content, heroClasses: heroes, decks: decks, statsStore: statsStore)
                        showSetup = false
                    }
                }
            }
            .navigationDestination(isPresented: $showDecks) {
                if let content { deckList(content: content) }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("This saved run can't be continued", isPresented: $resumeFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Its content or decks no longer exist. Start a new run.")
            }
            .task {
                do {
                    let loaded = try ContentLoader.load()
                    deckStore.seedStarterDecksIfNeeded(loaded.starterDecks)
                    content = loaded
                } catch {
                    loadError = String(describing: error)
                }
                refreshMenuInfo()
            }
        }
        .overlay {
            if let run = activeRun {
                RunMapView(run: run) {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        activeRun = nil
                    }
                    hasSavedRun = RunStore.hasSavedRun
                    refreshMenuInfo()
                }
                .id(ObjectIdentifier(run))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: activeRun != nil)
        .onChange(of: menuCommandsAvailable, initial: true) { _, available in
            menuRouter.canStartRun = available
            menuRouter.canOpenDecks = available
            menuRouter.canContinue = available && hasSavedRun
        }
        .onChange(of: hasSavedRun) { _, saved in
            menuRouter.canContinue = menuCommandsAvailable && saved
        }
        .onChange(of: menuRouter.pending) { _, action in
            guard let action else { return }
            menuRouter.pending = nil
            handleMenuCommand(action)
        }
    }

    // MARK: Mac Game menu (game.md §15)

    private var menuCommandsAvailable: Bool {
        content != nil && activeRun == nil && isMenuOnScreen
    }

    private func handleMenuCommand(_ action: GameMenuRouter.Action) {
        guard menuCommandsAvailable, let content else { return }
        switch action {
        case .newRun: showSetup = true
        case .continueRun: if hasSavedRun { resume(content: content) }
        case .decks: showDecks = true
        }
    }

    private func deckList(content: GameContent) -> some View {
        DeckListView(
            cardWeightConfig: content.balance.cardWeight,
            minDeckSize: content.balance.flashcards.minDeckSize,
            starterDecks: content.starterDecks
        )
    }

    // MARK: Menu column

    private func menuColumn(content: GameContent) -> some View {
        let minSize = content.balance.flashcards.minDeckSize
        let usableDecks = deckStore.decks.filter { $0.cards.count >= minSize }
        return VStack(spacing: 10) {
            if hasSavedRun {
                Button {
                    resume(content: content)
                } label: {
                    MenuPlaqueLabel(icon: "play.fill", title: "Continue", subtitle: savedRunSubtitle(content: content))
                }
                .buttonStyle(MenuPlaqueButtonStyle(prominent: true))
            }

            Button {
                showSetup = true
            } label: {
                MenuPlaqueLabel(
                    icon: hasSavedRun ? "plus" : "play.fill",
                    title: "New Run",
                    subtitle: usableDecks.isEmpty
                        ? L("Needs a deck with \(minSize)+ cards")
                        : (hasSavedRun ? L("Replaces your saved run") : L("Two heroes, one map, one dragon"))
                )
            }
            .buttonStyle(MenuPlaqueButtonStyle(prominent: !hasSavedRun))

            NavigationLink {
                deckList(content: content)
            } label: {
                MenuPlaqueLabel(icon: "rectangle.stack.fill", title: "Decks", subtitle: decksSubtitle)
            }
            .buttonStyle(MenuPlaqueButtonStyle())

            NavigationLink {
                RunHistoryView()
            } label: {
                MenuPlaqueLabel(icon: "scroll.fill", title: "History", subtitle: historySubtitle)
            }
            .buttonStyle(MenuPlaqueButtonStyle())

            // Glossary & Bestiary share one row so the column still fits a landscape iPhone.
            HStack(spacing: 10) {
                NavigationLink {
                    GlossaryView(content: content)
                } label: {
                    MenuPlaqueLabel(icon: "book.closed.fill", title: "Glossary", subtitle: glossarySubtitle(content: content), compact: true)
                }
                .buttonStyle(MenuPlaqueButtonStyle())

                NavigationLink {
                    BestiaryView(content: content)
                } label: {
                    MenuPlaqueLabel(icon: "pawprint.fill", title: "Bestiary", subtitle: bestiarySubtitle(content: content), compact: true)
                }
                .buttonStyle(MenuPlaqueButtonStyle())
            }

            NavigationLink {
                TestFightSetupView(content: content)
            } label: {
                Label("Test Fight", systemImage: "hammer.fill")
                    .font(.serif(12, .semibold))
                    .foregroundStyle(Palette.text.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.3), lineWidth: 0.8))
            }
            .buttonStyle(.gamePlain)
            .padding(.top, 4)
        }
    }

    private var decksSubtitle: String {
        let decks = deckStore.decks
        guard !decks.isEmpty else { return L("Write or import your flashcards") }
        let cards = decks.reduce(0) { $0 + $1.cards.count }
        let attempts = decks.reduce(into: (correct: 0, total: 0)) { sum, deck in
            for card in deck.cards {
                for id in [card.id, card.reverseID] {
                    let stats = statsStore.stats(for: id)
                    sum.correct += stats.correct
                    sum.total += stats.total
                }
            }
        }
        var parts = [decks.count == 1 ? L("1 deck") : L("\(decks.count) decks"), L("\(cards) cards")]
        if attempts.total > 0 { parts.append(L("\(Int(Double(attempts.correct) / Double(attempts.total) * 100))% right")) }
        return parts.joined(separator: " · ")
    }

    private var historySubtitle: String {
        guard !history.isEmpty else { return L("No finished runs yet") }
        let wins = history.filter { $0.outcome == .victory }.count
        return (history.count == 1 ? L("1 run") : L("\(history.count) runs")) + " · " + L("\(wins) won")
    }

    private func glossarySubtitle(content: GameContent) -> String {
        let all = content.classes.flatMap(\.skills).count + content.items.count + content.gear.count + content.relics.count
        let found = content.classes.flatMap(\.skills).filter { discoveries.skills.contains($0.id) }.count
            + content.items.filter { discoveries.potions.contains($0.id) }.count
            + content.gear.filter { discoveries.gear.contains($0.id) }.count
            + content.relics.filter { discoveries.relics.contains($0.id) }.count
        return L("\(found)/\(all) found")
    }

    private func bestiarySubtitle(content: GameContent) -> String {
        L("\(content.enemies.filter { discoveries.enemies.contains($0.id) }.count)/\(content.enemies.count) met")
    }

    private func savedRunSubtitle(content: GameContent) -> String {
        guard let run = savedRun else { return L("Resume your journey") }
        let totalRows = (run.map.nodes.map(\.row).max() ?? 0) + 1
        let row = run.currentNodeID.flatMap { run.map.node($0)?.row }.map { $0 + 1 } ?? 0
        let hp = run.heroes.map(\.hp).reduce(0, +)
        return L("Step \(row)/\(totalRows) · ♥ \(hp) · \(run.gold) gold")
    }

    private func refreshMenuInfo() {
        hasSavedRun = RunStore.hasSavedRun
        savedRun = hasSavedRun ? RunStore.load() : nil
        history = RunHistoryStore.load()
        discoveries = DiscoveryStore.load()
    }

    /// Continue the saved run. Its decks are looked up by id; if they were deleted, every usable
    /// deck is used instead so the run can still go on.
    private func resume(content: GameContent) {
        guard let snapshot = RunStore.load() else {
            RunStore.delete()
            hasSavedRun = false
            resumeFailed = true
            return
        }
        var decks = deckStore.decks.filter { snapshot.deckIDs.contains($0.id) }
        if decks.isEmpty {
            decks = deckStore.decks.filter { $0.cards.count >= content.balance.flashcards.minDeckSize }
        }
        guard !decks.isEmpty,
              let run = RunState(snapshot: snapshot, content: content, decks: decks, statsStore: statsStore) else {
            resumeFailed = true
            return
        }
        activeRun = run
    }
}

// MARK: - Menu pieces

/// The game's title over the two heroes standing on their floating islands. Static.
private struct MenuHeroShowcase: View {
    let classes: [HeroClassDef]

    var body: some View {
        VStack(spacing: 18) {
            ScreenTitle(title: "Study RPG", subtitle: "Know your cards. Slay the dragon.", size: 44)
            HStack(alignment: .bottom, spacing: 26) {
                ForEach(Array(classes.enumerated()), id: \.element.id) { index, heroClass in
                    // Same stand as the fight stage: the island is drawn first, so the hero's feet
                    // stand on its top instead of disappearing behind it.
                    BattleFigureStand(
                        spriteId: heroClass.spriteId,
                        kind: .hero,
                        spriteHeight: index == 0 ? 118 : 112,
                        anchorKey: "menu-\(heroClass.id)"
                    )
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                    // A slight stagger reads as a party, not a lineup.
                    .offset(y: index == 0 ? 0 : -10)
                }
            }
            .background(
                Ellipse()
                    .fill(RadialGradient(colors: [Palette.glow.opacity(0.22), .clear], center: .center, startRadius: 4, endRadius: 150))
                    .frame(width: 320, height: 200)
            )
        }
        .accessibilityElement(children: .combine)
    }
}

/// Icon medallion + title + one line of live info + chevron.
private struct MenuPlaqueLabel: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: String
    /// Half-width plaque (two per row): tighter spacing, no chevron.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.25)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.serif(compact ? 16 : 18, .bold))
                Text(subtitle)
                    .font(.serif(11, .medium))
                    .opacity(0.75)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            if !compact {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .opacity(0.5)
            }
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
    }
}

/// Gold plaque (the main action) or dark gilded panel (everything else).
private struct MenuPlaqueButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .foregroundStyle(prominent ? Palette.ink : Palette.text)
            .background(
                shape.fill(prominent
                    ? AnyShapeStyle(LinearGradient(colors: [Palette.goldGlow, Palette.gold], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Palette.panel.opacity(0.88)))
            )
            .overlay(shape.strokeBorder(prominent ? Palette.glow.opacity(0.9) : Palette.gold.opacity(0.45), lineWidth: 1))
            .overlay(shape.inset(by: 3.5).strokeBorder((prominent ? Palette.ink : Palette.gold).opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            .shadow(color: prominent ? Palette.gold.opacity(0.35) : .clear, radius: 12)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Sound.play(.tap) }
            }
            .hoverHighlight(isEnabled)
    }
}

#Preview {
    ContentView()
        .environment(DeckStore())
        .environment(CardStatsStore())
        .environment(GameSettings())
        .environment(GameMenuRouter())
}

#Preview("FightScreen") {
    if let content = try? ContentLoader.load(),
       let warrior = content.classDef(id: "warrior"),
       let wizard = content.classDef(id: "wizard"),
       let wolf = content.enemyDef(id: "wolf"),
       let goblin = content.enemyDef(id: "goblin") {
        let deck = Deck(name: "Sample Deck", cards: [
            Flashcard(question: CardFace(text: "Hund"), answer: CardFace(text: "Dog"), wrongAnswers: [CardFace(text: "Cat"), CardFace(text: "Bird")])
        ])
        let engine = CombatEngine(
            heroClasses: [warrior, wizard],
            enemyDefs: [wolf, wolf, goblin],
            balance: content.balance,
            decks: [deck],
            statsStore: CardStatsStore(),
            inventory: content.items
        )
        FightView(engine: engine)
            .environment(GameSettings())
    } else {
        Text("Failed to load preview")
    }
}
