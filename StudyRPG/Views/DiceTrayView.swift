import SwiftUI

// MARK: - Dice tray (game.md §8)

struct DiceRollRequest: Equatable {
    let id: UUID
    let count: Int
    /// Sides of every die in the roll: 6 or 8 — game.md §8.
    var sides: Int = DiceExpr.standardSides
    /// A hero roll throws the hero's own faces (game.md §8 "Hero dice"); nil = plain 1…sides.
    var die: [DieFace]? = nil
    /// To draw the stickers on hero faces.
    var stickers: [StickerDef] = []
    let isEnemy: Bool
    /// Fast mode: a quicker spin (game.md §8).
    var fast = false
    let onSettled: ([DieFace]) -> Void

    static func == (lhs: DiceRollRequest, rhs: DiceRollRequest) -> Bool {
        lhs.id == rhs.id
    }
}

/// The fight's dice: a flat, framed tray over the arena in which every die spins in place,
/// flickers through faces and clicks to a stop, one after another (game.md §8). The faces are
/// rolled when the spin starts and the dice stop on exactly those faces, which are then reported
/// to `onSettled` — the faces you see (numbers and stickers) are the ones the engine uses.
struct DiceTrayView: View {
    let request: DiceRollRequest?

    @State private var roll: DiceTrayRoll?
    /// When the tray started fading out (the request was cleared).
    @State private var clearedAt: Date?

    var body: some View {
        ZStack {
            if let roll {
                TimelineView(.animation) { timeline in
                    let fade = clearedAt.map { max(0, 1 - timeline.date.timeIntervalSince($0) / DiceTrayRoll.fadeDuration) } ?? 1
                    Canvas { ctx, size in
                        ctx.opacity = fade
                        roll.draw(in: ctx, canvas: size, time: timeline.date.timeIntervalSince(roll.start))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .task(id: request?.id) { await follow(request) }
    }

    /// Starts a roll (a click as each die stops, then the result) or fades the last one out.
    @MainActor
    private func follow(_ request: DiceRollRequest?) async {
        guard let request else {
            guard roll != nil else { return }
            clearedAt = Date()
            try? await Task.sleep(for: .seconds(DiceTrayRoll.fadeDuration))
            guard !Task.isCancelled else { return }
            roll = nil
            clearedAt = nil
            return
        }
        let newRoll = DiceTrayRoll(request: request)
        roll = newRoll
        clearedAt = nil
        guard request.count > 0 else {
            request.onSettled([])
            return
        }
        Sound.play(.diceThrow)
        var elapsed = 0.0
        for stop in newRoll.dice.map(\.stop) {
            try? await Task.sleep(for: .seconds(max(0, stop - elapsed)))
            guard !Task.isCancelled else { return }
            elapsed = stop
            Sound.play(.diceClack, volume: 0.8)
        }
        try? await Task.sleep(for: .seconds(max(0, newRoll.settleTime - elapsed)))
        guard !Task.isCancelled else { return }
        request.onSettled(newRoll.dice.map(\.value))
    }
}

/// One roll: the rolled faces plus everything needed to draw any moment of it.
private struct DiceTrayRoll {
    struct Die {
        let index: Int
        let value: DieFace
        let sides: Int
        /// The face shown at each quarter turn of the spin; the last one is `value`.
        let faces: [DieFace]
        /// Seconds after the start when this die stops.
        let stop: Double
    }

    static let fadeDuration = 0.3
    private static let perRow = 5

    let start = Date()
    let isEnemy: Bool
    let dice: [Die]
    let stickers: [StickerDef]

    init(request: DiceRollRequest) {
        isEnemy = request.isEnemy
        stickers = request.stickers
        let sides = max(2, request.sides)
        let die = request.die.flatMap { $0.isEmpty ? nil : $0 } ?? DieFace.plain(sides: sides)
        let spin = request.fast ? 0.6 : 1.0
        let stagger = request.fast ? 0.08 : 0.14
        dice = (0..<max(0, request.count)).map { index in
            let valueIndex = Int.random(in: die.indices)
            // Whole turns only, so every die (and a d8's number) ends upright.
            let quarterTurns = 4 * (request.fast ? Int.random(in: 3...4) : Int.random(in: 4...6))
            var faceIndexes: [Int] = []
            for turn in 0..<quarterTurns {
                var face = Int.random(in: die.indices)
                while face == faceIndexes.last || (turn == quarterTurns - 1 && face == valueIndex) {
                    face = Int.random(in: die.indices)
                }
                faceIndexes.append(face)
            }
            faceIndexes.append(valueIndex)
            return Die(index: index, value: die[valueIndex], sides: sides, faces: faceIndexes.map { die[$0] },
                       stop: spin + Double(index) * stagger)
        }
    }

    /// When every die has stopped and the result can be read.
    var settleTime: Double { (dice.map(\.stop).max() ?? 0) + 0.15 }

    private var tint: Color { isEnemy ? Palette.ember : Palette.goldGlow }

    // MARK: Layout

    private struct Layout {
        let die: CGFloat
        let slot: CGFloat
        let tray: CGRect
    }

    private func layout(_ canvas: CGSize) -> Layout {
        let die = min(52, max(36, canvas.height * 0.11))
        let slot = die * 1.45
        let columns = CGFloat(min(Self.perRow, max(1, dice.count)))
        let rows = CGFloat((dice.count + Self.perRow - 1) / Self.perRow)
        let width = columns * slot + die * 0.5
        let height = max(1, rows) * slot + die * 0.3
        // Over the arena floor, below the enemies' nameplates.
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2 + 50)
        return Layout(die: die, slot: slot,
                      tray: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
    }

    private func slotCenter(_ die: Die, _ layout: Layout) -> CGPoint {
        let row = die.index / Self.perRow
        let inRow = min(Self.perRow, dice.count - row * Self.perRow)
        let rows = (dice.count + Self.perRow - 1) / Self.perRow
        let column = CGFloat(die.index % Self.perRow) - CGFloat(inRow - 1) / 2
        let line = CGFloat(row) - CGFloat(rows - 1) / 2
        return CGPoint(x: layout.tray.midX + column * layout.slot, y: layout.tray.midY + line * layout.slot)
    }

    // MARK: Drawing

    func draw(in ctx: GraphicsContext, canvas: CGSize, time: Double) {
        let layout = layout(canvas)
        // The tray springs open, slightly overshooting.
        let k = min(1, time / 0.22)
        let open = 1 + 2.2 * pow(k - 1, 3) + 1.2 * pow(k - 1, 2)
        var tray = ctx
        tray.opacity = min(1, k * 1.5)
        tray.translateBy(x: layout.tray.midX, y: layout.tray.midY)
        tray.scaleBy(x: 0.85 + 0.15 * open, y: 0.85 + 0.15 * open)
        tray.translateBy(x: -layout.tray.midX, y: -layout.tray.midY)

        drawTray(tray, layout)
        for die in dice { drawSocket(tray, die, time, layout) }
        for die in dice { drawDie(tray, die, time, layout) }
        for die in dice { drawStopBurst(tray, die, time, layout) }
    }

    private func drawTray(_ ctx: GraphicsContext, _ layout: Layout) {
        let rect = layout.tray
        let s = layout.die
        let frame = Path(roundedRect: rect, cornerRadius: s * 0.35)
        ctx.fill(frame, with: .color(Color.black.opacity(0.8)))
        ctx.stroke(frame, with: .color(tint), lineWidth: 2)
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: s * 0.3),
                   with: .color(tint.opacity(0.35)), lineWidth: 1)
        // A gold diamond riveted to each end, like the game's ornament dividers.
        for x in [rect.minX, rect.maxX] {
            let d = s * 0.14
            var diamond = Path()
            diamond.addLines([CGPoint(x: x, y: rect.midY - d), CGPoint(x: x + d, y: rect.midY),
                              CGPoint(x: x, y: rect.midY + d), CGPoint(x: x - d, y: rect.midY)])
            diamond.closeSubpath()
            ctx.fill(diamond, with: .color(tint))
            ctx.stroke(diamond, with: .color(Color.black.opacity(0.6)), lineWidth: 1)
        }
    }

    /// The die's round socket: a faint ring that lights up into a rune circle once the die stops.
    private func drawSocket(_ ctx: GraphicsContext, _ die: Die, _ time: Double, _ layout: Layout) {
        let s = layout.die
        let center = slotCenter(die, layout)
        let since = time - die.stop
        let lit = since > 0 ? min(1, since / 0.2) : 0
        let radius = s * 0.66
        let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.fill(ring, with: .color(Color.white.opacity(0.04)))
        ctx.stroke(ring, with: .color(tint.opacity(0.18 + 0.62 * lit)), lineWidth: 1.4)
        guard lit > 0 else { return }

        var glow = ctx
        glow.blendMode = .plusLighter
        let halo = s * 0.95
        glow.fill(Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)),
                  with: .radialGradient(Gradient(colors: [tint.opacity(0.28 * lit), .clear]), center: center, startRadius: 0, endRadius: halo))
        // Rune ticks around the ring, turning slowly.
        var runes = Path()
        let turn = since * (isEnemy ? -0.4 : 0.4)
        for i in 0..<12 {
            let a = CGFloat(Double(i) / 12 * 2 * .pi + turn)
            let inner = radius + s * 0.04
            let outer = radius + s * (i.isMultiple(of: 3) ? 0.16 : 0.09)
            runes.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
            runes.addLine(to: CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer))
        }
        ctx.stroke(runes, with: .color(tint.opacity(0.75 * lit)), lineWidth: 1.4)
    }

    private func drawDie(_ ctx: GraphicsContext, _ die: Die, _ time: Double, _ layout: Layout) {
        let center = slotCenter(die, layout)
        let quarter = Double.pi / 2
        let turns = Double(die.faces.count - 1)
        let p = min(1, max(0, time / die.stop))
        // Fast at first, braking into the stop.
        let eased = 1 - pow(1 - p, 3)
        let direction: Double = isEnemy ? -1 : 1
        let angle = direction * turns * quarter * eased
        // The face changes while the die is diagonal, so the swap is hidden in the motion.
        let face = die.faces[min(die.faces.count - 1, Int(turns * eased + 0.5))]
        let speed = turns * quarter * 3 * pow(1 - p, 2) / die.stop

        let since = time - die.stop
        let pop: CGFloat = since > 0 && since < 0.25 ? 1 + 0.18 * CGFloat(sin(.pi * since / 0.25)) : (since > 0 ? 1 : 0.9)

        // Two fading after-images while it spins fast.
        if speed > 6 {
            for ghost in 1...2 {
                var g = ctx
                g.opacity = ghost == 1 ? 0.3 : 0.14
                drawFace(g, die, value: face, at: center, angle: angle - direction * Double(ghost) * 0.16, scale: pop, size: layout.die)
            }
        }
        drawFace(ctx, die, value: face, at: center, angle: angle, scale: pop, size: layout.die)
    }

    private func drawFace(_ ctx: GraphicsContext, _ die: Die, value face: DieFace, at center: CGPoint, angle: Double, scale: CGFloat, size s: CGFloat) {
        var f = ctx
        f.translateBy(x: center.x, y: center.y)
        f.rotate(by: .radians(angle))
        f.scaleBy(x: scale, y: scale)
        if die.sides == 8 {
            drawD8(f, value: face.value, size: s)
        } else {
            drawD6(f, value: face.value, size: s)
        }
        if let sticker = stickers.first(where: { $0.id == face.sticker }) {
            drawSticker(f, sticker, size: s)
        }
    }

    /// A sticker sits on the face's top-right corner as a small ink medallion with its symbol.
    private func drawSticker(_ f: GraphicsContext, _ sticker: StickerDef, size s: CGFloat) {
        let r = s * 0.21
        let center = CGPoint(x: s * 0.4, y: -s * 0.4)
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        f.fill(disc, with: .color(Palette.ink))
        f.stroke(disc, with: .color(StickerStyle.tint(sticker.type)), lineWidth: 1.2)
        var symbol = f.resolve(Image(systemName: sticker.symbol))
        symbol.shading = .color(StickerStyle.tint(sticker.type))
        let box = r * 1.2
        f.draw(symbol, in: CGRect(x: center.x - box / 2, y: center.y - box / 2, width: box, height: box))
    }

    private var colors: (face: Color, rim: Color, ink: Color, outline: Color) {
        isEnemy
            ? (Palette.dieBlood, Palette.dieBloodShade, Palette.dieBone, Color.black.opacity(0.75))
            : (Palette.dieBone, Palette.dieBoneShade, Palette.ink, Palette.ink.opacity(0.8))
    }

    private static let pips: [Int: [(CGFloat, CGFloat)]] = [
        1: [(0.5, 0.5)],
        2: [(0.27, 0.73), (0.73, 0.27)],
        3: [(0.27, 0.73), (0.5, 0.5), (0.73, 0.27)],
        4: [(0.27, 0.27), (0.27, 0.73), (0.73, 0.27), (0.73, 0.73)],
        5: [(0.27, 0.27), (0.27, 0.73), (0.5, 0.5), (0.73, 0.27), (0.73, 0.73)],
        6: [(0.27, 0.25), (0.27, 0.5), (0.27, 0.75), (0.73, 0.25), (0.73, 0.5), (0.73, 0.75)]
    ]

    /// A flat bone (or blood) die: face, an inset rim line, pips — a hero's single pip is crimson.
    /// Raised faces above 6 show their number instead of pips.
    private func drawD6(_ f: GraphicsContext, value: Int, size s: CGFloat) {
        let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
        let body = Path(roundedRect: rect, cornerRadius: s * 0.2)
        f.fill(body, with: .color(colors.face))
        f.stroke(Path(roundedRect: rect.insetBy(dx: s * 0.08, dy: s * 0.08), cornerRadius: s * 0.14),
                 with: .color(colors.rim), lineWidth: s * 0.035)
        if Self.pips[value] == nil {
            f.draw(Text(verbatim: "\(value)").font(.serif(s * 0.5, .heavy)).foregroundStyle(colors.ink), at: .zero)
        }
        for pip in Self.pips[value] ?? [] {
            let r = s * (value == 1 ? 0.13 : 0.09)
            let center = CGPoint(x: rect.minX + pip.0 * s, y: rect.minY + pip.1 * s)
            f.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                   with: .color(value == 1 && !isEnemy ? Palette.crimson : colors.ink))
        }
        f.stroke(body, with: .color(colors.outline), lineWidth: 1.5)
    }

    /// A flat diamond with an inset rim and the number.
    private func drawD8(_ f: GraphicsContext, value: Int, size s: CGFloat) {
        let w = s * 0.56, h = s * 0.62
        func diamond(_ scale: CGFloat) -> Path {
            var path = Path()
            path.addLines([CGPoint(x: 0, y: -h * scale), CGPoint(x: w * scale, y: 0),
                           CGPoint(x: 0, y: h * scale), CGPoint(x: -w * scale, y: 0)])
            path.closeSubpath()
            return path
        }
        let body = diamond(1)
        f.fill(body, with: .color(colors.face))
        f.stroke(diamond(0.8), with: .color(colors.rim), lineWidth: s * 0.035)
        let number = Text(verbatim: "\(value)")
            .font(.serif(s * 0.4, .heavy))
            .foregroundStyle(colors.ink)
        f.draw(number, at: .zero)
        f.stroke(body, with: .color(colors.outline), lineWidth: 1.5)
    }

    /// The click of a stop: a ring snapping outward and a ring of sparks.
    private func drawStopBurst(_ ctx: GraphicsContext, _ die: Die, _ time: Double, _ layout: Layout) {
        let since = time - die.stop
        guard since > 0, since < 0.45 else { return }
        let s = layout.die
        let center = slotCenter(die, layout)
        let k = since / 0.45
        var glow = ctx
        glow.blendMode = .plusLighter

        let r = s * (0.6 + 0.7 * CGFloat(k))
        glow.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                    with: .color(tint.opacity(0.8 * (1 - k))), lineWidth: 2.5 * (1 - k) + 0.5)

        for i in 0..<8 {
            let a = CGFloat(Double(i) / 8 * 2 * .pi + Double(die.index) * 0.4)
            let distance = s * (0.7 + 0.8 * CGFloat(k))
            let point = CGPoint(x: center.x + cos(a) * distance, y: center.y + sin(a) * distance)
            let size = s * 0.05 * CGFloat(1 - k * 0.5)
            glow.fill(Path(ellipseIn: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)),
                      with: .color(tint.opacity(1 - k)))
        }
    }
}
