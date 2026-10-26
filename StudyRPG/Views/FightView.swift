import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Fight View (Main Screen with Sequenced Rhythmic Flow)

/// Which character the info sheet is showing.
enum InspectTarget: Identifiable {
    case hero(Int)
    case enemy(UUID)

    var id: String {
        switch self {
        case .hero(let index): return "hero-\(index)"
        case .enemy(let id): return "enemy-\(id.uuidString)"
        }
    }
}

struct FightView: View {
    @Bindable var engine: CombatEngine
    /// The fight's stage (background + platform material). nil = default placeholder.
    var theme: FightThemeDef? = nil
    /// What victory pays out (shown on the victory screen). nil = just the enemies' gold.
    var reward: NodeReward? = nil
    /// Called from the victory/defeat screen.
    var onComplete: ((CombatEngine) -> Void)? = nil
    /// Leaving mid-fight. nil (run fights) hides the back button — no retreating from a run fight.
    var onAbandon: (() -> Void)? = nil
    /// The run this fight belongs to (nil for Test Fight) — the party button opens the same party
    /// sheet as the map (game.md §9).
    var run: RunState? = nil

    @Environment(GameSettings.self) private var settings
    @State private var showPartySheet = false
    @State private var activeRollRequest: DiceRollRequest?

    // Pacing states
    @State private var showRollBanner = false
    @State private var rollBannerText = ""
    @State private var rollBannerIsEnemy = false
    /// Who a batched (fast mode) segment hits, shown next to its total.
    @State private var rollBannerTargetSprite: String?

    // Character animation states
    @State private var heroFlashing: [Bool] = [false, false]
    @State private var heroShake: [CGFloat] = [0, 0]
    @State private var heroLunge: [CGFloat] = [0, 0]

    @State private var enemyFlashing: [UUID: Bool] = [:]
    @State private var enemyShake: [UUID: CGFloat] = [:]
    @State private var enemyLunge: [UUID: CGFloat] = [:]

    @State private var vfxEffects: [AttackVFXInstance] = []
    @State private var battleFloaters: [BattleFloater] = []
    @State private var inspectTarget: InspectTarget?
    @State private var showSettings = false

    /// Sprite frames in this screen's coordinate space, keyed `hero-<index>` / `enemy-<uuid>`.
    @State private var figureRects: [String: CGRect] = [:]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Static stage: the background never moves during a fight.
                FightBackdrop(theme: theme)

                VStack(spacing: 0) {
                    // Top bar: back button (Test Fight only), the run's relics, settings, party.
                    HStack(spacing: 10) {
                        if let onAbandon {
                            Button(action: onAbandon) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 36, height: 36)
                                    .modifier(TopBarChip(cornerRadius: 18))
                                    .contentShape(Circle())
                            }
                            .accessibilityLabel("Leave fight")
                        }
                        RelicTray(relics: engine.relics)
                            .contentShape(Rectangle())
                            .hoverHighlight()
                            .onTapGesture { showPartySheet = true }
                        Spacer(minLength: 6)
                        Button {
                            settings.fastMode.toggle()
                        } label: {
                            Image(systemName: settings.fastMode ? "hare.fill" : "tortoise.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 34, height: 30)
                                .modifier(TopBarChip(tint: settings.fastMode ? Palette.strength : nil))
                        }
                        .buttonStyle(.gamePlain)
                        .accessibilityLabel(settings.fastMode ? "Fast mode on" : "Fast mode off")
                        Button {
                            showPartySheet = true
                        } label: {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 34, height: 30)
                                .modifier(TopBarChip())
                        }
                        .buttonStyle(.gamePlain)
                        .accessibilityLabel("Party")
                        // Only while the fight waits for the player, so nothing plays out unseen.
                        MapPeekButton(size: 30)
                            .disabled(!engine.isAwaitingPlayer)
                        SettingsGearButton(chipSize: 30)
                    }
                    .frame(height: 36)
                    // Centered on the screen, whatever sits left and right of it.
                    .overlay { RoundTurnIndicator(engine: engine) }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // Arena Stage (Heroes & Enemies)
                    BattleStageView(
                        engine: engine,
                        platform: theme?.platform ?? .grass,
                        heroFlashing: heroFlashing,
                        heroShake: heroShake,
                        heroLunge: heroLunge,
                        enemyFlashing: enemyFlashing,
                        enemyShake: enemyShake,
                        enemyLunge: enemyLunge,
                        onSelectEnemy: { Sound.play(.tap); engine.selectTarget($0) },
                        onSelectHero: { Sound.play(.tap); engine.tapHero($0) },
                        onInspectHero: { inspectTarget = .hero($0) },
                        onInspectEnemy: { inspectTarget = .enemy($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    FullWidthBottomConsoleView(
                        engine: engine,
                        onSelectSkill: { Sound.play(.tap); engine.selectSkill($0) },
                        onUsePotion: { item, heroID in usePotion(item, on: heroID) },
                        onEndTurn: { Sound.play(.tap); engine.endPartyTurn() }
                    )
                }

                // Dice tray (game.md §8)
                DiceTrayView(request: activeRollRequest)
                    .ignoresSafeArea()

                // Roll Result Banner (icon + total only, plus the target in a batched throw)
                if showRollBanner {
                    VStack {
                        let banner = HStack(spacing: 8) {
                            Image(systemName: "die.face.5.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text(rollBannerText)
                                .font(.serif(24, .bold))
                            if let sprite = rollBannerTargetSprite {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                                SpriteView(spriteId: sprite, kind: .hero, size: 24)
                            }
                        }
                        banner
                            .foregroundStyle(rollBannerIsEnemy ? Palette.ember : Palette.goldGlow)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.85))
                                    .overlay(Capsule().strokeBorder(rollBannerIsEnemy ? Palette.ember : Palette.goldGlow, lineWidth: 2))
                            )
                            .shadow(color: (rollBannerIsEnemy ? Palette.ember : Palette.goldGlow).opacity(0.5), radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                // Attack VFX Overlay (no ignoresSafeArea, so it shares the anchor space)
                AttackVFXOverlay(effects: vfxEffects)
                    .allowsHitTesting(false)

                // Floating Damage / Heal Numbers
                ForEach(battleFloaters) { floater in
                    FloatingNumberView(item: floater)
                }

                // Flashcard quiz (game.md §7.6, teaching moments §4.1)
                if case .awaitingAnswer(let skillID, let targetEnemyID) = engine.phase {
                    if let card = engine.currentPresentedCard {
                        ZStack {
                            Color.black.opacity(0.62)
                                .ignoresSafeArea()
                            FlashcardQuizOverlay(card: card) { chosenIndex, responseMs in
                                let isCorrect = engine.recordAnswer(chosenOptionIndex: chosenIndex, responseMs: responseMs)
                                engine.proceedAfterAnswer(skillID: skillID, targetEnemyID: targetEnemyID, correct: isCorrect)
                            }
                        }
                        .transition(.opacity)
                    }
                }

                // Victory / Defeat Overlays
                if case .victory = engine.phase {
                    CombatVictoryOverlay(reward: reward ?? NodeReward(gold: engine.goldReward), experience: victoryExperience) {
                        onComplete?(engine)
                    }
                } else if case .defeat = engine.phase {
                    CombatDefeatOverlay {
                        onComplete?(engine)
                    }
                }

                // The victory / defeat screens cover the top bar: keep map + settings reachable.
                if engine.phase == .victory || engine.phase == .defeat {
                    HStack(spacing: 10) {
                        MapPeekButton(size: 30)
                        SettingsGearButton(chipSize: 30)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 13)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .onPreferenceChange(BattleAnchorKey.self) { anchors in
                var rects: [String: CGRect] = [:]
                for (key, anchor) in anchors {
                    rects[key] = proxy[anchor]
                }
                // Only publish real changes — every write re-renders the whole fight screen.
                if rects != figureRects { figureRects = rects }
            }
            .navigationBarBackButtonHidden(true)
            .hiddenNavigationBar()
            .onAppear { engine.fastMode = settings.fastMode }
            .onChange(of: settings.fastMode) { _, fast in engine.fastMode = fast }
            .onChange(of: engine.phase) { _, newPhase in
                handlePhaseChange(newPhase)
            }
            .onChange(of: engine.log.count) { oldCount, newCount in
                // Every applied effect is logged once by the engine; floaters and buff VFX are
                // driven from those entries, so the numbers shown are exactly what was applied.
                guard newCount > oldCount else { return }
                for entry in engine.log[oldCount..<newCount] {
                    presentFeedback(for: entry)
                }
            }
            .sheet(item: $inspectTarget) { target in
                CharacterInfoSheet(engine: engine, target: target)
            }
            .sheet(isPresented: $showPartySheet) {
                PartyInventorySheet(run: run, fight: engine, initialSelection: .hero(engine.activeHeroIndex))
            }
        }
    }

    /// Run fights: the experience every hero is about to gain (applied when the run takes the
    /// result back, game.md §5 "Levels").
    private var victoryExperience: VictoryExperience? {
        guard let run else { return nil }
        let gain = RunState.experience(for: engine)
        return VictoryExperience(
            gain: gain,
            heroes: engine.heroes.map { .init(id: $0.id, spriteId: $0.classDef.spriteId, xpBefore: $0.xp, xpAfter: $0.xp + gain) },
            leveling: run.leveling
        )
    }

    // MARK: Sequencing (game.md §7.6) — one thing at a time

    private func handlePhaseChange(_ newPhase: CombatPhase) {
        switch newPhase {
        case .awaitingAnswer:
            if engine.currentPresentedCard == nil, engine.presentCard() == nil {
                // No card can be drawn (no usable deck): cancel instead of freezing the fight.
                engine.cancelAwaitingAnswer()
            }

        case .rolling(let pending):
            Task { @MainActor in
                // Give the acting enemy's highlight a moment to register before its dice fly.
                try? await Task.sleep(for: settings.ms(pending.isEnemyRoll ? 600 : 150))
                guard case .rolling(let current) = engine.phase, current.id == pending.id else { return }
                let requestID = UUID()
                activeRollRequest = DiceRollRequest(id: requestID, count: pending.diceCount, sides: pending.sides, die: pending.heroDie,
                                                    stickers: engine.dice.stickers, isEnemy: pending.isEnemyRoll, fast: settings.fastMode) { faces in
                    handleDiceSettled(faces: faces, pending: pending, requestID: requestID)
                }
            }

        case .victory:
            Sound.play(.victory)

        case .defeat:
            Sound.play(.defeat)

        case .resolving(let beat, let id) where beat == .effect:
            // Instant effects (Shield Wall, mana gain, stuns, armor) get their own beat to read.
            Task { @MainActor in
                try? await Task.sleep(for: settings.ms(1000))
                engine.continueAfterResolution(id: id)
            }

        default:
            break
        }
    }

    // MARK: Anchored battle feedback

    private func heroIndex(_ id: String) -> Int? {
        engine.heroes.firstIndex { $0.id == id }
    }

    private func heroRect(_ index: Int) -> CGRect? {
        figureRects["hero-\(index)"]
    }

    private func enemyRect(_ id: UUID?) -> CGRect? {
        guard let id else { return nil }
        return figureRects["enemy-\(id.uuidString)"]
    }

    private func heroCenter(_ index: Int) -> CGPoint {
        if let rect = heroRect(index) {
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        return CGPoint(x: index == 0 ? 300 : 170, y: 215)
    }

    private func enemyCenter(_ id: UUID?) -> CGPoint {
        if let rect = enemyRect(id) {
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        return CGPoint(x: 560, y: 215)
    }

    private func actorRect(_ actor: CombatActor?) -> CGRect? {
        switch actor {
        case .hero(let id): return heroIndex(id).flatMap(heroRect)
        case .enemy(let id): return enemyRect(id)
        case .party, .none: return nil
        }
    }

    private func actorCenter(_ actor: CombatActor?) -> CGPoint? {
        actorRect(actor).map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    private func spawnVFX(_ kind: AttackVFXKind) {
        let effect = AttackVFXInstance(kind: kind)
        vfxEffects.append(effect)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            vfxEffects.removeAll { $0.id == effect.id }
        }
    }

    /// Damage/heal numbers float above the sprite's head instead of over its middle, so they stay
    /// readable regardless of the art underneath.
    private func spawnFloater(_ text: String, _ color: Color, above rect: CGRect?, icon: String? = nil) {
        // Clamp so a floater spawned high on screen still fits after rising ~50pt.
        let point = rect.map { CGPoint(x: $0.midX, y: max(72, $0.minY - 44)) } ?? CGPoint(x: 560, y: 170)
        let floater = BattleFloater(text: text, color: color, point: point, icon: icon)
        battleFloaters.append(floater)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            battleFloaters.removeAll { $0.id == floater.id }
        }
    }

    /// The floater (and, for buffs, the aura) for one applied effect. Color = meaning:
    /// red damage, green health, blue mana, yellow strength, silver block, violet control.
    private func presentFeedback(for entry: CombatLogEntry) {
        let tint = Palette.combatColor(entry.kind)
        switch entry.kind {
        case .damage:
            // Always shown — a fully blocked hit reads as a silver shield + 0.
            spawnFloater(
                entry.amount > 0 ? "-\(entry.amount)" : "0",
                entry.amount > 0 ? tint : Palette.block,
                above: actorRect(entry.target),
                icon: entry.amount > 0 ? "heart.slash.fill" : "shield.fill"
            )
        case .heal:
            let target = entry.target ?? entry.actor
            spawnFloater("+\(entry.amount)", entry.amount > 0 ? tint : Palette.textDim, above: actorRect(target), icon: "cross.case.fill")
        case .mana:
            Sound.play(.mana)
            if case .hero(let id) = entry.actor, let index = heroIndex(id) {
                spawnVFX(.manaBurst(heroCenter(index)))
            }
            spawnFloater("+\(entry.amount)", entry.amount > 0 ? tint : Palette.textDim, above: actorRect(entry.actor), icon: "diamond.fill")
        case .strength:
            Sound.play(.buff)
            if case .hero(let id) = entry.actor, let index = heroIndex(id) {
                spawnVFX(.strengthBurst(heroCenter(index)))
            }
            spawnFloater("+\(entry.amount)", entry.amount > 0 ? tint : Palette.textDim, above: actorRect(entry.actor), icon: "die.face.5.fill")
        case .block:
            Sound.play(.shield)
            for index in engine.heroes.indices where engine.heroes[index].isAlive {
                spawnVFX(.shieldPulse(heroCenter(index)))
            }
        case .armor:
            Sound.play(.shield)
            if case .enemy(let id) = entry.target ?? entry.actor {
                spawnVFX(.shieldPulse(enemyCenter(id)))
                spawnFloater("\(entry.amount)", tint, above: enemyRect(id), icon: "shield.fill")
            }
        case .buff:
            Sound.play(.buff)
            if let center = actorCenter(entry.target) { spawnVFX(.strengthBurst(center)) }
            spawnFloater("+\(entry.amount)", tint, above: actorRect(entry.target), icon: "arrow.up.circle.fill")
        case .stun, .debuff:
            Sound.play(entry.kind == .stun ? .stun : .debuff)
            if let center = actorCenter(entry.target) { spawnVFX(.controlBurst(center)) }
            spawnFloater(entry.kind == .stun ? "\(entry.amount)" : "−\(entry.amount)", tint, above: actorRect(entry.target),
                         icon: entry.kind == .stun ? "moon.zzz.fill" : "arrow.down.circle.fill")
        case .correct, .wrong:
            break
        }
    }

    private func pendingSkill(_ pending: PendingRoll, heroIndex: Int) -> SkillDef? {
        guard let id = pending.skillID else { return nil }
        return engine.heroes[heroIndex].skill(id: id)
    }

    // MARK: Potions

    private func usePotion(_ item: ItemDef, on heroID: String) {
        guard engine.canUsePotion(item, onHeroID: heroID), let index = heroIndex(heroID) else { return }
        let glowColor: Color
        switch item.effect.type {
        case .heal: glowColor = Color(red: 0.86, green: 0.20, blue: 0.22)
        case .bonusDice: glowColor = Color(red: 0.92, green: 0.60, blue: 0.20)
        case .resource: glowColor = Color(red: 0.55, green: 0.45, blue: 0.90)
        }
        spawnVFX(.potionGlow(heroCenter(index), glowColor))
        Sound.play(.potion)
        // The number itself comes from the log entry the engine writes.
        engine.usePotion(item, targetHeroID: heroID)
    }

    private func lungeHero(_ index: Int, by dx: CGFloat) {
        guard heroLunge.indices.contains(index) else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { heroLunge[index] = dx }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.2)) { heroLunge[index] = 0 }
        }
    }

    private func lungeEnemy(_ id: UUID, by dx: CGFloat) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { enemyLunge[id] = dx }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.2)) { enemyLunge[id] = 0 }
        }
    }

    private func flashHero(_ index: Int) {
        guard heroFlashing.indices.contains(index) else { return }
        heroFlashing[index] = true
        heroShake[index] = 1.0
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            heroFlashing[index] = false
            heroShake[index] = 0
        }
    }

    private func flashEnemy(_ id: UUID) {
        enemyFlashing[id] = true
        enemyShake[id] = 1.0
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            enemyFlashing[id] = false
            enemyShake[id] = 0
        }
    }

    /// The hero attack animation for one target.
    private func spawnHeroAttack(_ pending: PendingRoll, heroIdx: Int, at target: CGPoint) -> Int {
        switch pendingSkill(pending, heroIndex: heroIdx)?.vfx ?? "blade" {
        case "fireball":
            spawnVFX(.fireball(from: heroCenter(heroIdx), to: target))
            return 520
        case "missile":
            spawnVFX(.magicMissile(from: heroCenter(heroIdx), to: target))
            return 320
        default:
            spawnVFX(.bladeSlash(target))
            return 220
        }
    }

    /// One attack sound per throw segment (an area skill hits every enemy with one swing).
    private func playHeroAttackSound(_ pending: PendingRoll, heroIdx: Int) {
        switch pendingSkill(pending, heroIndex: heroIdx)?.vfx ?? "blade" {
        case "fireball": Sound.play(.fireball)  // the explosion is baked in at the VFX impact
        case "missile": Sound.play(.missile)
        default: Sound.play(.slash)
        }
    }

    /// For every segment of the throw (one, or one per hero in a fast-mode batch):
    /// banner → attacker lunge + VFX → impact (engine applies; floaters come from the log) → let it
    /// read. Then clear the dice and hand control back to the engine.
    private func handleDiceSettled(faces: [DieFace], pending: PendingRoll, requestID: UUID) {
        // Ignore a late callback from a roll that has already been replaced.
        guard activeRollRequest?.id == requestID else { return }
        let perSegment = pending.expr.count

        Task { @MainActor in
            for (index, purpose) in pending.segments.enumerated() {
                let start = min(faces.count, index * perSegment)
                let end = min(faces.count, start + perSegment)
                let segmentFaces = Array(faces[start..<end])
                let total = engine.segmentTotal(pending, rolled: segmentFaces)

                // Step 1: roll total banner.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    rollBannerText = "\(total)"
                    rollBannerIsEnemy = pending.isEnemyRoll
                    if pending.segments.count > 1, case .enemyAttack(_, let heroID, _) = purpose {
                        rollBannerTargetSprite = engine.heroes.first { $0.id == heroID }?.classDef.spriteId
                    } else {
                        rollBannerTargetSprite = nil
                    }
                    showRollBanner = true
                }
                Sound.play(.diceTotal)
                try? await Task.sleep(for: settings.ms(550))

                // Step 2: the attacker lunges and its effect flies at the target.
                var impactDelay = 220
                switch purpose {
                case .heroDamage(let targetEnemyID):
                    let heroIdx = engine.activeHeroIndex
                    lungeHero(heroIdx, by: 30)
                    playHeroAttackSound(pending, heroIdx: heroIdx)
                    impactDelay = spawnHeroAttack(pending, heroIdx: heroIdx, at: enemyCenter(targetEnemyID))
                case .heroDamageAll:
                    let heroIdx = engine.activeHeroIndex
                    lungeHero(heroIdx, by: 30)
                    playHeroAttackSound(pending, heroIdx: heroIdx)
                    for enemy in engine.livingEnemies {
                        impactDelay = spawnHeroAttack(pending, heroIdx: heroIdx, at: enemyCenter(enemy.id))
                    }
                case .heroHeal(let targetHeroID):
                    Sound.play(.heal)
                    for heroIdx in engine.heroes.indices where engine.heroes[heroIdx].isAlive
                        && (targetHeroID == nil || engine.heroes[heroIdx].id == targetHeroID) {
                        spawnVFX(.healBurst(heroCenter(heroIdx)))
                    }
                case .enemyAttack(let enemyID, let targetHeroID, let skillID):
                    // The skill's `vfx` (enemies.json): `fire`, `laser` or the default claw.
                    let skill = skillID == EnemyDef.basicAttackID
                        ? engine.enemies.first { $0.id == enemyID }?.def.basicAttack
                        : engine.enemySkill(enemyID: enemyID, skillID: skillID)
                    let vfx = skill?.vfx ?? "claw"
                    lungeEnemy(enemyID, by: -30)
                    Sound.play(vfx == "fire" ? .fireBreath : vfx == "laser" ? .laser : .claw)
                    if let heroIdx = heroIndex(targetHeroID) {
                        switch vfx {
                        case "fire": spawnVFX(.fireBurst(heroCenter(heroIdx)))
                        case "laser":
                            spawnVFX(.laserBeam(from: enemyCenter(enemyID), to: heroCenter(heroIdx)))
                            impactDelay = 260
                        default: spawnVFX(.clawSlash(heroCenter(heroIdx)))
                        }
                    }
                case .enemyHeal(_, _, let targetIDs):
                    Sound.play(.heal)
                    for id in targetIDs where engine.enemies.first(where: { $0.id == id })?.isAlive == true {
                        spawnVFX(.healBurst(enemyCenter(id)))
                    }
                }

                try? await Task.sleep(for: settings.ms(impactDelay))
                withAnimation { showRollBanner = false }

                // Step 3: the engine applies the result; each hit target flashes, or a fully
                // blocked hit clangs off a shield instead.
                let before = engine.log.count
                engine.applyRollSegment(index, rolled: segmentFaces)
                let hits = engine.log[before...].filter { $0.kind == .damage }
                if hits.contains(where: { $0.amount > 0 }) {
                    Sound.play(.hit)
                } else if !hits.isEmpty {
                    Sound.play(.block)
                }
                for entry in engine.log[before...] where entry.kind == .damage {
                    switch entry.target {
                    case .enemy(let id):
                        if entry.amount > 0 {
                            flashEnemy(id)
                        } else { spawnVFX(.shieldPulse(enemyCenter(id))) }
                    case .hero(let id):
                        if let heroIdx = heroIndex(id) {
                            if entry.amount > 0 {
                                flashHero(heroIdx)
                            } else { spawnVFX(.shieldPulse(heroCenter(heroIdx))) }
                        }
                    default:
                        break
                    }
                }

                // Step 4: let the number and HP bar read.
                try? await Task.sleep(for: settings.ms(850))
            }

            if activeRollRequest?.id == requestID {
                activeRollRequest = nil
            }
            try? await Task.sleep(for: settings.ms(300))
            engine.finishRoll()
            if case .resolving(let beat, let id) = engine.phase, beat == .roll {
                engine.continueAfterResolution(id: id)
            }
        }
    }
}

/// Haptic taps, respecting Settings → Haptics.
/// Mac has no haptics: `impact` does nothing there.
enum Haptics {
    #if os(iOS)
    typealias Style = UIImpactFeedbackGenerator.FeedbackStyle
    #else
    enum Style { case light, medium, heavy, soft, rigid }
    #endif

    static func impact(_ style: Style) {
        #if os(iOS)
        guard UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}

/// The small round/capsule buttons in the fight's top bar: dark chips with gold.
private struct TopBarChip: ViewModifier {
    var cornerRadius: CGFloat = 15
    /// Overrides the icon color (e.g. Fast mode on).
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint ?? Palette.goldGlow)
            .background(Capsule().fill(Color.black.opacity(0.65)))
            .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Round & Turn Indicator

/// Symbol-only top-bar chip: the round (`hourglass` + number), then the party's side — each living
/// hero's mini portrait with their action points (done heroes dimmed with a check) — then the
/// enemies' side. Whichever side's turn it is is lit; the acting enemy is ember-rimmed.
struct RoundTurnIndicator: View {
    let engine: CombatEngine

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 3) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10, weight: .bold))
                Text("\(engine.roundNumber)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Palette.goldGlow)

            divider

            // The party's turn: every hero acts, in any order, until their action points are spent.
            HStack(spacing: 5) {
                ForEach(Array(engine.heroes.enumerated()), id: \.element.id) { index, hero in
                    if hero.isAlive {
                        let isDone = !engine.canAct(heroAt: index)
                        let isCurrent = !engine.isEnemyTurn && index == engine.activeHeroIndex && !isDone
                        VStack(spacing: 1) {
                            SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, size: 15)
                                .frame(width: 20, height: 18)
                                .opacity(isDone ? 0.42 : 1)
                                .overlay(alignment: .bottomTrailing) {
                                    if isDone && !engine.isEnemyTurn {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(Palette.health)
                                            .background(Circle().fill(Palette.ink))
                                            .offset(x: 2, y: 1)
                                    }
                                }
                            ActionPointPips(filled: hero.actionPoints, total: engine.maxActionPoints(heroAt: index), size: 4)
                        }
                        .padding(.horizontal, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? Palette.gold.opacity(0.22) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isCurrent ? Palette.goldGlow : .clear, lineWidth: 1.2))
                    }
                }
            }
            .opacity(engine.isEnemyTurn ? 0.45 : 1)

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Palette.textDim)

            // The enemies' turn: each enemy plays one move, one after another.
            HStack(spacing: 3) {
                ForEach(engine.livingEnemies) { enemy in
                    let isActing = engine.actingEnemyID == enemy.id
                    SpriteView(spriteId: enemy.def.spriteId, kind: .enemy, size: 15)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isActing ? Palette.damage.opacity(0.25) : .clear))
                        .overlay(Circle().strokeBorder(isActing ? Palette.ember : .clear, lineWidth: 1.4))
                }
            }
            .opacity(engine.isEnemyTurn ? 1 : 0.45)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .modifier(TopBarChip(cornerRadius: 15))
        .animation(.easeInOut(duration: 0.2), value: engine.roundNumber)
        .animation(.easeInOut(duration: 0.2), value: engine.isEnemyTurn)
        .animation(.easeInOut(duration: 0.2), value: engine.actingEnemyID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(engine.isEnemyTurn ? "Round \(engine.roundNumber), enemies' turn" : "Round \(engine.roundNumber), your turn")
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.gold.opacity(0.35))
            .frame(width: 1, height: 14)
    }
}
