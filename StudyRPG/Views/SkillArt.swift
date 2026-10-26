import SwiftUI

// MARK: - Painted skill emblems (game.md §5 "Skill art")
//
// Every skill is shown as a small painted tile: a gilded frame, a background painted in the
// skill's element (flames, frost shards, a rune circle, …) and, on top, the skill's painted
// motif (`art`, `SkillMotifs.swift`) — or its SF Symbol `icon` embossed with a gradient and a
// glow when it has none. Entirely data-driven — element and motif come from classes.json
// (`element` is derived from the effects when missing) — so new skills always get art.
// A `skill_<skillId>` PNG in the asset catalog replaces the painting automatically.

struct SkillIcon: View {
    let skill: SkillDef
    var size: CGFloat = 40

    var body: some View {
        if let art = ArtCache.thumbnail("skill_\(skill.id)", height: size) {
            Image(platformImage: art)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay(SkillFrame(size: size))
        } else {
            SkillEmblem(element: skill.artElement, symbol: skill.icon, motif: skill.art, size: size)
        }
    }
}

/// The procedural painting: element background + painted motif (or embossed glyph) + gilded
/// frame. Static; rendered once into a single layer.
struct SkillEmblem: View {
    let element: SkillElement
    let symbol: String
    var motif: String? = nil
    var size: CGFloat = 40

    var body: some View {
        let style = element.style
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            Canvas { ctx, canvasSize in
                SkillBackdropPainter(element: element, size: canvasSize, detailed: size >= 30).paint(&ctx)
            }
            .clipShape(shape)

            if let motif, SkillMotif.canDraw(motif) {
                Canvas { ctx, canvasSize in
                    SkillMotif.draw(motif, in: &ctx, rect: CGRect(origin: .zero, size: canvasSize))
                }
                .padding(size * 0.12)
                // A soft drop so the object sits above the backdrop, then the element's glow.
                .shadow(color: .black.opacity(0.6), radius: max(0.5, size * 0.015), y: size * 0.025)
                .shadow(color: style.glow.opacity(0.45), radius: size * 0.06)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [style.glyphTop, style.glyphBottom], startPoint: .top, endPoint: .bottom))
                    // Engraved: a dark drop below, then the element's glow around it.
                    .shadow(color: .black.opacity(0.75), radius: max(0.5, size * 0.015), y: size * 0.03)
                    .shadow(color: style.glow.opacity(0.8), radius: size * 0.1)
            }

            // Glossy top highlight.
            shape
                .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)

            SkillFrame(size: size)
        }
        .frame(width: size, height: size)
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// Gilded bevel: ink outline, gold gradient ring, dark inner hairline.
struct SkillFrame: View {
    let size: CGFloat

    var body: some View {
        let radius = size * 0.22
        let ring = max(1.5, size * 0.065)
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Palette.goldGlow, Palette.gold, Color(red: 0.45, green: 0.32, blue: 0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: ring
                )
            RoundedRectangle(cornerRadius: max(0, radius - ring), style: .continuous)
                .strokeBorder(Color.black.opacity(0.55), lineWidth: max(0.5, size * 0.015))
                .padding(ring)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.ink, lineWidth: max(0.5, size * 0.02))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Element styles

extension SkillElement {
    struct Style {
        /// Background: dark rim → lit center.
        let deep: Color
        let lit: Color
        /// Pattern strokes/fills painted over the background.
        let accent: Color
        let glyphTop: Color
        let glyphBottom: Color
        let glow: Color
    }

    var style: Style {
        switch self {
        case .steel:
            return Style(deep: Color(red: 0.10, green: 0.12, blue: 0.17), lit: Color(red: 0.36, green: 0.42, blue: 0.52),
                         accent: Color(red: 0.80, green: 0.86, blue: 0.95), glyphTop: .white, glyphBottom: Color(red: 0.70, green: 0.76, blue: 0.86),
                         glow: Color(red: 0.6, green: 0.75, blue: 1.0))
        case .fire:
            return Style(deep: Color(red: 0.22, green: 0.04, blue: 0.03), lit: Color(red: 0.72, green: 0.22, blue: 0.06),
                         accent: Color(red: 1.0, green: 0.62, blue: 0.18), glyphTop: Color(red: 1, green: 0.97, blue: 0.75), glyphBottom: Color(red: 1.0, green: 0.62, blue: 0.16),
                         glow: Color(red: 1.0, green: 0.45, blue: 0.1))
        case .frost:
            return Style(deep: Color(red: 0.04, green: 0.10, blue: 0.22), lit: Color(red: 0.22, green: 0.48, blue: 0.70),
                         accent: Color(red: 0.75, green: 0.92, blue: 1.0), glyphTop: .white, glyphBottom: Color(red: 0.62, green: 0.86, blue: 1.0),
                         glow: Color(red: 0.5, green: 0.85, blue: 1.0))
        case .lightning:
            return Style(deep: Color(red: 0.08, green: 0.06, blue: 0.24), lit: Color(red: 0.32, green: 0.30, blue: 0.72),
                         accent: Color(red: 0.95, green: 0.92, blue: 0.55), glyphTop: Color(red: 1, green: 1, blue: 0.85), glyphBottom: Color(red: 1.0, green: 0.85, blue: 0.30),
                         glow: Color(red: 0.75, green: 0.75, blue: 1.0))
        case .arcane:
            return Style(deep: Color(red: 0.12, green: 0.05, blue: 0.22), lit: Color(red: 0.45, green: 0.25, blue: 0.72),
                         accent: Color(red: 0.85, green: 0.72, blue: 1.0), glyphTop: .white, glyphBottom: Color(red: 0.82, green: 0.70, blue: 1.0),
                         glow: Color(red: 0.75, green: 0.5, blue: 1.0))
        case .nature:
            return Style(deep: Color(red: 0.04, green: 0.16, blue: 0.08), lit: Color(red: 0.25, green: 0.55, blue: 0.28),
                         accent: Color(red: 0.75, green: 0.95, blue: 0.62), glyphTop: .white, glyphBottom: Color(red: 0.62, green: 0.92, blue: 0.55),
                         glow: Color(red: 0.5, green: 1.0, blue: 0.55))
        case .guard:
            return Style(deep: Color(red: 0.08, green: 0.11, blue: 0.16), lit: Color(red: 0.38, green: 0.47, blue: 0.58),
                         accent: Color(red: 0.70, green: 0.80, blue: 0.92), glyphTop: .white, glyphBottom: Color(red: 0.80, green: 0.86, blue: 0.94),
                         glow: Color(red: 0.85, green: 0.92, blue: 1.0))
        case .war:
            return Style(deep: Color(red: 0.20, green: 0.08, blue: 0.04), lit: Color(red: 0.62, green: 0.36, blue: 0.10),
                         accent: Color(red: 1.0, green: 0.82, blue: 0.40), glyphTop: Color(red: 1, green: 0.96, blue: 0.80), glyphBottom: Color(red: 1.0, green: 0.78, blue: 0.30),
                         glow: Color(red: 1.0, green: 0.75, blue: 0.3))
        case .shadow:
            return Style(deep: Color(red: 0.04, green: 0.02, blue: 0.08), lit: Color(red: 0.28, green: 0.14, blue: 0.40),
                         accent: Color(red: 0.62, green: 0.42, blue: 0.85), glyphTop: Color(red: 0.92, green: 0.86, blue: 1), glyphBottom: Color(red: 0.70, green: 0.52, blue: 0.95),
                         glow: Color(red: 0.6, green: 0.3, blue: 0.95))
        case .earth:
            return Style(deep: Color(red: 0.14, green: 0.09, blue: 0.05), lit: Color(red: 0.50, green: 0.36, blue: 0.20),
                         accent: Color(red: 0.88, green: 0.70, blue: 0.42), glyphTop: Color(red: 1, green: 0.94, blue: 0.80), glyphBottom: Color(red: 0.90, green: 0.70, blue: 0.40),
                         glow: Color(red: 1.0, green: 0.7, blue: 0.35))
        case .mana:
            return Style(deep: Color(red: 0.03, green: 0.07, blue: 0.22), lit: Color(red: 0.18, green: 0.36, blue: 0.82),
                         accent: Color(red: 0.62, green: 0.80, blue: 1.0), glyphTop: .white, glyphBottom: Color(red: 0.55, green: 0.74, blue: 1.0),
                         glow: Color(red: 0.42, green: 0.64, blue: 0.97))
        }
    }
}

// MARK: - Background painter

/// Paints an element's backdrop on a 100×100 grid. `detailed` adds the finer pattern work that
/// would only be noise below ~30pt.
private struct SkillBackdropPainter {
    let element: SkillElement
    let size: CGSize
    let detailed: Bool

    private var s: CGFloat { min(size.width, size.height) / 100 }
    private func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x) * s, y: CGFloat(y) * s) }
    private func v(_ length: Double) -> CGFloat { CGFloat(length) * s }

    func paint(_ ctx: inout GraphicsContext) {
        let style = element.style
        let all = Path(CGRect(origin: .zero, size: size))
        ctx.fill(all, with: .radialGradient(Gradient(colors: [style.lit, style.deep]),
                                             center: p(50, 46), startRadius: 0, endRadius: v(72)))
        var art = ctx
        art.blendMode = .plusLighter
        switch element {
        case .steel: steel(&art, style)
        case .fire: fire(&art, style)
        case .frost: frost(&art, style)
        case .lightning: lightning(&art, style)
        case .arcane: arcane(&art, style)
        case .nature: nature(&art, style)
        case .guard: guardPattern(&art, style)
        case .war: war(&art, style)
        case .shadow: shadow(&ctx, style)
        case .earth: earth(&art, style)
        case .mana: mana(&art, style)
        }
        // Vignette so the glyph always sits in the light.
        ctx.fill(all, with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.45)]),
                                             center: p(50, 50), startRadius: v(30), endRadius: v(78)))
    }

    private func stroke(_ ctx: inout GraphicsContext, _ points: [(Double, Double)], _ color: Color, _ width: Double) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: p(first.0, first.1))
        for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: v(width), lineCap: .round, lineJoin: .round))
    }

    private func dot(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p(x, y).x - v(r), y: p(x, y).y - v(r), width: v(r * 2), height: v(r * 2))), with: .color(color))
    }

    private func steel(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        // A bright diagonal sheen and two faint crossing slash marks.
        var band = Path()
        band.move(to: p(-10, 70)); band.addLine(to: p(70, -10)); band.addLine(to: p(92, -10)); band.addLine(to: p(-10, 92))
        band.closeSubpath()
        ctx.fill(band, with: .linearGradient(Gradient(colors: [.clear, style.accent.opacity(0.22), .clear]),
                                             startPoint: p(20, 40), endPoint: p(45, 65)))
        if detailed {
            var a = Path(); a.addArc(center: p(30, 80), radius: v(70), startAngle: .degrees(-80), endAngle: .degrees(-20), clockwise: false)
            var b = Path(); b.addArc(center: p(70, 80), radius: v(70), startAngle: .degrees(-160), endAngle: .degrees(-100), clockwise: false)
            ctx.stroke(a, with: .color(style.accent.opacity(0.25)), lineWidth: v(2))
            ctx.stroke(b, with: .color(style.accent.opacity(0.25)), lineWidth: v(2))
        }
    }

    private func fire(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        for (x, h, w) in [(18.0, 42.0, 16.0), (38.0, 58.0, 20.0), (60.0, 50.0, 18.0), (82.0, 40.0, 16.0), (50.0, 34.0, 12.0)] {
            var tongue = Path()
            tongue.move(to: p(x - w, 104))
            tongue.addQuadCurve(to: p(x + 3, 100 - h), control: p(x - w * 0.9, 100 - h * 0.45))
            tongue.addQuadCurve(to: p(x + w, 104), control: p(x + w * 0.7, 100 - h * 0.4))
            tongue.closeSubpath()
            ctx.fill(tongue, with: .linearGradient(Gradient(colors: [style.accent.opacity(0.65), Color.red.opacity(0.25), .clear]),
                                                   startPoint: p(x, 104), endPoint: p(x, 100 - h)))
        }
        if detailed {
            for (x, y, r) in [(22.0, 30.0, 1.4), (74.0, 22.0, 1.8), (64.0, 40.0, 1.0), (30.0, 52.0, 1.2), (84.0, 56.0, 1.0)] {
                dot(&ctx, x, y, r, style.accent.opacity(0.9))
            }
        }
    }

    private func frost(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        // Ice shards radiating from the center, plus a few flakes.
        for i in 0..<6 {
            let angle = Double(i) / 6 * 2 * .pi + 0.26
            var shard = Path()
            shard.move(to: p(50 + cos(angle - 0.12) * 18, 50 + sin(angle - 0.12) * 18))
            shard.addLine(to: p(50 + cos(angle) * 62, 50 + sin(angle) * 62))
            shard.addLine(to: p(50 + cos(angle + 0.12) * 18, 50 + sin(angle + 0.12) * 18))
            shard.closeSubpath()
            ctx.fill(shard, with: .linearGradient(Gradient(colors: [style.accent.opacity(0.05), style.accent.opacity(0.35)]),
                                                  startPoint: p(50, 50), endPoint: p(50 + cos(angle) * 62, 50 + sin(angle) * 62)))
        }
        if detailed {
            for (x, y) in [(16.0, 18.0), (84.0, 26.0), (22.0, 82.0), (80.0, 80.0)] {
                stroke(&ctx, [(x - 4, y), (x + 4, y)], style.accent.opacity(0.6), 1)
                stroke(&ctx, [(x - 2, y - 3.5), (x + 2, y + 3.5)], style.accent.opacity(0.6), 1)
                stroke(&ctx, [(x + 2, y - 3.5), (x - 2, y + 3.5)], style.accent.opacity(0.6), 1)
            }
        }
    }

    private func lightning(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        stroke(&ctx, [(14, -4), (30, 30), (20, 36), (40, 74), (34, 78), (46, 104)], style.accent.opacity(0.45), 3)
        stroke(&ctx, [(86, -4), (72, 24), (82, 30), (64, 62), (70, 66), (58, 104)], style.accent.opacity(0.35), 2.4)
        if detailed {
            stroke(&ctx, [(30, 30), (10, 44)], style.accent.opacity(0.3), 1.4)
            stroke(&ctx, [(64, 62), (90, 76)], style.accent.opacity(0.3), 1.4)
        }
    }

    private func arcane(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        let ring = style.accent.opacity(0.35)
        ctx.stroke(Path(ellipseIn: CGRect(x: v(12), y: v(12), width: v(76), height: v(76))), with: .color(ring), lineWidth: v(1.6))
        ctx.stroke(Path(ellipseIn: CGRect(x: v(20), y: v(20), width: v(60), height: v(60))), with: .color(ring), lineWidth: v(1))
        if detailed {
            for i in 0..<12 {
                let angle = Double(i) / 12 * 2 * .pi
                stroke(&ctx, [(50 + cos(angle) * 30, 50 + sin(angle) * 30), (50 + cos(angle) * 38, 50 + sin(angle) * 38)], ring, 1.6)
            }
            for (x, y, r) in [(18.0, 16.0, 1.2), (86.0, 20.0, 1.6), (12.0, 70.0, 1.0), (88.0, 84.0, 1.2)] {
                dot(&ctx, x, y, r, style.accent.opacity(0.85))
            }
        }
    }

    private func nature(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        // Soft rays falling from the top left, motes of light.
        for (i, width) in [12.0, 8.0, 14.0].enumerated() {
            let x = 10 + Double(i) * 26
            var ray = Path()
            ray.move(to: p(x, -5)); ray.addLine(to: p(x + width, -5)); ray.addLine(to: p(x + width + 30, 105)); ray.addLine(to: p(x + 30, 105))
            ray.closeSubpath()
            ctx.fill(ray, with: .linearGradient(Gradient(colors: [style.accent.opacity(0.28), .clear]), startPoint: p(x, 0), endPoint: p(x + 30, 100)))
        }
        if detailed {
            for (x, y, r) in [(20.0, 76.0, 1.6), (78.0, 70.0, 2.0), (66.0, 22.0, 1.2), (30.0, 34.0, 1.0), (86.0, 46.0, 1.2)] {
                dot(&ctx, x, y, r, style.accent.opacity(0.8))
            }
        }
    }

    private func guardPattern(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        // Faint riveted plate lattice.
        guard detailed else { return }
        let color = style.accent.opacity(0.18)
        var y = 0.0, row = 0
        while y <= 100 {
            var x = row.isMultiple(of: 2) ? 0.0 : 12.5
            while x <= 100 {
                let hex = (0..<6).map { k -> (Double, Double) in
                    let a = Double(k) / 6 * 2 * .pi + .pi / 6
                    return (x + cos(a) * 12, y + sin(a) * 12)
                }
                stroke(&ctx, hex + [hex[0]], color, 1)
                x += 25
            }
            y += 21
            row += 1
        }
    }

    private func war(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi
            var ray = Path()
            ray.move(to: p(50, 50))
            ray.addLine(to: p(50 + cos(a - 0.11) * 80, 50 + sin(a - 0.11) * 80))
            ray.addLine(to: p(50 + cos(a + 0.11) * 80, 50 + sin(a + 0.11) * 80))
            ray.closeSubpath()
            ctx.fill(ray, with: .color(style.accent.opacity(i.isMultiple(of: 2) ? 0.16 : 0.08)))
        }
    }

    private func shadow(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        // Curling wisps of dark mist (normal blend, darker than the background).
        for (cx, cy, r, from, to) in [(30.0, 70.0, 36.0, -80.0, 40.0), (74.0, 34.0, 30.0, 100.0, 220.0), (60.0, 80.0, 22.0, 180.0, 300.0)] {
            var arc = Path()
            arc.addArc(center: p(cx, cy), radius: v(r), startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
            ctx.stroke(arc, with: .color(style.accent.opacity(0.35)), style: StrokeStyle(lineWidth: v(3), lineCap: .round))
            ctx.stroke(arc, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: v(9), lineCap: .round))
        }
        if detailed {
            dot(&ctx, 22, 24, 1.6, style.accent.opacity(0.9))
            dot(&ctx, 80, 78, 1.2, style.accent.opacity(0.9))
        }
    }

    private func earth(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        // Cracks spreading from a point at the bottom.
        for path in [[(50.0, 104.0), (46.0, 80.0), (30.0, 66.0), (14.0, 64.0)],
                     [(50.0, 104.0), (56.0, 78.0), (74.0, 70.0), (90.0, 54.0)],
                     [(46.0, 80.0), (40.0, 58.0)],
                     [(56.0, 78.0), (64.0, 60.0)]] {
            stroke(&ctx, path, style.accent.opacity(0.45), 2)
        }
        if detailed {
            for (x, y, r) in [(20.0, 82.0, 2.6), (80.0, 84.0, 2.2), (30.0, 20.0, 1.4), (72.0, 26.0, 1.8)] {
                dot(&ctx, x, y, r, style.accent.opacity(0.35))
            }
        }
    }

    private func mana(_ ctx: inout GraphicsContext, _ style: SkillElement.Style) {
        for (x, y, r) in [(20.0, 22.0, 7.0), (82.0, 30.0, 5.0), (16.0, 78.0, 5.0), (80.0, 80.0, 8.0)] {
            var diamond = Path()
            diamond.move(to: p(x, y - r)); diamond.addLine(to: p(x + r * 0.65, y)); diamond.addLine(to: p(x, y + r)); diamond.addLine(to: p(x - r * 0.65, y))
            diamond.closeSubpath()
            ctx.fill(diamond, with: .color(style.accent.opacity(0.3)))
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: v(18), y: v(18), width: v(64), height: v(64))), with: .color(style.accent.opacity(0.22)), lineWidth: v(1.4))
    }
}
