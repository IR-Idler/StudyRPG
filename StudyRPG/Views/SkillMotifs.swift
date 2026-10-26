import SwiftUI

// MARK: - Painted skill motifs (game.md §5 "Skill art")
//
// The object painted on a skill's emblem, in the same ink-outlined style as the item art
// (`ItemArt` drawing kit): a sword with its slash, a war horn blasting, a cursed doll, …
// Picked by `classes.json → art` (presentation only, like an item's `spriteId`); a skill whose
// `art` isn't one of these falls back to its SF Symbol `icon`. Drawn on a 100×100 grid.

enum SkillMotif {
    static let supported: Set<String> = [
        "sword_slash", "shield_wall", "heavy_strike", "cleave", "shield_bash", "sunder",
        "battle_cry", "intimidate", "second_wind", "ground_slam",
        "arcane_bolt", "fireball", "heal", "chain_lightning", "ice_lance", "frost_nova",
        "mend", "empower", "hex", "meteor", "mana_surge"
    ]

    static func canDraw(_ motif: String?) -> Bool {
        guard let motif else { return false }
        return supported.contains(motif.lowercased())
    }

    /// Paints `motif` into the square that fits `rect`.
    static func draw(_ motif: String, in ctx: inout GraphicsContext, rect: CGRect) {
        let side = min(rect.width, rect.height)
        let g = ItemGrid(side: side, origin: CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2))
        switch motif.lowercased() {
        case "sword_slash": swordSlash(&ctx, g)
        case "shield_wall": shieldWall(&ctx, g)
        case "heavy_strike": heavyStrike(&ctx, g)
        case "cleave": cleave(&ctx, g)
        case "shield_bash": shieldBash(&ctx, g)
        case "sunder": sunder(&ctx, g)
        case "battle_cry": battleCry(&ctx, g)
        case "intimidate": intimidate(&ctx, g)
        case "second_wind": secondWind(&ctx, g)
        case "ground_slam": groundSlam(&ctx, g)
        case "arcane_bolt": arcaneBolt(&ctx, g)
        case "fireball": fireball(&ctx, g)
        case "heal": heal(&ctx, g)
        case "chain_lightning": chainLightning(&ctx, g)
        case "ice_lance": iceLance(&ctx, g)
        case "frost_nova": frostNova(&ctx, g)
        case "mend": mend(&ctx, g)
        case "empower": empower(&ctx, g)
        case "hex": hex(&ctx, g)
        case "meteor": meteor(&ctx, g)
        case "mana_surge": manaSurge(&ctx, g)
        default: break
        }
    }
}

private typealias Kit = ItemArt

// MARK: - Shared shapes & colors

private extension SkillMotif {
    static let ice = [Color.white, Color(red: 0.70, green: 0.88, blue: 1.0), Color(red: 0.36, green: 0.62, blue: 0.88)]
    static let violet = [Color.white, Color(red: 0.80, green: 0.62, blue: 1.0), Color(red: 0.46, green: 0.22, blue: 0.78)]
    static let manaBlue = [Color(red: 0.80, green: 0.90, blue: 1.0), Color(red: 0.36, green: 0.54, blue: 0.98), Color(red: 0.14, green: 0.20, blue: 0.58)]
    static let leaf = [Color(red: 0.62, green: 0.90, blue: 0.45), Color(red: 0.26, green: 0.58, blue: 0.24)]
    static let heartRed = [Color(red: 1.0, green: 0.52, blue: 0.50), Color(red: 0.82, green: 0.12, blue: 0.16), Color(red: 0.48, green: 0.04, blue: 0.08)]
    static let darkSteel = [Color(red: 0.62, green: 0.66, blue: 0.72), Color(red: 0.36, green: 0.38, blue: 0.45), Color(red: 0.17, green: 0.18, blue: 0.22)]
    static let flame = [Color(red: 1, green: 0.95, blue: 0.62), Color(red: 1, green: 0.58, blue: 0.14), Color(red: 0.80, green: 0.18, blue: 0.06)]

    /// Points around a star (stun stars, impact bursts).
    static func star(_ g: ItemGrid, _ cx: Double, _ cy: Double, outer: Double, inner: Double, points: Int = 5, rotation: Double = -90) -> Path {
        g.poly((0..<(points * 2)).map { k in
            let r = k.isMultiple(of: 2) ? outer : inner
            let a = (rotation + Double(k) * 180 / Double(points)) * .pi / 180
            return (cx + cos(a) * r, cy + sin(a) * r)
        })
    }

    /// A jagged lump of rock.
    static func rock(_ g: ItemGrid, _ cx: Double, _ cy: Double, _ r: Double, jag: [Double] = [1, 0.78, 0.95, 0.74, 1, 0.84]) -> Path {
        g.poly(jag.enumerated().map { k, scale in
            let a = (Double(k) / Double(jag.count) * 360 + 15) * .pi / 180
            return (cx + cos(a) * r * scale, cy + sin(a) * r * scale)
        })
    }

    /// A leaf from `base` to `tip`, bulging `width` to each side.
    static func leafPath(_ g: ItemGrid, _ base: (Double, Double), _ tip: (Double, Double), width: Double) -> Path {
        let mid = ((base.0 + tip.0) / 2, (base.1 + tip.1) / 2)
        let dx = tip.0 - base.0, dy = tip.1 - base.1
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let n = (-dy / len * width, dx / len * width)
        var path = Path()
        path.move(to: g.p(base.0, base.1))
        path.addQuadCurve(to: g.p(tip.0, tip.1), control: g.p(mid.0 + n.0, mid.1 + n.1))
        path.addQuadCurve(to: g.p(base.0, base.1), control: g.p(mid.0 - n.0, mid.1 - n.1))
        path.closeSubpath()
        return path
    }

    static func drawLeaf(_ ctx: inout GraphicsContext, _ g: ItemGrid, _ base: (Double, Double), _ tip: (Double, Double), width: Double) {
        Kit.paint(&ctx, g, leafPath(g, base, tip, width: width), leaf, from: tip, to: base, line: 1.6)
        Kit.line(&ctx, g, [base, ((base.0 + tip.0) / 2, (base.1 + tip.1) / 2)], Color(red: 0.18, green: 0.40, blue: 0.16), width: 1)
    }

    /// A falling drop (healing light), pointed end up.
    static func drop(_ g: ItemGrid, _ x: Double, _ y: Double, _ s: Double) -> Path {
        var path = Path()
        path.move(to: g.p(x, y - s))
        path.addQuadCurve(to: g.p(x + s * 0.7, y + s * 0.3), control: g.p(x + s * 0.55, y - s * 0.2))
        path.addCurve(to: g.p(x - s * 0.7, y + s * 0.3), control1: g.p(x + s * 0.7, y + s * 1.2), control2: g.p(x - s * 0.7, y + s * 1.2))
        path.addQuadCurve(to: g.p(x, y - s), control: g.p(x - s * 0.55, y - s * 0.2))
        path.closeSubpath()
        return path
    }

    /// A heater shield whose bounding box is (x, y, w, h).
    static func heater(_ g: ItemGrid, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        var path = Path()
        path.move(to: g.p(x, y))
        path.addLine(to: g.p(x + w, y))
        path.addLine(to: g.p(x + w, y + h * 0.4))
        path.addQuadCurve(to: g.p(x + w / 2, y + h), control: g.p(x + w, y + h * 0.8))
        path.addQuadCurve(to: g.p(x, y + h * 0.4), control: g.p(x, y + h * 0.8))
        path.closeSubpath()
        return path
    }

    /// Inked stroke: a dark line under a colored one, so thin magic/wind lines read on any backdrop.
    static func inked(_ ctx: inout GraphicsContext, _ g: ItemGrid, _ path: Path, _ color: Color, width: Double) {
        ctx.stroke(path, with: .color(Kit.ink), style: StrokeStyle(lineWidth: g.v(width + 2), lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: g.v(width), lineCap: .round, lineJoin: .round))
    }

    static func inkedLine(_ ctx: inout GraphicsContext, _ g: ItemGrid, _ points: [(Double, Double)], _ color: Color, width: Double) {
        Kit.line(&ctx, g, points, Kit.ink, width: width + 2)
        Kit.line(&ctx, g, points, color, width: width)
    }

    /// A comet-like trail from a ball at `head` (radius `r`) toward `tail`.
    static func trail(_ g: ItemGrid, head: (Double, Double), r: Double, tail: (Double, Double), bend: Double = 0.3) -> Path {
        let dx = tail.0 - head.0, dy = tail.1 - head.1
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let n = (-dy / len, dx / len)
        let a = (head.0 + n.0 * r, head.1 + n.1 * r), b = (head.0 - n.0 * r, head.1 - n.1 * r)
        var path = Path()
        path.move(to: g.p(a.0, a.1))
        path.addQuadCurve(to: g.p(tail.0, tail.1), control: g.p(head.0 + dx * 0.5 + n.0 * r * (1 + bend), head.1 + dy * 0.5 + n.1 * r * (1 + bend)))
        path.addQuadCurve(to: g.p(b.0, b.1), control: g.p(head.0 + dx * 0.5 - n.0 * r * (1 - bend), head.1 + dy * 0.5 - n.1 * r * (1 - bend)))
        path.closeSubpath()
        return path
    }
}

// MARK: - Warrior

private extension SkillMotif {
    /// Sword: a single blade with a bright crescent slash behind it.
    static func swordSlash(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        var slash = Path()
        slash.move(to: g.p(10, 34))
        slash.addQuadCurve(to: g.p(68, 92), control: g.p(12, 88))
        slash.addQuadCurve(to: g.p(10, 34), control: g.p(26, 70))
        slash.closeSubpath()
        ctx.fill(slash, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.85)]), startPoint: g.p(10, 34), endPoint: g.p(68, 92)))
        Kit.paint(&ctx, g, g.poly([(30, 62), (76, 16), (88, 10), (82, 22), (36, 68)]), Kit.steel, from: (34, 66), to: (84, 14))
        Kit.line(&ctx, g, [(35, 63), (80, 18)], Color(red: 0.45, green: 0.50, blue: 0.58), width: 1.4)
        Kit.line(&ctx, g, [(32, 61), (76, 18)], .white.opacity(0.75), width: 1)
        Kit.paint(&ctx, g, g.poly([(20, 58), (26, 52), (46, 72), (40, 78)]), Kit.gold, from: (20, 54), to: (46, 76))
        Kit.paint(&ctx, g, g.poly([(26, 68), (32, 74), (20, 86), (14, 80)]), Kit.leather, from: (26, 68), to: (16, 84))
        Kit.paint(&ctx, g, g.ellipse(7, 81, 11, 11), Kit.gold, line: 1.8)
        Kit.glint(&ctx, g, 80, 20, 5)
    }

    /// Shield Wall: two overlapping shields raised together (protects the whole party).
    static func shieldWall(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        Kit.paint(&ctx, g, heater(g, 10, 10, 46, 64), Kit.gold, from: (10, 10), to: (56, 74), line: 2.4)
        Kit.paint(&ctx, g, heater(g, 15, 15, 36, 52), [Color(red: 0.42, green: 0.55, blue: 0.78), Color(red: 0.18, green: 0.26, blue: 0.46)],
                  from: (15, 15), to: (51, 67), line: 1.4)
        Kit.line(&ctx, g, [(33, 16), (33, 64)], Kit.gold[1], width: 2.6)
        Kit.paint(&ctx, g, heater(g, 42, 24, 48, 68), Kit.gold, from: (42, 24), to: (90, 92), line: 2.6)
        Kit.paint(&ctx, g, heater(g, 47, 29, 38, 56), [Color(red: 0.78, green: 0.22, blue: 0.20), Color(red: 0.42, green: 0.07, blue: 0.08)],
                  from: (47, 29), to: (85, 85), line: 1.4)
        // Gold chevron emblem + boss on the front shield.
        Kit.paint(&ctx, g, g.poly([(52, 44), (66, 56), (80, 44), (80, 52), (66, 64), (52, 52)]), Kit.gold, line: 1.4)
        Kit.paint(&ctx, g, g.ellipse(62, 66, 8, 8), Kit.gold, line: 1.2)
        Kit.shine(&ctx, g, 49, 31, 9, 12, 0.3)
        Kit.glint(&ctx, g, 56, 34, 4)
    }

    /// Heavy Strike: a massive war hammer swung down, impact burst at the striking face.
    static func heavyStrike(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        for (r, opacity) in [(72.0, 0.55), (82.0, 0.35)] {
            var arc = Path()
            arc.addArc(center: g.p(16, 92), radius: g.v(r), startAngle: .degrees(-100), endAngle: .degrees(-76), clockwise: false)
            ctx.stroke(arc, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: g.v(3), lineCap: .round))
        }
        Kit.paint(&ctx, g, star(g, 84, 52, outer: 16, inner: 7, points: 8, rotation: -70),
                  [Color(red: 1, green: 0.98, blue: 0.8), Color(red: 1, green: 0.76, blue: 0.25)], from: (84, 40), to: (84, 66), line: 1.4)
        Kit.paint(&ctx, g, g.poly([(13, 90), (19, 94), (67, 32), (61, 28)]), Kit.wood, from: (15, 92), to: (64, 30))
        for t in [0.1, 0.2] {
            let x = 16 + 48 * t, y = 92 - 62 * t
            Kit.line(&ctx, g, [(x - 3, y - 2.5), (x + 3, y + 2.5)], Color(red: 0.25, green: 0.14, blue: 0.08), width: 1.6)
        }
        Kit.paint(&ctx, g, g.poly([(52, 6), (90, 35), (76, 54), (38, 25)]), darkSteel, from: (45, 15), to: (83, 45), line: 2.6)
        Kit.line(&ctx, g, [(62, 13), (47, 32)], Kit.ink.opacity(0.7), width: 1.6)
        Kit.line(&ctx, g, [(81, 28), (66, 47)], Kit.ink.opacity(0.7), width: 1.6)
        Kit.line(&ctx, g, [(54, 10), (86, 34)], .white.opacity(0.55), width: 1.4)
        Kit.glint(&ctx, g, 58, 14, 4)
    }

    /// Cleave: a broad axe with a wide sweeping trail (hits every enemy).
    static func cleave(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        for (r, width, opacity) in [(34.0, 5.0, 0.75), (43.0, 3.6, 0.5), (52.0, 2.4, 0.3)] {
            var arc = Path()
            arc.addArc(center: g.p(62, 52), radius: g.v(r), startAngle: .degrees(140), endAngle: .degrees(240), clockwise: false)
            ctx.stroke(arc, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: g.v(width), lineCap: .round))
        }
        Kit.paint(&ctx, g, g.poly([(36, 92), (42, 95), (62, 40), (56, 37)]), Kit.wood, from: (38, 94), to: (60, 38))
        var blade = Path()
        blade.move(to: g.p(54, 32))
        blade.addLine(to: g.p(66, 42))
        blade.addLine(to: g.p(70, 58))
        blade.addQuadCurve(to: g.p(88, 34), control: g.p(88, 56))
        blade.addQuadCurve(to: g.p(74, 8), control: g.p(92, 14))
        blade.addLine(to: g.p(60, 24))
        blade.closeSubpath()
        Kit.paint(&ctx, g, blade, [Color(red: 0.82, green: 0.84, blue: 0.90), Color(red: 0.48, green: 0.51, blue: 0.58), Color(red: 0.26, green: 0.28, blue: 0.34)],
                  from: (62, 12), to: (84, 54), line: 2.4)
        var edge = Path()
        edge.move(to: g.p(71, 55))
        edge.addQuadCurve(to: g.p(85, 34), control: g.p(85, 52))
        edge.addQuadCurve(to: g.p(75, 11), control: g.p(88, 16))
        ctx.stroke(edge, with: .color(.white.opacity(0.85)), lineWidth: g.v(1.8))
        Kit.paint(&ctx, g, g.poly([(51, 30), (57, 24), (67, 36), (61, 42)]), Kit.steel, line: 1.8)
        Kit.glint(&ctx, g, 82, 26, 4.5)
    }

    /// Shield Bash: a round buckler slamming into an impact burst, stun stars spinning off.
    static func shieldBash(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        for (a, b) in [((4.0, 74.0), (14.0, 66.0)), ((8.0, 88.0), (20.0, 78.0)), ((20.0, 94.0), (28.0, 86.0))] {
            Kit.line(&ctx, g, [a, b], .white.opacity(0.6), width: 2.2)
        }
        Kit.paint(&ctx, g, star(g, 74, 36, outer: 20, inner: 9, points: 8),
                  [Color(red: 1, green: 0.98, blue: 0.8), Color(red: 1, green: 0.74, blue: 0.22)], from: (74, 18), to: (74, 56), line: 1.4)
        Kit.paint(&ctx, g, g.ellipse(12, 30, 58, 58), Kit.steel, from: (12, 30), to: (70, 88), line: 2.6)
        let face = g.ellipse(18, 36, 46, 46)
        Kit.paint(&ctx, g, face, Kit.wood, from: (18, 36), to: (64, 82), line: 1.4)
        ctx.drawLayer { layer in
            layer.clip(to: face)
            for x in [30.0, 41.0, 52.0] { Kit.line(&layer, g, [(x, 34), (x, 84)], Color(red: 0.28, green: 0.17, blue: 0.08).opacity(0.7), width: 1) }
        }
        Kit.paint(&ctx, g, g.ellipse(32, 50, 18, 18), Kit.steel, line: 1.6)
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            ctx.fill(g.ellipse(41 + cos(a) * 26 - 1.6, 59 + sin(a) * 26 - 1.6, 3.2, 3.2), with: .color(Color(red: 0.95, green: 0.92, blue: 0.80)))
        }
        for (x, y, r) in [(88.0, 12.0, 6.0), (92.0, 62.0, 5.0), (58.0, 10.0, 4.5)] {
            Kit.paint(&ctx, g, star(g, x, y, outer: r, inner: r * 0.45), Kit.gold, line: 1.1)
        }
        Kit.glint(&ctx, g, 36, 54, 3.5)
    }

    /// Sunder: a breastplate split down a glowing crack (the enemy is left vulnerable).
    static func sunder(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let crack: [(Double, Double)] = [(52, 12), (46, 34), (55, 46), (44, 62), (52, 76), (47, 96)]
        Kit.aura(&ctx, g, 50, 54, 32, Color(red: 1, green: 0.25, blue: 0.15))
        Kit.line(&ctx, g, crack, Color(red: 1, green: 0.55, blue: 0.2), width: 4)
        var plate = Path()
        plate.move(to: g.p(22, 22))
        plate.addQuadCurve(to: g.p(40, 16), control: g.p(30, 16))
        plate.addQuadCurve(to: g.p(60, 16), control: g.p(50, 32))
        plate.addQuadCurve(to: g.p(78, 22), control: g.p(70, 16))
        plate.addLine(to: g.p(82, 40))
        plate.addQuadCurve(to: g.p(74, 86), control: g.p(78, 70))
        plate.addQuadCurve(to: g.p(26, 86), control: g.p(50, 96))
        plate.addQuadCurve(to: g.p(18, 40), control: g.p(22, 70))
        plate.closeSubpath()
        let left = g.poly([(0, 0)] + crack + [(0, 100)])
        let right = g.poly([(100, 0)] + crack + [(100, 100)])
        for (half, dx, dy) in [(left, -4.0, 1.0), (right, 4.0, -1.0)] {
            ctx.drawLayer { layer in
                layer.translateBy(x: g.v(dx), y: g.v(dy))
                layer.clip(to: half)
                Kit.paint(&layer, g, plate, Kit.steel, from: (20, 16), to: (80, 90), line: 2.6)
                var pecs = Path()
                pecs.move(to: g.p(26, 44))
                pecs.addQuadCurve(to: g.p(74, 44), control: g.p(50, 62))
                layer.stroke(pecs, with: .color(Color(red: 0.32, green: 0.36, blue: 0.44)), lineWidth: g.v(1.8))
                for y in [68.0, 78.0] {
                    var band = Path()
                    band.move(to: g.p(24, y))
                    band.addQuadCurve(to: g.p(76, y), control: g.p(50, y + 8))
                    layer.stroke(band, with: .color(Color(red: 0.32, green: 0.36, blue: 0.44)), lineWidth: g.v(1.4))
                }
                Kit.line(&layer, g, crack, Kit.ink, width: 3)
                Kit.shine(&layer, g, 28, 24, 10, 14, 0.35)
            }
        }
        for (x, y, r) in [(64.0, 24.0, 4.0), (36.0, 84.0, 3.5), (62.0, 62.0, 3.0)] {
            Kit.paint(&ctx, g, g.poly([(x, y - r), (x + r, y + r * 0.6), (x - r * 0.8, y + r * 0.4)]), Kit.steel, line: 1.1)
        }
    }

    /// Battle Cry: a war horn blasting rings of sound (rallies the party).
    static func battleCry(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        for r in [12.0, 20.0, 28.0] {
            var arc = Path()
            arc.addArc(center: g.p(66, 30), radius: g.v(r), startAngle: .degrees(-42), endAngle: .degrees(42), clockwise: false)
            inked(&ctx, g, arc, Kit.gold[0], width: 2.2)
        }
        // Horn: a tapering curve sampled along a quadratic centerline.
        let a = (14.0, 82.0), c = (18.0, 34.0), b = (62.0, 30.0)
        var leftSide: [(Double, Double)] = [], rightSide: [(Double, Double)] = []
        func point(_ t: Double) -> (pt: (Double, Double), n: (Double, Double), w: Double) {
            let u = 1 - t
            let pt = (u * u * a.0 + 2 * u * t * c.0 + t * t * b.0, u * u * a.1 + 2 * u * t * c.1 + t * t * b.1)
            let tan = (2 * u * (c.0 - a.0) + 2 * t * (b.0 - c.0), 2 * u * (c.1 - a.1) + 2 * t * (b.1 - c.1))
            let len = max(0.001, (tan.0 * tan.0 + tan.1 * tan.1).squareRoot())
            return (pt, (-tan.1 / len, tan.0 / len), 2.5 + 13 * t * t)
        }
        for k in 0...14 {
            let s = point(Double(k) / 14)
            leftSide.append((s.pt.0 + s.n.0 * s.w, s.pt.1 + s.n.1 * s.w))
            rightSide.append((s.pt.0 - s.n.0 * s.w, s.pt.1 - s.n.1 * s.w))
        }
        let ivory = [Color(red: 0.98, green: 0.93, blue: 0.80), Color(red: 0.80, green: 0.68, blue: 0.48), Color(red: 0.52, green: 0.40, blue: 0.26)]
        Kit.paint(&ctx, g, g.poly(leftSide + rightSide.reversed()), ivory, from: (20, 30), to: (50, 70), line: 2.4)
        for t in [0.4, 0.72] {
            let s = point(t)
            inkedLine(&ctx, g, [(s.pt.0 + s.n.0 * s.w, s.pt.1 + s.n.1 * s.w), (s.pt.0 - s.n.0 * s.w, s.pt.1 - s.n.1 * s.w)], Kit.gold[1], width: 2.6)
        }
        Kit.paint(&ctx, g, g.ellipse(58, 14, 9, 32), [Color(red: 0.30, green: 0.20, blue: 0.12), Color(red: 0.12, green: 0.08, blue: 0.05)], line: 1.6)
        ctx.stroke(g.ellipse(58, 14, 9, 32), with: .color(Kit.gold[0]), lineWidth: g.v(1.4))
        Kit.paint(&ctx, g, g.ellipse(10, 78, 9, 9), Kit.gold, line: 1.4)
        Kit.shine(&ctx, g, 22, 50, 5, 18, 0.4)
    }

    /// Intimidate: a horned helm with burning red eyes (weakens every enemy).
    static func intimidate(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let ivory = [Color(red: 0.96, green: 0.91, blue: 0.78), Color(red: 0.70, green: 0.60, blue: 0.44)]
        for mirror in [false, true] {
            func m(_ x: Double) -> Double { mirror ? 100 - x : x }
            var horn = Path()
            horn.move(to: g.p(m(31), 52))
            horn.addQuadCurve(to: g.p(m(6), 8), control: g.p(m(4), 46))
            horn.addQuadCurve(to: g.p(m(33), 36), control: g.p(m(14), 32))
            horn.closeSubpath()
            Kit.paint(&ctx, g, horn, ivory, from: (m(6), 8), to: (m(30), 50), line: 2)
            Kit.line(&ctx, g, [(m(14), 40), (m(20), 36)], Color(red: 0.45, green: 0.36, blue: 0.24), width: 1.2)
            Kit.line(&ctx, g, [(m(9), 26), (m(15), 25)], Color(red: 0.45, green: 0.36, blue: 0.24), width: 1.2)
        }
        var helm = Path()
        helm.move(to: g.p(28, 86))
        helm.addLine(to: g.p(28, 48))
        helm.addCurve(to: g.p(50, 18), control1: g.p(28, 28), control2: g.p(38, 18))
        helm.addCurve(to: g.p(72, 48), control1: g.p(62, 18), control2: g.p(72, 28))
        helm.addLine(to: g.p(72, 86))
        helm.addQuadCurve(to: g.p(28, 86), control: g.p(50, 94))
        helm.closeSubpath()
        Kit.paint(&ctx, g, helm, darkSteel, from: (30, 18), to: (70, 90), line: 2.6)
        Kit.line(&ctx, g, [(30, 47), (70, 47)], Kit.ink.opacity(0.8), width: 1.6)
        Kit.aura(&ctx, g, 40, 56, 12, Color(red: 1, green: 0.15, blue: 0.1))
        Kit.aura(&ctx, g, 60, 56, 12, Color(red: 1, green: 0.15, blue: 0.1))
        let slitColors = [Color(red: 1, green: 0.85, blue: 0.5), Color(red: 1, green: 0.22, blue: 0.10)]
        Kit.paint(&ctx, g, g.poly([(31, 51), (46, 56), (46, 61), (33, 57)]), slitColors, line: 1.4)
        Kit.paint(&ctx, g, g.poly([(69, 51), (54, 56), (54, 61), (67, 57)]), slitColors, line: 1.4)
        Kit.paint(&ctx, g, g.rounded(47, 47, 6, 30, 2), Kit.steel, line: 1.4)
        for x in [36.0, 41.0, 59.0, 64.0] {
            ctx.fill(g.ellipse(x - 1.3, 72, 2.6, 4), with: .color(Kit.ink))
        }
        Kit.shine(&ctx, g, 36, 24, 10, 10, 0.3)
    }

    /// Second Wind: a fresh gust swirling around a heart (the warrior heals himself).
    static func secondWind(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let wind = Color(red: 0.88, green: 0.98, blue: 0.95)
        var back = Path()
        back.move(to: g.p(8, 40))
        back.addCurve(to: g.p(74, 28), control1: g.p(30, 22), control2: g.p(58, 18))
        back.addArc(center: g.p(74, 38), radius: g.v(10), startAngle: .degrees(-90), endAngle: .degrees(150), clockwise: false)
        inked(&ctx, g, back, wind, width: 3)
        Kit.aura(&ctx, g, 50, 56, 26, Color(red: 1, green: 0.4, blue: 0.4))
        Kit.paint(&ctx, g, Kit.heartPath(g, cx: 50, cy: 56, size: 42), heartRed, from: (40, 38), to: (60, 80), line: 2.2)
        Kit.shine(&ctx, g, 36, 46, 7, 5, 0.55)
        var front = Path()
        front.move(to: g.p(92, 70))
        front.addCurve(to: g.p(30, 76), control1: g.p(72, 86), control2: g.p(44, 88))
        front.addArc(center: g.p(30, 66), radius: g.v(10), startAngle: .degrees(90), endAngle: .degrees(330), clockwise: false)
        inked(&ctx, g, front, wind, width: 3)
        inkedLine(&ctx, g, [(78, 52), (92, 50)], wind, width: 2)
        inkedLine(&ctx, g, [(6, 56), (16, 55)], wind, width: 2)
    }

    /// Ground Slam: the earth cracks under a blow, rocks fly and a shock ring spreads (stuns all).
    static func groundSlam(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let earth = [Color(red: 0.66, green: 0.50, blue: 0.32), Color(red: 0.42, green: 0.30, blue: 0.18)]
        var side = Path()
        side.move(to: g.p(8, 71))
        side.addLine(to: g.p(10, 79))
        side.addQuadCurve(to: g.p(90, 79), control: g.p(50, 112))
        side.addLine(to: g.p(92, 71))
        side.addQuadCurve(to: g.p(8, 71), control: g.p(50, 101))
        side.closeSubpath()
        Kit.paint(&ctx, g, side, [Color(red: 0.36, green: 0.25, blue: 0.15), Color(red: 0.22, green: 0.15, blue: 0.09)], line: 2)
        let top = g.ellipse(8, 56, 84, 30)
        Kit.paint(&ctx, g, top, earth, from: (50, 56), to: (50, 86), line: 2.2)
        ctx.fill(g.ellipse(41, 66, 18, 8), with: .color(Color(red: 0.20, green: 0.13, blue: 0.07)))
        for crack in [[(50.0, 70.0), (38.0, 66.0), (26.0, 68.0), (15.0, 65.0)], [(50.0, 70.0), (62.0, 64.0), (72.0, 66.0), (85.0, 62.0)],
                      [(50.0, 70.0), (44.0, 78.0), (35.0, 82.0)], [(50.0, 70.0), (58.0, 77.0), (67.0, 82.0)], [(50.0, 70.0), (52.0, 60.0)]] {
            Kit.line(&ctx, g, crack, Kit.ink, width: 1.8)
        }
        ctx.stroke(g.ellipse(16, 58, 68, 26), with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: g.v(2), dash: [g.v(6), g.v(4)]))
        for (x, y) in [(10.0, 64.0), (88.0, 62.0)] {
            ctx.fill(g.ellipse(x - 7, y - 5, 14, 10), with: .color(Color(red: 0.85, green: 0.78, blue: 0.66).opacity(0.5)))
        }
        let stone = [Color(red: 0.72, green: 0.62, blue: 0.48), Color(red: 0.42, green: 0.34, blue: 0.24)]
        for (x, y, r) in [(24.0, 36.0, 8.0), (72.0, 28.0, 10.0), (48.0, 18.0, 6.0), (88.0, 46.0, 5.0), (10.0, 48.0, 4.0)] {
            Kit.line(&ctx, g, [(x, y + r + 2), (x + (50 - x) * 0.2, y + r + 10)], .white.opacity(0.4), width: 1.4)
            Kit.paint(&ctx, g, rock(g, x, y, r), stone, from: (x, y - r), to: (x, y + r), line: 1.6)
        }
    }
}

// MARK: - Wizard

private extension SkillMotif {
    /// Bolt: a violet arcane missile streaking in; a little mana spark rewards the caster.
    static func arcaneBolt(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        ctx.fill(trail(g, head: (64, 36), r: 12, tail: (8, 92), bend: 0), with: .linearGradient(
            Gradient(colors: [Color(red: 0.72, green: 0.5, blue: 1).opacity(0.85), Color(red: 0.5, green: 0.2, blue: 0.9).opacity(0)]),
            startPoint: g.p(64, 36), endPoint: g.p(10, 90)))
        for (a, b) in [((52.0, 40.0), (20.0, 72.0)), ((60.0, 52.0), (34.0, 80.0)), ((48.0, 30.0), (26.0, 50.0))] {
            Kit.line(&ctx, g, [a, b], .white.opacity(0.6), width: 1.4)
        }
        Kit.aura(&ctx, g, 64, 36, 28, Color(red: 0.75, green: 0.45, blue: 1))
        Kit.paint(&ctx, g, g.ellipse(50, 22, 28, 28), violet, from: (56, 24), to: (76, 50), line: 2)
        Kit.paint(&ctx, g, star(g, 64, 36, outer: 10, inner: 3, points: 4), [.white, Color(red: 0.92, green: 0.85, blue: 1)], line: 1)
        Kit.glint(&ctx, g, 30, 66, 3)
        Kit.glint(&ctx, g, 18, 82, 2.4)
        // Mana spark: a small blue diamond.
        Kit.paint(&ctx, g, g.poly([(82, 66), (89, 76), (82, 88), (75, 76)]), manaBlue, from: (82, 66), to: (82, 88), line: 1.4)
        Kit.glint(&ctx, g, 80, 72, 2.4)
    }

    /// Fireball: a blazing ball with a roaring tail of flame.
    static func fireball(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let head = (62.0, 38.0)
        let outer = trail(g, head: head, r: 22, tail: (8, 92), bend: 0.4)
        Kit.paint(&ctx, g, outer, [Color(red: 1, green: 0.40, blue: 0.10), Color(red: 0.75, green: 0.12, blue: 0.05)],
                  from: head, to: (8, 92), line: 1.8)
        ctx.fill(trail(g, head: head, r: 15, tail: (20, 80), bend: 0.4), with: .color(Color(red: 1, green: 0.64, blue: 0.18)))
        ctx.fill(trail(g, head: head, r: 9, tail: (32, 68), bend: 0.3), with: .color(Color(red: 1, green: 0.90, blue: 0.45)))
        Kit.aura(&ctx, g, head.0, head.1, 30, Color(red: 1, green: 0.55, blue: 0.1))
        ctx.fill(g.ellipse(head.0 - 16, head.1 - 16, 32, 32), with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 1, blue: 0.9), flame[0], flame[1]]), center: g.p(head.0 + 3, head.1 - 3), startRadius: 0, endRadius: g.v(17)))
        ctx.stroke(g.ellipse(head.0 - 16, head.1 - 16, 32, 32), with: .color(Color(red: 0.7, green: 0.18, blue: 0.05)), lineWidth: g.v(1.2))
        for (x, y, r) in [(84.0, 16.0, 1.8), (88.0, 44.0, 1.4), (40.0, 22.0, 1.6), (70.0, 70.0, 1.4)] {
            ctx.fill(g.ellipse(x - r, y - r, r * 2, r * 2), with: .color(Color(red: 1, green: 0.75, blue: 0.3)))
        }
    }

    /// Heal: a sprig of healing herbs shedding glowing drops (heals the whole party).
    static func heal(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        var stem = Path()
        stem.move(to: g.p(34, 92))
        stem.addQuadCurve(to: g.p(58, 14), control: g.p(26, 50))
        inked(&ctx, g, stem, Color(red: 0.42, green: 0.56, blue: 0.24), width: 2.6)
        drawLeaf(&ctx, g, (33, 70), (10, 56), width: 8)
        drawLeaf(&ctx, g, (34, 50), (58, 42), width: 8)
        drawLeaf(&ctx, g, (40, 32), (20, 16), width: 7)
        drawLeaf(&ctx, g, (57, 16), (74, 6), width: 5)
        let glow = Color(red: 0.55, green: 1, blue: 0.55)
        for (x, y, s) in [(70.0, 56.0, 7.0), (82.0, 74.0, 6.0), (62.0, 80.0, 5.5)] {
            Kit.aura(&ctx, g, x, y, s * 2, glow)
            Kit.paint(&ctx, g, drop(g, x, y, s), [Color(red: 0.92, green: 1, blue: 0.85), glow, Color(red: 0.2, green: 0.68, blue: 0.3)],
                      from: (x, y - s), to: (x, y + s), line: 1.2)
        }
        Kit.glint(&ctx, g, 68, 30, 4)
        Kit.glint(&ctx, g, 88, 54, 2.6)
    }

    /// Chain Lightning: one bolt leaping from foe to foe (hits every enemy).
    static func chainLightning(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let nodes: [(Double, Double)] = [(26, 40), (72, 28), (60, 78)]
        let bolt: [(Double, Double)] = [(6, 10), (18, 22), (12, 27), (26, 40), (40, 30), (46, 38), (58, 26), (72, 28),
                                        (80, 46), (66, 51), (74, 63), (60, 78)]
        for (x, y) in nodes { Kit.aura(&ctx, g, x, y, 14, Color(red: 0.9, green: 0.9, blue: 0.4)) }
        Kit.line(&ctx, g, bolt, Kit.ink, width: 7)
        Kit.line(&ctx, g, bolt, Color(red: 1, green: 0.86, blue: 0.3), width: 4.2)
        Kit.line(&ctx, g, bolt, .white, width: 1.6)
        for fork in [[(60.0, 78.0), (52.0, 86.0), (48.0, 94.0)], [(60.0, 78.0), (70.0, 88.0)], [(72.0, 28.0), (86.0, 18.0)]] {
            inkedLine(&ctx, g, fork, Color(red: 1, green: 0.9, blue: 0.45), width: 1.8)
        }
        for (x, y) in nodes {
            Kit.paint(&ctx, g, g.ellipse(x - 6.5, y - 6.5, 13, 13), [.white, Color(red: 1, green: 0.9, blue: 0.4), Color(red: 0.85, green: 0.6, blue: 0.1)],
                      from: (x, y - 6), to: (x, y + 6), line: 1.6)
        }
    }

    /// Ice Lance: a faceted spear of ice, frost chips flying from its tip (freezes the target).
    static func iceLance(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        for (x, y, w, h) in [(4.0, 76.0, 20.0, 14.0), (12.0, 84.0, 16.0, 10.0)] {
            ctx.fill(g.ellipse(x, y, w, h), with: .color(.white.opacity(0.25)))
        }
        let lance = g.poly([(90, 10), (43, 70), (17, 89), (11, 83), (30, 57)])
        Kit.paint(&ctx, g, lance, ice, from: (30, 50), to: (60, 80), line: 2.2)
        ctx.drawLayer { layer in
            layer.clip(to: lance)
            layer.fill(g.poly([(90, 10), (43, 70), (17, 89), (14, 86)]), with: .color(Color(red: 0.18, green: 0.38, blue: 0.70).opacity(0.45)))
        }
        Kit.line(&ctx, g, [(88, 12), (14, 86)], .white.opacity(0.8), width: 1.2)
        Kit.line(&ctx, g, [(30, 57), (37, 64), (43, 70)], Color(red: 0.25, green: 0.45, blue: 0.75), width: 1.2)
        for (x, y, r) in [(78.0, 34.0, 4.0), (66.0, 12.0, 3.4), (92.0, 30.0, 3.0), (84.0, 46.0, 2.4)] {
            Kit.paint(&ctx, g, g.poly([(x, y - r), (x + r * 0.6, y), (x, y + r), (x - r * 0.6, y)]), ice, line: 1)
        }
        Kit.glint(&ctx, g, 80, 20, 5)
    }

    /// Frost Nova: a great six-armed burst of ice ringed in frost (freezes every enemy).
    static func frostNova(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        Kit.aura(&ctx, g, 50, 50, 44, Color(red: 0.6, green: 0.9, blue: 1))
        ctx.stroke(g.ellipse(10, 10, 80, 80), with: .color(Kit.ink), lineWidth: g.v(4.4))
        ctx.stroke(g.ellipse(10, 10, 80, 80), with: .color(Color(red: 0.80, green: 0.94, blue: 1)), lineWidth: g.v(2.4))
        for i in 0..<6 {
            let a = (Double(i) * 60 - 90) * .pi / 180
            let d = (cos(a), sin(a)), n = (-sin(a), cos(a))
            let tip = (50 + d.0 * 44, 50 + d.1 * 44)
            for side in [-1.0, 1.0] {
                let b = (50 + d.0 * 26, 50 + d.1 * 26)
                let ba = a + side * 0.9
                inkedLine(&ctx, g, [b, (b.0 + cos(ba) * 10, b.1 + sin(ba) * 10)], .white, width: 1.8)
            }
            Kit.paint(&ctx, g, g.poly([(50, 50), (50 + d.0 * 16 + n.0 * 6, 50 + d.1 * 16 + n.1 * 6), tip,
                                       (50 + d.0 * 16 - n.0 * 6, 50 + d.1 * 16 - n.1 * 6)]),
                      ice, from: (50, 50), to: tip, line: 1.6)
        }
        let hexagon = (0..<6).map { k -> (Double, Double) in
            let a = (Double(k) * 60 - 60) * .pi / 180
            return (50 + cos(a) * 9, 50 + sin(a) * 9)
        }
        Kit.paint(&ctx, g, g.poly(hexagon), [.white, Color(red: 0.72, green: 0.9, blue: 1)], line: 1.4)
        Kit.glint(&ctx, g, 50, 50, 5)
    }

    /// Mend: a heart bound with a bandage (a big heal for one ally).
    static func mend(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        Kit.aura(&ctx, g, 50, 54, 36, Color(red: 0.5, green: 1, blue: 0.55))
        Kit.paint(&ctx, g, Kit.heartPath(g, cx: 50, cy: 54, size: 66), heartRed, from: (36, 24), to: (64, 90), line: 2.4)
        Kit.shine(&ctx, g, 26, 38, 10, 7, 0.5)
        let cloth = [Color(red: 0.98, green: 0.95, blue: 0.86), Color(red: 0.82, green: 0.76, blue: 0.62)]
        Kit.paint(&ctx, g, g.poly([(10, 65), (82, 29), (90, 43), (18, 79)]), cloth, from: (50, 40), to: (54, 70), line: 1.8)
        for k in [0.12, 0.24, 0.76, 0.88] {
            let x = 14 + 72 * k, y = 72 - 36 * k
            Kit.line(&ctx, g, [(x - 3, y - 6), (x + 3, y + 6)], Color(red: 0.70, green: 0.64, blue: 0.52), width: 0.9)
        }
        Kit.paint(&ctx, g, g.poly([(37, 54), (58, 43), (63, 54), (42, 65)]), [Color(red: 0.92, green: 0.86, blue: 0.72), Color(red: 0.76, green: 0.68, blue: 0.52)], line: 1.2)
        for (x, y) in [(45.0, 52.0), (52.0, 49.0), (48.0, 58.0), (55.0, 55.0)] {
            ctx.fill(g.ellipse(x - 0.9, y - 0.9, 1.8, 1.8), with: .color(Color(red: 0.6, green: 0.52, blue: 0.4)))
        }
        Kit.glint(&ctx, g, 80, 18, 4)
        Kit.glint(&ctx, g, 16, 30, 3)
    }

    /// Empower: a sword wreathed in arcane light with rising chevrons (an ally hits harder).
    static func empower(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        Kit.aura(&ctx, g, 50, 40, 36, Color(red: 0.75, green: 0.45, blue: 1))
        for cx in [18.0, 82.0] {
            for cy in [34.0, 52.0, 70.0] {
                let w = 9.0
                Kit.paint(&ctx, g, g.poly([(cx - w, cy + w * 0.5), (cx, cy - w * 0.5), (cx + w, cy + w * 0.5),
                                           (cx + w, cy + w * 0.5 + 5), (cx, cy - w * 0.5 + 5), (cx - w, cy + w * 0.5 + 5)]),
                          Kit.gold, line: 1.3)
            }
        }
        Kit.paint(&ctx, g, g.poly([(45, 64), (45, 18), (50, 6), (55, 18), (55, 64)]), Kit.steel, from: (45, 30), to: (55, 30))
        Kit.line(&ctx, g, [(50, 12), (50, 62)], Color(red: 0.45, green: 0.50, blue: 0.58), width: 1.2)
        Kit.paint(&ctx, g, g.rounded(32, 63, 36, 7, 2), Kit.gold, line: 1.8)
        Kit.paint(&ctx, g, Path(g.rect(46.5, 70, 7, 15)), Kit.leather, line: 1.6)
        Kit.paint(&ctx, g, g.ellipse(44, 84, 12, 11), Kit.gold, line: 1.6)
        Kit.paint(&ctx, g, g.ellipse(47, 64, 6, 5), violet, line: 1)
        Kit.glint(&ctx, g, 50, 10, 6)
        Kit.glint(&ctx, g, 54, 40, 3)
    }

    /// Hex: a cursed rag doll pierced by pins (the target is weakened and vulnerable).
    static func hex(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        Kit.aura(&ctx, g, 50, 52, 42, Color(red: 0.6, green: 0.25, blue: 0.95))
        let burlap = [Color(red: 0.82, green: 0.68, blue: 0.46), Color(red: 0.56, green: 0.42, blue: 0.25)]
        let body = g.poly([(40, 38), (60, 38), (62, 46), (82, 50), (82, 60), (62, 58), (64, 76), (70, 90), (56, 92), (50, 80),
                           (44, 92), (30, 90), (36, 76), (38, 58), (18, 60), (18, 50), (38, 46)])
        Kit.paint(&ctx, g, body, burlap, from: (50, 38), to: (50, 92), line: 2.2)
        var seam = Path()
        seam.move(to: g.p(50, 40))
        seam.addLine(to: g.p(50, 78))
        ctx.stroke(seam, with: .color(Color(red: 0.32, green: 0.20, blue: 0.10)), style: StrokeStyle(lineWidth: g.v(1.2), lineCap: .round, dash: [g.v(3), g.v(2.5)]))
        Kit.paint(&ctx, g, g.ellipse(34, 8, 32, 32), burlap, from: (50, 8), to: (50, 40), line: 2.2)
        // X-stitched eye, button eye, stitched mouth.
        Kit.line(&ctx, g, [(40, 18), (47, 25)], Kit.ink, width: 2)
        Kit.line(&ctx, g, [(47, 18), (40, 25)], Kit.ink, width: 2)
        Kit.paint(&ctx, g, g.ellipse(52, 17, 9, 9), [Color(red: 0.35, green: 0.25, blue: 0.45), Color(red: 0.15, green: 0.10, blue: 0.20)], line: 1.2)
        Kit.line(&ctx, g, [(41, 32), (59, 32)], Kit.ink, width: 1.4)
        for x in [44.0, 50.0, 56.0] { Kit.line(&ctx, g, [(x, 29.5), (x, 34.5)], Kit.ink, width: 1.2) }
        // Pins with glowing heads.
        for (from, to, head) in [((52.0, 52.0), (74.0, 28.0), Color(red: 0.85, green: 0.15, blue: 0.2)),
                                 ((42.0, 64.0), (18.0, 76.0), Color(red: 0.62, green: 0.30, blue: 0.95))] {
            inkedLine(&ctx, g, [from, to], Color(red: 0.85, green: 0.88, blue: 0.94), width: 1.6)
            Kit.paint(&ctx, g, g.ellipse(to.0 - 5, to.1 - 5, 10, 10), [head.mixed(with: .white, 0.45), head, head.mixed(with: .black, 0.4)], line: 1.4)
            Kit.glint(&ctx, g, to.0 - 1.5, to.1 - 1.5, 2.4)
        }
    }

    /// Meteor: a burning boulder plunging down with a huge tail of fire.
    static func meteor(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        let head = (40.0, 62.0)
        Kit.paint(&ctx, g, trail(g, head: head, r: 25, tail: (94, 6), bend: 0.3), [Color(red: 1, green: 0.42, blue: 0.10), Color(red: 0.70, green: 0.10, blue: 0.05)],
                  from: head, to: (94, 6), line: 1.8)
        ctx.fill(trail(g, head: head, r: 18, tail: (84, 16), bend: 0.3), with: .color(Color(red: 1, green: 0.64, blue: 0.18)))
        ctx.fill(trail(g, head: head, r: 10, tail: (70, 30), bend: 0.3), with: .color(Color(red: 1, green: 0.90, blue: 0.45)))
        Kit.aura(&ctx, g, head.0, head.1, 32, Color(red: 1, green: 0.5, blue: 0.1))
        let boulder = rock(g, head.0, head.1, 22, jag: [1, 0.86, 0.98, 0.82, 1, 0.9, 0.95, 0.84])
        Kit.paint(&ctx, g, boulder, [Color(red: 0.52, green: 0.34, blue: 0.24), Color(red: 0.30, green: 0.18, blue: 0.12), Color(red: 0.16, green: 0.09, blue: 0.06)],
                  from: (head.0 + 12, head.1 - 18), to: (head.0 - 12, head.1 + 18), line: 2.4)
        for crack in [[(30.0, 56.0), (38.0, 62.0), (34.0, 72.0)], [(38.0, 62.0), (50.0, 60.0)], [(46.0, 72.0), (52.0, 66.0)]] {
            Kit.line(&ctx, g, crack, Color(red: 1, green: 0.62, blue: 0.2), width: 1.8)
        }
        for (x, y, r) in [(32.0, 50.0, 4.0), (48.0, 76.0, 3.0)] {
            ctx.fill(g.ellipse(x - r, y - r, r * 2, r * 2), with: .color(Color(red: 0.14, green: 0.08, blue: 0.05).opacity(0.7)))
        }
        for (x, y, r) in [(14.0, 86.0, 3.0), (22.0, 92.0, 2.0), (10.0, 72.0, 2.2)] {
            Kit.paint(&ctx, g, rock(g, x, y, r), [Color(red: 0.5, green: 0.32, blue: 0.22), Color(red: 0.25, green: 0.15, blue: 0.1)], line: 1)
        }
    }

    /// Mana Surge: a cluster of mana crystals with energy spiralling upward (restores mana).
    static func manaSurge(_ ctx: inout GraphicsContext, _ g: ItemGrid) {
        Kit.aura(&ctx, g, 50, 50, 44, Color(red: 0.4, green: 0.6, blue: 1))
        let stream = Color(red: 0.78, green: 0.90, blue: 1)
        for mirror in [false, true] {
            func m(_ x: Double) -> Double { mirror ? 100 - x : x }
            var swirl = Path()
            swirl.move(to: g.p(m(14), 88))
            swirl.addCurve(to: g.p(m(30), 8), control1: g.p(m(2), 56), control2: g.p(m(40), 40))
            inked(&ctx, g, swirl, stream, width: 2)
        }
        Kit.paint(&ctx, g, g.poly([(28, 48), (38, 56), (38, 84), (30, 88), (22, 82), (20, 58)]), manaBlue, from: (28, 48), to: (28, 88), line: 1.8)
        Kit.paint(&ctx, g, g.poly([(72, 48), (80, 58), (78, 82), (70, 88), (62, 84), (62, 56)]), manaBlue, from: (72, 48), to: (72, 88), line: 1.8)
        let main = g.poly([(50, 14), (62, 30), (60, 80), (50, 88), (40, 80), (38, 30)])
        Kit.paint(&ctx, g, main, manaBlue, from: (50, 14), to: (50, 88), line: 2.2)
        Kit.line(&ctx, g, [(50, 14), (50, 88)], .white.opacity(0.4), width: 1.2)
        Kit.line(&ctx, g, [(38, 30), (50, 36), (62, 30)], .white.opacity(0.4), width: 1.2)
        for (x, y, r) in [(22.0, 26.0, 5.0), (78.0, 18.0, 6.0)] {
            Kit.paint(&ctx, g, g.poly([(x, y - r), (x + r * 0.65, y), (x, y + r), (x - r * 0.65, y)]), manaBlue, line: 1.2)
        }
        Kit.glint(&ctx, g, 45, 26, 5)
        Kit.glint(&ctx, g, 28, 62, 2.6)
        Kit.glint(&ctx, g, 72, 62, 2.6)
    }
}
