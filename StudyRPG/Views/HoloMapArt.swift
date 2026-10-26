import SwiftUI

// MARK: - Act II holographic map (game.md §9, §16)
//
// The future act's run map: instead of a parchment sheet on a wooden table, a glowing holographic
// sheet floating over a dark console. Same layout, roads and places as the parchment map
// (`WorldMapLayout`, `RoadCurve`); only the painting differs. Static, like the rest of the map.

enum HoloPalette {
    static let cyan = Color(red: 0.30, green: 0.88, blue: 1.0)
    static let deep = Color(red: 0.03, green: 0.07, blue: 0.13)
    static let glass = Color(red: 0.05, green: 0.12, blue: 0.20)
    static let mint = Color(red: 0.42, green: 1.0, blue: 0.80)
    static let alert = Color(red: 1.0, green: 0.32, blue: 0.40)
}

/// The dark console the holo-sheet floats over: brushed gunmetal with panel seams and a soft
/// cyan underglow. Replaces the wooden tabletop in Act II.
struct HoloConsoleSurfaceView: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.13), Color(red: 0.03, green: 0.04, blue: 0.06)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // Brushed-metal streaks.
            var rng = LinearCongruentialGenerator(seed: 41)
            for _ in 0..<Int(h / 3) {
                let y = rng.next(in: 0...h)
                ctx.stroke(Path(CGRect(x: 0, y: y, width: w, height: 0.5)), with: .color(Color.white.opacity(Double(rng.next(in: 0.01...0.035)))), lineWidth: 0.6)
            }
            // Panel seams with tiny status lights.
            for fx in stride(from: 0.0, through: 1.0, by: 0.25) {
                let x = w * CGFloat(fx)
                ctx.stroke(Path(CGRect(x: x, y: 0, width: 0.5, height: h)), with: .color(Color.black.opacity(0.6)), lineWidth: 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: x + 6, y: h - 14, width: 4, height: 4)), with: .color(HoloPalette.mint.opacity(0.7)))
            }
            // Underglow from the projected sheet.
            ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.1, y: h * 0.1, width: w * 1.2, height: h * 0.8)),
                     with: .radialGradient(Gradient(colors: [HoloPalette.cyan.opacity(0.14), .clear]),
                                           center: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endRadius: max(w, h) * 0.6))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The holo-sheet's painting (rasterized once per map height, like `WorldMapTerrain`): deep glass
/// with a fine cyan grid and scanlines, circuit traces and a data stream winding across, city
/// blocks along the way, a ring of towers around the boss's reactor glow, and HUD corner brackets.
/// Uses `map_future_tower` / `map_future_block` art if it exists, else draws them.
struct HoloMapTerrain: View {
    let layout: WorldMapLayout
    let height: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [HoloPalette.glass, HoloPalette.deep]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

            // Fine grid + every fifth line brighter.
            let cell: CGFloat = 24
            var index = 0
            for x in stride(from: CGFloat(0), through: w, by: cell) {
                ctx.stroke(Path(CGRect(x: x, y: 0, width: 0.5, height: h)), with: .color(HoloPalette.cyan.opacity(index % 5 == 0 ? 0.16 : 0.06)), lineWidth: 0.6)
                index += 1
            }
            index = 0
            for y in stride(from: CGFloat(0), through: h, by: cell) {
                ctx.stroke(Path(CGRect(x: 0, y: y, width: w, height: 0.5)), with: .color(HoloPalette.cyan.opacity(index % 5 == 0 ? 0.16 : 0.06)), lineWidth: 0.6)
                index += 1
            }
            // Scanlines.
            for y in stride(from: CGFloat(0), through: h, by: 3) {
                ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: 1)), with: .color(Color.black.opacity(0.10)))
            }

            // Keep props off places and roads.
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

            // A glowing data stream winding across the whole sheet (the parchment map's river).
            var stream = Path()
            for i in 0...120 {
                let t = CGFloat(i) / 120
                let p = CGPoint(x: t * w, y: h * (0.5 + 0.30 * sin(t * .pi * 3.2 + 0.6)))
                if i == 0 { stream.move(to: p) } else { stream.addLine(to: p) }
            }
            ctx.stroke(stream, with: .color(HoloPalette.cyan.opacity(0.10)), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
            ctx.stroke(stream, with: .color(HoloPalette.cyan.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 7]))

            // Circuit traces: right-angled lines ending in solder pads.
            var rng = LinearCongruentialGenerator(seed: 23)
            for _ in 0..<Int(w / 60) {
                var p = CGPoint(x: rng.next(in: 0...w), y: rng.next(in: 20...(h - 20)))
                guard isClear(p, 26) else { continue }
                var trace = Path()
                trace.move(to: p)
                for step in 0..<3 {
                    let length = rng.next(in: 18...50)
                    p = step.isMultiple(of: 2) ? CGPoint(x: p.x + length, y: p.y) : CGPoint(x: p.x, y: p.y + (rng.next(in: 0...1) < 0.5 ? -length : length))
                    trace.addLine(to: p)
                }
                ctx.stroke(trace, with: .color(HoloPalette.cyan.opacity(0.28)), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(HoloPalette.cyan.opacity(0.6)))
            }

            // City blocks along the way: isometric-ish wireframe cubes.
            let blockArt = ArtCache.thumbnail("map_future_block", height: 34).map { ctx.resolve(Image(platformImage: $0)) }
            for x in stride(from: CGFloat(30), through: w * 0.82, by: 46) {
                for y in stride(from: CGFloat(30), through: h - 20, by: 40) {
                    let density = 0.18 + (x / w) * 0.25
                    guard rng.next(in: 0...1) < density else { continue }
                    let p = CGPoint(x: x + rng.next(in: -10...10), y: y + rng.next(in: -8...8))
                    guard isClear(p, 36) else { continue }
                    let size = rng.next(in: 12...22)
                    if let blockArt {
                        ctx.draw(blockArt, in: CGRect(x: p.x - size, y: p.y - size * 1.6, width: size * 2, height: size * 2))
                    } else {
                        Self.drawBlock(&ctx, base: p, size: size, height: size * rng.next(in: 0.6...1.8))
                    }
                }
            }

            // The boss's reactor: a glow, and a ring of towers around it.
            if let boss = layout.map.nodes.first(where: { $0.type == .boss }) {
                let c = layout.point(boss.id, height: h)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 100, y: c.y - 100, width: 200, height: 200)),
                         with: .radialGradient(Gradient(colors: [HoloPalette.alert.opacity(0.35), HoloPalette.cyan.opacity(0.08), .clear]),
                                               center: c, startRadius: 0, endRadius: 100))
                for ring in [46.0, 64.0] as [CGFloat] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)),
                               with: .color(HoloPalette.cyan.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                }
                let towerArt = ArtCache.thumbnail("map_future_tower", height: 90)
                let towers: [(CGFloat, CGFloat, CGFloat)] = [
                    (w - 120, h * 0.22, 90), (w - 44, h * 0.30, 76), (w - 150, h * 0.86, 84), (w - 60, h * 0.90, 70), (w * 0.72, h * 0.14, 56)
                ]
                for tower in towers {
                    let base = CGPoint(x: tower.0, y: tower.1)
                    guard isClear(CGPoint(x: base.x, y: base.y - tower.2 * 0.3), tower.2 * 0.3) else { continue }
                    if let towerArt {
                        ctx.draw(Image(platformImage: towerArt), in: CGRect(x: base.x - tower.2 * 0.3, y: base.y - tower.2, width: tower.2 * 0.6, height: tower.2))
                    } else {
                        Self.drawTower(&ctx, base: base, height: tower.2)
                    }
                }
            }

            // HUD corner brackets and a small "uplink" glyph at the trailhead.
            let inset: CGFloat = 14, arm: CGFloat = 26
            for (corner, dx, dy) in [(CGPoint(x: inset, y: inset), 1.0, 1.0), (CGPoint(x: w - inset, y: inset), -1.0, 1.0),
                                     (CGPoint(x: inset, y: h - inset), 1.0, -1.0), (CGPoint(x: w - inset, y: h - inset), -1.0, -1.0)] as [(CGPoint, CGFloat, CGFloat)] {
                var bracket = Path()
                bracket.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
                bracket.addLine(to: corner)
                bracket.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
                ctx.stroke(bracket, with: .color(HoloPalette.cyan.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .square))
            }
            ctx.stroke(Path(CGRect(x: 8, y: 8, width: w - 16, height: h - 16)), with: .color(HoloPalette.cyan.opacity(0.25)), lineWidth: 1)
            let uplink = CGPoint(x: 52, y: h - 52)
            for r in [8.0, 15.0, 22.0] as [CGFloat] {
                var arc = Path()
                arc.addArc(center: uplink, radius: r, startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
                ctx.stroke(arc, with: .color(HoloPalette.cyan.opacity(0.55)), lineWidth: 1.5)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: uplink.x - 3, y: uplink.y - 3, width: 6, height: 6)), with: .color(HoloPalette.cyan))
        }
        .allowsHitTesting(false)
    }

    /// A wireframe city block: top face, two side faces, a few lit windows.
    private static func drawBlock(_ ctx: inout GraphicsContext, base: CGPoint, size: CGFloat, height: CGFloat) {
        let half = size * 0.9
        let top = CGPoint(x: base.x, y: base.y - height)
        var faces = Path()
        // Front-left and front-right faces.
        faces.move(to: CGPoint(x: base.x - half, y: base.y - half * 0.5))
        faces.addLine(to: base)
        faces.addLine(to: CGPoint(x: base.x + half, y: base.y - half * 0.5))
        faces.addLine(to: CGPoint(x: base.x + half, y: top.y - half * 0.5))
        faces.addLine(to: top)
        faces.addLine(to: CGPoint(x: base.x - half, y: top.y - half * 0.5))
        faces.closeSubpath()
        ctx.fill(faces, with: .color(HoloPalette.cyan.opacity(0.07)))
        var roof = Path()
        roof.move(to: top)
        roof.addLine(to: CGPoint(x: base.x + half, y: top.y - half * 0.5))
        roof.addLine(to: CGPoint(x: base.x, y: top.y - half))
        roof.addLine(to: CGPoint(x: base.x - half, y: top.y - half * 0.5))
        roof.closeSubpath()
        ctx.fill(roof, with: .color(HoloPalette.cyan.opacity(0.16)))
        var edges = faces
        edges.addPath(roof)
        edges.move(to: base)
        edges.addLine(to: top)
        ctx.stroke(edges, with: .color(HoloPalette.cyan.opacity(0.6)), lineWidth: 0.8)
        for i in 0..<3 {
            let y = base.y - height * CGFloat(0.3 + 0.2 * Double(i)) - half * 0.2
            ctx.fill(Path(CGRect(x: base.x + half * 0.35, y: y, width: 2.5, height: 1.5)), with: .color(HoloPalette.mint.opacity(0.8)))
        }
    }

    /// A slim wireframe tower with a beacon on top.
    private static func drawTower(_ ctx: inout GraphicsContext, base: CGPoint, height: CGFloat) {
        let width = height * 0.18
        var body = Path()
        body.move(to: CGPoint(x: base.x - width, y: base.y))
        body.addLine(to: CGPoint(x: base.x - width * 0.6, y: base.y - height))
        body.addLine(to: CGPoint(x: base.x + width * 0.6, y: base.y - height))
        body.addLine(to: CGPoint(x: base.x + width, y: base.y))
        body.closeSubpath()
        ctx.fill(body, with: .linearGradient(Gradient(colors: [HoloPalette.cyan.opacity(0.22), HoloPalette.cyan.opacity(0.04)]),
                                             startPoint: CGPoint(x: base.x, y: base.y - height), endPoint: base))
        ctx.stroke(body, with: .color(HoloPalette.cyan.opacity(0.7)), lineWidth: 1)
        for f in stride(from: 0.15, to: 0.95, by: 0.12) {
            let y = base.y - height * CGFloat(f)
            let half = width * (1 - 0.4 * CGFloat(f))
            ctx.stroke(Path(CGRect(x: base.x - half, y: y, width: half * 2, height: 0.5)), with: .color(HoloPalette.cyan.opacity(0.3)), lineWidth: 0.6)
        }
        let beacon = CGPoint(x: base.x, y: base.y - height - 4)
        ctx.fill(Path(ellipseIn: CGRect(x: beacon.x - 8, y: beacon.y - 8, width: 16, height: 16)),
                 with: .radialGradient(Gradient(colors: [HoloPalette.alert.opacity(0.8), .clear]), center: beacon, startRadius: 0, endRadius: 8))
        ctx.fill(Path(ellipseIn: CGRect(x: beacon.x - 2, y: beacon.y - 2, width: 4, height: 4)), with: .color(.white))
    }
}
