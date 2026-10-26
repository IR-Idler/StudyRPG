import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Static scene backdrops (game.md §7.6, §17)

extension Color {
    /// `#RRGGBB` from content JSON (validated at load time; falls back to magenta so a bad value is obvious).
    init(hex: String) {
        if let rgb = HexColor.parse(hex) {
            self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
        } else {
            self.init(red: 1, green: 0, blue: 1)
        }
    }

    /// Linear mix toward `other` (0 = self, 1 = other). Uses resolved RGB so it works in Canvas.
    func mixed(with other: Color, _ amount: Double) -> Color {
        let a = rgbaComponents, b = other.rgbaComponents
        let t = CGFloat(amount)
        return Color(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t, blue: a.blue + (b.blue - a.blue) * t)
    }
}

/// A fight's stage: `bg_<themeId>` art if it exists, otherwise a static procedural placeholder in
/// the theme's style. Never moves — fights are static scenes.
struct FightBackdrop: View {
    let theme: FightThemeDef?

    var body: some View {
        if let theme, let art = ArtCache.thumbnail("bg_\(theme.id)", covering: ArtCache.largestScreen) {
            Image(platformImage: art)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            ThemePlaceholderPainting(theme: theme ?? FightBackdrop.fallback)
                .ignoresSafeArea()
        }
    }

    static let fallback = FightThemeDef(
        id: "fallback", style: .forest, skyTop: "#0e1626", skyBottom: "#2b3d55",
        ground: "#14201a", accent: "#e8e6c8", platform: .grass
    )
}

/// Calm, static night backdrop for menus, lists and sheets — no art assets, no motion.
struct SceneryBackground: View {
    var body: some View {
        ThemePlaceholderPainting(theme: SceneryBackground.theme)
            .ignoresSafeArea()
    }

    static let theme = FightThemeDef(
        id: "menu", style: .mountain, skyTop: "#0b1220", skyBottom: "#25324a",
        ground: "#0e131c", accent: "#e8e6c8", platform: .grass
    )
}

/// Procedural, flat-shaded placeholder painting for a fight theme. Drawn once in a single Canvas
/// (cheap; only redraws if the size or theme changes). Deterministic, so a theme always looks
/// the same.
struct ThemePlaceholderPainting: View {
    let theme: FightThemeDef

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            ThemePainter(theme: theme, size: size).paint(&ctx)
        }
        .allowsHitTesting(false)
    }
}

private struct ThemePainter {
    let theme: FightThemeDef
    let size: CGSize

    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    /// Where the painted ground starts.
    var horizon: CGFloat { h * 0.60 }
    var sky0: Color { Color(hex: theme.skyTop) }
    var sky1: Color { Color(hex: theme.skyBottom) }
    var ground: Color { Color(hex: theme.ground) }
    var accent: Color { Color(hex: theme.accent) }

    func paint(_ ctx: inout GraphicsContext) {
        var rng = LinearCongruentialGenerator(seed: UInt64(abs(theme.id.hashValueStable)))
        // Sky
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [sky0, sky1]), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        switch theme.style {
        case .forest:
            stars(&ctx, &rng, count: 50); moon(&ctx, at: CGPoint(x: w * 0.80, y: h * 0.17))
            pineLayer(&ctx, &rng, baseY: horizon - h * 0.02, height: h * 0.20, color: sky1.mixed(with: ground, 0.45), count: 26)
            pineLayer(&ctx, &rng, baseY: horizon + h * 0.02, height: h * 0.27, color: sky1.mixed(with: ground, 0.75), count: 18)
            groundBand(&ctx)
            mist(&ctx, y: horizon, color: accent.opacity(0.10))
        case .camp:
            stars(&ctx, &rng, count: 40)
            pineLayer(&ctx, &rng, baseY: horizon, height: h * 0.24, color: sky1.mixed(with: ground, 0.6), count: 24)
            groundBand(&ctx)
            glow(&ctx, at: CGPoint(x: w * 0.50, y: horizon + h * 0.02), radius: w * 0.22, color: accent.opacity(0.35))
            tent(&ctx, center: CGPoint(x: w * 0.36, y: horizon + h * 0.03), width: w * 0.12, color: Color(red: 0.42, green: 0.30, blue: 0.20))
            tent(&ctx, center: CGPoint(x: w * 0.64, y: horizon + h * 0.01), width: w * 0.10, color: Color(red: 0.36, green: 0.27, blue: 0.22))
            fireSpot(&ctx, at: CGPoint(x: w * 0.50, y: horizon + h * 0.04))
        case .graveyard:
            stars(&ctx, &rng, count: 30); moon(&ctx, at: CGPoint(x: w * 0.22, y: h * 0.18))
            hills(&ctx, baseY: horizon, color: sky1.mixed(with: ground, 0.6))
            deadTree(&ctx, base: CGPoint(x: w * 0.83, y: horizon + h * 0.02), height: h * 0.40, color: ground.mixed(with: .black, 0.3))
            groundBand(&ctx)
            tombstones(&ctx, &rng, y: horizon + h * 0.03)
            fence(&ctx, y: horizon - h * 0.005)
            mist(&ctx, y: horizon + h * 0.04, color: accent.opacity(0.14))
        case .ruins:
            stars(&ctx, &rng, count: 40); moon(&ctx, at: CGPoint(x: w * 0.75, y: h * 0.16))
            hills(&ctx, baseY: horizon, color: sky1.mixed(with: ground, 0.55))
            groundBand(&ctx)
            columns(&ctx, &rng, y: horizon + h * 0.02, color: sky1.mixed(with: .white, 0.18))
            mist(&ctx, y: horizon + h * 0.02, color: accent.opacity(0.14))
        case .cave:
            caveInterior(&ctx, &rng, crystals: true, lava: false)
        case .crypt:
            cryptInterior(&ctx, &rng)
        case .mountain:
            stars(&ctx, &rng, count: 60); moon(&ctx, at: CGPoint(x: w * 0.82, y: h * 0.15))
            peaks(&ctx, &rng, baseY: horizon, height: h * 0.42, color: sky1.mixed(with: ground, 0.25), snow: accent.opacity(0.75), count: 5)
            peaks(&ctx, &rng, baseY: horizon + h * 0.04, height: h * 0.30, color: sky1.mixed(with: ground, 0.6), snow: accent.opacity(0.55), count: 7)
            groundBand(&ctx)
            mist(&ctx, y: horizon, color: accent.opacity(0.08))
        case .swamp:
            stars(&ctx, &rng, count: 20)
            deadTree(&ctx, base: CGPoint(x: w * 0.12, y: horizon + h * 0.02), height: h * 0.45, color: ground.mixed(with: .black, 0.2))
            deadTree(&ctx, base: CGPoint(x: w * 0.88, y: horizon), height: h * 0.36, color: ground.mixed(with: .black, 0.1))
            groundBand(&ctx)
            water(&ctx, y: horizon + h * 0.04)
            reeds(&ctx, &rng, y: horizon + h * 0.05)
            mist(&ctx, y: horizon - h * 0.02, color: accent.opacity(0.16))
            fireflies(&ctx, &rng)
        case .lair:
            caveInterior(&ctx, &rng, crystals: false, lava: true)
        case .future:
            futureCity(&ctx, &rng)
        }

        // Darken toward the bottom so the console and platforms always read.
        ctx.fill(Path(CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45)), with: .linearGradient(
            Gradient(colors: [.clear, Color.black.opacity(0.55)]),
            startPoint: CGPoint(x: 0, y: h * 0.55), endPoint: CGPoint(x: 0, y: h)))
    }

    // MARK: Act II — the future (game.md §16)

    /// A clean night skyline: two layers of towers with lit windows, a neon line on the horizon,
    /// then a dark floor with a glowing perspective grid.
    func futureCity(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator) {
        stars(&ctx, &rng, count: 25)
        // Far towers: thin, pale, few lights.
        var x: CGFloat = -10
        while x < w {
            let tw = rng.next(in: 18...42), th = rng.next(in: h * 0.10...h * 0.30)
            let rect = CGRect(x: x, y: horizon - th, width: tw, height: th)
            ctx.fill(Path(rect), with: .color(sky1.mixed(with: ground, 0.35)))
            x += tw + rng.next(in: 2...10)
        }
        // Near towers: taller, with rows of lit windows and a beacon on top.
        x = -20
        while x < w {
            let tw = rng.next(in: 34...70), th = rng.next(in: h * 0.18...h * 0.44)
            let rect = CGRect(x: x, y: horizon - th, width: tw, height: th)
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [ground.mixed(with: sky1, 0.5), ground]),
                                                       startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            ctx.stroke(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1)), with: .color(accent.opacity(0.45)), lineWidth: 1)
            var wy = rect.minY + 8
            while wy < rect.maxY - 6 {
                var wx = rect.minX + 5
                while wx < rect.maxX - 6 {
                    if rng.next(in: 0...1) < 0.32 {
                        ctx.fill(Path(CGRect(x: wx, y: wy, width: 3, height: 2)), with: .color(accent.opacity(Double(rng.next(in: 0.35...0.9)))))
                    }
                    wx += 7
                }
                wy += 7
            }
            if rng.next(in: 0...1) < 0.4 {
                glow(&ctx, at: CGPoint(x: rect.midX, y: rect.minY - 3), radius: 7, color: Color(red: 1, green: 0.3, blue: 0.35).opacity(0.8))
            }
            x += tw + rng.next(in: 6...24)
        }
        // Neon horizon and a dark, glossy floor with a glowing perspective grid.
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)), with: .linearGradient(
            Gradient(colors: [ground.mixed(with: sky1, 0.3), ground]), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
        glow(&ctx, at: CGPoint(x: w * 0.5, y: horizon), radius: w * 0.45, color: accent.opacity(0.16))
        ctx.stroke(Path(CGRect(x: 0, y: horizon, width: w, height: 0.5)), with: .color(accent.opacity(0.9)), lineWidth: 2)
        let vanishing = CGPoint(x: w * 0.5, y: horizon - h * 0.12)
        for i in -12...12 {
            var line = Path()
            let bottomX = w * 0.5 + CGFloat(i) * w * 0.09
            let t = (horizon - vanishing.y) / (h - vanishing.y)
            line.move(to: CGPoint(x: vanishing.x + (bottomX - vanishing.x) * t, y: horizon))
            line.addLine(to: CGPoint(x: bottomX, y: h))
            ctx.stroke(line, with: .color(accent.opacity(0.22)), lineWidth: 1)
        }
        var rowY = horizon + 4.0
        var gap: CGFloat = 4
        while rowY < h {
            ctx.stroke(Path(CGRect(x: 0, y: rowY, width: w, height: 0.5)), with: .color(accent.opacity(0.18)), lineWidth: 1)
            gap *= 1.35
            rowY += gap
        }
    }

    // MARK: Building blocks

    func stars(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator, count: Int) {
        for _ in 0..<count {
            let x = rng.next(in: 0...w), y = rng.next(in: 0...horizon * 0.8), r = rng.next(in: 0.6...1.8)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(Palette.goldGlow.opacity(Double(rng.next(in: 0.25...0.8)))))
        }
    }

    func moon(_ ctx: inout GraphicsContext, at p: CGPoint) {
        glow(&ctx, at: p, radius: 70, color: accent.opacity(0.22))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)), with: .radialGradient(
            Gradient(colors: [.white, accent]), center: CGPoint(x: p.x - 6, y: p.y - 6), startRadius: 2, endRadius: 26))
    }

    func glow(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                 with: .radialGradient(Gradient(colors: [color, .clear]), center: p, startRadius: 0, endRadius: radius))
    }

    func groundBand(_ ctx: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: horizon + h * 0.01))
        path.addCurve(to: CGPoint(x: w, y: horizon - h * 0.01),
                      control1: CGPoint(x: w * 0.3, y: horizon - h * 0.03),
                      control2: CGPoint(x: w * 0.7, y: horizon + h * 0.03))
        path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.closeSubpath()
        ctx.fill(path, with: .linearGradient(Gradient(colors: [ground.mixed(with: sky1, 0.25), ground]),
                                             startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
    }

    func mist(_ ctx: inout GraphicsContext, y: CGFloat, color: Color) {
        ctx.fill(Path(CGRect(x: 0, y: y - h * 0.08, width: w, height: h * 0.16)), with: .linearGradient(
            Gradient(colors: [.clear, color, .clear]), startPoint: CGPoint(x: 0, y: y - h * 0.08), endPoint: CGPoint(x: 0, y: y + h * 0.08)))
    }

    func pineLayer(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator, baseY: CGFloat, height: CGFloat, color: Color, count: Int) {
        for i in 0..<count {
            let x = w * (CGFloat(i) + rng.next(in: 0...0.8)) / CGFloat(count - 1) - w * 0.03
            let th = height * rng.next(in: 0.6...1.1), tw = th * 0.42
            var tree = Path()
            tree.move(to: CGPoint(x: x, y: baseY - th))
            for tier in 0..<3 {
                let t = CGFloat(tier + 1) / 3
                tree.addLine(to: CGPoint(x: x + tw * 0.5 * t, y: baseY - th + th * t * 0.95))
                tree.addLine(to: CGPoint(x: x + tw * 0.18 * t, y: baseY - th + th * t * 0.95))
            }
            tree.addLine(to: CGPoint(x: x + tw * 0.06, y: baseY + 4))
            tree.addLine(to: CGPoint(x: x - tw * 0.06, y: baseY + 4))
            for tier in (0..<3).reversed() {
                let t = CGFloat(tier + 1) / 3
                tree.addLine(to: CGPoint(x: x - tw * 0.18 * t, y: baseY - th + th * t * 0.95))
                tree.addLine(to: CGPoint(x: x - tw * 0.5 * t, y: baseY - th + th * t * 0.95))
            }
            tree.closeSubpath()
            ctx.fill(tree, with: .color(color))
        }
    }

    func hills(_ ctx: inout GraphicsContext, baseY: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseY))
        path.addCurve(to: CGPoint(x: w * 0.5, y: baseY - h * 0.05), control1: CGPoint(x: w * 0.15, y: baseY - h * 0.14), control2: CGPoint(x: w * 0.35, y: baseY - h * 0.02))
        path.addCurve(to: CGPoint(x: w, y: baseY - h * 0.03), control1: CGPoint(x: w * 0.65, y: baseY - h * 0.12), control2: CGPoint(x: w * 0.85, y: baseY - h * 0.10))
        path.addLine(to: CGPoint(x: w, y: baseY + h * 0.05)); path.addLine(to: CGPoint(x: 0, y: baseY + h * 0.05)); path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    func peaks(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator, baseY: CGFloat, height: CGFloat, color: Color, snow: Color, count: Int) {
        for i in 0..<count {
            let cx = w * (CGFloat(i) + rng.next(in: 0.1...0.9)) / CGFloat(count)
            let ph = height * rng.next(in: 0.6...1.0), pw = ph * rng.next(in: 1.2...1.8)
            let top = CGPoint(x: cx, y: baseY - ph)
            var mountain = Path()
            mountain.move(to: CGPoint(x: cx - pw / 2, y: baseY + 2))
            mountain.addLine(to: top)
            mountain.addLine(to: CGPoint(x: cx + pw / 2, y: baseY + 2))
            mountain.closeSubpath()
            ctx.fill(mountain, with: .color(color))
            var cap = Path()
            cap.move(to: top)
            cap.addLine(to: CGPoint(x: cx + pw * 0.14, y: top.y + ph * 0.28))
            cap.addLine(to: CGPoint(x: cx + pw * 0.04, y: top.y + ph * 0.22))
            cap.addLine(to: CGPoint(x: cx - pw * 0.04, y: top.y + ph * 0.31))
            cap.addLine(to: CGPoint(x: cx - pw * 0.14, y: top.y + ph * 0.27))
            cap.closeSubpath()
            ctx.fill(cap, with: .color(snow))
        }
    }

    func deadTree(_ ctx: inout GraphicsContext, base: CGPoint, height: CGFloat, color: Color) {
        let style = StrokeStyle(lineWidth: height * 0.05, lineCap: .round, lineJoin: .round)
        var trunk = Path()
        trunk.move(to: base); trunk.addQuadCurve(to: CGPoint(x: base.x + height * 0.05, y: base.y - height), control: CGPoint(x: base.x - height * 0.08, y: base.y - height * 0.5))
        ctx.stroke(trunk, with: .color(color), style: style)
        let branches: [(CGFloat, CGFloat, CGFloat)] = [(0.45, -0.28, -0.18), (0.6, 0.25, -0.2), (0.78, -0.18, -0.14), (0.88, 0.16, -0.1)]
        for (t, dx, dy) in branches {
            let start = CGPoint(x: base.x + height * 0.02, y: base.y - height * t)
            var branch = Path()
            branch.move(to: start)
            branch.addQuadCurve(to: CGPoint(x: start.x + height * dx, y: start.y + height * dy), control: CGPoint(x: start.x + height * dx * 0.4, y: start.y + height * dy * 0.1))
            ctx.stroke(branch, with: .color(color), style: StrokeStyle(lineWidth: height * 0.022, lineCap: .round))
        }
    }

    func tombstones(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator, y: CGFloat) {
        let stone = sky1.mixed(with: .white, 0.22)
        for i in 0..<9 {
            let x = w * (0.05 + CGFloat(i) * 0.11) + rng.next(in: -10...10)
            let sh = h * rng.next(in: 0.05...0.09), sw = sh * 0.6
            let tilt = Angle.degrees(Double(rng.next(in: -8...8)))
            var c = ctx
            c.translateBy(x: x, y: y)
            c.rotate(by: tilt)
            if i % 3 == 1 {
                c.fill(Path(CGRect(x: -sw * 0.12, y: -sh, width: sw * 0.24, height: sh)), with: .color(stone))
                c.fill(Path(CGRect(x: -sw * 0.4, y: -sh * 0.75, width: sw * 0.8, height: sh * 0.18)), with: .color(stone))
            } else {
                c.fill(Path(roundedRect: CGRect(x: -sw / 2, y: -sh, width: sw, height: sh), cornerSize: CGSize(width: sw / 2, height: sw / 2)), with: .color(stone))
                c.fill(Path(CGRect(x: -sw / 2, y: -sh * 0.2, width: sw, height: sh * 0.2)), with: .color(stone.mixed(with: .black, 0.3)))
            }
        }
    }

    func fence(_ ctx: inout GraphicsContext, y: CGFloat) {
        let iron = Color.black.opacity(0.55)
        ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y - h * 0.05)); $0.addLine(to: CGPoint(x: w, y: y - h * 0.05)) }, with: .color(iron), lineWidth: 2)
        for x in stride(from: CGFloat(4), to: w, by: 14) {
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: y)); $0.addLine(to: CGPoint(x: x, y: y - h * 0.08)) }, with: .color(iron), lineWidth: 2)
        }
    }

    func columns(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator, y: CGFloat, color: Color) {
        for (i, fx) in [0.08, 0.22, 0.40, 0.62, 0.80, 0.94].enumerated() {
            let cw = w * 0.035, full = h * 0.38
            let ch = i % 2 == 0 ? full * rng.next(in: 0.4...0.75) : full
            let x = w * fx
            ctx.fill(Path(CGRect(x: x - cw / 2, y: y - ch, width: cw, height: ch)), with: .color(color))
            for f in stride(from: CGFloat(0.25), to: 1, by: 0.25) {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x - cw / 2 + cw * f, y: y - ch)); $0.addLine(to: CGPoint(x: x - cw / 2 + cw * f, y: y)) },
                           with: .color(Color.black.opacity(0.15)), lineWidth: 1)
            }
            ctx.fill(Path(CGRect(x: x - cw * 0.75, y: y - ch - 6, width: cw * 1.5, height: 6)), with: .color(color))
            // Broken top
            if i % 2 == 0 {
                var broken = Path()
                broken.move(to: CGPoint(x: x - cw / 2, y: y - ch))
                broken.addLine(to: CGPoint(x: x - cw * 0.1, y: y - ch - 10))
                broken.addLine(to: CGPoint(x: x + cw * 0.2, y: y - ch - 3))
                broken.addLine(to: CGPoint(x: x + cw / 2, y: y - ch - 8))
                broken.addLine(to: CGPoint(x: x + cw / 2, y: y - ch))
                ctx.fill(broken, with: .color(color))
            }
            // Ivy
            for k in 0..<5 {
                let iy = y - ch * rng.next(in: 0.1...0.9)
                ctx.fill(Path(ellipseIn: CGRect(x: x - cw / 2 + CGFloat(k % 2) * cw * 0.6, y: iy, width: 6, height: 4)), with: .color(Color(red: 0.25, green: 0.38, blue: 0.22)))
            }
        }
        // Arch between the middle columns
        var arch = Path()
        arch.move(to: CGPoint(x: w * 0.22, y: y - h * 0.38))
        arch.addQuadCurve(to: CGPoint(x: w * 0.40, y: y - h * 0.38), control: CGPoint(x: w * 0.31, y: y - h * 0.50))
        ctx.stroke(arch, with: .color(color), lineWidth: w * 0.02)
    }

    func caveInterior(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator, crystals: Bool, lava: Bool) {
        let rock = ground.mixed(with: sky1, 0.3)
        groundBand(&ctx)
        if lava {
            glow(&ctx, at: CGPoint(x: w * 0.5, y: horizon + h * 0.08), radius: w * 0.45, color: accent.opacity(0.35))
            var pool = Path(ellipseIn: CGRect(x: w * 0.25, y: horizon + h * 0.02, width: w * 0.5, height: h * 0.07))
            ctx.fill(pool, with: .linearGradient(Gradient(colors: [accent, accent.mixed(with: .red, 0.5)]), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: horizon + h * 0.09)))
            pool = Path(ellipseIn: CGRect(x: w * 0.32, y: horizon + h * 0.035, width: w * 0.36, height: h * 0.03))
            ctx.fill(pool, with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.7)))
            for _ in 0..<30 {
                let p = CGPoint(x: rng.next(in: 0...w), y: rng.next(in: h * 0.1...horizon))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 2.5, height: 2.5)), with: .color(accent.opacity(Double(rng.next(in: 0.3...0.9)))))
            }
        }
        // Ceiling with stalactites
        var ceiling = Path()
        ceiling.move(to: .zero)
        ceiling.addLine(to: CGPoint(x: w, y: 0))
        var x = w
        while x > 0 {
            let step = rng.next(in: w * 0.03...w * 0.08)
            let drop = rng.next(in: h * 0.04...h * 0.20)
            ceiling.addLine(to: CGPoint(x: x - step * 0.5, y: drop))
            ceiling.addLine(to: CGPoint(x: x - step, y: h * 0.03))
            x -= step
        }
        ceiling.closeSubpath()
        ctx.fill(ceiling, with: .color(rock.mixed(with: .black, 0.35)))
        // Side walls
        for left in [true, false] {
            var wall = Path()
            let edge: CGFloat = left ? 0 : w
            let inward: CGFloat = left ? 1 : -1
            wall.move(to: CGPoint(x: edge, y: 0))
            wall.addLine(to: CGPoint(x: edge + inward * w * 0.10, y: h * 0.15))
            wall.addLine(to: CGPoint(x: edge + inward * w * 0.06, y: h * 0.35))
            wall.addLine(to: CGPoint(x: edge + inward * w * 0.13, y: h * 0.55))
            wall.addLine(to: CGPoint(x: edge + inward * w * 0.08, y: h))
            wall.addLine(to: CGPoint(x: edge, y: h))
            wall.closeSubpath()
            ctx.fill(wall, with: .color(rock.mixed(with: .black, 0.25)))
        }
        // Rock spires
        for fx in [0.22, 0.78] as [CGFloat] {
            var spire = Path()
            spire.move(to: CGPoint(x: w * fx - w * 0.04, y: horizon + 4))
            spire.addLine(to: CGPoint(x: w * fx, y: horizon - h * 0.22))
            spire.addLine(to: CGPoint(x: w * fx + w * 0.035, y: horizon + 4))
            spire.closeSubpath()
            ctx.fill(spire, with: .color(rock))
        }
        if crystals {
            for (fx, fy, s) in [(0.12, 0.42, 1.0), (0.86, 0.36, 0.8), (0.30, 0.56, 0.6), (0.70, 0.55, 0.7)] as [(CGFloat, CGFloat, CGFloat)] {
                let base = CGPoint(x: w * fx, y: h * fy)
                glow(&ctx, at: base, radius: 46 * s, color: accent.opacity(0.35))
                for (dx, ch) in [(-8.0, 26.0), (0.0, 38.0), (9.0, 22.0)] as [(CGFloat, CGFloat)] {
                    var crystal = Path()
                    crystal.move(to: CGPoint(x: base.x + dx * s - 4 * s, y: base.y))
                    crystal.addLine(to: CGPoint(x: base.x + dx * s, y: base.y - ch * s))
                    crystal.addLine(to: CGPoint(x: base.x + dx * s + 4 * s, y: base.y))
                    crystal.closeSubpath()
                    ctx.fill(crystal, with: .color(accent.opacity(0.85)))
                }
            }
        }
        if lava {
            // Bones scattered on the floor
            for fx in [0.12, 0.85, 0.66] as [CGFloat] {
                let p = CGPoint(x: w * fx, y: horizon + h * 0.10)
                ctx.stroke(Path { $0.move(to: CGPoint(x: p.x - 10, y: p.y)); $0.addLine(to: CGPoint(x: p.x + 10, y: p.y - 3)) }, with: .color(Color(white: 0.8).opacity(0.6)), lineWidth: 3)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x + 12, y: p.y - 10, width: 10, height: 9)), with: .color(Color(white: 0.8).opacity(0.6)))
            }
        }
    }

    func cryptInterior(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator) {
        let brick = sky1.mixed(with: ground, 0.3)
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)), with: .color(brick))
        let rowH = h * 0.045
        var row = 0
        var y: CGFloat = 0
        while y < horizon {
            let offset = row % 2 == 0 ? 0 : w * 0.035
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: w, y: y)) }, with: .color(Color.black.opacity(0.35)), lineWidth: 1)
            var x = offset
            while x < w {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: y)); $0.addLine(to: CGPoint(x: x, y: y + rowH)) }, with: .color(Color.black.opacity(0.3)), lineWidth: 1)
                x += w * 0.07
            }
            y += rowH; row += 1
        }
        // Dark arched alcoves
        for fx in [0.2, 0.5, 0.8] as [CGFloat] {
            var arch = Path()
            let aw = w * 0.14, top = horizon - h * 0.36
            arch.move(to: CGPoint(x: w * fx - aw / 2, y: horizon))
            arch.addLine(to: CGPoint(x: w * fx - aw / 2, y: top + aw / 2))
            arch.addArc(center: CGPoint(x: w * fx, y: top + aw / 2), radius: aw / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            arch.addLine(to: CGPoint(x: w * fx + aw / 2, y: horizon))
            arch.closeSubpath()
            ctx.fill(arch, with: .color(Color.black.opacity(0.55)))
        }
        // Torches between the alcoves
        for fx in [0.35, 0.65] as [CGFloat] {
            let p = CGPoint(x: w * fx, y: horizon - h * 0.26)
            glow(&ctx, at: p, radius: w * 0.10, color: accent.opacity(0.45))
            ctx.fill(Path(CGRect(x: p.x - 2, y: p.y, width: 4, height: 18)), with: .color(Color(red: 0.3, green: 0.2, blue: 0.12)))
            var flame = Path()
            flame.move(to: CGPoint(x: p.x - 6, y: p.y))
            flame.addQuadCurve(to: CGPoint(x: p.x, y: p.y - 16), control: CGPoint(x: p.x - 6, y: p.y - 10))
            flame.addQuadCurve(to: CGPoint(x: p.x + 6, y: p.y), control: CGPoint(x: p.x + 6, y: p.y - 10))
            flame.closeSubpath()
            ctx.fill(flame, with: .color(accent))
        }
        // Stone floor
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)), with: .linearGradient(
            Gradient(colors: [ground.mixed(with: sky1, 0.3), ground]), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
        for i in 0..<8 {
            let fy = horizon + (h - horizon) * CGFloat(i) / 8
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: fy)); $0.addLine(to: CGPoint(x: w, y: fy)) }, with: .color(Color.black.opacity(0.2)), lineWidth: 1)
        }
    }

    func water(_ ctx: inout GraphicsContext, y: CGFloat) {
        let rect = CGRect(x: 0, y: y, width: w, height: h * 0.10)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [sky1.mixed(with: accent, 0.15).opacity(0.8), ground]), startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: rect.maxY)))
        for i in 0..<10 {
            let x = w * CGFloat(i) / 10 + 10
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: y + h * 0.03 + CGFloat(i % 3) * 6)); $0.addLine(to: CGPoint(x: x + 28, y: y + h * 0.03 + CGFloat(i % 3) * 6)) },
                       with: .color(accent.opacity(0.25)), lineWidth: 1)
        }
    }

    func reeds(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator, y: CGFloat) {
        for _ in 0..<40 {
            let x = rng.next(in: 0...w), rh = rng.next(in: h * 0.04...h * 0.10)
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: y)); $0.addQuadCurve(to: CGPoint(x: x + rng.next(in: -6...6), y: y - rh), control: CGPoint(x: x, y: y - rh * 0.5)) },
                       with: .color(ground.mixed(with: accent, 0.15)), lineWidth: 1.5)
        }
    }

    func fireflies(_ ctx: inout GraphicsContext, _ rng: inout LinearCongruentialGenerator) {
        for _ in 0..<16 {
            let p = CGPoint(x: rng.next(in: 0...w), y: rng.next(in: h * 0.25...horizon + h * 0.05))
            glow(&ctx, at: p, radius: 6, color: accent.opacity(0.7))
        }
    }

    func tent(_ ctx: inout GraphicsContext, center: CGPoint, width: CGFloat, color: Color) {
        var tent = Path()
        tent.move(to: CGPoint(x: center.x - width / 2, y: center.y))
        tent.addLine(to: CGPoint(x: center.x, y: center.y - width * 0.7))
        tent.addLine(to: CGPoint(x: center.x + width / 2, y: center.y))
        tent.closeSubpath()
        ctx.fill(tent, with: .color(color))
        var door = Path()
        door.move(to: CGPoint(x: center.x - width * 0.12, y: center.y))
        door.addLine(to: CGPoint(x: center.x, y: center.y - width * 0.35))
        door.addLine(to: CGPoint(x: center.x + width * 0.12, y: center.y))
        door.closeSubpath()
        ctx.fill(door, with: .color(Color.black.opacity(0.5)))
    }

    func fireSpot(_ ctx: inout GraphicsContext, at p: CGPoint) {
        var flame = Path()
        flame.move(to: CGPoint(x: p.x - 10, y: p.y))
        flame.addQuadCurve(to: CGPoint(x: p.x, y: p.y - 24), control: CGPoint(x: p.x - 10, y: p.y - 14))
        flame.addQuadCurve(to: CGPoint(x: p.x + 10, y: p.y), control: CGPoint(x: p.x + 10, y: p.y - 14))
        flame.closeSubpath()
        ctx.fill(flame, with: .color(accent))
    }
}

private extension String {
    /// Stable across launches (Swift's `hashValue` is randomly seeded per process).
    var hashValueStable: Int {
        var hash = 5381
        for byte in utf8 { hash = (hash &* 33) &+ Int(byte) }
        return hash
    }
}
