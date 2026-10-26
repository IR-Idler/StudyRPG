import SwiftUI

// MARK: - Painted item art (game.md §17)
//
// Procedural "hand-drawn" art for every potion, relic and piece of gear that has no PNG yet:
// ink outlines like the hero/enemy art, shaded fills, a highlight and a glint. Drawn on a
// normalized 100×100 grid, so it reads from a 14pt HUD icon to a 90pt shop ware. Keyed by the
// item's `spriteId` (art, not behavior); an `item_<spriteId>` PNG in the asset catalog always
// wins (`SpriteView`, `GearArt`).

enum ItemArt {
    static let supported: Set<String> = [
        "health_potion", "strength_potion", "mana_potion",
        "iron_shield", "lucky_ring", "heart_amulet",
        "iron_sword", "executioner_axe", "oak_staff", "ember_wand",
        "chainmail", "padded_robe", "troll_hide",
        "mana_crystal", "healers_charm", "whetstone"
    ]

    static func canDraw(_ spriteId: String) -> Bool { supported.contains(spriteId.lowercased()) }

    /// Paints `spriteId` into the square that fits `rect`.
    static func draw(_ spriteId: String, in ctx: inout GraphicsContext, rect: CGRect) {
        let side = min(rect.width, rect.height)
        let g = ItemGrid(side: side, origin: CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2))
        switch spriteId.lowercased() {
        case "health_potion": roundFlask(&ctx, g, liquid: Color(red: 0.78, green: 0.13, blue: 0.16), emblem: .heart)
        case "strength_potion": coneFlask(&ctx, g)
        case "mana_potion": slimVial(&ctx, g)
        case "iron_shield": heaterShield(&ctx, g)
        case "lucky_ring": ring(&ctx, g)
        case "heart_amulet": amulet(&ctx, g)
        case "iron_sword": sword(&ctx, g)
        case "executioner_axe": axe(&ctx, g)
        case "oak_staff": staff(&ctx, g)
        case "ember_wand": wand(&ctx, g)
        case "chainmail": chainmail(&ctx, g)
        case "padded_robe": robe(&ctx, g)
        case "troll_hide": hide(&ctx, g)
        case "mana_crystal": crystal(&ctx, g)
        case "healers_charm": charm(&ctx, g)
        case "whetstone": whetstone(&ctx, g)
        default: break
        }
    }
}

/// A SwiftUI view of one painted item (used by `SpriteView` and `GearArt` as the fallback).
struct ItemArtView: View {
    let spriteId: String

    var body: some View {
        Canvas { ctx, size in
            ItemArt.draw(spriteId, in: &ctx, rect: CGRect(origin: .zero, size: size))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Drawing kit

/// Normalized 100×100 drawing grid (shared with the painted skill motifs, `SkillMotifs.swift`).
struct ItemGrid {
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

/// The shared painting kit: also used by the skill motifs (`SkillMotifs.swift`).
extension ItemArt {
    static let ink = Color(red: 0.11, green: 0.08, blue: 0.07)

    /// Fill with a top-to-bottom gradient, then ink outline.
    static func paint(_ ctx: inout GraphicsContext, _ g: ItemGrid, _ path: Path, _ colors: [Color],
                      from: (Double, Double) = (50, 0), to: (Double, Double) = (50, 100), line: Double = 2.2) {
        ctx.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: g.p(from.0, from.1), endPoint: g.p(to.0, to.1)))
        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: g.v(line), lineCap: .round, lineJoin: .round))
    }

    static func line(_ ctx: inout GraphicsContext, _ g: ItemGrid, _ points: [(Double, Double)], _ color: Color, width: Double) {
        var path = Path()
        guard let first = points.first else { return }
        path.move(to: g.p(first.0, first.1))
        for point in points.dropFirst() { path.addLine(to: g.p(point.0, point.1)) }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: g.v(width), lineCap: .round, lineJoin: .round))
    }

    /// Soft white highlight blob.
    static func shine(_ ctx: inout GraphicsContext, _ g: ItemGrid, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ opacity: Double = 0.45) {
        ctx.fill(g.ellipse(x, y, w, h), with: .color(.white.opacity(opacity)))
    }

    /// Four-pointed sparkle.
    static func glint(_ ctx: inout GraphicsContext, _ g: ItemGrid, _ x: Double, _ y: Double, _ r: Double) {
        let path = g.poly([(x, y - r), (x + r * 0.22, y - r * 0.22), (x + r, y), (x + r * 0.22, y + r * 0.22),
                           (x, y + r), (x - r * 0.22, y + r * 0.22), (x - r, y), (x - r * 0.22, y - r * 0.22)])
        ctx.fill(path, with: .color(.white.opacity(0.95)))
    }

    /// Soft colored glow behind magical things.
    static func aura(_ ctx: inout GraphicsContext, _ g: ItemGrid, _ x: Double, _ y: Double, _ r: Double, _ color: Color) {
        ctx.fill(g.ellipse(x - r, y - r, r * 2, r * 2), with: .radialGradient(
            Gradient(colors: [color.opacity(0.55), color.opacity(0)]), center: g.p(x, y), startRadius: 0, endRadius: g.v(r)))
    }

    static func heartPath(_ g: ItemGrid, cx: Double, cy: Double, size s: Double) -> Path {
        var path = Path()
        path.move(to: g.p(cx, cy + s * 0.55))
        path.addCurve(to: g.p(cx - s * 0.5, cy - s * 0.1), control1: g.p(cx - s * 0.15, cy + s * 0.35), control2: g.p(cx - s * 0.5, cy + s * 0.15))
        path.addCurve(to: g.p(cx, cy - s * 0.25), control1: g.p(cx - s * 0.5, cy - s * 0.45), control2: g.p(cx - s * 0.08, cy - s * 0.45))
        path.addCurve(to: g.p(cx + s * 0.5, cy - s * 0.1), control1: g.p(cx + s * 0.08, cy - s * 0.45), control2: g.p(cx + s * 0.5, cy - s * 0.45))
        path.addCurve(to: g.p(cx, cy + s * 0.55), control1: g.p(cx + s * 0.5, cy + s * 0.15), control2: g.p(cx + s * 0.15, cy + s * 0.35))
        path.closeSubpath()
        return path
    }

    static let gold = [Color(red: 1.0, green: 0.88, blue: 0.52), Color(red: 0.80, green: 0.60, blue: 0.22), Color(red: 0.55, green: 0.38, blue: 0.12)]
    static let steel = [Color(red: 0.90, green: 0.93, blue: 0.97), Color(red: 0.62, green: 0.67, blue: 0.75), Color(red: 0.38, green: 0.42, blue: 0.50)]
    static let wood = [Color(red: 0.62, green: 0.42, blue: 0.24), Color(red: 0.42, green: 0.27, blue: 0.14)]
    static let leather = [Color(red: 0.50, green: 0.30, blue: 0.18), Color(red: 0.32, green: 0.18, blue: 0.10)]
}

// MARK: - Potions

private extension ItemArt {
    enum FlaskEmblem { case heart }

    static func cork(_ ctx: inout GraphicsContext, _ g: ItemGrid, x: Double, y: Double, w: Double) {
        paint(&ctx, g, g.rounded(x, y, w, 10, 2.5), [Color(red: 0.72, green: 0.52, blue: 0.32), Color(red: 0.46, green: 0.31, blue: 0.18)])
        line(&ctx, g, [(x + 1, y + 10.5), (x + w - 1, y + 10.5)], Color(red: 0.75, green: 0.62, blue: 0.40), width: 2.2)
    }

    /// Round-bellied flask with liquid, bubbles and a little parchment label.
    static func roundFlask(_ ctx: inout GraphicsContext, _ g: ItemGrid, liquid: Color, emblem: FlaskEmblem) {
        let body = g.ellipse(22, 36, 56, 56)
        // Glass.
        ctx.fill(body, with: .color(Color(red: 0.85, green: 0.92, blue: 0.95).opacity(0.35)))
        ctx.fill(Path(g.rect(41, 20, 18, 20)), with: .color(Color(red: 0.85, green: 0.92, blue: 0.95).opacity(0.35)))
        // Liquid up to the shoulder, with a lighter meniscus.
        ctx.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(Path(g.rect(15, 50, 70, 50)), with: .linearGradient(
                Gradient(colors: [liquid.mixed(with: .white, 0.25), liquid, liquid.mixed(with: .black, 0.35)]),
                startPoint: g.p(50, 50), endPoint: g.p(50, 92)))
            layer.fill(g.ellipse(24, 47, 52, 7), with: .color(liquid.mixed(with: .white, 0.45)))
            for (x, y, r) in [(40.0, 70.0, 3.0), (58.0, 62.0, 2.0), (52.0, 80.0, 2.4), (64.0, 74.0, 1.5)] {
                layer.stroke(g.ellipse(x - r, y - r, r * 2, r * 2), with: .color(.white.opacity(0.6)), lineWidth: g.v(1))
            }
        }
        // Outline: neck + body as one silhouette.
        var outline = Path()
        outline.move(to: g.p(41, 21))
        outline.addLine(to: g.p(41, 37.5))
        outline.addArc(center: g.p(50, 64), radius: g.v(28), startAngle: .degrees(-109), endAngle: .degrees(-71 + 360), clockwise: false)
        outline.addLine(to: g.p(59, 21))
        ctx.stroke(outline, with: .color(ink), style: StrokeStyle(lineWidth: g.v(2.4), lineJoin: .round))
        // Label.
        paint(&ctx, g, g.rounded(39, 61, 22, 17, 2), [Palette.parchment, Palette.parchmentShade], line: 1.4)
        switch emblem {
        case .heart:
            ctx.fill(heartPath(g, cx: 50, cy: 69, size: 11), with: .color(liquid))
        }
        cork(&ctx, g, x: 39, y: 12, w: 22)
        shine(&ctx, g, 29, 46, 9, 22, 0.5)
        glint(&ctx, g, 33, 44, 4)
    }

    /// Conical flask of amber strength draught with a crossed-swords tag on a string.
    static func coneFlask(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let amber = Color(red: 0.93, green: 0.60, blue: 0.16)
        let cone = g.poly([(42, 22), (58, 22), (58, 40), (80, 86), (76, 91), (24, 91), (20, 86), (42, 40)])
        ctx.fill(cone, with: .color(Color(red: 0.85, green: 0.92, blue: 0.95).opacity(0.35)))
        ctx.drawLayer { layer in
            layer.clip(to: cone)
            layer.fill(Path(g.rect(10, 55, 80, 40)), with: .linearGradient(
                Gradient(colors: [amber.mixed(with: .white, 0.3), amber, amber.mixed(with: .black, 0.4)]),
                startPoint: g.p(50, 55), endPoint: g.p(50, 92)))
            layer.fill(g.ellipse(26, 52, 48, 6), with: .color(amber.mixed(with: .white, 0.5)))
            for (x, y, r) in [(44.0, 74.0, 2.6), (60.0, 80.0, 2.0), (52.0, 66.0, 1.6)] {
                layer.stroke(g.ellipse(x - r, y - r, r * 2, r * 2), with: .color(.white.opacity(0.6)), lineWidth: g.v(1))
            }
        }
        ctx.stroke(cone, with: .color(ink), style: StrokeStyle(lineWidth: g.v(2.4), lineJoin: .round))
        // Tag with crossed swords.
        line(&ctx, g, [(58, 30), (70, 34)], ink, width: 1.2)
        paint(&ctx, g, g.poly([(66, 30), (84, 34), (82, 48), (64, 44)]), [Palette.parchment, Palette.parchmentShade], line: 1.4)
        line(&ctx, g, [(68, 35), (79, 44)], Color(red: 0.45, green: 0.30, blue: 0.10), width: 1.8)
        line(&ctx, g, [(79, 36), (69, 44)], Color(red: 0.45, green: 0.30, blue: 0.10), width: 1.8)
        cork(&ctx, g, x: 40, y: 13, w: 20)
        shine(&ctx, g, 30, 64, 6, 20, 0.45)
        glint(&ctx, g, 34, 62, 3.5)
    }

    /// Slim glowing vial of mana with a wax seal.
    static func slimVial(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let blue = Color(red: 0.30, green: 0.52, blue: 0.98)
        aura(&ctx, g, 50, 62, 34, blue)
        let vial = g.rounded(37, 22, 26, 70, 13)
        ctx.fill(vial, with: .color(Color(red: 0.85, green: 0.92, blue: 0.95).opacity(0.35)))
        ctx.drawLayer { layer in
            layer.clip(to: vial)
            layer.fill(Path(g.rect(30, 40, 40, 55)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.70, green: 0.86, blue: 1), blue, Color(red: 0.16, green: 0.22, blue: 0.62)]),
                startPoint: g.p(50, 40), endPoint: g.p(50, 92)))
            layer.fill(g.ellipse(38, 38, 24, 5), with: .color(Color(red: 0.8, green: 0.9, blue: 1)))
        }
        ctx.stroke(vial, with: .color(ink), lineWidth: g.v(2.4))
        // Wax seal over the stopper.
        paint(&ctx, g, g.rounded(38, 12, 24, 13, 4), [Color(red: 0.55, green: 0.35, blue: 0.85), Color(red: 0.32, green: 0.18, blue: 0.55)])
        paint(&ctx, g, g.ellipse(44, 20, 12, 9), [Color(red: 0.62, green: 0.40, blue: 0.92), Color(red: 0.38, green: 0.22, blue: 0.62)], line: 1.4)
        glint(&ctx, g, 50, 64, 6)
        glint(&ctx, g, 45, 78, 2.6)
        shine(&ctx, g, 40, 30, 5, 26, 0.45)
    }
}

// MARK: - Relics

private extension ItemArt {
    static func heaterShield(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        var shield = Path()
        shield.move(to: g.p(20, 14))
        shield.addLine(to: g.p(80, 14))
        shield.addLine(to: g.p(80, 44))
        shield.addQuadCurve(to: g.p(50, 92), control: g.p(80, 76))
        shield.addQuadCurve(to: g.p(20, 44), control: g.p(20, 76))
        shield.closeSubpath()
        paint(&ctx, g, shield, gold, from: (20, 14), to: (80, 90), line: 2.6)
        // Steel face inset inside the gold rim.
        var face = Path()
        face.move(to: g.p(27, 20))
        face.addLine(to: g.p(73, 20))
        face.addLine(to: g.p(73, 44))
        face.addQuadCurve(to: g.p(50, 84), control: g.p(73, 71))
        face.addQuadCurve(to: g.p(27, 44), control: g.p(27, 71))
        face.closeSubpath()
        paint(&ctx, g, face, steel, from: (27, 20), to: (73, 84), line: 1.6)
        // Cross bands + boss.
        line(&ctx, g, [(50, 21), (50, 83)], Color(red: 0.32, green: 0.36, blue: 0.44), width: 3.2)
        line(&ctx, g, [(28, 42), (72, 42)], Color(red: 0.32, green: 0.36, blue: 0.44), width: 3.2)
        paint(&ctx, g, g.ellipse(42, 34, 16, 16), gold, line: 1.6)
        for (x, y) in [(31.0, 25.0), (69.0, 25.0), (34.0, 60.0), (66.0, 60.0)] {
            ctx.fill(g.ellipse(x - 1.8, y - 1.8, 3.6, 3.6), with: .color(Color(red: 0.95, green: 0.9, blue: 0.7)))
        }
        shine(&ctx, g, 31, 24, 10, 16, 0.35)
        glint(&ctx, g, 46, 38, 3.5)
    }

    static func ring(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        aura(&ctx, g, 50, 36, 22, Color(red: 0.3, green: 0.95, blue: 0.55))
        // Band in perspective: outer ellipse minus inner ellipse.
        var band = Path()
        band.addEllipse(in: g.rect(18, 40, 64, 46))
        band.addEllipse(in: g.rect(28, 50, 44, 28))
        ctx.fill(band, with: .linearGradient(Gradient(colors: gold), startPoint: g.p(18, 40), endPoint: g.p(82, 86)), style: FillStyle(eoFill: true))
        ctx.stroke(g.ellipse(18, 40, 64, 46), with: .color(ink), lineWidth: g.v(2.4))
        ctx.stroke(g.ellipse(28, 50, 44, 28), with: .color(ink), lineWidth: g.v(1.8))
        line(&ctx, g, [(24, 56), (30, 50)], .white.opacity(0.6), width: 2)
        // Setting + emerald.
        paint(&ctx, g, g.poly([(36, 42), (64, 42), (60, 50), (40, 50)]), gold, line: 1.8)
        let gem = g.poly([(50, 14), (66, 26), (60, 44), (40, 44), (34, 26)])
        paint(&ctx, g, gem, [Color(red: 0.55, green: 1.0, blue: 0.7), Color(red: 0.12, green: 0.62, blue: 0.36), Color(red: 0.05, green: 0.32, blue: 0.20)],
              from: (50, 14), to: (50, 44))
        line(&ctx, g, [(34, 26), (50, 30), (66, 26)], .white.opacity(0.45), width: 1.2)
        line(&ctx, g, [(50, 30), (50, 44)], .white.opacity(0.3), width: 1.2)
        glint(&ctx, g, 44, 22, 4.5)
    }

    static func amulet(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        // Chain: two strands of little links hanging down to the bail.
        for (sx, cx) in [(14.0, 22.0), (86.0, 78.0)] {
            for i in 0...8 {
                let t = Double(i) / 8
                let x = (1 - t) * (1 - t) * sx + 2 * (1 - t) * t * cx + t * t * 50
                let y = (1 - t) * (1 - t) * 6 + 2 * (1 - t) * t * 34 + t * t * 38
                paint(&ctx, g, g.ellipse(x - 2.6, y - 2, 5.2, 4), gold, line: 1)
            }
        }
        aura(&ctx, g, 50, 62, 30, Color(red: 1, green: 0.25, blue: 0.3))
        // Gold setting with a ruby heart.
        paint(&ctx, g, heartPath(g, cx: 50, cy: 64, size: 46), gold, from: (30, 45), to: (70, 90), line: 2.4)
        let ruby = heartPath(g, cx: 50, cy: 64, size: 34)
        paint(&ctx, g, ruby, [Color(red: 1, green: 0.5, blue: 0.5), Color(red: 0.82, green: 0.10, blue: 0.16), Color(red: 0.45, green: 0.03, blue: 0.08)],
              from: (40, 50), to: (60, 84), line: 1.6)
        paint(&ctx, g, g.ellipse(46, 38, 8, 8), gold, line: 1.4)
        shine(&ctx, g, 39, 55, 8, 6, 0.55)
        glint(&ctx, g, 42, 56, 4)
    }
}

// MARK: - Weapons

private extension ItemArt {
    /// A sword lying diagonally from bottom-left (pommel) to top-right (tip).
    static func sword(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        paint(&ctx, g, g.poly([(36, 58), (78, 16), (86, 14), (84, 22), (42, 64)]), steel, from: (40, 60), to: (84, 16))
        line(&ctx, g, [(41, 59), (80, 20)], Color(red: 0.45, green: 0.50, blue: 0.58), width: 1.4)
        line(&ctx, g, [(38, 57), (76, 19)], .white.opacity(0.7), width: 1)
        // Crossguard, grip with wraps, pommel.
        paint(&ctx, g, g.poly([(26, 54), (32, 48), (50, 66), (44, 72)]), gold, from: (26, 50), to: (50, 70))
        paint(&ctx, g, g.poly([(30, 64), (36, 70), (24, 82), (18, 76)]), leather, from: (30, 64), to: (20, 80))
        for t in [0.3, 0.55, 0.8] {
            let x = 33 - 12 * t, y = 67 + 12 * t
            line(&ctx, g, [(x - 3, y - 3), (x + 3, y + 3)], Color(red: 0.22, green: 0.12, blue: 0.06), width: 1.2)
        }
        paint(&ctx, g, g.ellipse(12, 78, 11, 11), gold, line: 1.8)
        glint(&ctx, g, 72, 26, 4)
    }

    static func axe(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        // Long haft, bottom-left to top-right, with leather wraps.
        paint(&ctx, g, g.poly([(16, 90), (22, 94), (66, 30), (60, 26)]), wood, from: (18, 92), to: (62, 28))
        for t in [0.12, 0.2, 0.28] {
            let x = 19 + 44 * t, y = 92 - 64 * t
            line(&ctx, g, [(x - 4, y - 2), (x + 3, y + 3)], Color(red: 0.25, green: 0.14, blue: 0.08), width: 1.6)
        }
        // Broad bearded blade fanning out to the right of the haft head.
        var blade = Path()
        blade.move(to: g.p(56, 22))
        blade.addLine(to: g.p(66, 32))
        blade.addLine(to: g.p(72, 50))
        blade.addQuadCurve(to: g.p(92, 30), control: g.p(90, 50))
        blade.addQuadCurve(to: g.p(78, 4), control: g.p(96, 12))
        blade.addLine(to: g.p(64, 18))
        blade.closeSubpath()
        paint(&ctx, g, blade, [Color(red: 0.78, green: 0.80, blue: 0.86), Color(red: 0.46, green: 0.49, blue: 0.56), Color(red: 0.26, green: 0.28, blue: 0.34)],
              from: (64, 8), to: (86, 48), line: 2.4)
        // Honed edge along the curve, a dark stain near the beard.
        var edge = Path()
        edge.move(to: g.p(73, 48))
        edge.addQuadCurve(to: g.p(90, 30), control: g.p(87, 47))
        edge.addQuadCurve(to: g.p(79, 7), control: g.p(93, 14))
        ctx.stroke(edge, with: .color(.white.opacity(0.8)), lineWidth: g.v(1.8))
        ctx.fill(g.ellipse(70, 34, 8, 6), with: .color(Color(red: 0.45, green: 0.08, blue: 0.08).opacity(0.5)))
        // Socket where blade meets haft, and a spike on the back.
        paint(&ctx, g, g.poly([(52, 20), (58, 14), (68, 26), (62, 32)]), steel, line: 1.8)
        paint(&ctx, g, g.poly([(54, 18), (44, 12), (50, 24)]), steel, line: 1.4)
        glint(&ctx, g, 84, 22, 4)
    }

    static func staff(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        aura(&ctx, g, 62, 22, 20, Color(red: 0.55, green: 1, blue: 0.6))
        // Gnarled shaft with a knot.
        var shaft = Path()
        shaft.move(to: g.p(26, 94))
        shaft.addCurve(to: g.p(60, 30), control1: g.p(40, 70), control2: g.p(50, 52))
        shaft.addLine(to: g.p(66, 33))
        shaft.addCurve(to: g.p(32, 96), control1: g.p(56, 56), control2: g.p(46, 74))
        shaft.closeSubpath()
        paint(&ctx, g, shaft, wood, from: (30, 94), to: (62, 30))
        paint(&ctx, g, g.ellipse(41, 58, 8, 6), [wood[1], wood[1].mixed(with: .black, 0.3)], line: 1.2)
        // Twig claws holding a green gem.
        for (a, b) in [((58.0, 32.0), (50.0, 14.0)), ((64.0, 32.0), (74.0, 12.0)), ((61.0, 30.0), (62.0, 8.0))] {
            line(&ctx, g, [a, b], ink, width: 4.2)
            line(&ctx, g, [a, b], wood[0], width: 2.4)
        }
        paint(&ctx, g, g.ellipse(53, 13, 18, 18), [Color(red: 0.8, green: 1, blue: 0.8), Color(red: 0.3, green: 0.78, blue: 0.42), Color(red: 0.1, green: 0.42, blue: 0.2)],
              from: (55, 13), to: (68, 30), line: 1.8)
        // A leaf.
        var leaf = Path()
        leaf.move(to: g.p(46, 60))
        leaf.addQuadCurve(to: g.p(30, 52), control: g.p(36, 62))
        leaf.addQuadCurve(to: g.p(46, 60), control: g.p(38, 48))
        paint(&ctx, g, leaf, [Color(red: 0.5, green: 0.75, blue: 0.35), Color(red: 0.25, green: 0.5, blue: 0.2)], line: 1.2)
        glint(&ctx, g, 59, 18, 3.5)
    }

    static func wand(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        aura(&ctx, g, 70, 28, 26, Color(red: 1, green: 0.45, blue: 0.1))
        paint(&ctx, g, g.poly([(22, 86), (28, 92), (70, 34), (64, 28)]), [Color(red: 0.30, green: 0.20, blue: 0.16), Color(red: 0.14, green: 0.09, blue: 0.08)],
              from: (24, 90), to: (66, 30))
        for t in [0.15, 0.62] {
            let x = 25 + 42 * t, y = 89 - 58 * t
            paint(&ctx, g, g.poly([(x - 5, y - 1), (x - 1, y - 5), (x + 4, y), (x, y + 4)]), gold, line: 1.2)
        }
        // Ember tip: flame tongues around a hot core.
        var flame = Path()
        flame.move(to: g.p(62, 34))
        flame.addQuadCurve(to: g.p(72, 6), control: g.p(58, 16))
        flame.addQuadCurve(to: g.p(80, 22), control: g.p(80, 12))
        flame.addQuadCurve(to: g.p(84, 18), control: g.p(83, 20))
        flame.addQuadCurve(to: g.p(70, 38), control: g.p(86, 34))
        flame.closeSubpath()
        paint(&ctx, g, flame, [Color(red: 1, green: 0.92, blue: 0.5), Color(red: 1, green: 0.52, blue: 0.12), Color(red: 0.78, green: 0.18, blue: 0.06)],
              from: (72, 6), to: (66, 38), line: 1.8)
        ctx.fill(g.ellipse(64, 22, 10, 12), with: .color(Color(red: 1, green: 0.97, blue: 0.8)))
        for (x, y) in [(56.0, 14.0), (86.0, 8.0), (88.0, 30.0)] {
            ctx.fill(g.ellipse(x - 1.4, y - 1.4, 2.8, 2.8), with: .color(Color(red: 1, green: 0.7, blue: 0.3)))
        }
    }
}

// MARK: - Armor

private extension ItemArt {
    /// A shirt silhouette shared by chainmail and robe.
    static func shirt(_ g: ItemGrid, hem: Double = 88) -> Path {
        g.poly([(36, 14), (44, 20), (56, 20), (64, 14), (84, 24), (90, 46), (76, 50), (72, 40), (72, hem),
                (28, hem), (28, 40), (24, 50), (10, 46), (16, 24)])
    }

    static func chainmail(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let shape = shirt(g)
        ctx.fill(shape, with: .linearGradient(Gradient(colors: steel), startPoint: g.p(30, 14), endPoint: g.p(70, 88)))
        // Interlocking rings.
        ctx.drawLayer { layer in
            layer.clip(to: shape)
            var y = 14.0
            var row = 0
            while y < 92 {
                var x = row.isMultiple(of: 2) ? 8.0 : 12.0
                while x < 94 {
                    layer.stroke(g.ellipse(x - 3.2, y - 2.6, 6.4, 5.2), with: .color(Color(red: 0.30, green: 0.34, blue: 0.42).opacity(0.7)), lineWidth: g.v(0.9))
                    x += 8
                }
                y += 5
                row += 1
            }
            layer.fill(Path(g.rect(0, 0, 100, 100)), with: .linearGradient(
                Gradient(colors: [.white.opacity(0.3), .clear, .black.opacity(0.2)]), startPoint: g.p(20, 14), endPoint: g.p(80, 90)))
        }
        ctx.stroke(shape, with: .color(ink), style: StrokeStyle(lineWidth: g.v(2.4), lineJoin: .round))
        // Leather collar and belt.
        paint(&ctx, g, g.poly([(36, 14), (44, 20), (56, 20), (64, 14), (60, 12), (40, 12)]), leather, line: 1.6)
        paint(&ctx, g, Path(g.rect(28, 62, 44, 7)), leather, line: 1.6)
        paint(&ctx, g, g.rounded(45, 61, 10, 9, 1.5), gold, line: 1.4)
        glint(&ctx, g, 38, 30, 3.5)
    }

    static func robe(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let cloth = [Color(red: 0.45, green: 0.38, blue: 0.72), Color(red: 0.28, green: 0.22, blue: 0.50)]
        let shape = g.poly([(36, 12), (44, 18), (56, 18), (64, 12), (84, 22), (92, 50), (78, 54), (72, 42), (78, 92),
                            (22, 92), (28, 42), (22, 54), (8, 50), (16, 22)])
        ctx.fill(shape, with: .linearGradient(Gradient(colors: cloth), startPoint: g.p(30, 12), endPoint: g.p(70, 92)))
        // Quilted diamond stitching.
        ctx.drawLayer { layer in
            layer.clip(to: shape)
            for k in stride(from: -100.0, through: 100.0, by: 10) {
                line(&layer, g, [(k, 0), (k + 100, 100)], Color.white.opacity(0.18), width: 0.8)
                line(&layer, g, [(k + 100, 0), (k, 100)], Color.white.opacity(0.18), width: 0.8)
            }
        }
        ctx.stroke(shape, with: .color(ink), style: StrokeStyle(lineWidth: g.v(2.4), lineJoin: .round))
        // Gold trim down the front and at the hem.
        line(&ctx, g, [(50, 19), (50, 91)], gold[1], width: 3)
        line(&ctx, g, [(23, 89), (77, 89)], gold[1], width: 3)
        paint(&ctx, g, g.poly([(36, 12), (44, 18), (56, 18), (64, 12), (60, 10), (40, 10)]), gold, line: 1.4)
        paint(&ctx, g, g.ellipse(46, 36, 8, 8), gold, line: 1.2)
        glint(&ctx, g, 47, 39, 2.5)
    }

    static func hide(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        // A pelt cloak hanging from a tied leather thong, with a soft lumpy hem.
        var pelt = Path()
        pelt.move(to: g.p(24, 22))
        pelt.addQuadCurve(to: g.p(76, 22), control: g.p(50, 16))
        pelt.addQuadCurve(to: g.p(86, 70), control: g.p(90, 44))
        pelt.addQuadCurve(to: g.p(72, 86), control: g.p(84, 84))
        pelt.addQuadCurve(to: g.p(58, 90), control: g.p(66, 84))
        pelt.addQuadCurve(to: g.p(42, 90), control: g.p(50, 96))
        pelt.addQuadCurve(to: g.p(28, 86), control: g.p(34, 84))
        pelt.addQuadCurve(to: g.p(14, 70), control: g.p(16, 84))
        pelt.addQuadCurve(to: g.p(24, 22), control: g.p(10, 44))
        pelt.closeSubpath()
        paint(&ctx, g, pelt, [Color(red: 0.56, green: 0.62, blue: 0.46), Color(red: 0.38, green: 0.44, blue: 0.32), Color(red: 0.24, green: 0.28, blue: 0.21)],
              from: (30, 18), to: (70, 92), line: 2.4)
        ctx.drawLayer { layer in
            layer.clip(to: pelt)
            // Warty troll-skin spots and a few fold shadows.
            for (x, y, w, h) in [(32.0, 38.0, 9.0, 6.0), (58.0, 46.0, 11.0, 7.0), (40.0, 64.0, 8.0, 5.0), (64.0, 70.0, 7.0, 5.0), (26.0, 56.0, 6.0, 4.0)] {
                layer.fill(g.ellipse(x, y, w, h), with: .color(Color(red: 0.22, green: 0.26, blue: 0.18).opacity(0.65)))
            }
            line(&layer, g, [(40, 26), (36, 88)], Color.black.opacity(0.18), width: 2.5)
            line(&layer, g, [(62, 26), (66, 88)], Color.black.opacity(0.18), width: 2.5)
            line(&layer, g, [(50, 24), (50, 92)], Color.white.opacity(0.10), width: 3)
        }
        // Fur collar.
        var collar = Path()
        collar.move(to: g.p(20, 24))
        for i in 0...12 {
            let x = 20 + Double(i) * 5
            collar.addLine(to: g.p(x, i.isMultiple(of: 2) ? 32 : 28))
        }
        collar.addLine(to: g.p(80, 22))
        collar.addQuadCurve(to: g.p(20, 22), control: g.p(50, 14))
        collar.closeSubpath()
        paint(&ctx, g, collar, [Color(red: 0.74, green: 0.68, blue: 0.54), Color(red: 0.52, green: 0.46, blue: 0.34)], line: 1.6)
        // Thong knot.
        line(&ctx, g, [(40, 18), (60, 18)], ink, width: 3.4)
        line(&ctx, g, [(40, 18), (60, 18)], leather[0], width: 1.8)
        paint(&ctx, g, g.ellipse(46, 14, 8, 8), leather, line: 1.4)
        line(&ctx, g, [(48, 21), (44, 30)], leather[1], width: 1.8)
        line(&ctx, g, [(52, 21), (56, 30)], leather[1], width: 1.8)
    }
}

// MARK: - Trinkets

private extension ItemArt {
    static func crystal(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        aura(&ctx, g, 50, 44, 34, Color(red: 0.35, green: 0.55, blue: 1))
        let gem = g.poly([(50, 6), (70, 34), (62, 76), (50, 84), (38, 76), (30, 34)])
        paint(&ctx, g, gem, [Color(red: 0.75, green: 0.88, blue: 1), Color(red: 0.36, green: 0.52, blue: 0.96), Color(red: 0.16, green: 0.22, blue: 0.60)],
              from: (50, 6), to: (50, 84))
        line(&ctx, g, [(50, 6), (50, 84)], .white.opacity(0.35), width: 1.2)
        line(&ctx, g, [(30, 34), (50, 44), (70, 34)], .white.opacity(0.35), width: 1.2)
        line(&ctx, g, [(38, 76), (50, 44), (62, 76)], Color(red: 0.1, green: 0.15, blue: 0.45).opacity(0.4), width: 1.2)
        // Silver claw setting at the base.
        paint(&ctx, g, g.poly([(36, 76), (64, 76), (60, 94), (40, 94)]), steel, line: 1.8)
        line(&ctx, g, [(38, 78), (34, 68)], ink, width: 2.6)
        line(&ctx, g, [(62, 78), (66, 68)], ink, width: 2.6)
        glint(&ctx, g, 44, 26, 5)
        glint(&ctx, g, 58, 58, 2.5)
    }

    static func charm(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        // Cord loop.
        var cord = Path()
        cord.move(to: g.p(38, 30))
        cord.addQuadCurve(to: g.p(62, 30), control: g.p(50, -4))
        ctx.stroke(cord, with: .color(ink), lineWidth: g.v(3.6))
        ctx.stroke(cord, with: .color(Color(red: 0.70, green: 0.55, blue: 0.35)), lineWidth: g.v(2))
        aura(&ctx, g, 50, 60, 30, Color(red: 0.4, green: 0.95, blue: 0.5))
        // Carved wooden disc in a gold rim, green cross of leaves.
        paint(&ctx, g, g.ellipse(22, 30, 56, 56), gold, line: 2.4)
        paint(&ctx, g, g.ellipse(28, 36, 44, 44), [Color(red: 0.70, green: 0.50, blue: 0.30), Color(red: 0.48, green: 0.32, blue: 0.18)], line: 1.4)
        let cross = g.poly([(45, 44), (55, 44), (55, 53), (64, 53), (64, 63), (55, 63), (55, 72), (45, 72), (45, 63), (36, 63), (36, 53), (45, 53)])
        paint(&ctx, g, cross, [Color(red: 0.55, green: 0.92, blue: 0.55), Color(red: 0.20, green: 0.58, blue: 0.28)], from: (50, 44), to: (50, 72), line: 1.6)
        shine(&ctx, g, 32, 40, 10, 7, 0.35)
        glint(&ctx, g, 48, 48, 3)
    }

    static func whetstone(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let stone = g.poly([(12, 62), (66, 28), (88, 40), (34, 76)])
        paint(&ctx, g, stone, [Color(red: 0.70, green: 0.70, blue: 0.68), Color(red: 0.48, green: 0.48, blue: 0.47)], from: (40, 28), to: (60, 76))
        // Side face for depth.
        paint(&ctx, g, g.poly([(12, 62), (34, 76), (34, 84), (12, 70)]), [Color(red: 0.42, green: 0.42, blue: 0.42), Color(red: 0.30, green: 0.30, blue: 0.30)])
        paint(&ctx, g, g.poly([(34, 76), (88, 40), (88, 48), (34, 84)]), [Color(red: 0.36, green: 0.36, blue: 0.36), Color(red: 0.26, green: 0.26, blue: 0.26)])
        // Grain and a bright sharpening streak.
        for k in [0.3, 0.5, 0.7] {
            line(&ctx, g, [(12 + 54 * k - 6, 62 - 34 * k + 4), (34 + 54 * k - 6, 76 - 36 * k + 4)], Color.black.opacity(0.18), width: 0.8)
        }
        line(&ctx, g, [(30, 56), (70, 38)], .white.opacity(0.75), width: 2)
        // Sparks flying off the streak.
        for (x, y) in [(72.0, 30.0), (78.0, 24.0), (66.0, 22.0), (82.0, 32.0)] {
            line(&ctx, g, [(x - 2, y + 2), (x + 2, y - 2)], Color(red: 1, green: 0.82, blue: 0.4), width: 1.4)
        }
        glint(&ctx, g, 70, 36, 4.5)
    }
}
