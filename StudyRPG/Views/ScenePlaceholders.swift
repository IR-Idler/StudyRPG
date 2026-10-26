import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Scene placeholders (campfire, shop, events) — game.md §10-12, §17
//
// Every scene checks the asset catalog first (`scene_campfire`, `shop_stall`, `shop_keeper`,
// `event_<eventId>`) and only paints these procedural placeholders when the art doesn't exist.

/// 100×100 design grid, aspect-fit and centered, for placeholder scene art.
struct SceneGrid {
    let scale: CGFloat
    let origin: CGPoint

    init(_ size: CGSize) {
        scale = min(size.width, size.height) / 100
        origin = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
    }

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: w * scale, height: h * scale)
    }
    func len(_ v: CGFloat) -> CGFloat { v * scale }
    func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path { Path(ellipseIn: rect(x, y, w, h)) }
    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: rect(x, y, w, h), cornerRadius: len(r))
    }
    func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: p(first.0, first.1))
        for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
        path.closeSubpath()
        return path
    }
    func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) -> Path {
        var path = Path()
        path.move(to: p(a.0, a.1))
        path.addLine(to: p(b.0, b.1))
        return path
    }
    func sparkle(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> Path {
        let k = s * 0.22
        return polygon([(x, y - s), (x + k, y - k), (x + s, y), (x + k, y + k), (x, y + s), (x - k, y + k), (x - s, y), (x - k, y - k)])
    }
    func stroke(_ width: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: len(width), lineCap: .round, lineJoin: .round) }
    func glow(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
        ctx.fill(ellipse(x - r, y - r, r * 2, r * 2), with: .radialGradient(Gradient(colors: [color, .clear]), center: p(x, y), startRadius: 0, endRadius: len(r)))
    }
}

/// Shows `assetName` if it exists in the catalog, otherwise the placeholder.
struct ArtOrPlaceholder<Placeholder: View>: View {
    let assetName: String
    var contentMode: ContentMode = .fit
    @ViewBuilder var placeholder: Placeholder

    var body: some View {
        // Scene art never needs more than a full screen's worth of pixels.
        if let image = ArtCache.thumbnail(assetName, covering: ArtCache.largestScreen) {
            Image(platformImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else {
            placeholder
        }
    }
}

/// Backdrop used by scenes that sit "on the road" (events, campfire): a static forest night.
let roadsideTheme = FightThemeDef(
    id: "roadside", style: .forest, skyTop: "#0c1424", skyBottom: "#2a3a52",
    ground: "#121a14", accent: "#e8e6c8", platform: .grass
)

// MARK: Campfire

/// The party resting around a fire in a forest clearing.
struct CampfireSceneView: View {
    let heroes: [HeroState]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ArtOrPlaceholder(assetName: "scene_campfire", contentMode: .fill) {
                    ZStack {
                        ThemePlaceholderPainting(theme: roadsideTheme)
                        // Warm light pooling around the fire.
                        RadialGradient(colors: [Palette.ember.opacity(0.45), .clear], center: UnitPoint(x: 0.5, y: 0.72), startRadius: 0, endRadius: w * 0.42)
                    }
                }
                .frame(width: w, height: h)
                .clipped()

                // Log bench behind the fire.
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.29, blue: 0.18), Color(red: 0.24, green: 0.16, blue: 0.10)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.42, height: h * 0.06)
                    .position(x: w * 0.5, y: h * 0.78)

                // Heroes on either side, facing the fire, lit warm.
                ForEach(Array(heroes.enumerated()), id: \.element.id) { index, hero in
                    let left = index == 0
                    SpriteView(spriteId: hero.classDef.spriteId, kind: .hero, targetHeight: h * 0.36, breathes: false)
                        .scaleEffect(x: left ? 1 : -1, y: 1)
                        .colorMultiply(Color(red: 1, green: 0.86, blue: 0.70))
                        .shadow(color: Palette.ember.opacity(0.5), radius: 10)
                        .opacity(hero.isAlive ? 1 : 0.5)
                        .position(x: w * (left ? 0.33 : 0.67), y: h * 0.64)
                }

                // Big enough to be the heart of the scene, and lifted clear of the bottom button.
                CampfireFlameView()
                    .frame(width: h * 0.5, height: h * 0.5)
                    .position(x: w * 0.5, y: h * 0.56)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Flickering campfire (the only motion in the campfire scene): crossed glowing logs, layered
/// flame tongues with a white-hot core, a breathing pool of light and sparks drifting up.
/// One Canvas at 24 fps.
struct CampfireFlameView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let g = SceneGrid(size)
                let breathe = 0.85 + 0.15 * sin(t * 2.3) * sin(t * 3.7 + 1)
                g.glow(&ctx, 50, 74, 52 * CGFloat(breathe), Palette.ember.opacity(0.55))

                // Logs: dark wood with glowing ends.
                let wood = GraphicsContext.Shading.color(Color(red: 0.22, green: 0.15, blue: 0.10))
                ctx.fill(g.polygon([(16, 88), (21, 80), (82, 92), (77, 99)]), with: wood)
                ctx.fill(g.polygon([(84, 88), (79, 80), (18, 92), (23, 99)]), with: wood)
                for (x, y) in [(20.0, 84.0), (80.0, 84.0)] as [(CGFloat, CGFloat)] {
                    g.glow(&ctx, x, y, 6, Color(red: 1, green: 0.45, blue: 0.15).opacity(0.7 * breathe))
                }
                for x in [8, 24, 68, 86] as [CGFloat] {
                    ctx.fill(g.ellipse(x, 93, 10, 7), with: .color(Color(red: 0.28, green: 0.28, blue: 0.31)))
                }

                // Flame tongues, back to front, additive so overlaps burn brighter.
                ctx.blendMode = .plusLighter
                func tongue(x: CGFloat, width: CGFloat, height: CGFloat, phase: Double, colors: [Color]) {
                    let flicker = CGFloat(0.82 + 0.18 * sin(t * 7.1 + phase) * sin(t * 4.3 + phase * 2))
                    let fh = height * flicker
                    let sway = CGFloat(sin(t * 2.6 + phase)) * 3 + CGFloat(sin(t * 6.3 + phase)) * 1.2
                    let base: CGFloat = 86
                    var path = Path()
                    path.move(to: g.p(x - width / 2, base))
                    path.addCurve(to: g.p(x + sway, base - fh),
                                  control1: g.p(x - width * 0.62, base - fh * 0.45),
                                  control2: g.p(x - width * 0.18 + sway * 0.5, base - fh * 0.78))
                    path.addCurve(to: g.p(x + width / 2, base),
                                  control1: g.p(x + width * 0.18 + sway * 0.5, base - fh * 0.78),
                                  control2: g.p(x + width * 0.62, base - fh * 0.45))
                    path.closeSubpath()
                    ctx.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: g.p(x, base), endPoint: g.p(x, base - fh)))
                }
                let outer = [Color(red: 0.85, green: 0.25, blue: 0.08).opacity(0.9), Color(red: 0.75, green: 0.18, blue: 0.06).opacity(0.5), .clear]
                let middle = [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.95, green: 0.38, blue: 0.1).opacity(0.6), .clear]
                let core = [Color.white.opacity(0.95), Color(red: 1, green: 0.9, blue: 0.5), Color(red: 1, green: 0.7, blue: 0.25).opacity(0)]
                tongue(x: 40, width: 22, height: 42, phase: 0.4, colors: outer)
                tongue(x: 60, width: 22, height: 46, phase: 2.1, colors: outer)
                tongue(x: 50, width: 36, height: 62, phase: 0, colors: outer)
                tongue(x: 45, width: 20, height: 44, phase: 1.3, colors: middle)
                tongue(x: 56, width: 18, height: 40, phase: 3.0, colors: middle)
                tongue(x: 50, width: 14, height: 30, phase: 2.6, colors: core)

                // Sparks: each rises, sways and fades on its own loop.
                for i in 0..<9 {
                    let seed = Double(i)
                    let period = 1.6 + seed.truncatingRemainder(dividingBy: 4) * 0.35
                    let u = (t / period + seed * 0.37).truncatingRemainder(dividingBy: 1)
                    let x = 50 + CGFloat(sin(seed * 2.7) * 14) + CGFloat(sin(t * 3 + seed) * 4 * u)
                    let y = 70 - CGFloat(u * 66)
                    let r = CGFloat(1.4 * (1 - u) + 0.4)
                    let p = g.p(x, y)
                    let scale = g.scale
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * scale, y: p.y - r * scale, width: r * 2 * scale, height: r * 2 * scale)),
                             with: .color(Color(red: 1, green: 0.75, blue: 0.35).opacity((1 - u) * 0.9)))
                }
            }
        }
    }
}

// MARK: Shop

/// Wooden market stall: plank wall, posts, striped scalloped awning and a lantern.
struct ShopStallBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let wall = CGRect(x: w * 0.04, y: h * 0.16, width: w * 0.92, height: h * 0.84)
            ctx.fill(Path(roundedRect: wall, cornerRadius: 8), with: .color(Color(red: 0.30, green: 0.21, blue: 0.15)))
            for i in 1..<8 {
                let x = wall.minX + wall.width * CGFloat(i) / 8
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: wall.minY)); $0.addLine(to: CGPoint(x: x, y: wall.maxY)) },
                           with: .color(.black.opacity(0.25)), lineWidth: 2)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.3, y: h * 0.1, width: w * 0.4, height: h * 0.8)),
                     with: .radialGradient(Gradient(colors: [Palette.glow.opacity(0.30), .clear]),
                                           center: CGPoint(x: w * 0.5, y: h * 0.45), startRadius: 0, endRadius: w * 0.25))
            for x in [w * 0.04, w * 0.96 - 14] {
                ctx.fill(Path(CGRect(x: x, y: h * 0.1, width: 14, height: h * 0.9)), with: .color(Color(red: 0.50, green: 0.34, blue: 0.20)))
            }
            let stripes = 14
            let stripeW = w / CGFloat(stripes)
            for i in 0..<stripes {
                let x = CGFloat(i) * stripeW
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: 0))
                stripe.addLine(to: CGPoint(x: x + stripeW, y: 0))
                stripe.addLine(to: CGPoint(x: x + stripeW, y: h * 0.13))
                stripe.addQuadCurve(to: CGPoint(x: x, y: h * 0.13), control: CGPoint(x: x + stripeW / 2, y: h * 0.20))
                stripe.closeSubpath()
                ctx.fill(stripe, with: .color(i % 2 == 0 ? Color(red: 0.72, green: 0.30, blue: 0.26) : Color(red: 0.90, green: 0.84, blue: 0.72)))
            }
            let lantern = CGRect(x: w * 0.5 - 9, y: h * 0.13, width: 18, height: 24)
            ctx.fill(Path(roundedRect: lantern, cornerRadius: 4), with: .color(Palette.glow))
            ctx.stroke(Path(roundedRect: lantern, cornerRadius: 4), with: .color(Color(red: 0.36, green: 0.26, blue: 0.18)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

/// A plank shelf for the shop wares.
struct ShopShelf: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(colors: [Color(red: 0.66, green: 0.47, blue: 0.29), Color(red: 0.48, green: 0.33, blue: 0.20)], startPoint: .top, endPoint: .bottom))
            .frame(height: 10)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 3)
    }
}

/// Front counter of the stall.
struct ShopCounter: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(red: 0.58, green: 0.40, blue: 0.24), Color(red: 0.40, green: 0.27, blue: 0.16)], startPoint: .top, endPoint: .bottom))
                .padding(.top, 8)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.66, green: 0.47, blue: 0.29))
                .frame(height: 12)
                .padding(.horizontal, -8)
        }
        .allowsHitTesting(false)
    }
}

/// Friendly hooded alchemist with round glasses holding up a glowing potion.
struct MerchantPlaceholder: View {
    var body: some View {
        Canvas { ctx, size in
            let g = SceneGrid(size)
            func f(_ path: Path, _ color: Color) { ctx.fill(path, with: .color(color)) }
            let robe = Color(red: 0.42, green: 0.32, blue: 0.52)
            let robeDark = Color(red: 0.30, green: 0.22, blue: 0.38)
            let skin = Color(red: 0.92, green: 0.78, blue: 0.64)
            f(g.polygon([(30, 50), (70, 50), (82, 100), (18, 100)]), robe)
            f(g.rounded(40, 60, 20, 40, 3), Color(red: 0.82, green: 0.74, blue: 0.58))
            f(Path(g.rect(40, 66, 20, 3)), Color(red: 0.58, green: 0.42, blue: 0.26))
            f(g.ellipse(26, 10, 48, 50), robeDark)
            f(g.ellipse(34, 18, 32, 34), skin)
            f(g.polygon([(36, 38), (64, 38), (60, 58), (50, 68), (40, 58)]), Color(red: 0.94, green: 0.93, blue: 0.90))
            f(g.ellipse(46.5, 32, 7, 6), Color(red: 0.84, green: 0.64, blue: 0.52))
            f(g.ellipse(41, 27, 4, 4), Palette.ink)
            f(g.ellipse(55, 27, 4, 4), Palette.ink)
            ctx.stroke(g.ellipse(37.5, 23.5, 11, 11), with: .color(Palette.gold), style: g.stroke(1.4))
            ctx.stroke(g.ellipse(51.5, 23.5, 11, 11), with: .color(Palette.gold), style: g.stroke(1.4))
            ctx.stroke(g.line((48.5, 29), (51.5, 29)), with: .color(Palette.gold), style: g.stroke(1.2))
            var smile = Path()
            smile.move(to: g.p(45, 42)); smile.addQuadCurve(to: g.p(55, 42), control: g.p(50, 46))
            ctx.stroke(smile, with: .color(Palette.ink.opacity(0.6)), style: g.stroke(1.2))
            ctx.stroke(g.line((66, 56), (74, 46)), with: .color(robe), style: g.stroke(8))
            f(g.ellipse(70, 40, 9, 9), skin)
            g.glow(&ctx, 78, 30, 12, Color(red: 0.5, green: 0.9, blue: 0.5).opacity(0.6))
            f(g.ellipse(70, 22, 16, 16), Color(red: 0.48, green: 0.82, blue: 0.48))
            f(Path(g.rect(75.5, 14, 5, 9)), Color(red: 0.86, green: 0.90, blue: 0.92))
            f(g.rounded(74.5, 10, 7, 5, 1.5), Color(red: 0.62, green: 0.47, blue: 0.32))
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
    }
}

// MARK: Events

/// An event's painted vignette (`EventArt`, game.md §12), used when there's no `event_<id>` art.
struct EventScenePlaceholder: View {
    let scene: EventScene

    var body: some View {
        Canvas { ctx, size in
            EventArt.draw(scene, in: &ctx, rect: CGRect(origin: .zero, size: size))
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
    }
}

/// An event's illustration: `event_<id>` art if it exists, otherwise the colored vector scene.
struct EventSceneView: View {
    let event: EventDef

    var body: some View {
        ArtOrPlaceholder(assetName: "event_\(event.id)") {
            EventScenePlaceholder(scene: event.scene)
        }
    }
}

/// Procedural vector treasure chest overflowing with gold, shown on the Victory screen.
struct VictoryTreasureIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let g = SceneGrid(size)
            let ink = Color(red: 0.08, green: 0.07, blue: 0.09)
            let wood = Color(red: 0.46, green: 0.30, blue: 0.18)
            let woodDark = Color(red: 0.28, green: 0.18, blue: 0.11)
            let iron = Color(red: 0.28, green: 0.30, blue: 0.35)
            func fill(_ path: Path, _ color: Color, outline: CGFloat = 1.4) {
                ctx.fill(path, with: .color(color))
                if outline > 0 { ctx.stroke(path, with: .color(ink), style: g.stroke(outline)) }
            }

            g.glow(&ctx, 50, 54, 44, Palette.goldGlow.opacity(0.45))
            // Open chest lid at the back
            fill(g.rounded(18, 20, 64, 28, 5), woodDark)
            fill(g.rounded(26, 18, 6, 30, 1), iron, outline: 1.0)
            fill(g.rounded(68, 18, 6, 30, 1), iron, outline: 1.0)
            // Overflowing mound of gold coins & gems
            fill(g.ellipse(20, 36, 60, 26), Palette.gold)
            for (cx, cy, cr) in [(30.0, 42.0, 8.0), (42.0, 38.0, 9.0), (54.0, 40.0, 9.0), (65.0, 43.0, 8.0), (36.0, 46.0, 8.0), (48.0, 45.0, 9.0), (60.0, 46.0, 8.0)] {
                fill(g.ellipse(cx, cy, cr, cr * 0.75), Palette.goldGlow, outline: 0.9)
            }
            // Ruby gem in the hoard
            fill(g.polygon([(50, 32), (56, 39), (50, 46), (44, 39)]), Palette.crimson, outline: 1.0)
            // Front chest body & iron bands
            fill(g.rounded(16, 48, 68, 38, 4), wood)
            fill(g.rounded(25, 48, 6, 38, 1), iron, outline: 1.0)
            fill(g.rounded(69, 48, 6, 38, 1), iron, outline: 1.0)
            fill(g.rounded(43, 46, 14, 18, 2.5), Palette.gold, outline: 1.2)
            ctx.fill(g.ellipse(48, 52, 4, 4), with: .color(ink))
            for (sx, sy, ss) in [(22.0, 26.0, 4.5), (78.0, 24.0, 5.0), (50.0, 12.0, 4.0)] {
                ctx.fill(g.sparkle(sx, sy, ss), with: .color(Palette.goldGlow))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
    }
}
