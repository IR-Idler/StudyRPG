import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Character Figure Views (Clean Sprites, Pure Illustrations)

/// Anchors every battle figure's sprite in the fight screen's coordinate space, so VFX and
/// floating numbers land on the character they actually affect instead of a hard-coded point.
struct BattleAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct Diamond: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        path.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.midY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        Diamond(insetAmount: insetAmount + amount)
    }
}

/// Small faceted pips used for a hero's mana pool (game.md §7.6 "mana diamonds").
struct ManaDiamonds: View {
    var filled: Int
    var total: Int
    var size: CGFloat = 7
    var spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(0, total), id: \.self) { index in
                Diamond()
                    .fill(index < filled ? Palette.mana : Palette.mana.opacity(0.12))
                    .overlay(
                        Diamond().strokeBorder(
                            index < filled ? Color.white.opacity(0.7) : Palette.mana.opacity(0.45),
                            lineWidth: 0.8
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: index < filled ? Palette.mana.opacity(0.7) : .clear, radius: 2)
            }
        }
    }
}

/// Classic heater-shield silhouette, used for the persistent Shield Wall barrier.
struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let insetX = rect.width * 0.08
        let top = rect.minY + rect.height * 0.05
        path.move(to: CGPoint(x: rect.minX + insetX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - insetX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - insetX, y: rect.minY + rect.height * 0.52))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.02),
            control: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.24)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + insetX, y: rect.minY + rect.height * 0.52),
            control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.24)
        )
        path.closeSubpath()
        return path
    }
}

/// The single party-wide Shield Wall, standing between the heroes and the enemies while the buff
/// lasts (game.md §7.6). Shows the block amount inside and the remaining rounds underneath.
struct PartyShieldView: View {
    let block: Int
    let rounds: Int
    var size: CGFloat = 72

    @State private var pulse = false
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                ShieldShape()
                    .fill(
                        LinearGradient(
                            colors: [Palette.block.opacity(0.55), Palette.steel.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                ShieldShape()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.35), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(x: shimmer ? size * 0.55 : -size * 0.55)
                    .clipShape(ShieldShape())

                ShieldShape()
                    .stroke(Palette.block, lineWidth: 2)

                ShieldShape()
                    .stroke(Palette.block.opacity(0.6), lineWidth: 6)
                    .blur(radius: 6)

                Text("\(block)")
                    .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .offset(y: -size * 0.04)
            }
            .frame(width: size * 0.82, height: size)
            .scaleEffect(pulse ? 1.04 : 1)
            .shadow(color: Palette.block.opacity(0.55), radius: 10)

            HStack(spacing: 3) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10, weight: .bold))
                Text("\(rounds)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(rounds <= 1 ? Palette.damage : Palette.block)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .overlay(Capsule().strokeBorder(Palette.block.opacity(0.6), lineWidth: 1))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { shimmer = true }
        }
        .allowsHitTesting(false)
    }
}

/// Enemy charge pips, colored by what the next move will do (red attack, green heal, silver armor).
struct ChargePips: View {
    var filled: Int
    var total: Int
    var tint: Color = Palette.damage

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(0, total), id: \.self) { index in
                let isFilled = index < filled
                Diamond()
                    .fill(isFilled ? tint : Color.white.opacity(0.10))
                    .overlay(
                        Diamond().strokeBorder(
                            isFilled ? Color.white.opacity(0.7) : Color.white.opacity(0.35),
                            lineWidth: 0.8
                        )
                    )
                    .frame(width: 7, height: 7)
                    .shadow(color: isFilled ? tint.opacity(0.7) : .clear, radius: 2)
            }
        }
    }
}

/// A hero's action points this party turn (game.md §7.2): gold pips, spent ones hollow.
struct ActionPointPips: View {
    var filled: Int
    var total: Int
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(0, max(total, filled)), id: \.self) { index in
                let isFilled = index < filled
                Circle()
                    .fill(isFilled
                          ? AnyShapeStyle(RadialGradient(colors: [Palette.goldGlow, Palette.gold], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
                          : AnyShapeStyle(Color.black.opacity(0.5)))
                    .overlay(Circle().strokeBorder(isFilled ? Palette.ink.opacity(0.6) : Palette.gold.opacity(0.55), lineWidth: 0.8))
                    .frame(width: size, height: size)
                    .shadow(color: isFilled ? Palette.goldGlow.opacity(0.6) : .clear, radius: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(total) action points")
    }
}

/// How many action points something costs: a gold pip with the number (game.md §7.2).
struct ActionPointCostBadge: View {
    let cost: Int
    var size: CGFloat = 13

    var body: some View {
        Text("\(cost)")
            .font(.system(size: size * 0.72, weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(RadialGradient(colors: [Palette.goldGlow, Palette.gold], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7)))
            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.5), lineWidth: 0.8))
            .accessibilityLabel(cost == 1 ? "Costs 1 action point" : "Costs \(cost) action points")
    }
}

/// The armed skill hits a whole group (all enemies / the whole party): one gilded bracket over
/// every target with the group symbol in the middle, so it never reads as "pick one" (game.md §7.6).
struct TargetGroupBracket: View {
    let xs: [CGFloat]
    var tint: Color = Palette.damage
    var icon: String = "person.3.fill"

    var body: some View {
        let minX = (xs.min() ?? 0) - 20, maxX = (xs.max() ?? 0) + 20
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: minX, y: 12))
                path.addLine(to: CGPoint(x: minX, y: 4))
                path.addLine(to: CGPoint(x: maxX, y: 4))
                path.addLine(to: CGPoint(x: maxX, y: 12))
                for x in xs {
                    path.move(to: CGPoint(x: x, y: 4))
                    path.addLine(to: CGPoint(x: x, y: 12))
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .shadow(color: tint.opacity(0.9), radius: 4)

            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.goldGlow)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.85)))
                .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
                .position(x: (minX + maxX) / 2, y: 4)
        }
        .allowsHitTesting(false)
    }
}

/// Bouncing arrow over an enemy that can be targeted by the armed skill (game.md §7.6).
struct TargetArrowView: View {
    /// Red over enemies (attack), green over heroes (help).
    var tint: Color = Palette.damage
    @State private var bounce = false

    var body: some View {
        ZStack {
            Image(systemName: "arrowtriangle.down.fill")
                .foregroundStyle(tint)
            Image(systemName: "arrowtriangle.down")
                .foregroundStyle(Palette.goldGlow)
        }
        .font(.system(size: 20, weight: .bold))
        .shadow(color: tint.opacity(0.9), radius: 6)
        .offset(y: bounce ? -5 : 3)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { bounce = true }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Floating platforms (game.md §7.6)

/// A small floating island — grass on top, dirt and rocks underneath — that every combatant
/// stands on. Drawn procedurally so it fits any sprite; `width` is the walkable top surface.
struct FloatingPlatformView: View {
    let width: CGFloat
    var material: PlatformMaterial = .grass
    /// Optional highlight color pooled on the top surface (active hero / acting enemy).
    var glow: Color? = nil

    /// (top light, top dark, body top, body bottom, chunk color, overhang color)
    private var palette: (Color, Color, Color, Color, Color, Color?) {
        switch material {
        case .grass:
            return (Color(red: 0.45, green: 0.58, blue: 0.33), Color(red: 0.28, green: 0.40, blue: 0.22),
                    Color(red: 0.42, green: 0.31, blue: 0.21), Color(red: 0.22, green: 0.16, blue: 0.12),
                    Color(red: 0.47, green: 0.47, blue: 0.48), Color(red: 0.26, green: 0.38, blue: 0.20))
        case .moss:
            return (Color(red: 0.33, green: 0.42, blue: 0.25), Color(red: 0.20, green: 0.28, blue: 0.17),
                    Color(red: 0.25, green: 0.21, blue: 0.15), Color(red: 0.12, green: 0.10, blue: 0.08),
                    Color(red: 0.34, green: 0.36, blue: 0.30), Color(red: 0.18, green: 0.27, blue: 0.15))
        case .stone:
            return (Color(red: 0.58, green: 0.58, blue: 0.60), Color(red: 0.40, green: 0.40, blue: 0.43),
                    Color(red: 0.36, green: 0.36, blue: 0.39), Color(red: 0.18, green: 0.18, blue: 0.21),
                    Color(red: 0.50, green: 0.50, blue: 0.53), nil)
        case .snow:
            return (Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.78, green: 0.84, blue: 0.92),
                    Color(red: 0.38, green: 0.42, blue: 0.50), Color(red: 0.18, green: 0.21, blue: 0.27),
                    Color(red: 0.55, green: 0.58, blue: 0.64), Color(red: 0.92, green: 0.95, blue: 1.0))
        case .ash:
            return (Color(red: 0.25, green: 0.22, blue: 0.21), Color(red: 0.15, green: 0.13, blue: 0.13),
                    Color(red: 0.20, green: 0.15, blue: 0.13), Color(red: 0.08, green: 0.05, blue: 0.05),
                    Color(red: 0.32, green: 0.28, blue: 0.27), nil)
        case .rock:
            return (Color(red: 0.52, green: 0.47, blue: 0.40), Color(red: 0.36, green: 0.32, blue: 0.27),
                    Color(red: 0.38, green: 0.33, blue: 0.27), Color(red: 0.18, green: 0.15, blue: 0.12),
                    Color(red: 0.50, green: 0.47, blue: 0.43), nil)
        case .metal:
            return (Color(red: 0.86, green: 0.89, blue: 0.93), Color(red: 0.55, green: 0.60, blue: 0.68),
                    Color(red: 0.30, green: 0.33, blue: 0.40), Color(red: 0.12, green: 0.13, blue: 0.18),
                    Color(red: 0.45, green: 0.85, blue: 1.0), nil)
        }
    }

    static func topHeight(for width: CGFloat) -> CGFloat { width * 0.24 }
    static func height(for width: CGFloat) -> CGFloat { min(width * 0.46, 58) }
    /// How far the platform hangs below a character's feet (feet stand on the top's center line).
    static func depthBelowFeet(for width: CGFloat) -> CGFloat { height(for: width) - topHeight(for: width) * 0.5 }

    private static let outline = Color(red: 0.10, green: 0.08, blue: 0.07)

    /// Act II (game.md §16): a hovering steel disc — polished top with a cyan rim light, a short
    /// panelled rim, and a soft hover glow underneath instead of rocks.
    private static func drawMetal(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, top: CGFloat,
                                  palette: (Color, Color, Color, Color, Color, Color?), glow: Color?) {
        let (topLight, topDark, rimTop, rimBottom, light, _) = palette
        let rimDepth = top * 0.55
        // Hover glow under the disc.
        let glowCenter = CGPoint(x: w / 2, y: top + rimDepth + (h - top - rimDepth) * 0.45)
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.18, y: glowCenter.y - (h - top) * 0.32, width: w * 0.64, height: (h - top) * 0.64)),
                 with: .radialGradient(Gradient(colors: [light.opacity(0.55), light.opacity(0.12), .clear]),
                                       center: glowCenter, startRadius: 0, endRadius: w * 0.32))
        // Rim: the disc's side, with panel seams.
        var rim = Path()
        rim.move(to: CGPoint(x: 0, y: top / 2))
        rim.addLine(to: CGPoint(x: 0, y: top / 2 + rimDepth * 0.5))
        rim.addQuadCurve(to: CGPoint(x: w, y: top / 2 + rimDepth * 0.5), control: CGPoint(x: w / 2, y: top + rimDepth * 1.1))
        rim.addLine(to: CGPoint(x: w, y: top / 2))
        rim.closeSubpath()
        ctx.fill(rim, with: .linearGradient(Gradient(colors: [rimTop, rimBottom]),
                                            startPoint: CGPoint(x: w / 2, y: top / 2), endPoint: CGPoint(x: w / 2, y: top + rimDepth)))
        for fx in [0.22, 0.4, 0.6, 0.78] as [CGFloat] {
            var seam = Path()
            seam.move(to: CGPoint(x: w * fx, y: top * 0.75))
            seam.addLine(to: CGPoint(x: w * fx, y: top * 0.75 + rimDepth * 0.7))
            ctx.stroke(seam, with: .color(Color.black.opacity(0.35)), lineWidth: 1)
        }
        // A thin light strip along the rim.
        var strip = Path()
        strip.move(to: CGPoint(x: w * 0.08, y: top * 0.72))
        strip.addQuadCurve(to: CGPoint(x: w * 0.92, y: top * 0.72), control: CGPoint(x: w / 2, y: top * 1.18))
        ctx.stroke(strip, with: .color(light), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        ctx.stroke(rim, with: .color(Color.black.opacity(0.6)), lineWidth: 1)
        // Polished top with a highlight and a cyan edge.
        let topRect = CGRect(x: 0, y: 0, width: w, height: top)
        let disc = Path(ellipseIn: topRect)
        ctx.fill(disc, with: .linearGradient(Gradient(colors: [topLight, topDark]),
                                             startPoint: CGPoint(x: w * 0.3, y: 0), endPoint: CGPoint(x: w * 0.7, y: top)))
        ctx.stroke(Path(ellipseIn: topRect.insetBy(dx: w * 0.12, dy: top * 0.18)), with: .color(Color.black.opacity(0.12)), lineWidth: 1)
        if let glow {
            ctx.fill(Path(ellipseIn: topRect.insetBy(dx: w * 0.08, dy: top * 0.12)), with: .radialGradient(
                Gradient(colors: [glow.opacity(0.7), glow.opacity(0.2), .clear]),
                center: CGPoint(x: w / 2, y: top / 2), startRadius: 1, endRadius: w * 0.45))
        }
        ctx.stroke(disc, with: .color(light.opacity(0.85)), lineWidth: 1.4)
    }

    var body: some View {
        let w = width
        let h = Self.height(for: w)
        let top = Self.topHeight(for: w)

        Canvas { ctx, _ in
            if material == .metal {
                Self.drawMetal(&ctx, w: w, h: h, top: top, palette: palette, glow: glow)
                return
            }
            let midTop = top * 0.5
            func y(_ fraction: CGFloat) -> CGFloat { midTop + (h - midTop) * fraction }

            // Underside: dirt tapering into a jagged rocky point.
            let jag: [(CGFloat, CGFloat)] = [
                (0.0, 0), (0.05, 0.24), (0.13, 0.36), (0.21, 0.55), (0.29, 0.58), (0.37, 0.80),
                (0.46, 1.0), (0.54, 0.86), (0.62, 0.70), (0.71, 0.63), (0.79, 0.44), (0.89, 0.32),
                (0.96, 0.14), (1.0, 0)
            ]
            var underside = Path()
            underside.move(to: CGPoint(x: 0, y: midTop))
            for (fx, fy) in jag { underside.addLine(to: CGPoint(x: w * fx, y: y(fy))) }
            underside.closeSubpath()

            let (topLight, topDark, bodyTop, bodyBottom, chunk, overhang) = palette
            ctx.fill(underside, with: .linearGradient(
                Gradient(colors: [bodyTop, bodyBottom]),
                startPoint: CGPoint(x: w / 2, y: midTop),
                endPoint: CGPoint(x: w / 2, y: h)
            ))

            // Strata, rocks and pebbles, clipped to the dirt.
            ctx.drawLayer { layer in
                layer.clip(to: underside)
                for fraction in [0.28, 0.56] as [CGFloat] {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y(fraction)))
                    line.addCurve(
                        to: CGPoint(x: w, y: y(fraction - 0.04)),
                        control1: CGPoint(x: w * 0.3, y: y(fraction + 0.10)),
                        control2: CGPoint(x: w * 0.7, y: y(fraction - 0.12))
                    )
                    layer.stroke(line, with: .color(Color(red: 0.17, green: 0.12, blue: 0.09).opacity(0.7)), lineWidth: 1.2)
                }
                let rocks: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.27, 0.30, 0.13), (0.62, 0.26, 0.11), (0.47, 0.60, 0.12),
                    (0.77, 0.47, 0.07), (0.15, 0.22, 0.07), (0.38, 0.40, 0.05)
                ]
                for (fx, fy, size) in rocks {
                    let rect = CGRect(x: w * fx - w * size / 2, y: y(fy) - w * size * 0.32, width: w * size, height: w * size * 0.64)
                    let rock = Path(roundedRect: rect, cornerRadius: rect.height * 0.4)
                    layer.fill(rock, with: .color(chunk))
                    layer.fill(
                        Path(ellipseIn: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.25).offsetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.12)),
                        with: .color(Color(red: 0.64, green: 0.64, blue: 0.64).opacity(0.8))
                    )
                    layer.stroke(rock, with: .color(Self.outline.opacity(0.8)), lineWidth: 0.8)
                }
            }
            ctx.stroke(underside, with: .color(Self.outline), lineWidth: 1.3)

            // Grass top.
            let topRect = CGRect(x: 0, y: 0, width: w, height: top)
            let grassTop = Path(ellipseIn: topRect)
            ctx.fill(grassTop, with: .linearGradient(
                Gradient(colors: [topLight, topDark]),
                startPoint: CGPoint(x: w * 0.3, y: 0),
                endPoint: CGPoint(x: w * 0.6, y: top)
            ))

            if let glow {
                ctx.fill(Path(ellipseIn: topRect.insetBy(dx: w * 0.08, dy: top * 0.12)), with: .radialGradient(
                    Gradient(colors: [glow.opacity(0.75), glow.opacity(0.25), .clear]),
                    center: CGPoint(x: w / 2, y: top / 2),
                    startRadius: 1,
                    endRadius: w * 0.45
                ))
            }

            // Ash: glowing ember cracks across the top.
            if material == .ash {
                for (a, b) in [((0.2, 0.5), (0.45, 0.62)), ((0.55, 0.35), (0.8, 0.55)), ((0.45, 0.62), (0.6, 0.8))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
                    var crack = Path()
                    crack.move(to: CGPoint(x: w * a.0, y: top * a.1))
                    crack.addLine(to: CGPoint(x: w * b.0, y: top * b.1))
                    ctx.stroke(crack, with: .color(Color(red: 1, green: 0.5, blue: 0.15)), lineWidth: 1.4)
                }
            }

            // Grass / snow overhanging the front edge.
            for i in 0..<(overhang == nil ? 0 : 10) {
                let fx = 0.07 + CGFloat(i) * 0.096
                let dx = (fx - 0.5) / 0.5
                let edgeY = top / 2 + top / 2 * sqrt(max(0, 1 - dx * dx))
                let x = w * fx
                var tuft = Path()
                tuft.move(to: CGPoint(x: x - 3.5, y: edgeY - 1.5))
                tuft.addLine(to: CGPoint(x: x + 3.5, y: edgeY - 1.5))
                tuft.addLine(to: CGPoint(x: x + (i.isMultiple(of: 2) ? 0.5 : -0.5), y: edgeY + (i.isMultiple(of: 3) ? 5 : 3.5)))
                tuft.closeSubpath()
                ctx.fill(tuft, with: .color(overhang ?? .clear))
            }

            // A few blades of grass near the back edge.
            for fx in (material == .grass || material == .moss ? [0.22, 0.35, 0.68, 0.81] : []) as [CGFloat] {
                let base = CGPoint(x: w * fx, y: top * 0.32)
                var blade = Path()
                blade.move(to: base)
                blade.addLine(to: CGPoint(x: base.x - 2, y: base.y - 4))
                blade.move(to: base)
                blade.addLine(to: CGPoint(x: base.x + 1.5, y: base.y - 5))
                ctx.stroke(blade, with: .color(Color(red: 0.55, green: 0.68, blue: 0.40)), lineWidth: 1)
            }

            ctx.stroke(grassTop, with: .color(Self.outline), lineWidth: 1.3)
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }
}

/// Width/height of a sprite's art (1 for procedural/placeholder art), used to size its platform.
private func spriteAspect(_ spriteId: String, kind: SpriteKind) -> CGFloat {
    let assetName = "\(kind.assetPrefix)\(spriteId)"
    return ArtCache.aspect(assetName) ?? 1
}

private func platformWidth(spriteId: String, kind: SpriteKind, spriteHeight: CGFloat) -> CGFloat {
    let natural = spriteHeight * spriteAspect(spriteId, kind: kind) * 0.95
    return min(max(natural, spriteHeight * 0.72), spriteHeight * 1.25)
}

/// Fixed height of the nameplate/HP/pips block above every combatant, so stage math stays exact.
private let battleHeaderHeight: CGFloat = 46

/// A combatant's sprite standing on its floating platform. Any highlight glow is layered *behind*
/// the sprite (halo + glow pooled on the grass), never over it.
struct BattleFigureStand: View {
    let spriteId: String
    let kind: SpriteKind
    let spriteHeight: CGFloat
    let anchorKey: String
    var glow: Color? = nil
    var isFlashing = false
    var shake: CGFloat = 0
    var lunge: CGFloat = 0
    var isDown = false
    /// Already merged by kind; shown as a badge row on the front of the platform.
    var statusEffects: [StatusEffect] = []
    var material: PlatformMaterial = .grass

    var body: some View {
        let pw = platformWidth(spriteId: spriteId, kind: kind, spriteHeight: spriteHeight)
        let topH = FloatingPlatformView.topHeight(for: pw)
        let depth = FloatingPlatformView.depthBelowFeet(for: pw)

        ZStack(alignment: .top) {
            if let glow {
                Ellipse()
                    .fill(RadialGradient(
                        colors: [glow.opacity(0.55), glow.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: spriteHeight * 0.55
                    ))
                    .frame(width: max(pw, spriteHeight * 0.9), height: spriteHeight * 1.05)
                    .transition(.opacity)
            }

            FloatingPlatformView(width: pw, material: material, glow: glow)
                .offset(y: spriteHeight - topH * 0.5)

            SpriteView(spriteId: spriteId, kind: kind, targetHeight: spriteHeight, breathes: false)
                // Anchor *before* shake/lunge, so VFX targeting never changes mid-animation (a
                // moving anchor re-rendered the whole fight screen every frame).
                .anchorPreference(key: BattleAnchorKey.self, value: .bounds) { [anchorKey: $0] }
                .brightness(isFlashing ? 0.5 : 0)
                .colorMultiply(isFlashing ? Color(red: 1, green: 0.55, blue: 0.55) : .white)
                .modifier(ShakeEffect(travel: 6, animatableData: shake))
                .rotationEffect(.degrees(isDown ? -85 : 0), anchor: .bottom)
                .opacity(isDown ? 0.45 : 1)
                .offset(x: lunge)
                .frame(height: spriteHeight, alignment: .bottom)

            // Every buff/debuff, summed by kind, on the platform's front face below the feet.
            if !statusEffects.isEmpty {
                StatusEffectRow(effects: statusEffects)
                    .offset(y: spriteHeight + topH * 0.45)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: spriteHeight + depth, alignment: .top)
        .animation(.easeInOut(duration: 0.3), value: glow != nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: statusEffects.map { "\($0.id)\($0.value ?? 0)\($0.duration ?? 0)" })
    }
}

/// Name, HP and the small icon row above a combatant — no "i" glyphs, no prose.
private struct BattleNameplate: View {
    let name: String
    let highlight: Color?
    let current: Int
    let max: Int
    let isEnemy: Bool
    /// Tapping the name (only the name — never the sprite) opens the info sheet.
    var onInspect: () -> Void = {}

    var body: some View {
        VStack(spacing: 2) {
            Button(action: onInspect) {
                label
                .padding(6)
                .contentShape(Rectangle())
                .padding(-6)
            }
            .buttonStyle(.gamePlain)
            .accessibilityHint("Shows details")
            // Bar + the exact number, so a hit always reads even when it barely moves the bar.
            HStack(spacing: 4) {
                HPBarView(current: current, max: max, width: 54, height: 6, isEnemy: isEnemy)
                Text("\(current)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .shadow(color: .black, radius: 1.5)
                    .contentTransition(.numericText(value: Double(current)))
                    .animation(.easeOut(duration: 0.3), value: current)
                    .frame(minWidth: 14, alignment: .leading)
            }
            .offset(x: 9)
        }
    }

    private var label: some View {
        Text(name)
            .font(.serif(11, .bold))
            .foregroundStyle(highlight ?? Palette.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black.opacity(highlight == nil ? 0.65 : 0.85))
                    .overlay(Capsule().strokeBorder(highlight ?? Palette.ink.opacity(0.5), lineWidth: highlight == nil ? 1 : 1.5))
            )
    }
}

struct HeroFigureView: View {
    let hero: HeroState
    /// It's this hero's turn (they stand forward).
    let isActive: Bool
    /// It's this hero's turn *and* no enemy is acting right now (they glow).
    let isActing: Bool
    let isFlashing: Bool
    let shake: CGFloat
    let lunge: CGFloat
    let spriteHeight: CGFloat
    let anchorKey: String
    var statusEffects: [StatusEffect] = []
    var material: PlatformMaterial = .grass
    /// An ally/party/self skill is armed and this hero can receive it.
    var isSelectable = false
    /// Show the bouncing arrow over this target (single-target skills; a group gets a bracket).
    var showsArrow = true
    /// It's the party's turn and this hero still has action points: tapping the sprite selects them.
    var isChoosable = false
    var actionPoints = 0
    var maxActionPoints = 0
    var onInspect: () -> Void = {}
    var onSelect: () -> Void = {}

    var body: some View {
        VStack(spacing: 3) {
            VStack(spacing: 2) {
                BattleNameplate(name: hero.classDef.name, highlight: isActive ? Palette.goldGlow : nil,
                                current: hero.hp, max: hero.maxHP, isEnemy: false, onInspect: onInspect)
                HStack(spacing: 5) {
                    if hero.isAlive && maxActionPoints > 0 {
                        ActionPointPips(filled: actionPoints, total: maxActionPoints)
                    }
                    if let res = hero.classDef.resource {
                        ManaDiamonds(filled: hero.resource, total: res.max)
                    }
                }
                .frame(height: 12)
            }
            .frame(height: battleHeaderHeight, alignment: .bottom)
            .overlay(alignment: .top) {
                if isSelectable && showsArrow {
                    TargetArrowView(tint: Palette.health)
                        .offset(y: -20)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            BattleFigureStand(
                spriteId: hero.classDef.spriteId,
                kind: .hero,
                spriteHeight: spriteHeight,
                anchorKey: anchorKey,
                glow: isActing && hero.isAlive ? Palette.goldGlow : nil,
                isFlashing: isFlashing,
                shake: shake,
                lunge: lunge,
                isDown: !hero.isAlive,
                statusEffects: hero.isAlive ? statusEffects : [],
                material: material
            )
            .contentShape(Rectangle())
            .hoverHighlight(isSelectable || isChoosable)
            .onTapGesture {
                if isSelectable || isChoosable { onSelect() }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelectable)
    }
}

struct EnemyFigureView: View {
    let enemy: EnemyInstance
    let isSelectable: Bool
    /// This enemy is the one doing something right now (game.md §7.6).
    let isActing: Bool
    let isFlashing: Bool
    let shake: CGFloat
    let lunge: CGFloat
    let spriteHeight: CGFloat
    let anchorKey: String
    var statusEffects: [StatusEffect] = []
    /// What it will do when its charge fills (game.md §7.3): colors the pips and shows its icon.
    var nextMove: EnemySkillDef? = nil
    /// Single-target skill: a bouncing arrow over it (a group skill shows a bracket instead).
    var showsArrow = true
    var material: PlatformMaterial = .grass
    var onInspect: () -> Void = {}
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 3) {
                VStack(spacing: 2) {
                    BattleNameplate(name: enemy.def.name, highlight: isActing ? Palette.ember : nil,
                                    current: enemy.hp, max: enemy.maxHP, isEnemy: true, onInspect: onInspect)
                    HStack(spacing: 5) {
                        if let nextMove {
                            // Pips only matter for enemies that wait several turns between moves.
                            if enemy.def.attackEvery > 1 {
                                ChargePips(filled: enemy.chargeCounter, total: enemy.def.attackEvery, tint: nextMove.tint)
                            }
                            Image(systemName: nextMove.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(nextMove.tint)
                                .shadow(color: nextMove.tint.opacity(0.7), radius: 3)
                                .accessibilityLabel("Next: \(nextMove.name)")
                        }
                    }
                    .frame(height: 12)
                }
                .frame(height: battleHeaderHeight, alignment: .bottom)
                .overlay(alignment: .top) {
                    if isSelectable && showsArrow {
                        TargetArrowView()
                            .offset(y: -20)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                // Tapping the sprite only ever targets — never opens the info sheet.
                BattleFigureStand(
                    spriteId: enemy.def.spriteId,
                    kind: .enemy,
                    spriteHeight: spriteHeight,
                    anchorKey: anchorKey,
                    glow: isActing ? Palette.ember : nil,
                    isFlashing: isFlashing,
                    shake: shake,
                    lunge: lunge,
                    statusEffects: statusEffects,
                    material: material
                )
                .contentShape(Rectangle())
                .hoverHighlight(isSelectable)
                .onTapGesture {
                    if isSelectable { onSelect() }
                }
        }
        .scaleEffect(isActing ? 1.04 : 1, anchor: .bottom)
        .opacity(enemy.isAlive ? 1 : 0)
        .allowsHitTesting(enemy.isAlive)
        .animation(.easeInOut(duration: 0.5), value: enemy.isAlive)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActing)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelectable)
    }

}

// MARK: - Battle Stage View

struct BattleStageView: View {
    @Bindable var engine: CombatEngine
    var platform: PlatformMaterial = .grass
    var heroFlashing: [Bool]
    var heroShake: [CGFloat]
    var heroLunge: [CGFloat]
    var enemyFlashing: [UUID: Bool]
    var enemyShake: [UUID: CGFloat]
    var enemyLunge: [UUID: CGFloat]
    var onSelectEnemy: (UUID) -> Void
    var onSelectHero: (String) -> Void = { _ in }
    var onInspectHero: (Int) -> Void = { _ in }
    var onInspectEnemy: (UUID) -> Void = { _ in }


    private var isFightOver: Bool {
        engine.phase == .victory || engine.phase == .defeat
    }

    var body: some View {
        GeometryReader { geo in
            let stageW = geo.size.width
            let stageH = geo.size.height
            // Everything is sized so header + sprite + hanging platform always fits the stage.
            let heroSpriteH = min(126, (stageH - battleHeaderHeight - 30) / 1.3)
            let maxEnemySpriteH = (stageH - battleHeaderHeight - 24) / 1.3
            // Feet line of the front row; the platforms hang below it.
            let frontFeetY = stageH - FloatingPlatformView.depthBelowFeet(for: heroSpriteH) - 6
            let showShield = engine.shieldWallRoundsRemaining > 0 && engine.heroes.contains(where: \.isAlive)

            ZStack {
                // MARK: Heroes — whoever's turn it is steps forward, the other steps back.
                ForEach(Array(engine.heroes.enumerated()), id: \.element.id) { index, hero in
                    let isActive = index == engine.activeHeroIndex && !isFightOver
                    let spriteH = heroSpriteH * (isActive ? 1 : 0.92)
                    let depth = FloatingPlatformView.depthBelowFeet(
                        for: platformWidth(spriteId: hero.classDef.spriteId, kind: .hero, spriteHeight: spriteH)
                    )
                    let baseX = stageW * (index == 0 ? 0.32 : 0.17)
                    let heroX = baseX + (isActive ? 14 : -10)
                    let feetY = frontFeetY - (isActive ? 0 : 22)
                    let totalH = battleHeaderHeight + 3 + spriteH + depth
                    let centerY = feetY - spriteH - 3 - battleHeaderHeight + totalH / 2

                    HeroFigureView(
                        hero: hero,
                        isActive: isActive,
                        isActing: isActive && engine.actingEnemyID == nil,
                        isFlashing: heroFlashing.indices.contains(index) ? heroFlashing[index] : false,
                        shake: heroShake.indices.contains(index) ? heroShake[index] : 0,
                        lunge: heroLunge.indices.contains(index) ? heroLunge[index] : 0,
                        spriteHeight: spriteH,
                        anchorKey: "hero-\(index)",
                        // The party shield carries Shield Wall's rounds, so the block badge shows only the total.
                        statusEffects: mergedStatusEffects(heroStatusEffects(engine: engine, index: index)).map { effect in
                            var effect = effect
                            if effect.kind == "block" { effect.duration = nil }
                            return effect
                        },
                        material: platform,
                        isSelectable: engine.isValidTarget(heroID: hero.id),
                        showsArrow: !engine.armedSkillHitsGroup,
                        isChoosable: engine.isChoosing && index != engine.activeHeroIndex && engine.canAct(heroAt: index),
                        actionPoints: hero.actionPoints,
                        maxActionPoints: engine.maxActionPoints(heroAt: index),
                        onInspect: { onInspectHero(index) },
                        onSelect: { onSelectHero(hero.id) }
                    )
                    .position(x: heroX, y: centerY)
                    // Depth-sorted: whoever stands lower on the floor draws in front.
                    .zIndex(Double(feetY) + Double(index) * 0.1)
                    .animation(.spring(response: 0.5, dampingFraction: 0.78), value: isActive)
                }

                // MARK: Party shield — one shield ahead of both heroes while Shield Wall lasts.
                if showShield {
                    PartyShieldView(block: engine.shieldWallBlock, rounds: engine.shieldWallRoundsRemaining, size: min(76, heroSpriteH * 0.6))
                        .position(x: stageW * 0.39, y: frontFeetY - heroSpriteH * 0.5)
                        .zIndex(Double(frontFeetY) + 1)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                // MARK: Enemies — stable slots by roster position, so nobody slides when one falls.
                let formation = enemyFormation(stageW: stageW, maxSpriteH: maxEnemySpriteH)
                ForEach(Array(engine.enemies.enumerated()), id: \.element.id) { index, enemy in
                    let slot = formation[index]
                    let spriteH = min(CGFloat(enemy.def.spriteHeight ?? 125), maxEnemySpriteH) * slot.scale
                    let depth = FloatingPlatformView.depthBelowFeet(
                        for: platformWidth(spriteId: enemy.def.spriteId, kind: .enemy, spriteHeight: spriteH)
                    )
                    let feetY = stageH - depth - 6 - slot.raise
                    let totalH = battleHeaderHeight + 3 + spriteH + depth
                    let centerY = feetY - spriteH - 3 - battleHeaderHeight + totalH / 2

                    EnemyFigureView(
                        enemy: enemy,
                        isSelectable: engine.isValidTarget(enemyID: enemy.id),
                        isActing: engine.actingEnemyID == enemy.id,
                        isFlashing: enemyFlashing[enemy.id] ?? false,
                        shake: enemyShake[enemy.id] ?? 0,
                        lunge: enemyLunge[enemy.id] ?? 0,
                        spriteHeight: spriteH,
                        anchorKey: "enemy-\(enemy.id.uuidString)",
                        statusEffects: mergedStatusEffects(enemyStatusEffects(engine: engine, enemy: enemy)),
                        nextMove: engine.plannedMove(for: enemy)?.skill,
                        showsArrow: !engine.armedSkillHitsGroup,
                        material: platform,
                        onInspect: { onInspectEnemy(enemy.id) },
                        onSelect: { onSelectEnemy(enemy.id) }
                    )
                    .position(x: slot.x, y: centerY)
                    // Depth-sorted: whoever stands lower on the floor draws in front.
                    .zIndex(Double(feetY) + Double(index) * 0.1)
                }

                // MARK: Group targets — one bracket over everyone the armed skill will hit.
                if engine.armedSkillHitsGroup {
                    let enemySide = engine.armedSkill?.target == .allEnemies
                    let xs: [CGFloat] = enemySide
                        ? engine.enemies.indices.filter { engine.enemies[$0].isAlive }.map { formation[$0].x }
                        : engine.heroes.indices.filter { engine.heroes[$0].isAlive }.map { index in
                            stageW * (index == 0 ? 0.32 : 0.17) + (index == engine.activeHeroIndex ? 14 : -10)
                        }
                    TargetGroupBracket(xs: xs, tint: enemySide ? Palette.damage : Palette.health,
                                       icon: enemySide ? "person.3.fill" : "person.2.fill")
                        .frame(width: stageW, height: 24)
                        .position(x: stageW / 2, y: groupBracketY(stageH: stageH, heroSpriteH: heroSpriteH, maxEnemySpriteH: maxEnemySpriteH, enemySide: enemySide))
                        .zIndex(10_000)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showShield)
        }
    }

    /// Just above the tallest target's nameplate.
    private func groupBracketY(stageH: CGFloat, heroSpriteH: CGFloat, maxEnemySpriteH: CGFloat, enemySide: Bool) -> CGFloat {
        let tallest: CGFloat
        if enemySide {
            tallest = engine.enemies.filter(\.isAlive).map { min(CGFloat($0.def.spriteHeight ?? 125), maxEnemySpriteH) }.max() ?? maxEnemySpriteH
        } else {
            tallest = heroSpriteH
        }
        let feetY = stageH - FloatingPlatformView.depthBelowFeet(for: tallest) - 6
        // Back-row enemies stand raised (up to 18 pt); inactive heroes stand 22 pt back.
        return max(14, feetY - tallest - battleHeaderHeight - 18 - (enemySide ? 18 : 22))
    }

    /// Formation slots for the whole roster (dead enemies keep their place): x center in points,
    /// how far a back-row slot is raised, and a shrink factor. A lone enemy stands at 72% of the
    /// stage; 2–3 are packed left→right into the right half by their real art widths (the raised
    /// middle one may overlap its neighbours a little), shrunk only if they wouldn't fit.
    private func enemyFormation(stageW: CGFloat, maxSpriteH: CGFloat) -> [(x: CGFloat, raise: CGFloat, scale: CGFloat)] {
        let enemies = engine.enemies
        guard enemies.count > 1 else { return enemies.map { _ in (stageW * 0.72, 0, 1) } }
        let widths: [CGFloat] = enemies.map { enemy in
            let h = min(CGFloat(enemy.def.spriteHeight ?? 125), maxSpriteH)
            let art = h * spriteAspect(enemy.def.spriteId, kind: .enemy)
            return max(art, platformWidth(spriteId: enemy.def.spriteId, kind: .enemy, spriteHeight: h))
        }
        let overlap: CGFloat = enemies.count >= 3 ? 0.14 : 0.04
        let start = stageW * 0.52, end = stageW * 0.98
        let needed = widths.reduce(0, +) - widths.dropLast().reduce(0) { $0 + $1 * overlap }
        let scale = min(1, (end - start) / max(1, needed))
        var cursor = start + ((end - start) - needed * scale) / 2
        return widths.enumerated().map { index, width in
            let w = width * scale
            let x = cursor + w / 2
            cursor += w * (1 - overlap)
            let raise: CGFloat = (enemies.count == 2 && index == 1) || (enemies.count >= 3 && index % 3 == 1) ? 18 : 0
            return (x, raise, scale)
        }
    }
}

// MARK: - Buff/debuff summaries (game.md §7.6)
//
// One `StatusEffect` per *source*. The battlefield sums effects of the same `kind` into a single
// badge with no source; the info sheet lists every source separately with its explanation.

func heroStatusEffects(engine: CombatEngine, index: Int) -> [StatusEffect] {
    var effects: [StatusEffect] = []
    if engine.shieldWallBlock > 0 {
        effects.append(StatusEffect(
            id: "shield-wall",
            kind: "block",
            icon: "shield.fill",
            value: engine.shieldWallBlock,
            duration: engine.shieldWallRoundsRemaining,
            tint: Palette.block,
            name: L("Shield Wall"),
            source: L("Warrior's Shield Wall skill"),
            detail: L("Each hit on the party deals \(engine.shieldWallBlock) less damage.")
        ))
    }
    for relic in engine.relics where relic.effect.type == .damageReduction {
        effects.append(StatusEffect(
            id: "relic-\(relic.id)",
            kind: "block",
            icon: "shield.fill",
            value: relic.effect.amount,
            duration: nil,
            tint: Palette.block,
            name: relic.name,
            source: L("Relic"),
            detail: L("Each hit on the party deals \(relic.effect.amount) less damage, all run.")
        ))
    }
    let hero = engine.heroes[index]
    for gear in hero.gear {
        for effect in gear.effects where effect.type == .block {
            effects.append(StatusEffect(
                id: "gear-\(gear.id)",
                kind: "block",
                icon: "shield.fill",
                value: effect.amount,
                duration: nil,
                tint: Palette.block,
                name: gear.name,
                source: L("Gear"),
                detail: L("Each hit on \(hero.classDef.name) deals \(effect.amount) less damage.")
            ))
        }
    }
    if hero.stickerBlock > 0 {
        // Landed guard stickers (game.md §8 "Hero dice"), until the hero's next turn.
        effects.append(StatusEffect(
            id: "sticker-block",
            kind: "block",
            icon: "shield.fill",
            value: hero.stickerBlock,
            duration: nil,
            tint: Palette.block,
            name: engine.dice.stickers.first { $0.type == .block }?.name ?? L("Die sticker"),
            source: L("Die sticker"),
            detail: L("Each hit on \(hero.classDef.name) deals \(hero.stickerBlock) less damage until their next turn.")
        ))
    }
    for (offset, buff) in hero.damageBuffs.enumerated() {
        effects.append(StatusEffect(
            id: "buff-\(offset)",
            kind: "damage-buff",
            icon: "arrow.up.circle.fill",
            value: buff.amount,
            duration: buff.rounds,
            tint: Palette.strength,
            name: L("Damage Up"),
            source: L("A hero skill"),
            detail: L("+\(buff.amount) on every damage roll for \(buff.rounds) more round(s).")
        ))
    }
    if hero.isStunned {
        effects.append(StatusEffect(
            id: "stun",
            kind: "stun",
            icon: "moon.zzz.fill",
            value: hero.stunTurns,
            duration: nil,
            tint: Palette.control,
            name: L("Stunned"),
            source: L("A monster skill"),
            detail: L("Loses the next \(hero.stunTurns) turn(s).")
        ))
    }
    for (offset, status) in hero.weakens.enumerated() {
        effects.append(StatusEffect(
            id: "weaken-\(offset)",
            kind: "weaken",
            icon: "arrow.down.circle.fill",
            value: status.amount,
            duration: status.rounds,
            tint: Palette.control,
            name: L("Weakened"),
            source: L("A monster skill"),
            detail: L("Deals \(status.amount) less on every damage roll.")
        ))
    }
    for (offset, status) in hero.vulnerables.enumerated() {
        effects.append(StatusEffect(
            id: "vulnerable-\(offset)",
            kind: "vulnerable",
            icon: "scope",
            value: status.amount,
            duration: status.rounds,
            tint: Palette.control,
            name: L("Vulnerable"),
            source: L("A monster skill"),
            detail: L("Takes \(status.amount) more damage per hit.")
        ))
    }
    // Recharging skills aren't buffs: their cooldown shows on the skill button (game.md §7.6).
    let bonus = engine.heroes[index].bonusDiceNextTurn
    if bonus > 0 {
        effects.append(StatusEffect(
            id: "bonus-dice",
            kind: "bonus-dice",
            icon: "die.face.5.fill",
            value: bonus,
            duration: nil,
            tint: Palette.strength,
            name: L("Bonus Dice"),
            source: L("Strength Potion / gear"),
            detail: L("Adds \(bonus)d\(engine.dieSides(heroAt: index)) to this hero's next damage or healing roll.")
        ))
    }
    if hero.trainingDamageBonus > 0 {
        effects.append(StatusEffect(
            id: "training",
            kind: "training",
            icon: "figure.strengthtraining.traditional",
            value: hero.trainingDamageBonus,
            duration: nil,
            tint: Palette.strength,
            name: L("Training"),
            source: L("Campfire"),
            detail: L("+\(hero.trainingDamageBonus) on every damage roll, all run.")
        ))
    }
    for relic in engine.relics where relic.effect.type == .rollBonus {
        effects.append(StatusEffect(
            id: "relic-\(relic.id)",
            kind: "roll-bonus",
            icon: "arrow.up.circle.fill",
            value: relic.effect.amount,
            duration: nil,
            tint: Palette.strength,
            name: relic.name,
            source: L("Relic"),
            detail: L("+\(relic.effect.amount) to every damage and healing roll, all run.")
        ))
    }
    return effects
}

func enemyStatusEffects(engine: CombatEngine, enemy: EnemyInstance) -> [StatusEffect] {
    var effects: [StatusEffect] = []
    if enemy.hasArmor {
        let block = enemy.armorAmount
        effects.append(StatusEffect(
            id: "armor",
            kind: "armor",
            icon: "shield.fill",
            value: block,
            duration: enemy.armorRoundsRemaining,
            tint: Palette.block,
            name: L("Armor"),
            source: L("A monster skill"),
            detail: L("Absorbs \(block) damage from each incoming hit.")
        ))
    }
    for (offset, buff) in enemy.damageBuffs.enumerated() {
        effects.append(StatusEffect(
            id: "buff-\(offset)",
            kind: "damage-buff",
            icon: "arrow.up.circle.fill",
            value: buff.amount,
            duration: buff.rounds,
            tint: Palette.strength,
            name: L("Damage Up"),
            source: L("A monster skill"),
            detail: L("+\(buff.amount) on every hit for \(buff.rounds) more round(s).")
        ))
    }
    if enemy.isStunned {
        effects.append(StatusEffect(
            id: "stun",
            kind: "stun",
            icon: "moon.zzz.fill",
            value: enemy.stunTicks,
            duration: nil,
            tint: Palette.control,
            name: L("Stunned"),
            source: L("A hero skill"),
            detail: L("Sleeps through its next \(enemy.stunTicks) turn(s) and can't strike back after a wrong answer.")
        ))
    }
    for (offset, status) in enemy.weakens.enumerated() {
        effects.append(StatusEffect(
            id: "weaken-\(offset)",
            kind: "weaken",
            icon: "arrow.down.circle.fill",
            value: status.amount,
            duration: status.rounds,
            tint: Palette.control,
            name: L("Weakened"),
            source: L("A hero skill"),
            detail: L("Deals \(status.amount) less damage per hit.")
        ))
    }
    for (offset, status) in enemy.vulnerables.enumerated() {
        effects.append(StatusEffect(
            id: "vulnerable-\(offset)",
            kind: "vulnerable",
            icon: "scope",
            value: status.amount,
            duration: status.rounds,
            tint: Palette.control,
            name: L("Vulnerable"),
            source: L("A hero skill"),
            detail: L("Takes \(status.amount) more damage per hit.")
        ))
    }
    return effects
}

/// Sums effects of the same kind into one badge (e.g. Shield Wall 2 + Iron Shield 1 → `[shield] 3`).
/// A merged badge only keeps a duration if every part of it is timed.
func mergedStatusEffects(_ effects: [StatusEffect]) -> [StatusEffect] {
    var order: [String] = []
    var result: [String: StatusEffect] = [:]
    for effect in effects {
        if var existing = result[effect.kind] {
            existing.value = (existing.value ?? 0) + (effect.value ?? 0)
            if let a = existing.duration, let b = effect.duration {
                existing.duration = max(a, b)
            } else {
                existing.duration = nil
            }
            result[effect.kind] = existing
        } else {
            var first = effect
            first.id = effect.kind
            result[effect.kind] = first
            order.append(effect.kind)
        }
    }
    return order.compactMap { result[$0] }
}
