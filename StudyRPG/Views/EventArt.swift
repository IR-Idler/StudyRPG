import SwiftUI

// MARK: - Painted event illustrations (game.md §12 "Event scenes")
//
// One vignette per `EventScene`, painted in the same inked, shaded style as the item art and
// the hand-drawn heroes: ink outlines, gradient fills, highlights, a glowing focal point that
// lights its surroundings, and a natural patch of ground with a cast shadow. Drawn on a
// normalized 100×100 grid, so it works both at ~200pt on the event screen and ~78pt on the
// map's preview card. Static (no motion), painted once. `event_<id>` art replaces it.

enum EventArt {
    static func draw(_ scene: EventScene, in ctx: inout GraphicsContext, rect: CGRect) {
        let side = min(rect.width, rect.height)
        let g = EGrid(side: side, origin: CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2))
        switch scene {
        case .shrine: shrine(&ctx, g)
        case .chest: chest(&ctx, g)
        case .spring: spring(&ctx, g)
        case .library: library(&ctx, g)
        case .merchantCart: cart(&ctx, g)
        case .questGiver: stranger(&ctx, g)
        case .signpost: signpost(&ctx, g)
        case .fallenKnight: fallenKnight(&ctx, g)
        }
    }
}

// MARK: - Kit

private struct EGrid {
    let side: CGFloat
    let origin: CGPoint

    func p(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(x / 100) * side, y: origin.y + CGFloat(y / 100) * side)
    }
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: origin.x + CGFloat(x / 100) * side, y: origin.y + CGFloat(y / 100) * side,
               width: CGFloat(w / 100) * side, height: CGFloat(h / 100) * side)
    }
    func v(_ length: Double) -> CGFloat { CGFloat(length / 100) * side }
    func poly(_ points: [(Double, Double)]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: p(first.0, first.1))
        for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
        path.closeSubpath()
        return path
    }
    func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path { Path(ellipseIn: rect(x, y, w, h)) }
    func rounded(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
        Path(roundedRect: rect(x, y, w, h), cornerRadius: v(r))
    }
}

private let ink = Color(red: 0.09, green: 0.07, blue: 0.07)

private enum Pal {
    static let stone = [Color(red: 0.66, green: 0.66, blue: 0.68), Color(red: 0.44, green: 0.45, blue: 0.48), Color(red: 0.28, green: 0.29, blue: 0.32)]
    static let darkStone = [Color(red: 0.46, green: 0.46, blue: 0.50), Color(red: 0.28, green: 0.28, blue: 0.32)]
    static let wood = [Color(red: 0.62, green: 0.43, blue: 0.26), Color(red: 0.40, green: 0.26, blue: 0.15)]
    static let darkWood = [Color(red: 0.42, green: 0.28, blue: 0.17), Color(red: 0.24, green: 0.15, blue: 0.09)]
    static let iron = [Color(red: 0.50, green: 0.53, blue: 0.58), Color(red: 0.26, green: 0.28, blue: 0.32)]
    static let steel = [Color(red: 0.90, green: 0.93, blue: 0.97), Color(red: 0.60, green: 0.65, blue: 0.73), Color(red: 0.36, green: 0.40, blue: 0.48)]
    static let gold = [Color(red: 1.0, green: 0.88, blue: 0.52), Color(red: 0.80, green: 0.60, blue: 0.22), Color(red: 0.52, green: 0.36, blue: 0.12)]
    static let leaf = Color(red: 0.36, green: 0.54, blue: 0.28)
    static let leafDark = Color(red: 0.20, green: 0.34, blue: 0.16)
}

private extension EventArt {
    static func paint(_ ctx: inout GraphicsContext, _ g: EGrid, _ path: Path, _ colors: [Color],
                      from: (Double, Double) = (50, 0), to: (Double, Double) = (50, 100), line: Double = 1.6) {
        ctx.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: g.p(from.0, from.1), endPoint: g.p(to.0, to.1)))
        if line > 0 {
            ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: g.v(line), lineCap: .round, lineJoin: .round))
        }
    }

    static func line(_ ctx: inout GraphicsContext, _ g: EGrid, _ points: [(Double, Double)], _ color: Color, _ width: Double) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: g.p(first.0, first.1))
        for point in points.dropFirst() { path.addLine(to: g.p(point.0, point.1)) }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: g.v(width), lineCap: .round, lineJoin: .round))
    }

    static func curve(_ ctx: inout GraphicsContext, _ g: EGrid, _ a: (Double, Double), _ c: (Double, Double), _ b: (Double, Double), _ color: Color, _ width: Double) {
        var path = Path()
        path.move(to: g.p(a.0, a.1))
        path.addQuadCurve(to: g.p(b.0, b.1), control: g.p(c.0, c.1))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: g.v(width), lineCap: .round))
    }

    /// Additive light pool.
    static func glow(_ ctx: inout GraphicsContext, _ g: EGrid, _ x: Double, _ y: Double, _ r: Double, _ color: Color, _ strength: Double = 0.6) {
        var light = ctx
        light.blendMode = .plusLighter
        light.fill(g.ellipse(x - r, y - r, r * 2, r * 2), with: .radialGradient(
            Gradient(colors: [color.opacity(strength), color.opacity(strength * 0.35), color.opacity(0)]),
            center: g.p(x, y), startRadius: 0, endRadius: g.v(r)))
    }

    static func sparkle(_ ctx: inout GraphicsContext, _ g: EGrid, _ x: Double, _ y: Double, _ r: Double, _ color: Color = .white) {
        let path = g.poly([(x, y - r), (x + r * 0.22, y - r * 0.22), (x + r, y), (x + r * 0.22, y + r * 0.22),
                           (x, y + r), (x - r * 0.22, y + r * 0.22), (x - r, y), (x - r * 0.22, y - r * 0.22)])
        ctx.fill(path, with: .color(color))
    }

    static func dot(_ ctx: inout GraphicsContext, _ g: EGrid, _ x: Double, _ y: Double, _ r: Double, _ color: Color) {
        ctx.fill(g.ellipse(x - r, y - r, r * 2, r * 2), with: .color(color))
    }

    /// A soft, irregular patch of grassy ground with a contact shadow, tufts and pebbles.
    static func ground(_ ctx: inout GraphicsContext, _ g: EGrid, width: Double = 84, shadowUnder: (Double, Double)? = nil) {
        let left = 50 - width / 2, right = 50 + width / 2
        var patch = Path()
        patch.move(to: g.p(left, 88))
        patch.addQuadCurve(to: g.p(50, 80), control: g.p(left + width * 0.2, 80))
        patch.addQuadCurve(to: g.p(right, 88), control: g.p(right - width * 0.2, 80))
        patch.addQuadCurve(to: g.p(50, 96), control: g.p(right - width * 0.15, 96))
        patch.addQuadCurve(to: g.p(left, 88), control: g.p(left + width * 0.15, 96))
        patch.closeSubpath()
        paint(&ctx, g, patch, [Color(red: 0.30, green: 0.40, blue: 0.22), Color(red: 0.16, green: 0.22, blue: 0.12)], from: (50, 80), to: (50, 96), line: 1.4)
        if let (x, w) = shadowUnder {
            ctx.fill(g.ellipse(x - w / 2, 84, w, 6), with: .color(.black.opacity(0.35)))
        }
        // Grass tufts along the top edge and a few pebbles.
        for i in 0..<9 {
            let x = left + 6 + Double(i) * (width - 12) / 8
            let y = 84 + abs(x - 50) * 0.08
            line(&ctx, g, [(x - 1.6, y + 1.5), (x - 2.4, y - 2.5)], Pal.leaf, 0.9)
            line(&ctx, g, [(x, y + 1.5), (x + 0.4, y - 3.4)], Color(red: 0.48, green: 0.64, blue: 0.34), 0.9)
            line(&ctx, g, [(x + 1.6, y + 1.5), (x + 2.6, y - 2)], Pal.leaf, 0.9)
        }
        for (x, y, r) in [(left + 8, 90.0, 1.8), (right - 10, 91.0, 2.2), (right - 18, 93.0, 1.3)] {
            paint(&ctx, g, g.ellipse(x - r, y - r * 0.7, r * 2, r * 1.4), Pal.darkStone, line: 0.8)
        }
    }

    /// Hanging ivy: a curving stem with little leaves.
    static func ivy(_ ctx: inout GraphicsContext, _ g: EGrid, from a: (Double, Double), to b: (Double, Double), bend: Double) {
        let c = ((a.0 + b.0) / 2 + bend, (a.1 + b.1) / 2)
        curve(&ctx, g, a, c, b, Pal.leafDark, 1.1)
        for k in 1...4 {
            let t = Double(k) / 5
            let x = (1 - t) * (1 - t) * a.0 + 2 * (1 - t) * t * c.0 + t * t * b.0
            let y = (1 - t) * (1 - t) * a.1 + 2 * (1 - t) * t * c.1 + t * t * b.1
            let side = k.isMultiple(of: 2) ? 1.0 : -1.0
            paint(&ctx, g, g.ellipse(x + side * 0.6 - 1.6, y - 1.1, 3.2, 2.2), [Pal.leaf, Pal.leafDark], line: 0.5)
        }
    }

    /// Light motes drifting near a glow.
    static func motes(_ ctx: inout GraphicsContext, _ g: EGrid, _ points: [(Double, Double, Double)], _ color: Color) {
        var light = ctx
        light.blendMode = .plusLighter
        for (x, y, r) in points {
            light.fill(g.ellipse(x - r * 2.5, y - r * 2.5, r * 5, r * 5), with: .radialGradient(
                Gradient(colors: [color.opacity(0.6), color.opacity(0)]), center: g.p(x, y), startRadius: 0, endRadius: g.v(r * 2.5)))
            dot(&light, g, x, y, r * 0.6, .white.opacity(0.9))
        }
    }
}

// MARK: - Scenes

private extension EventArt {
    /// A forgotten shrine: stepped base, mossy fluted columns, a cracked lintel and a floating
    /// violet crystal spilling light over the stone.
    static func shrine(_ ctx: inout GraphicsContext, _ g: EGrid) {
        let violet = Color(red: 0.74, green: 0.56, blue: 1.0)
        glow(&ctx, g, 50, 46, 40, violet, 0.45)
        ground(&ctx, g, width: 88, shadowUnder: (50, 64))
        // Steps.
        paint(&ctx, g, g.rounded(16, 78, 68, 9, 1.5), Pal.darkStone)
        paint(&ctx, g, g.rounded(22, 70, 56, 9, 1.5), Pal.stone, from: (50, 70), to: (50, 79))
        line(&ctx, g, [(24, 71.5), (76, 71.5)], .white.opacity(0.35), 0.8)
        line(&ctx, g, [(40, 72), (37, 78)], ink.opacity(0.5), 0.7)
        // Glowing runes on the top step.
        for x in [34.0, 44.0, 56.0, 66.0] {
            line(&ctx, g, [(x - 1.6, 76), (x, 73), (x + 1.6, 76)], violet, 0.9)
        }
        // Columns with flutes and capitals.
        for x in [24.0, 66.0] {
            paint(&ctx, g, g.rect(x, 30, 10, 40).path(), Pal.stone, from: (x, 50), to: (x + 10, 50))
            for k in [2.5, 5.0, 7.5] { line(&ctx, g, [(x + k, 32), (x + k, 68)], ink.opacity(0.25), 0.6) }
            paint(&ctx, g, g.rounded(x - 2, 26, 14, 5, 1), Pal.stone)
            paint(&ctx, g, g.rounded(x - 2, 68, 14, 4, 1), Pal.darkStone)
        }
        // Lintel with a broken-off corner and a crack.
        paint(&ctx, g, g.poly([(18, 18), (78, 18), (84, 22), (82, 27), (18, 27)]), Pal.stone, from: (50, 18), to: (50, 27))
        line(&ctx, g, [(20, 19.5), (76, 19.5)], .white.opacity(0.35), 0.8)
        line(&ctx, g, [(52, 18), (50, 22), (53, 27)], ink.opacity(0.6), 0.8)
        // Moss and ivy.
        paint(&ctx, g, g.ellipse(22, 25, 14, 5), [Pal.leaf, Pal.leafDark], line: 0.8)
        paint(&ctx, g, g.ellipse(64, 60, 8, 6), [Pal.leaf, Pal.leafDark], line: 0.8)
        ivy(&ctx, g, from: (30, 27), to: (26, 52), bend: -5)
        ivy(&ctx, g, from: (70, 27), to: (74, 44), bend: 5)
        // Floating crystal, light beams falling onto the steps.
        var beam = ctx
        beam.blendMode = .plusLighter
        beam.fill(g.poly([(44, 50), (56, 50), (64, 72), (36, 72)]), with: .linearGradient(
            Gradient(colors: [violet.opacity(0.4), violet.opacity(0)]), startPoint: g.p(50, 50), endPoint: g.p(50, 72)))
        paint(&ctx, g, g.poly([(50, 32), (58, 44), (50, 58), (42, 44)]),
              [Color(red: 0.95, green: 0.88, blue: 1), violet, Color(red: 0.40, green: 0.24, blue: 0.70)], from: (46, 32), to: (54, 58), line: 1.2)
        line(&ctx, g, [(42, 44), (50, 46), (58, 44)], .white.opacity(0.5), 0.7)
        sparkle(&ctx, g, 48, 40, 3.5)
        motes(&ctx, g, [(38, 38, 0.9), (63, 46, 0.7), (45, 62, 0.6), (58, 34, 0.6)], violet)
    }

    /// A riddle chest: plank box and domed lid, iron bands with rivets, a gold lock and glowing
    /// runes, with golden light leaking from the seam.
    static func chest(_ ctx: inout GraphicsContext, _ g: EGrid) {
        let goldLight = Color(red: 1, green: 0.82, blue: 0.4)
        glow(&ctx, g, 50, 50, 38, goldLight, 0.35)
        ground(&ctx, g, width: 84, shadowUnder: (50, 66))
        // Box.
        paint(&ctx, g, g.rounded(18, 52, 64, 32, 2), Pal.wood, line: 1.8)
        for y in [62.0, 72.0] { line(&ctx, g, [(19, y), (81, y)], Pal.darkWood[1], 0.9) }
        // Domed lid.
        var lid = Path()
        lid.move(to: g.p(16, 53))
        lid.addLine(to: g.p(16, 42))
        lid.addQuadCurve(to: g.p(84, 42), control: g.p(50, 18))
        lid.addLine(to: g.p(84, 53))
        lid.closeSubpath()
        paint(&ctx, g, lid, Pal.darkWood, from: (50, 26), to: (50, 53), line: 1.8)
        for x in [32.0, 50.0, 68.0] { curve(&ctx, g, (x, 31 + abs(x - 50) * 0.18), (x, 42), (x, 53), Pal.darkWood[1].mixed(with: .black, 0.3), 0.8) }
        // Light leaking from the seam.
        var seam = ctx
        seam.blendMode = .plusLighter
        seam.stroke(Path(g.rect(17, 52.3, 66, 0.1)), with: .color(goldLight), lineWidth: g.v(1.6))
        glow(&ctx, g, 50, 53, 18, goldLight, 0.4)
        // Iron bands with rivets.
        for x in [26.0, 68.0] {
            paint(&ctx, g, g.rounded(x, 30, 6, 54, 1), Pal.iron, from: (x, 50), to: (x + 6, 50), line: 1.1)
            for y in [38.0, 58.0, 78.0] { dot(&ctx, g, x + 3, y, 0.9, Color(red: 0.85, green: 0.86, blue: 0.88)) }
        }
        // Gold lock plate with keyhole.
        paint(&ctx, g, g.rounded(43, 47, 14, 16, 2), Pal.gold, line: 1.3)
        dot(&ctx, g, 50, 53, 1.6, ink)
        paint(&ctx, g, g.poly([(49, 54), (51, 54), (51.6, 59), (48.4, 59)]), [ink, ink], line: 0)
        // Carved runes on the lid.
        for (x, y) in [(36.0, 36.0), (50.0, 32.0), (64.0, 36.0)] {
            line(&ctx, g, [(x - 2, y + 2.5), (x, y - 2.5), (x + 2, y + 2.5)], goldLight, 1)
            line(&ctx, g, [(x - 1.2, y + 0.8), (x + 1.2, y + 0.8)], goldLight, 0.8)
        }
        line(&ctx, g, [(20, 43), (34, 30)], .white.opacity(0.25), 1.2)
        // Spilled coins.
        for (x, y) in [(22.0, 88.0), (27.0, 90.0), (76.0, 89.0)] {
            paint(&ctx, g, g.ellipse(x - 2.4, y - 1.4, 4.8, 2.8), Pal.gold, line: 0.7)
        }
        sparkle(&ctx, g, 30, 24, 3)
        sparkle(&ctx, g, 72, 22, 3.5, goldLight)
    }

    /// A glowing spring in a ring of mossy rocks, with ripples, a rising light column, reeds
    /// and fireflies.
    static func spring(_ ctx: inout GraphicsContext, _ g: EGrid) {
        let aqua = Color(red: 0.40, green: 0.95, blue: 0.90)
        glow(&ctx, g, 50, 66, 40, aqua, 0.4)
        ground(&ctx, g, width: 90)
        // Back rocks.
        for (x, y, w, h) in [(14.0, 56.0, 22.0, 18.0), (32.0, 50.0, 22.0, 18.0), (52.0, 49.0, 22.0, 19.0), (68.0, 55.0, 20.0, 17.0)] {
            paint(&ctx, g, g.ellipse(x, y, w, h), Pal.stone, from: (x + w * 0.3, y), to: (x + w * 0.7, y + h))
            ctx.fill(g.ellipse(x + w * 0.22, y + h * 0.15, w * 0.35, h * 0.22), with: .color(.white.opacity(0.18)))
        }
        paint(&ctx, g, g.ellipse(34, 49, 12, 5), [Pal.leaf, Pal.leafDark], line: 0.7)
        // Water.
        let pool = g.ellipse(18, 62, 64, 22)
        paint(&ctx, g, pool, [Color(red: 0.70, green: 1, blue: 0.96), Color(red: 0.20, green: 0.70, blue: 0.74), Color(red: 0.08, green: 0.34, blue: 0.40)],
              from: (50, 62), to: (50, 84), line: 1.4)
        for (w, h, o) in [(40.0, 9.0, 0.6), (26.0, 5.5, 0.75), (12.0, 2.6, 0.9)] {
            ctx.stroke(g.ellipse(50 - w / 2, 72 - h / 2, w, h), with: .color(.white.opacity(o * 0.6)), lineWidth: g.v(0.8))
        }
        // Rising column of light and bubbles.
        var column = ctx
        column.blendMode = .plusLighter
        column.fill(g.poly([(42, 72), (58, 72), (54, 22), (46, 22)]), with: .linearGradient(
            Gradient(colors: [aqua.opacity(0.45), aqua.opacity(0)]), startPoint: g.p(50, 72), endPoint: g.p(50, 22)))
        for (x, y, r) in [(47.0, 58.0, 1.6), (53.0, 50.0, 2.0), (49.0, 40.0, 1.3), (52.0, 32.0, 1.0)] {
            ctx.stroke(g.ellipse(x - r, y - r, r * 2, r * 2), with: .color(.white.opacity(0.8)), lineWidth: g.v(0.7))
        }
        // Front stones.
        for (x, y, w, h) in [(10.0, 74.0, 16.0, 12.0), (72.0, 73.0, 18.0, 13.0), (40.0, 82.0, 10.0, 6.0)] {
            paint(&ctx, g, g.ellipse(x, y, w, h), Pal.darkStone, from: (x, y), to: (x + w, y + h))
        }
        // Reeds.
        for (x, lean) in [(14.0, -3.0), (17.0, 1.0), (84.0, 3.0), (81.0, -1.0)] {
            curve(&ctx, g, (x, 78), (x + lean * 0.5, 64), (x + lean, 52), Pal.leafDark, 1.2)
            paint(&ctx, g, g.rounded(x + lean - 1.1, 50, 2.2, 7, 1.1), Pal.darkWood, line: 0.6)
        }
        motes(&ctx, g, [(26, 40, 0.8), (72, 36, 0.9), (62, 26, 0.6), (34, 28, 0.6)], Color(red: 0.8, green: 1, blue: 0.6))
    }

    /// A ruined library: a broken wall with a moonlit arch, a bookcase of tilting books, rubble
    /// and a lectern with an open glowing book.
    static func library(_ ctx: inout GraphicsContext, _ g: EGrid) {
        let page = Color(red: 1, green: 0.86, blue: 0.5)
        ground(&ctx, g, width: 92)
        // Broken wall with a moonlit arched window.
        let wall = g.poly([(10, 86), (10, 22), (22, 14), (34, 20), (42, 12), (60, 18), (72, 10), (90, 20), (90, 86)])
        paint(&ctx, g, wall, Pal.darkStone, from: (50, 10), to: (50, 86), line: 1.6)
        ctx.drawLayer { layer in
            layer.clip(to: wall)
            for row in 0..<8 {
                let y = 20.0 + Double(row) * 8.5
                line(&layer, g, [(10, y), (90, y)], ink.opacity(0.25), 0.6)
                for k in 0..<6 {
                    let x = 12 + Double(k) * 16 + (row.isMultiple(of: 2) ? 0 : 8)
                    line(&layer, g, [(x, y), (x, y + 8.5)], ink.opacity(0.22), 0.6)
                }
            }
        }
        var arch = Path()
        arch.move(to: g.p(66, 46))
        arch.addLine(to: g.p(66, 30))
        arch.addQuadCurve(to: g.p(82, 30), control: g.p(74, 18))
        arch.addLine(to: g.p(82, 46))
        arch.closeSubpath()
        paint(&ctx, g, arch, [Color(red: 0.30, green: 0.38, blue: 0.58), Color(red: 0.12, green: 0.16, blue: 0.28)], line: 1.4)
        dot(&ctx, g, 77, 30, 3, Color(red: 0.95, green: 0.94, blue: 0.84))
        // Bookcase.
        paint(&ctx, g, g.rounded(16, 26, 44, 58, 1.5), Pal.darkWood, line: 1.6)
        let spines: [Color] = [Color(red: 0.62, green: 0.22, blue: 0.20), Color(red: 0.24, green: 0.40, blue: 0.58),
                               Color(red: 0.30, green: 0.46, blue: 0.28), Color(red: 0.58, green: 0.44, blue: 0.22), Color(red: 0.42, green: 0.30, blue: 0.52)]
        for row in 0..<3 {
            let shelfY = 42.0 + Double(row) * 15
            paint(&ctx, g, g.rect(17, shelfY, 42, 2.4).path(), Pal.wood, line: 0.7)
            var x = 19.0
            var k = row * 2
            while x < 55 {
                let w = 3.2 + Double((k * 7) % 3) * 0.6
                let h = 9.0 + Double((k * 5) % 4)
                let tilt = (k % 5 == 3) ? 2.5 : 0
                paint(&ctx, g, g.poly([(x + tilt, shelfY - h), (x + w + tilt, shelfY - h), (x + w, shelfY), (x, shelfY)]),
                      [spines[k % spines.count].mixed(with: .white, 0.15), spines[k % spines.count]], line: 0.6)
                line(&ctx, g, [(x + 0.6, shelfY - h + 2), (x + w - 0.6, shelfY - h + 2)], Pal.gold[1].opacity(0.8), 0.5)
                x += w + 0.6 + tilt
                k += 1
            }
        }
        // Cobweb in the corner.
        for k in 0..<3 { curve(&ctx, g, (17, 27 + Double(k) * 3), (19 + Double(k), 29 + Double(k)), (17 + Double(k) * 3, 27), .white.opacity(0.35), 0.4) }
        line(&ctx, g, [(17, 27), (25, 35)], .white.opacity(0.3), 0.4)
        // Rubble.
        for (x, y, w, h) in [(60.0, 80.0, 10.0, 7.0), (70.0, 83.0, 7.0, 5.0), (12.0, 82.0, 8.0, 5.0)] {
            paint(&ctx, g, g.poly([(x, y + h), (x + w * 0.2, y), (x + w * 0.8, y + h * 0.1), (x + w, y + h)]), Pal.stone, line: 0.9)
        }
        // Lectern and glowing book.
        glow(&ctx, g, 72, 58, 26, page, 0.55)
        paint(&ctx, g, g.poly([(69, 66), (75, 66), (77, 86), (67, 86)]), Pal.wood, line: 1.2)
        paint(&ctx, g, g.poly([(62, 64), (82, 64), (80, 68), (64, 68)]), Pal.darkWood, line: 1.2)
        var book = Path()
        book.move(to: g.p(62, 63))
        book.addQuadCurve(to: g.p(72, 62), control: g.p(66, 58))
        book.addQuadCurve(to: g.p(82, 63), control: g.p(78, 58))
        book.addLine(to: g.p(72, 65))
        book.closeSubpath()
        paint(&ctx, g, book, [Color(red: 1, green: 0.97, blue: 0.85), page], line: 1)
        line(&ctx, g, [(72, 62), (72, 65)], ink.opacity(0.4), 0.5)
        // Floating glowing letters.
        for (x, y) in [(68.0, 52.0), (75.0, 47.0), (71.0, 41.0)] {
            line(&ctx, g, [(x - 1.4, y + 1.4), (x, y - 1.4), (x + 1.4, y + 1.4)], page, 0.8)
        }
        motes(&ctx, g, [(64, 46, 0.7), (80, 52, 0.6)], page)
    }

    /// An overturned merchant cart: planks on their side, a wheel in the air, torn canvas,
    /// a spilled sack of coins, crates and potion bottles, and a lantern still burning.
    static func cart(_ ctx: inout GraphicsContext, _ g: EGrid) {
        let lamp = Color(red: 1, green: 0.78, blue: 0.4)
        ground(&ctx, g, width: 94, shadowUnder: (48, 70))
        // Torn canvas spilling out behind.
        var canvas = Path()
        canvas.move(to: g.p(20, 70))
        canvas.addQuadCurve(to: g.p(42, 30), control: g.p(16, 40))
        canvas.addLine(to: g.p(50, 40))
        canvas.addLine(to: g.p(46, 48))
        canvas.addLine(to: g.p(54, 56))
        canvas.addQuadCurve(to: g.p(40, 74), control: g.p(46, 70))
        canvas.closeSubpath()
        paint(&ctx, g, canvas, [Color(red: 0.90, green: 0.85, blue: 0.72), Color(red: 0.64, green: 0.57, blue: 0.44)], from: (30, 30), to: (40, 74))
        curve(&ctx, g, (24, 62), (30, 46), (42, 36), ink.opacity(0.25), 0.7)
        // Cart bed on its side.
        paint(&ctx, g, g.poly([(36, 84), (40, 46), (78, 40), (80, 80)]), Pal.wood, from: (40, 40), to: (76, 84), line: 1.8)
        for k in 1...3 {
            let t = Double(k) / 4
            line(&ctx, g, [(36 + 4 * t, 84 - 38 * t), (80 - 2 * t, 80 - 40 * t)], Pal.darkWood[1], 0.8)
        }
        paint(&ctx, g, g.poly([(40, 46), (78, 40), (79, 44), (40, 50)]), Pal.darkWood, line: 1)
        // Wheel up in the air, broken spoke.
        let center = (66.0, 32.0), radius = 15.0
        ctx.stroke(g.ellipse(center.0 - radius, center.1 - radius, radius * 2, radius * 2), with: .color(ink), lineWidth: g.v(4.6))
        ctx.stroke(g.ellipse(center.0 - radius, center.1 - radius, radius * 2, radius * 2), with: .color(Pal.iron[0]), lineWidth: g.v(2.4))
        ctx.stroke(g.ellipse(center.0 - radius + 2, center.1 - radius + 2, radius * 2 - 4, radius * 2 - 4), with: .color(Pal.wood[0]), lineWidth: g.v(1.6))
        for k in 0..<6 where k != 4 {
            let a = Double(k) / 6 * 2 * .pi + 0.3
            line(&ctx, g, [center, (center.0 + cos(a) * 12.5, center.1 + sin(a) * 12.5)], ink, 2.4)
            line(&ctx, g, [center, (center.0 + cos(a) * 12.5, center.1 + sin(a) * 12.5)], Pal.wood[0], 1.2)
        }
        paint(&ctx, g, g.ellipse(center.0 - 3.2, center.1 - 3.2, 6.4, 6.4), Pal.iron, line: 1)
        // Crate, sack, coins, bottles.
        paint(&ctx, g, g.rounded(10, 70, 16, 15, 1), Pal.wood, line: 1.4)
        line(&ctx, g, [(10, 70), (26, 85)], Pal.darkWood[1], 0.9)
        line(&ctx, g, [(26, 70), (10, 85)], Pal.darkWood[1], 0.9)
        var sack = Path()
        sack.move(to: g.p(80, 88))
        sack.addQuadCurve(to: g.p(84, 70), control: g.p(76, 76))
        sack.addLine(to: g.p(88, 68))
        sack.addQuadCurve(to: g.p(94, 88), control: g.p(98, 78))
        sack.closeSubpath()
        paint(&ctx, g, sack, [Color(red: 0.72, green: 0.60, blue: 0.40), Color(red: 0.48, green: 0.38, blue: 0.24)], line: 1.2)
        for (x, y) in [(70.0, 90.0), (74.0, 92.0), (66.0, 92.0), (77.0, 89.0)] {
            paint(&ctx, g, g.ellipse(x - 2, y - 1.2, 4, 2.4), Pal.gold, line: 0.6)
        }
        for (x, color) in [(30.0, Color(red: 0.80, green: 0.18, blue: 0.20)), (35.0, Color(red: 0.30, green: 0.55, blue: 0.95))] {
            paint(&ctx, g, g.ellipse(x - 2.6, 85, 5.2, 5.2), [color.mixed(with: .white, 0.3), color], line: 0.8)
            paint(&ctx, g, g.rect(x - 0.9, 82.5, 1.8, 3).path(), [Color(red: 0.7, green: 0.6, blue: 0.5), Color(red: 0.5, green: 0.4, blue: 0.3)], line: 0.5)
        }
        // Lantern still burning on the road.
        glow(&ctx, g, 52, 84, 16, lamp, 0.6)
        paint(&ctx, g, g.rounded(48.5, 79, 7, 9, 1.5), [Color(red: 1, green: 0.95, blue: 0.7), lamp], line: 1)
        paint(&ctx, g, g.rect(48, 77.5, 8, 2).path(), Pal.iron, line: 0.6)
        curve(&ctx, g, (49.5, 77.5), (52, 74), (54.5, 77.5), ink, 0.8)
    }

    /// The hooded stranger: a tall cloak with folds, a dark hood with glowing eyes, a staff whose
    /// orb lights the cloak's edge, and mist curling at the feet.
    static func stranger(_ ctx: inout GraphicsContext, _ g: EGrid) {
        let orb = Color(red: 0.55, green: 0.88, blue: 1.0)
        glow(&ctx, g, 74, 20, 30, orb, 0.5)
        ground(&ctx, g, width: 80, shadowUnder: (50, 46))
        // Cloak.
        var cloak = Path()
        cloak.move(to: g.p(36, 34))
        cloak.addQuadCurve(to: g.p(24, 88), control: g.p(28, 60))
        cloak.addLine(to: g.p(76, 88))
        cloak.addQuadCurve(to: g.p(64, 34), control: g.p(72, 60))
        cloak.closeSubpath()
        paint(&ctx, g, cloak, [Color(red: 0.34, green: 0.30, blue: 0.50), Color(red: 0.18, green: 0.15, blue: 0.30), Color(red: 0.10, green: 0.08, blue: 0.18)],
              from: (40, 34), to: (60, 88), line: 1.8)
        for (a, c, b) in [((42.0, 44.0), (38.0, 66.0), (34.0, 87.0)), ((50.0, 48.0), (51.0, 68.0), (49.0, 87.0)), ((58.0, 44.0), (62.0, 66.0), (65.0, 87.0))] {
            curve(&ctx, g, a, c, b, Color.black.opacity(0.35), 1.2)
        }
        // Rim light from the orb on the cloak's right edge.
        var rim = Path()
        rim.move(to: g.p(64, 36))
        rim.addQuadCurve(to: g.p(75, 86), control: g.p(71, 60))
        var lit = ctx
        lit.blendMode = .plusLighter
        lit.stroke(rim, with: .color(orb.opacity(0.6)), lineWidth: g.v(1.4))
        // Mantle + gold clasp.
        paint(&ctx, g, g.poly([(34, 38), (50, 50), (66, 38), (60, 30), (40, 30)]), [Color(red: 0.26, green: 0.22, blue: 0.40), Color(red: 0.14, green: 0.12, blue: 0.24)], line: 1.4)
        paint(&ctx, g, g.ellipse(47, 42.5, 6, 6), Pal.gold, line: 0.9)
        // Hood with deep shadow and glowing eyes.
        var hood = Path()
        hood.move(to: g.p(36, 36))
        hood.addQuadCurve(to: g.p(50, 8), control: g.p(34, 12))
        hood.addQuadCurve(to: g.p(64, 36), control: g.p(66, 12))
        hood.addQuadCurve(to: g.p(36, 36), control: g.p(50, 42))
        paint(&ctx, g, hood, [Color(red: 0.32, green: 0.28, blue: 0.48), Color(red: 0.16, green: 0.13, blue: 0.27)], line: 1.6)
        paint(&ctx, g, g.ellipse(41, 17, 18, 18), [Color(red: 0.05, green: 0.04, blue: 0.08), Color(red: 0.09, green: 0.07, blue: 0.12)], line: 0)
        for x in [45.5, 54.5] {
            glow(&ctx, g, x, 26, 3.4, orb, 0.9)
            ctx.fill(g.ellipse(x - 1.8, 25, 3.6, 2.2), with: .color(Color(red: 0.8, green: 0.97, blue: 1)))
        }
        // Hand on the staff; gnarled staff with glowing orb.
        line(&ctx, g, [(75, 22), (72, 89)], ink, 4.2)
        line(&ctx, g, [(75, 22), (72, 89)], Pal.wood[0], 2.4)
        paint(&ctx, g, g.ellipse(69, 52, 8, 6), [Color(red: 0.86, green: 0.74, blue: 0.62), Color(red: 0.62, green: 0.50, blue: 0.40)], line: 1)
        for (a, b) in [((75.0, 22.0), (70.0, 12.0)), ((75.0, 22.0), (81.0, 13.0))] {
            line(&ctx, g, [a, b], ink, 2.6)
            line(&ctx, g, [a, b], Pal.wood[0], 1.4)
        }
        paint(&ctx, g, g.ellipse(69.5, 9, 11, 11), [Color.white, orb, Color(red: 0.2, green: 0.5, blue: 0.8)], from: (72, 9), to: (78, 20), line: 1.1)
        sparkle(&ctx, g, 73, 12.5, 3)
        // Mist at the feet.
        var mist = ctx
        mist.blendMode = .plusLighter
        for (x, w) in [(30.0, 26.0), (52.0, 30.0), (40.0, 20.0)] {
            mist.fill(g.ellipse(x - w / 2, 82, w, 8), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.16), .clear]), center: g.p(x, 86), startRadius: 0, endRadius: g.v(w / 2)))
        }
        motes(&ctx, g, [(62, 6, 0.6), (86, 26, 0.7), (82, 6, 0.5)], orb)
    }

    /// A weathered crossroads signpost: grained post, three worn pointing planks, a crow on top,
    /// a hanging lantern and the road forking behind it.
    static func signpost(_ ctx: inout GraphicsContext, _ g: EGrid) {
        let lamp = Color(red: 1, green: 0.78, blue: 0.4)
        ground(&ctx, g, width: 94)
        // Forking dirt road.
        var road = Path()
        road.move(to: g.p(34, 96)); road.addQuadCurve(to: g.p(14, 82), control: g.p(22, 88))
        road.addLine(to: g.p(22, 81)); road.addQuadCurve(to: g.p(48, 90), control: g.p(36, 86))
        road.addQuadCurve(to: g.p(80, 81), control: g.p(66, 86)); road.addLine(to: g.p(88, 82))
        road.addQuadCurve(to: g.p(64, 96), control: g.p(76, 90))
        road.closeSubpath()
        paint(&ctx, g, road, [Color(red: 0.52, green: 0.40, blue: 0.27), Color(red: 0.36, green: 0.27, blue: 0.18)], from: (50, 81), to: (50, 96), line: 0)
        // Base stones and post.
        for (x, y, w, h) in [(38.0, 82.0, 12.0, 8.0), (52.0, 84.0, 11.0, 7.0)] {
            paint(&ctx, g, g.ellipse(x, y, w, h), Pal.stone, line: 0.9)
        }
        paint(&ctx, g, g.poly([(46, 86), (47, 14), (53, 14), (54, 86)]), Pal.darkWood, from: (46, 50), to: (54, 50), line: 1.6)
        for y in [30.0, 52.0, 70.0] { curve(&ctx, g, (48.5, y), (50, y + 4), (49, y + 9), Color.black.opacity(0.3), 0.6) }
        // Planks: left, right, and a crooked one.
        func plank(_ points: [(Double, Double)], _ arrow: [(Double, Double)]) {
            paint(&ctx, g, g.poly(points), Pal.wood, from: (50, points[0].1), to: (50, points[0].1 + 12), line: 1.4)
            line(&ctx, g, [points[0], points[1]].map { ($0.0, $0.1 + 1.6) }, .white.opacity(0.2), 0.6)
            line(&ctx, g, arrow, Color(red: 0.90, green: 0.86, blue: 0.74).opacity(0.55), 1.4)
        }
        plank([(16, 26), (52, 24), (52, 34), (16, 36), (10, 31)], [(18, 30.5), (44, 29)])
        plank([(48, 40), (82, 42), (90, 47.5), (82, 53), (48, 51)], [(54, 46), (80, 47.5)])
        plank([(20, 58), (52, 62), (51, 70), (19, 66), (14, 61)], [(22, 62), (40, 64.5)])
        for (x, y) in [(50.0, 29.0), (50.0, 46.0), (50.0, 64.0)] { dot(&ctx, g, x, y, 0.9, Color(red: 0.8, green: 0.8, blue: 0.82)) }
        // Crow on top.
        var crow = Path()
        crow.move(to: g.p(44, 14)); crow.addQuadCurve(to: g.p(52, 6), control: g.p(44, 6))
        crow.addLine(to: g.p(56, 5)); crow.addLine(to: g.p(54, 8))
        crow.addQuadCurve(to: g.p(58, 14), control: g.p(58, 10))
        crow.addLine(to: g.p(62, 18)); crow.addLine(to: g.p(54, 15))
        crow.closeSubpath()
        paint(&ctx, g, crow, [Color(red: 0.22, green: 0.22, blue: 0.28), Color(red: 0.08, green: 0.08, blue: 0.10)], line: 1)
        dot(&ctx, g, 52.5, 8, 0.6, Color(red: 1, green: 0.85, blue: 0.4))
        // Lantern hanging off the right plank.
        line(&ctx, g, [(76, 53), (76, 60)], Pal.iron[1], 0.9)
        glow(&ctx, g, 76, 65, 16, lamp, 0.6)
        paint(&ctx, g, g.rounded(72.5, 60, 7, 10, 1.5), [Color(red: 1, green: 0.95, blue: 0.7), lamp], line: 1)
        line(&ctx, g, [(74.8, 61), (74.8, 69)], ink.opacity(0.5), 0.5)
        line(&ctx, g, [(77.2, 61), (77.2, 69)], ink.opacity(0.5), 0.5)
        paint(&ctx, g, g.rect(72, 59, 8, 1.8).path(), Pal.iron, line: 0.6)
        motes(&ctx, g, [(68, 58, 0.5), (84, 70, 0.5)], lamp)
    }

    /// A fallen knight's resting place: an inscribed stele with glowing runes, a sword planted in
    /// the earth, a dented helm, a shield leaning on the stone, the pack, and a few flowers.
    static func fallenKnight(_ ctx: inout GraphicsContext, _ g: EGrid) {
        let rune = Color(red: 1, green: 0.84, blue: 0.45)
        glow(&ctx, g, 34, 48, 26, rune, 0.3)
        ground(&ctx, g, width: 90, shadowUnder: (44, 60))
        // Stele.
        var stele = Path()
        stele.move(to: g.p(20, 86))
        stele.addLine(to: g.p(21, 32))
        stele.addQuadCurve(to: g.p(47, 32), control: g.p(34, 18))
        stele.addLine(to: g.p(48, 86))
        stele.closeSubpath()
        paint(&ctx, g, stele, Pal.stone, from: (22, 30), to: (46, 86), line: 1.6)
        line(&ctx, g, [(23, 34), (26, 28)], .white.opacity(0.3), 0.9)
        line(&ctx, g, [(40, 26), (38, 34), (42, 40)], ink.opacity(0.5), 0.7)
        for (k, y) in [40.0, 47.0, 54.0, 61.0].enumerated() {
            line(&ctx, g, [(27, y), (k.isMultiple(of: 2) ? 41 : 38, y)], rune, 1.1)
        }
        glow(&ctx, g, 34, 50, 12, rune, 0.35)
        paint(&ctx, g, g.ellipse(18, 30, 12, 6), [Pal.leaf, Pal.leafDark], line: 0.7)
        ivy(&ctx, g, from: (24, 34), to: (22, 60), bend: -3)
        // Sword planted in the earth.
        paint(&ctx, g, g.poly([(73.5, 30), (77.5, 30), (77, 86), (74, 86)]), Pal.steel, from: (73, 50), to: (78, 50), line: 1.2)
        line(&ctx, g, [(75.5, 32), (75.5, 84)], .white.opacity(0.6), 0.6)
        paint(&ctx, g, g.rounded(66, 27, 19, 4, 1.5), Pal.gold, line: 1.1)
        paint(&ctx, g, g.rounded(73.6, 16, 4, 11, 1), [Color(red: 0.50, green: 0.30, blue: 0.18), Color(red: 0.30, green: 0.18, blue: 0.10)], line: 1)
        paint(&ctx, g, g.ellipse(73, 12, 5, 5), Pal.gold, line: 0.9)
        // Shield leaning on the stele, with a heraldic chevron.
        var shield = Path()
        shield.move(to: g.p(42, 54)); shield.addLine(to: g.p(64, 52))
        shield.addQuadCurve(to: g.p(56, 88), control: g.p(66, 78))
        shield.addQuadCurve(to: g.p(42, 54), control: g.p(42, 80))
        shield.closeSubpath()
        paint(&ctx, g, shield, [Color(red: 0.70, green: 0.20, blue: 0.20), Color(red: 0.42, green: 0.10, blue: 0.10)], from: (44, 52), to: (60, 88), line: 1.6)
        line(&ctx, g, [(45, 66), (53, 60), (61, 64)], Pal.gold[1], 2.2)
        ctx.stroke(shield, with: .color(Pal.gold[1].opacity(0.8)), lineWidth: g.v(0.9))
        // Dented helm resting at the base.
        var helm = Path()
        helm.move(to: g.p(60, 88)); helm.addQuadCurve(to: g.p(72, 74), control: g.p(60, 74))
        helm.addQuadCurve(to: g.p(84, 88), control: g.p(84, 74))
        helm.closeSubpath()
        paint(&ctx, g, helm, Pal.steel, from: (64, 74), to: (80, 88), line: 1.4)
        line(&ctx, g, [(63, 83), (81, 83)], ink, 1.4)
        line(&ctx, g, [(72, 76), (72, 82)], ink.opacity(0.6), 0.7)
        ctx.fill(g.ellipse(64, 76, 5, 3), with: .color(.white.opacity(0.35)))
        // Flowers.
        for (x, color) in [(16.0, Color(red: 0.95, green: 0.85, blue: 0.95)), (88.0, Color(red: 1, green: 0.9, blue: 0.5)), (52.0, Color(red: 0.95, green: 0.95, blue: 1))] {
            line(&ctx, g, [(x, 90), (x + 0.5, 85)], Pal.leafDark, 0.8)
            for k in 0..<5 {
                let a = Double(k) / 5 * 2 * .pi
                dot(&ctx, g, x + 0.5 + cos(a) * 1.4, 84 + sin(a) * 1.4, 0.9, color)
            }
            dot(&ctx, g, x + 0.5, 84, 0.6, Color(red: 0.95, green: 0.75, blue: 0.2))
        }
        motes(&ctx, g, [(30, 22, 0.6), (44, 36, 0.5), (24, 70, 0.5)], rune)
    }
}

private extension CGRect {
    func path() -> Path { Path(self) }
}
