import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Map (game.md §9)

/// A fight in progress on a map node.
private struct ActiveFight: Identifiable, Hashable {
    let id = UUID()
    let nodeID: Int
    let engine: CombatEngine
    let reward: NodeReward
    let theme: FightThemeDef?

    static func == (lhs: ActiveFight, rhs: ActiveFight) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The run's world map (game.md §9): an aged parchment map sheet resting on a dark wooden tabletop,
/// scrolling left → right from the trailhead to the boss. Tap a place to preview it, then the party
/// walks the road to it with an animated stride and it opens smoothly in place.
struct RunMapView: View {
    @Bindable var run: RunState
    /// Leave the run (after the recap, or on abandon).
    var onExit: () -> Void

    @State private var activeFight: ActiveFight?
    @State private var activeNode: MapNode?
    @State private var confirmAbandon = false
    @State private var inspectedNodeID: Int?
    @State private var walkingToNodeID: Int?
    @State private var arrivedNodeID: Int?
    @State private var travelProgress: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    /// The painted terrain, rasterized once per map height, act and pixel scale (painting it live
    /// was the main cost).
    @State private var terrain: (height: CGFloat, act: Int, scale: CGFloat, image: PlatformImage)?
    /// Shows the "Act II" card once when a new act's map begins (game.md §16).
    @State private var introActIndex: Int?
    @State private var partySheetSelection: PartyInspectorSelection?
    /// The covering screen is hidden (but kept alive) so the player can look at the map
    /// (game.md §9 "Looking at the map"); a return chip brings it back.
    @State private var peekingMap = false
    @Environment(\.displayScale) private var displayScale

    private var content: GameContent { run.content }
    /// The current act's map look (game.md §9, §16).
    private var mapStyle: MapStyle { run.act.mapStyle }
    /// Something full-screen sits on top of the map (fight, shop, campfire, event, skill offer,
    /// recap). While it does, the map can be looked at but not travelled.
    private var hasCover: Bool { activeFight != nil || activeNode != nil || run.pendingSkillOffer != nil || !run.pendingDieUpgrades.isEmpty || run.isOver }
    private var layout: WorldMapLayout { WorldMapLayout(map: run.map, rowCount: content.balance.map.rowCount, laneCount: content.balance.map.maxLanes) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                RunHUD(run: run, onAbandon: { confirmAbandon = true })

                GeometryReader { viewport in
                    // The sheet doesn't fill the table top to bottom: more wood shows around it, and
                    // the parchment's rolled ends need room at the sides (game.md §9).
                    let tablePadV: CGFloat = min(60, max(16, viewport.size.height * 0.09))
                    let tablePadH: CGFloat = mapStyle == .hologram ? 26 : 50
                    let sheetHeight = max(200, viewport.size.height - tablePadV * 2)
                    let sheetShape = mapStyle == .hologram ? AnyShape(RoundedRectangle(cornerRadius: 6)) : AnyShape(TornSheetShape(seed: UInt64(11 + run.actIndex)))
                    let layout = self.layout
                    let width = layout.width
                    // Computed once per render, not once per node.
                    let alive = aliveNodeIDs
                    let reachable = walkingToNodeID == nil ? Set(run.reachableNodeIDs) : []

                    ZStack {
                        if mapStyle == .hologram {
                            HoloConsoleSurfaceView()
                        } else {
                            TabletopSurfaceView()
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            ZStack {
                                // Physical parchment sheet resting on the dark wooden table
                                ZStack {
                                    Group {
                                        if let terrain, terrain.height == sheetHeight, terrain.act == run.actIndex {
                                            Image(platformImage: terrain.image).resizable()
                                        } else {
                                            mapStyle == .hologram ? HoloPalette.deep : Palette.parchment
                                        }
                                    }
                                    .frame(width: width, height: sheetHeight)
                                    .task(id: "\(sheetHeight)-\(run.actIndex)-\(terrainScale)") { renderTerrain(layout: layout, height: sheetHeight) }

                                    WorldMapRoads(
                                        layout: layout,
                                        height: sheetHeight,
                                        visited: run.visitedNodeIDs,
                                        currentNodeID: run.currentNodeID,
                                        reachable: reachable,
                                        alive: alive,
                                        style: mapStyle
                                    )
                                    .equatable()

                                    // Only the roads you can walk next move: gilded and shimmering.
                                    OpenRoadShimmer(
                                        roads: hasCover || run.isOver ? [] : reachable.map { (from: partyPoint(height: sheetHeight), to: layout.point($0, height: sheetHeight)) },
                                        places: hasCover || run.isOver ? [] : reachable.compactMap { id in
                                            run.map.node(id).map { (center: layout.point(id, height: sheetHeight), radius: PaintedPlaceMark.size(for: $0.type) * 0.38) }
                                        },
                                        tint: mapStyle == .hologram ? HoloPalette.cyan : Palette.gold,
                                        glint: mapStyle == .hologram ? .white : Color(red: 1.0, green: 0.95, blue: 0.75),
                                        paused: hasCover && !peekingMap
                                    )

                                    // Gold trail drawn in behind the walking heroes.
                                    if let target = walkingToNodeID {
                                        RoadCurveShape(from: partyPoint(height: sheetHeight), to: layout.point(target, height: sheetHeight))
                                            .trim(from: 0, to: travelProgress)
                                            .stroke(Palette.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 6]))
                                            .allowsHitTesting(false)
                                    }

                                    ForEach(run.map.nodes) { node in
                                        Button {
                                            Sound.play(.tap)
                                            inspectedNodeID = node.id
                                        } label: {
                                            let isReachable = reachable.contains(node.id) && !run.isOver && !hasCover
                                            if mapStyle == .hologram {
                                                WorldMapBadge(
                                                    node: node,
                                                    isReachable: isReachable,
                                                    isVisited: run.visitedNodeIDs.contains(node.id),
                                                    isAlive: alive.contains(node.id),
                                                    style: mapStyle
                                                )
                                            } else {
                                                PaintedPlaceMark(
                                                    type: node.type,
                                                    isReachable: isReachable,
                                                    isVisited: run.visitedNodeIDs.contains(node.id),
                                                    isAlive: alive.contains(node.id)
                                                )
                                            }
                                        }
                                        .buttonStyle(.gamePlain)
                                        .disabled(walkingToNodeID != nil)
                                        .position(layout.point(node.id, height: sheetHeight))
                                    }

                                    partyWalkers(height: sheetHeight)
                                }
                                .frame(width: width, height: sheetHeight)
                                .clipShape(sheetShape)
                                // Layered paper edge & bevel on the wooden table
                                .background(
                                    ZStack {
                                        // Under-sheet of slightly offset parchment
                                        // A dark offset sheet instead of large blurred shadows, which
                                        // made scrolling the ~1500pt-wide map expensive.
                                        sheetShape
                                            .fill(Color.black.opacity(0.45))
                                            .offset(x: 6, y: 10)
                                        if mapStyle == .hologram {
                                            // The holo-sheet floats: a soft cyan halo instead of paper layers.
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(HoloPalette.cyan.opacity(0.10))
                                                .padding(-5)
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(HoloPalette.deep)
                                        } else {
                                            sheetShape
                                                .fill(Color(red: 0.80, green: 0.72, blue: 0.57))
                                                .offset(x: 2, y: 4)
                                            sheetShape
                                                .fill(Palette.parchment)
                                        }
                                    }
                                )
                                .overlay(
                                    sheetShape
                                        .stroke(mapStyle == .hologram ? HoloPalette.cyan.opacity(0.7) : Palette.ink.opacity(0.4), lineWidth: mapStyle == .hologram ? 1.5 : 1)
                                )
                                // Rolled up at both ends (parchment only).
                                .overlay(alignment: .leading) {
                                    if mapStyle != .hologram {
                                        ScrollRollerView(height: sheetHeight).offset(x: -22)
                                    }
                                }
                                .overlay(alignment: .trailing) {
                                    if mapStyle != .hologram {
                                        ScrollRollerView(height: sheetHeight).offset(x: 22)
                                    }
                                }
                            }
                            .padding(.horizontal, tablePadH)
                            .padding(.vertical, tablePadV)
                        }
                        .scrollPosition($scrollPosition)
                        #if os(macOS)
                        // A mouse can't swipe a scroll view; click-and-drag pans the map (game.md §15).
                        .modifier(DragToScroll(position: $scrollPosition))
                        #endif
                        .onAppear {
                            scrollToParty(x: partyPoint(height: sheetHeight).x, viewport: viewport.size.width, animated: false)
                        }
                        .onChange(of: walkingToNodeID) { _, target in
                            guard let target else { return }
                            scrollToParty(x: layout.point(target, height: sheetHeight).x, viewport: viewport.size.width, animated: true)
                        }
                    }
                }
            }

            if let nodeID = inspectedNodeID, let node = run.map.node(nodeID) {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { inspectedNodeID = nil }
                    MapNodePreviewCard(
                        node: node,
                        run: run,
                        canTravel: walkingToNodeID == nil && !hasCover && run.isReachable(node.id),
                        onTravel: { travel(to: node) },
                        onClose: { inspectedNodeID = nil }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(1)
            }

            // Fast in-place screen transitions (keeps RunMapView alive underneath with 0ms rebuild)
            if let fight = activeFight {
                FightView(engine: fight.engine, theme: fight.theme, reward: fight.reward, onComplete: { finished in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        run.finishFight(at: fight.nodeID, engine: finished, reward: fight.reward)
                        activeFight = nil
                    }
                }, run: run)
                .id(fight.id)
                .modifier(MapPeekCover(peeking: peekingMap) { peekingMap = true })
                .transition(.opacity)
                .zIndex(2)
            }

            if let node = activeNode {
                Group {
                    switch node.type {
                    case .shop:
                        ShopView(run: run, nodeID: node.id) {
                            withAnimation(.easeInOut(duration: 0.22)) { activeNode = nil }
                        }
                    case .campfire:
                        CampfireView(run: run, nodeID: node.id) {
                            withAnimation(.easeInOut(duration: 0.22)) { activeNode = nil }
                        }
                    default:
                        EventView(run: run, nodeID: node.id) {
                            withAnimation(.easeInOut(duration: 0.22)) { activeNode = nil }
                        }
                    }
                }
                .id(node.id)
                .modifier(MapPeekCover(peeking: peekingMap) { peekingMap = true })
                .transition(.opacity)
                .zIndex(2)
            }

            // Level-ups first (game.md §5 "Levels"), then the fight's skill offer.
            if let offer = run.pendingDieUpgrades.first, activeFight == nil, activeNode == nil {
                DieUpgradeView(run: run, offer: offer)
                    .id(run.pendingDieUpgrades.count)
                    .modifier(MapPeekCover(peeking: peekingMap) { peekingMap = true })
                    .transition(.opacity)
                    .zIndex(2.6)
            } else if let offer = run.pendingSkillOffer, activeFight == nil {
                // Also over the shop, right after buying a skill scroll (game.md §10).
                SkillRewardView(run: run, offer: offer)
                    .id(offer)
                    .modifier(MapPeekCover(peeking: peekingMap) { peekingMap = true })
                    .transition(.opacity)
                    .zIndex(2.5)
            }

            // Looking at the map from a fight / shop / campfire / event / skill offer: the screen
            // stays alive underneath, this brings it back.
            if peekingMap && hasCover {
                VStack {
                    Spacer()
                    Button {
                        Sound.play(.tap)
                        peekingMap = false
                    } label: {
                        Label("Back", systemImage: "arrow.uturn.backward")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(QuestButtonStyle(kind: .primary))
                    .accessibilityLabel("Back to the current screen")
                    .padding(.bottom, 18)
                }
                .transition(.opacity)
                .zIndex(2.8)
            }

            if run.isOver && activeFight == nil {
                RunEndView(run: run, onExit: onExit)
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: inspectedNodeID)
        .animation(.easeInOut(duration: 0.22), value: activeFight?.id)
        .animation(.easeInOut(duration: 0.22), value: activeNode?.id)
        .animation(.easeInOut(duration: 0.24), value: run.isOver)
        .overlay {
            // A new act's map has begun (game.md §16): its name, once, until tapped away.
            if let index = introActIndex, index == run.actIndex, !hasCover {
                ActIntroCard(act: run.act, number: index + 1) { introActIndex = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: introActIndex)
        .onChange(of: run.actIndex) { _, index in
            arrivedNodeID = nil
            scrollPosition.scrollTo(x: 0)
            introActIndex = index
        }
        .animation(.easeInOut(duration: 0.2), value: peekingMap)
        .onChange(of: hasCover) { _, covered in
            if !covered { peekingMap = false }
        }
        .onChange(of: run.currentNodeID) { _, newID in
            arrivedNodeID = newID
        }
        .hiddenNavigationBar()
        .sheet(item: $partySheetSelection) { selection in
            PartyInventorySheet(run: run, initialSelection: selection)
        }
        .confirmationDialog("Abandon this run?", isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("Abandon", role: .destructive) {
                run.abandon()
                onExit()
            }
        } message: {
            Text("Gold, potions, relics and progress are lost. Card stats are kept.")
        }
    }

    /// The terrain's pixel scale: the screen's, raised in a scaled-up Mac canvas (game.md §15).
    /// Rounded up to quarter steps so resizing a window doesn't repaint it every frame.
    private var terrainScale: CGFloat { (displayScale * 4).rounded(.up) / 4 }

    /// Paints the terrain once into an image for this height, act and scale.
    private func renderTerrain(layout: WorldMapLayout, height: CGFloat) {
        guard terrain?.height != height || terrain?.act != run.actIndex || terrain?.scale != terrainScale else { return }
        let renderer = ImageRenderer(content: Group {
            if mapStyle == .hologram {
                HoloMapTerrain(layout: layout, height: height)
            } else {
                WorldMapTerrain(layout: layout, height: height)
            }
        }
        .frame(width: layout.width, height: height))
        renderer.scale = terrainScale
        #if canImport(UIKit)
        let rendered = renderer.uiImage
        #else
        let rendered = renderer.nsImage
        #endif
        if let image = rendered {
            terrain = (height, run.actIndex, terrainScale, image)
        }
    }

    /// Visited nodes plus everything still reachable from here; the rest are paths not taken.
    private var aliveNodeIDs: Set<Int> {
        var alive = run.visitedNodeIDs
        var seen = Set<Int>()
        var queue = run.reachableNodeIDs
        while let id = queue.popLast() {
            guard seen.insert(id).inserted else { continue }
            alive.insert(id)
            if let node = run.map.node(id) { queue.append(contentsOf: node.nextNodeIDs) }
        }
        return alive
    }

    /// Where the party stands: the arrived node, the current node, or the trailhead at the left edge.
    private func partyPoint(height: CGFloat) -> CGPoint {
        if let current = arrivedNodeID ?? run.currentNodeID { return layout.point(current, height: height) }
        return layout.entryPoint(height: height)
    }

    private func scrollToParty(x: CGFloat, viewport: CGFloat, animated: Bool) {
        let target = max(0, min(layout.width - viewport + 52, x - viewport * 0.35))
        if animated {
            withAnimation(.easeInOut(duration: 0.9)) { scrollPosition.scrollTo(x: target) }
        } else {
            scrollPosition.scrollTo(x: target)
        }
    }

    /// The heroes walk the winding road to the chosen place, then the place opens.
    private func travel(to node: MapNode) {
        inspectedNodeID = nil
        travelProgress = 0
        walkingToNodeID = node.id
        withAnimation(.easeInOut(duration: 0.9)) { travelProgress = 1 }
        // Footfalls in step with the walk animation.
        for step in 0..<5 {
            Sound.play(.footstep, volume: 0.8, delay: 0.06 + Double(step) * 0.17)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(920))
            arrivedNodeID = node.id
            walkingToNodeID = nil
            travelProgress = 0
            withAnimation(.easeInOut(duration: 0.22)) {
                open(node)
            }
        }
    }

    private func open(_ node: MapNode) {
        guard run.isReachable(node.id) else { return }
        switch node.type {
        case .fight, .elite, .boss:
            // Built once here and kept in state — never rebuilt by a view re-render. The reward
            // (incl. any skill offer) is rolled and saved the first time.
            guard let started = run.startFight(at: node.id) else { return }
            activeFight = ActiveFight(nodeID: node.id, engine: started.engine, reward: started.reward, theme: started.theme)
        case .shop, .event, .campfire:
            activeNode = node
        }
    }

    private func partyWalkers(height: CGFloat) -> some View {
        let from = partyPoint(height: height)
        let to = walkingToNodeID.map { layout.point($0, height: height) } ?? from
        let isWalking = walkingToNodeID != nil
        return ZStack {
            ForEach(Array(run.heroes.enumerated().reversed()), id: \.element.id) { index, hero in
                WalkerFigureView(
                    hero: hero,
                    isWalking: isWalking,
                    breathes: false,
                    progress: travelProgress,
                    from: from,
                    to: to,
                    lag: index == 0 ? 0 : 0.09,
                    sideOffset: index == 0 ? 14 : -18
                ) {
                    if !isWalking {
                        partySheetSelection = .hero(index)
                    }
                }
            }
        }
    }
}


/// A screen covering the map: hidden but kept alive while the player looks at the map, and given
/// the `openRunMap` action so its map chip can start that (game.md §9 "Looking at the map").
private struct MapPeekCover: ViewModifier {
    let peeking: Bool
    let open: () -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.openRunMap, open)
            .opacity(peeking ? 0 : 1)
            .allowsHitTesting(!peeking)
    }
}

/// Animated hero miniature on the map that walks with alternating left/right boot strides,
/// bouncy step arcs, squash-and-stretch, and trailing dust puffs when traveling between nodes.
private struct WalkerFigureView: View {
    let hero: HeroState
    let isWalking: Bool
    var breathes = true
    let progress: CGFloat
    let from: CGPoint
    let to: CGPoint
    let lag: CGFloat
    let sideOffset: CGFloat
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: 62, breathes: breathes)
                    .id(breathes)
                    .saturation(hero.isAlive ? 1 : 0)
            }
        }
        .buttonStyle(.gamePlain)
        .modifier(FollowRoad(
            progress: progress,
            from: from,
            to: to,
            lag: lag,
            sideOffset: sideOffset
        ))
    }
}

/// Where every node sits on the painted map. Rows run left → right; lanes spread vertically with
/// a small deterministic jitter so the map doesn't look like a grid.
struct WorldMapLayout {
    let map: GameMap
    let rowCount: Int
    let laneCount: Int
    private let nodesByID: [Int: MapNode]

    init(map: GameMap, rowCount: Int, laneCount: Int) {
        self.map = map
        self.rowCount = rowCount
        self.laneCount = laneCount
        self.nodesByID = Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0) })
    }

    static let columnWidth: CGFloat = 150
    static let leftMargin: CGFloat = 130

    var width: CGFloat { Self.leftMargin + CGFloat(rowCount) * Self.columnWidth + 140 }

    func point(_ nodeID: Int, height: CGFloat) -> CGPoint {
        guard let node = nodesByID[nodeID] else { return .zero }
        let jitterX = CGFloat((node.id * 37) % 29) - 14
        let jitterY = CGFloat((node.id * 53) % 25) - 12
        let x = Self.leftMargin + CGFloat(node.row) * Self.columnWidth + (node.type == .boss ? 20 : jitterX)
        if node.type == .boss { return CGPoint(x: x, y: height * 0.5) }
        let usable = height - 110
        let y = 62 + usable * (CGFloat(node.column) + 0.5) / CGFloat(max(1, laneCount)) + jitterY
        return CGPoint(x: x, y: y)
    }

    func entryPoint(height: CGFloat) -> CGPoint { CGPoint(x: 42, y: height * 0.55) }
}

/// Moves a view along the same S-curve the roads use, with a lively walking stride:
/// alternating left/right boots, bouncy step arcs, squash-and-stretch at footfalls, and dust puffs.
private struct FollowRoad: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGPoint
    let to: CGPoint
    let lag: CGFloat
    let sideOffset: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = min(1, max(0, (progress - lag) / (1 - lag)))
        let p = RoadCurve.point(from: from, to: to, t: t)
        let isMoving = t > 0.001 && t < 0.999
        let phase = t * .pi * 12 // 6 full left-right strides along the road
        let sinP = sin(phase)
        let absSin = abs(sinP)

        // Vertical hop on each stride + subtle squash at landing and stretch at apex
        let stepHop: CGFloat = isMoving ? absSin * 6.5 : 0
        let scaleX: CGFloat = isMoving ? (1.0 + (0.5 - absSin) * 0.09) : 1.0
        let scaleY: CGFloat = isMoving ? (1.0 + (absSin - 0.5) * 0.09) : 1.0
        let swayDeg: Double = isMoving ? Double(sinP) * 7.5 : 0

        // Alternating left and right foot swing
        let leftFootX: CGFloat = isMoving ? CGFloat(sinP) * 5.5 : -3.5
        let leftFootY: CGFloat = isMoving ? max(0, CGFloat(-sinP)) * -4.5 : 0
        let rightFootX: CGFloat = isMoving ? CGFloat(-sinP) * 5.5 : 3.5
        let rightFootY: CGFloat = isMoving ? max(0, CGFloat(sinP)) * -4.5 : 0

        let shadowWidth: CGFloat = 34 - stepHop * 0.9

        return ZStack {
            // Trailing dust puffs kicked up behind the boots while walking
            if isMoving {
                Circle()
                    .fill(Palette.parchmentShade.opacity(0.65 * Double(1 - absSin)))
                    .frame(width: 7 + (1 - absSin) * 5, height: 7 + (1 - absSin) * 5)
                    .offset(x: -12 - CGFloat(absSin) * 8, y: 28 - CGFloat(1 - absSin) * 4)
                Circle()
                    .fill(Palette.ink.opacity(0.18 * Double(absSin)))
                    .frame(width: 5 + absSin * 4, height: 5 + absSin * 4)
                    .offset(x: -17 - CGFloat(1 - absSin) * 6, y: 30)
            }

            // Dynamic ground shadow on the parchment
            Ellipse()
                .fill(Palette.ink.opacity(isMoving ? 0.24 : 0.30))
                .frame(width: shadowWidth, height: 7)
                .offset(y: 30)

            // Animated stepping boots beneath the character
            Capsule()
                .fill(Palette.ink.opacity(0.88))
                .frame(width: 7, height: 4.5)
                .offset(x: leftFootX - 2, y: 27 + leftFootY)
            Capsule()
                .fill(Palette.ink.opacity(0.88))
                .frame(width: 7, height: 4.5)
                .offset(x: rightFootX + 2, y: 27 + rightFootY)

            // Hero sprite with stride bounce, squash/stretch, and tilt
            content
                .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
                .rotationEffect(.degrees(swayDeg), anchor: .bottom)
                .offset(y: -stepHop)
        }
        .position(x: p.x + sideOffset, y: p.y - 32)
    }
}

/// Shared geometry for the winding roads: they leave and arrive horizontally, bowing in between.
enum RoadCurve {
    static func controls(from p0: CGPoint, to p1: CGPoint) -> (CGPoint, CGPoint) {
        let dx = p1.x - p0.x
        return (CGPoint(x: p0.x + dx * 0.5, y: p0.y), CGPoint(x: p1.x - dx * 0.5, y: p1.y))
    }

    static func point(from p0: CGPoint, to p1: CGPoint, t: CGFloat) -> CGPoint {
        let (c1, c2) = controls(from: p0, to: p1)
        let mt = 1 - t
        let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x, y: a * p0.y + b * c1.y + c * c2.y + d * p1.y)
    }

    static func path(from p0: CGPoint, to p1: CGPoint) -> Path {
        let (c1, c2) = controls(from: p0, to: p1)
        var path = Path()
        path.move(to: p0)
        path.addCurve(to: p1, control1: c1, control2: c2)
        return path
    }
}

private struct RoadCurveShape: Shape {
    let from: CGPoint
    let to: CGPoint
    func path(in rect: CGRect) -> Path { RoadCurve.path(from: from, to: to) }
}

/// Roads painted on the map: red ink for the route taken, inked dashes for the roads you can take
/// next (gilded and animated on top by `OpenRoadShimmer`), dotted footpaths ahead. Static: only
/// redrawn when the party's progress changes.
private struct WorldMapRoads: View, Equatable {
    let layout: WorldMapLayout
    let height: CGFloat
    let visited: Set<Int>
    let currentNodeID: Int?
    let reachable: Set<Int>
    let alive: Set<Int>
    var style: MapStyle = .parchment

    static func == (a: WorldMapRoads, b: WorldMapRoads) -> Bool {
        a.height == b.height && a.visited == b.visited && a.currentNodeID == b.currentNodeID
            && a.reachable == b.reachable && a.alive == b.alive && a.layout.map == b.layout.map && a.style == b.style
    }

    private enum RoadState { case traveled, open, future, closed }

    var body: some View {
        Canvas { ctx, _ in
            func draw(_ path: Path, _ state: RoadState) {
                if style == .hologram {
                    drawLightTrace(path, state)
                    return
                }
                let opacity: Double
                switch state {
                case .traveled, .open: opacity = 1
                case .future: opacity = 0.6
                case .closed: opacity = 0.2
                }
                // Painted on: a soft watercolor wash under an inked line.
                ctx.stroke(path, with: .color(Color(red: 0.55, green: 0.43, blue: 0.28).opacity(0.16 * opacity)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                switch state {
                case .traveled:
                    // The route taken, in red ink like on an old treasure map.
                    ctx.stroke(path, with: .color(Color(red: 0.60, green: 0.20, blue: 0.14).opacity(0.85)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [8, 5]))
                case .open:
                    // Inked here; the gold shimmer on top is `OpenRoadShimmer`.
                    ctx.stroke(path, with: .color(Palette.ink.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6]))
                case .future:
                    // A dotted footpath ahead.
                    ctx.stroke(path, with: .color(Palette.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.5, 7]))
                case .closed:
                    ctx.stroke(path, with: .color(Palette.ink.opacity(0.16)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.5, 8]))
                }
            }

            /// Act II: roads are lines of light — bright where travelled or open, faint ahead.
            func drawLightTrace(_ path: Path, _ state: RoadState) {
                let cyan = HoloPalette.cyan
                switch state {
                case .traveled:
                    ctx.stroke(path, with: .color(cyan.opacity(0.25)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    ctx.stroke(path, with: .color(Color.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                case .open:
                    ctx.stroke(path, with: .color(cyan.opacity(0.22)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    ctx.stroke(path, with: .color(cyan), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [6, 5]))
                case .future:
                    ctx.stroke(path, with: .color(cyan.opacity(0.35)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 5]))
                case .closed:
                    ctx.stroke(path, with: .color(cyan.opacity(0.10)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
            }

            var layers: [(Path, RoadState)] = []
            // From the trailhead to every first-row place.
            let entry = layout.entryPoint(height: height)
            for node in layout.map.nodes where node.row == 0 {
                let state: RoadState
                if visited.contains(node.id) { state = .traveled }
                else if currentNodeID == nil && reachable.contains(node.id) { state = .open }
                else { state = alive.contains(node.id) ? .future : .closed }
                layers.append((RoadCurve.path(from: entry, to: layout.point(node.id, height: height)), state))
            }
            for node in layout.map.nodes {
                for nextID in node.nextNodeIDs {
                    let state: RoadState
                    if visited.contains(node.id) && visited.contains(nextID) {
                        state = .traveled
                    } else if node.id == currentNodeID && reachable.contains(nextID) {
                        state = .open
                    } else if alive.contains(node.id) && alive.contains(nextID) && !visited.contains(node.id) {
                        state = .future
                    } else {
                        state = .closed
                    }
                    layers.append((RoadCurve.path(from: layout.point(node.id, height: height), to: layout.point(nextID, height: height)), state))
                }
            }
            for state in [RoadState.closed, .future, .traveled, .open] {
                for layer in layers where layer.1 == state { draw(layer.0, state) }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Hand-painted landscape on parchment: a forest at the trailhead thinning out along the way, a
/// river winding across, hills, and a mountain range around the dragon's lair at the end, on worn
/// paper (water stains, a scorch mark, shading where it rolls up). Uses the hand-drawn
/// `map_fantasy_*` art as map illustrations (ink triangles if it's missing). Static.
private struct WorldMapTerrain: View {
    let layout: WorldMapLayout
    let height: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let w = size.width, h = size.height

            // Parchment with darker, worn edges.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Palette.parchment, Palette.parchmentShade.mixed(with: Palette.parchment, 0.4)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            for edge in [CGRect(x: 0, y: 0, width: w, height: 26), CGRect(x: 0, y: h - 26, width: w, height: 26)] {
                ctx.fill(Path(edge), with: .linearGradient(
                    Gradient(colors: edge.minY == 0 ? [Palette.ink.opacity(0.22), .clear] : [.clear, Palette.ink.opacity(0.22)]),
                    startPoint: CGPoint(x: 0, y: edge.minY), endPoint: CGPoint(x: 0, y: edge.maxY)))
            }
            var rng = LinearCongruentialGenerator(seed: 7)
            for _ in 0..<Int(w / 90) {
                let p = CGPoint(x: rng.next(in: 0...w), y: rng.next(in: 0...h))
                let r = rng.next(in: 20...60)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.7, width: r * 2, height: r * 1.4)),
                         with: .color(Palette.parchmentShade.opacity(0.18)))
            }

            // Keep scenery off places and roads.
            var avoid: [CGPoint] = layout.map.nodes.map { layout.point($0.id, height: h) } + [layout.entryPoint(height: h)]
            for node in layout.map.nodes {
                for nextID in node.nextNodeIDs {
                    let a = layout.point(node.id, height: h), b = layout.point(nextID, height: h)
                    for i in 1..<14 { avoid.append(RoadCurve.point(from: a, to: b, t: CGFloat(i) / 14)) }
                }
            }
            func isClear(_ p: CGPoint, _ radius: CGFloat) -> Bool {
                avoid.allSatisfy { q in (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y) > radius * radius }
            }

            // River winding across the whole map.
            var river = Path()
            for i in 0...120 {
                let t = CGFloat(i) / 120
                let p = CGPoint(x: t * w, y: h * (0.5 + 0.30 * sin(t * .pi * 3.2 + 0.6)))
                if i == 0 { river.move(to: p) } else { river.addLine(to: p) }
            }
            ctx.stroke(river, with: .color(Color(red: 0.52, green: 0.65, blue: 0.74).opacity(0.85)), style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round))
            ctx.stroke(river, with: .color(Color(red: 0.74, green: 0.83, blue: 0.87).opacity(0.7)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [10, 14]))

            // Hills sketched in ink along the middle stretch.
            for i in 0..<Int(w / 160) {
                let p = CGPoint(x: rng.next(in: w * 0.25...w * 0.8), y: rng.next(in: h * 0.15...h * 0.9))
                guard isClear(p, 46) else { continue }
                let half = rng.next(in: 22...38)
                var arc = Path()
                arc.move(to: CGPoint(x: p.x - half, y: p.y))
                arc.addQuadCurve(to: CGPoint(x: p.x + half, y: p.y), control: CGPoint(x: p.x, y: p.y - half * 1.1))
                ctx.stroke(arc, with: .color(Palette.ink.opacity(0.25)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                if i % 2 == 0 {
                    var inner = Path()
                    inner.move(to: CGPoint(x: p.x - half * 0.4, y: p.y - half * 0.3))
                    inner.addQuadCurve(to: CGPoint(x: p.x + half * 0.2, y: p.y - half * 0.3), control: CGPoint(x: p.x - half * 0.1, y: p.y - half * 0.7))
                    ctx.stroke(inner, with: .color(Palette.ink.opacity(0.18)), lineWidth: 1)
                }
            }

            // Mountains: a range around the boss at the far right, a few foothills before it.
            let mountainArt = ["map_fantasy_mountain", "map_fantasy_mountain_alt1", "map_fantasy_mountain_alt2"]
            let peaks: [(CGFloat, CGFloat, CGFloat)] = [
                (w - 120, h * 0.20, 150), (w - 40, h * 0.30, 130), (w - 150, h * 0.86, 140),
                (w - 60, h * 0.90, 120), (w * 0.72, h * 0.14, 90), (w * 0.62, h * 0.92, 80)
            ]
            for (index, peak) in peaks.enumerated() {
                let rect = CGRect(x: peak.0 - peak.2 / 2, y: peak.1 - peak.2 * 0.7, width: peak.2, height: peak.2 * 0.7)
                guard isClear(CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.3), peak.2 * 0.35) else { continue }
                if let thumb = ArtCache.thumbnail(mountainArt[index % 3], height: 105) {
                    var art = ctx
                    art.opacity = 0.9
                    art.draw(Image(platformImage: thumb), in: rect)
                } else {
                    var m = Path()
                    m.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                    m.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
                    m.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    ctx.stroke(m, with: .color(Palette.ink.opacity(0.4)), lineWidth: 1.5)
                }
            }

            // The dragon's glow behind the boss.
            if let boss = layout.map.nodes.first(where: { $0.type == .boss }) {
                let c = layout.point(boss.id, height: h)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 90, y: c.y - 90, width: 180, height: 180)),
                         with: .radialGradient(Gradient(colors: [Palette.ember.opacity(0.55), .clear]), center: c, startRadius: 0, endRadius: 90))
            }

            // Forest: thick at the trailhead, thinning out toward the mountains.
            // Each tree keeps its own proportions (the set has wide oaks and a tall cypress).
            let treeNames = ["map_fantasy_tree", "map_fantasy_tree_alt"] + (1...6).map { "map_fantasy_tree_\($0)" }
            let treeArt = treeNames.compactMap { name -> (image: GraphicsContext.ResolvedImage, aspect: CGFloat)? in
                guard let thumb = ArtCache.thumbnail(name, height: 34) else { return nil }
                return (ctx.resolve(Image(platformImage: thumb)), ArtCache.aspect(name) ?? 1)
            }
            let hasTreeArt = !treeArt.isEmpty
            var index = 0
            for x in stride(from: CGFloat(14), through: w * 0.8, by: 34) {
                for y in stride(from: CGFloat(24), through: h - 10, by: 32) {
                    index += 1
                    let density = 0.55 - (x / w) * 0.75
                    guard rng.next(in: 0...1) < density else { continue }
                    let p = CGPoint(x: x + rng.next(in: -10...10), y: y + rng.next(in: -8...8))
                    guard isClear(p, 40) else { continue }
                    let th = rng.next(in: 22...34)
                    let rect = CGRect(x: p.x - th / 2, y: p.y - th, width: th, height: th)
                    if hasTreeArt {
                        let art = treeArt[index % treeArt.count]
                        let artWidth = th * art.aspect
                        ctx.draw(art.image, in: CGRect(x: p.x - artWidth / 2, y: rect.minY, width: artWidth, height: th))
                    } else {
                        var tree = Path()
                        tree.move(to: CGPoint(x: rect.midX, y: rect.minY))
                        tree.addLine(to: CGPoint(x: rect.maxX - th * 0.2, y: rect.maxY))
                        tree.addLine(to: CGPoint(x: rect.minX + th * 0.2, y: rect.maxY))
                        tree.closeSubpath()
                        ctx.fill(tree, with: .color(Color(red: 0.32, green: 0.42, blue: 0.28).opacity(0.8)))
                    }
                }
            }

            // Compass rose at the trailhead.
            let compass = CGPoint(x: 70, y: h - 58)
            let r: CGFloat = 22
            ctx.stroke(Path(ellipseIn: CGRect(x: compass.x - r, y: compass.y - r, width: r * 2, height: r * 2)), with: .color(Palette.ink.opacity(0.35)), lineWidth: 1)
            for angle in stride(from: 0.0, to: 360.0, by: 90.0) {
                let rad = angle * .pi / 180
                var arm = Path()
                arm.move(to: CGPoint(x: compass.x + cos(rad) * r * 1.5, y: compass.y + sin(rad) * r * 1.5))
                arm.addLine(to: CGPoint(x: compass.x + cos(rad + .pi / 2) * r * 0.25, y: compass.y + sin(rad + .pi / 2) * r * 0.25))
                arm.addLine(to: CGPoint(x: compass.x + cos(rad - .pi / 2) * r * 0.25, y: compass.y + sin(rad - .pi / 2) * r * 0.25))
                arm.closeSubpath()
                ctx.fill(arm, with: .color(Palette.ink.opacity(angle == 270 ? 0.6 : 0.35)))
            }

            // The paper curves away into the rolls at both ends.
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 70, height: h)), with: .linearGradient(
                Gradient(colors: [Palette.ink.opacity(0.28), .clear]), startPoint: .zero, endPoint: CGPoint(x: 70, y: 0)))
            ctx.fill(Path(CGRect(x: w - 70, y: 0, width: 70, height: h)), with: .linearGradient(
                Gradient(colors: [.clear, Palette.ink.opacity(0.28)]), startPoint: CGPoint(x: w - 70, y: 0), endPoint: CGPoint(x: w, y: 0)))

            // Wear: a few water-stain rings and a scorch mark on the top edge.
            var wear = LinearCongruentialGenerator(seed: 23)
            for _ in 0..<max(2, Int(w / 520)) {
                let c = CGPoint(x: wear.next(in: w * 0.12...w * 0.88), y: wear.next(in: h * 0.2...h * 0.8))
                let r = wear.next(in: 26...44)
                let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.9, width: r * 2, height: r * 1.8))
                ctx.fill(ring, with: .color(Color(red: 0.55, green: 0.40, blue: 0.22).opacity(0.06)))
                ctx.stroke(ring, with: .color(Color(red: 0.50, green: 0.35, blue: 0.18).opacity(0.16)), lineWidth: 2.5)
            }
            let scorch = CGPoint(x: w * 0.58, y: 0)
            ctx.fill(Path(ellipseIn: CGRect(x: scorch.x - 60, y: -40, width: 120, height: 80)), with: .radialGradient(
                Gradient(colors: [Color(red: 0.22, green: 0.12, blue: 0.05).opacity(0.75), Color(red: 0.45, green: 0.28, blue: 0.12).opacity(0.35), .clear]),
                center: scorch, startRadius: 4, endRadius: 58))

            // Double-ruled cartographic ink border, inside the ragged edges and the rolls.
            let outerBorder = CGRect(x: 30, y: 20, width: w - 60, height: h - 40)
            let innerBorder = CGRect(x: 35, y: 25, width: w - 70, height: h - 50)
            ctx.stroke(Path(outerBorder), with: .color(Palette.ink.opacity(0.4)), lineWidth: 1.6)
            ctx.stroke(Path(innerBorder), with: .color(Palette.ink.opacity(0.22)), lineWidth: 0.9)

            // Crimson wax seal stamped near the bottom-right corner of the map
            let seal = CGPoint(x: w - 78, y: h - 50)
            ctx.fill(
                Path(ellipseIn: CGRect(x: seal.x - 17, y: seal.y - 15, width: 34, height: 34)),
                with: .color(Color.black.opacity(0.28))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: seal.x - 16, y: seal.y - 16, width: 32, height: 32)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.72, green: 0.16, blue: 0.14),
                        Color(red: 0.45, green: 0.08, blue: 0.08)
                    ]),
                    center: CGPoint(x: seal.x - 3, y: seal.y - 3),
                    startRadius: 2,
                    endRadius: 17
                )
            )
            ctx.stroke(
                Path(ellipseIn: CGRect(x: seal.x - 11, y: seal.y - 11, width: 22, height: 22)),
                with: .color(Color(red: 0.90, green: 0.35, blue: 0.30).opacity(0.65)),
                lineWidth: 1.2
            )
        }
        .allowsHitTesting(false)
    }
}

/// A place on the map: parchment medallion with its glyph. Reachable places get a gold ring;
/// finished places get a check; places on paths not taken fade out. Static (no pulse).
private struct WorldMapBadge: View {
    let node: MapNode
    let isReachable: Bool
    let isVisited: Bool
    let isAlive: Bool
    var style: MapStyle = .parchment

    private var diameter: CGFloat { node.type == .boss ? 62 : 46 }
    private var holo: Bool { style == .hologram }

    var body: some View {
        ZStack {
            if isReachable {
                Circle()
                    .stroke(holo ? HoloPalette.cyan : Palette.gold.opacity(0.8), lineWidth: 2.5)
                    .frame(width: diameter + 12, height: diameter + 12)
            }
            Circle()
                .fill(holo
                      ? (isVisited ? HoloPalette.cyan.opacity(0.35) : HoloPalette.glass)
                      : (isVisited ? Palette.ink.opacity(0.78) : Palette.parchment))
                .overlay(Circle().strokeBorder(
                    holo ? HoloPalette.cyan.opacity(isReachable ? 1 : 0.6) : (isReachable ? Palette.gold : Palette.ink.opacity(0.55)),
                    lineWidth: isReachable ? 2.5 : 1.5))
                .shadow(color: holo ? HoloPalette.cyan.opacity(0.4) : .black.opacity(0.25), radius: 3, y: holo ? 0 : 2)
                .frame(width: diameter, height: diameter)
            Image(systemName: nodeIcon(node.type))
                .font(.system(size: diameter * 0.40, weight: .bold))
                .foregroundStyle(holo
                                 ? (isVisited ? Color.white.opacity(0.7) : holoTint(node.type))
                                 : (isVisited ? Palette.parchment.opacity(0.75) : nodeTint(node.type)))
            if isVisited {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.moss, Palette.parchment)
                    .offset(x: diameter * 0.36, y: diameter * 0.36)
            }
        }
        .frame(width: diameter + 18, height: diameter + 18)
        .scaleEffect(isReachable ? 1.06 : 1.0)
        .opacity(isAlive ? 1 : 0.35)
        .saturation(isAlive ? 1 : 0)
        .contentShape(Circle())
    }
}

/// Place glyph colors on the holographic map: light tints that read on dark glass.
private func holoTint(_ type: MapNodeType) -> Color {
    switch type {
    case .fight: return HoloPalette.cyan
    case .elite: return HoloPalette.alert
    case .boss: return HoloPalette.alert
    case .shop: return Palette.goldGlow
    case .event: return Color(red: 0.75, green: 0.65, blue: 1.0)
    case .campfire: return Color(red: 1.0, green: 0.62, blue: 0.30)
    }
}

/// "Act II — Neon Frontier": shown once when a new act's map begins (game.md §16). Tap to start.
private struct ActIntroCard: View {
    let act: ActDef
    let number: Int
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("ACT \(roman(number))")
                    .font(.serif(14, .heavy))
                    .tracking(4)
                    .foregroundStyle(act.mapStyle == .hologram ? HoloPalette.cyan : Palette.gold)
                Text(act.name)
                    .font(.serif(30, .bold))
                    .foregroundStyle(Palette.text)
                    .shadow(color: (act.mapStyle == .hologram ? HoloPalette.cyan : Palette.goldGlow).opacity(0.7), radius: 10)
                Button {
                    Sound.play(.tap)
                    onDismiss()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 60)
                }
                .buttonStyle(QuestButtonStyle(kind: .primary))
                .padding(.top, 6)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 14).fill(act.mapStyle == .hologram ? HoloPalette.deep.opacity(0.95) : Palette.panel.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(act.mapStyle == .hologram ? HoloPalette.cyan : Palette.gold, lineWidth: 1.5))
        }
        .onTapGesture(perform: onDismiss)
    }

    private func roman(_ n: Int) -> String {
        ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][max(0, min(9, n - 1))]
    }
}

func nodeIcon(_ type: MapNodeType) -> String {
    switch type {
    // `swords` can render blank on some SF Symbols versions; `burst.fill` renders reliably.
    case .fight: return "burst.fill"
    case .elite: return "shield.fill"
    case .boss: return "crown.fill"
    case .shop: return "cart.fill"
    case .event: return "questionmark"
    case .campfire: return "flame.fill"
    }
}

private func nodeTint(_ type: MapNodeType) -> Color {
    switch type {
    case .fight: return Palette.ink
    case .elite: return Palette.crimson
    case .boss: return Palette.ember
    case .shop: return Color(red: 0.45, green: 0.32, blue: 0.18)
    case .event: return Color(red: 0.32, green: 0.30, blue: 0.55)
    case .campfire: return Color(red: 0.80, green: 0.42, blue: 0.20)
    }
}

/// Tap-a-place preview: what's there (the actual enemies with their HP, dice and gold; or what a
/// shop / campfire / event offers), and a travel button if it's reachable.
private struct MapNodePreviewCard: View {
    let node: MapNode
    let run: RunState
    let canTravel: Bool
    var onTravel: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: nodeIcon(node.type))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(nodeTint(node.type))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.ink.opacity(0.88)))
                Text(title)
                    .font(.serif(17, .bold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 12)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.ink.opacity(0.65))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.ink.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.gamePlain)
                .accessibilityLabel("Close")
                .macKeyboardShortcut(.cancelAction)
            }

            preview

            if canTravel {
                Button(action: onTravel) {
                    Label("Travel", systemImage: "figure.walk")
                        .frame(minWidth: 120)
                }
                .buttonStyle(QuestButtonStyle(kind: .primary))
                .accessibilityLabel("Travel here")
            } else {
                Label("Not on your road", systemImage: "lock.fill")
                    .font(.serif(12, .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.5))
            }
        }
        .frame(minWidth: 230)
        .fixedSize()
        .parchment(padding: 16)
    }

    private var title: String {
        switch node.type {
        case .fight: return L("Fight")
        case .elite: return L("Elite")
        case .boss: return L("Boss")
        case .shop: return L("Shop")
        case .event: return L("Event")
        case .campfire: return L("Campfire")
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch node.type {
        case .fight, .elite, .boss:
            let enemies = run.encounter(for: node.id)?.enemyIds.compactMap { run.content.enemyDef(id: $0) } ?? []
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(Array(enemies.enumerated()), id: \.offset) { _, enemy in
                    VStack(spacing: 4) {
                        SpriteView(spriteId: enemy.spriteId, kind: .enemy, targetHeight: 78, breathes: false)
                            .frame(height: 80)
                        HStack(spacing: 6) {
                            HStack(spacing: 2) { Image(systemName: "heart.fill"); Text("\(enemy.baseHP)") }
                                .foregroundStyle(Color(red: 0.25, green: 0.5, blue: 0.22))
                            HStack(spacing: 2) {
                                Image(systemName: "die.face.5.fill")
                                Text(enemy.attackDice.flat > 0 ? "\(enemy.attackDice.count)+\(enemy.attackDice.flat)" : "\(enemy.attackDice.count)")
                            }
                            .foregroundStyle(Palette.crimson)
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                }
            }
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    GoldCoin(size: 14)
                    Text("+\(enemies.reduce(0) { $0 + $1.goldReward })")
                }
                if node.type == .elite {
                    Image(systemName: "seal.fill").foregroundStyle(Palette.gold)
                }
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.ink)
        case .shop:
            HStack(spacing: 10) {
                ForEach(run.content.items) { SpriteView(spriteId: $0.spriteId, kind: .consumable, size: 30) }
                Image(systemName: "seal.fill").foregroundStyle(Palette.gold).font(.system(size: 22))
                Image(systemName: "shippingbox.fill").foregroundStyle(Palette.gold).font(.system(size: 20))
            }
        case .campfire:
            HStack(spacing: 16) {
                HStack(spacing: 3) {
                    Text("+\(run.content.balance.campfire.restHeal)")
                    Image(systemName: "heart.fill")
                }
                .foregroundStyle(Color(red: 0.25, green: 0.5, blue: 0.22))
                Text("/").foregroundStyle(Palette.ink.opacity(0.4))
                HStack(spacing: 3) {
                    Text("+\(run.content.balance.campfire.trainDamageBonus)")
                    Image(systemName: "arrow.up.circle.fill")
                }
                .foregroundStyle(Color(red: 0.7, green: 0.5, blue: 0.1))
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
        case .event:
            if let event = run.event(for: node.id) {
                EventSceneView(event: event)
                    .frame(width: 78, height: 78)
            } else {
                EventScenePlaceholder(scene: .signpost)
                    .frame(width: 78, height: 78)
            }
        }
    }
}

#if os(macOS)
/// Click-and-drag horizontal panning for a scroll view (Mac). The scroll offset lives in a plain
/// object, not state, so tracking it never re-renders the map.
private struct DragToScroll: ViewModifier {
    @Binding var position: ScrollPosition
    @State private var tracker = Tracker()

    final class Tracker {
        var offsetX: CGFloat = 0
        var maxOffsetX: CGFloat = 0
        var dragStartX: CGFloat?
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGRect.self) { geometry in
                CGRect(x: geometry.contentOffset.x, y: 0,
                       width: max(0, geometry.contentSize.width - geometry.containerSize.width), height: 0)
            } action: { _, value in
                tracker.offsetX = value.minX
                tracker.maxOffsetX = value.width
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { drag in
                        let start = tracker.dragStartX ?? tracker.offsetX
                        tracker.dragStartX = start
                        position.scrollTo(x: min(tracker.maxOffsetX, max(0, start - drag.translation.width)))
                    }
                    .onEnded { _ in tracker.dragStartX = nil }
            )
    }
}
#endif
