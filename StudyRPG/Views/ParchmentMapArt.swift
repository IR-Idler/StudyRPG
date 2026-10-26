import SwiftUI

// MARK: - Parchment map art (game.md §9)
//
// The Act I world map as an old scroll lying on the table: a sheet with ragged, nicked top and
// bottom edges, rolled up at both ends, places and roads painted on in ink and watercolor. Only
// the roads you can walk next move (a gilded shimmer); everything else is static.

/// The parchment's outline: straight where it runs into the rollers, ragged along the top and
/// bottom with a few deeper nicks, like a well-used map. Deterministic per seed.
struct TornSheetShape: Shape {
    var seed: UInt64 = 11

    func path(in rect: CGRect) -> Path {
        var rng = LinearCongruentialGenerator(seed: seed)
        var path = Path()
        let step: CGFloat = 16
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 3))
        var x = rect.minX
        while x < rect.maxX {
            x = min(rect.maxX, x + step * rng.next(in: 0.6...1.4))
            var y = rect.minY + rng.next(in: 0...5)
            if rng.next(in: 0...1) < 0.06 { y += rng.next(in: 7...13) }
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
        x = rect.maxX
        while x > rect.minX {
            x = max(rect.minX, x - step * rng.next(in: 0.6...1.4))
            var y = rect.maxY - rng.next(in: 0...5)
            if rng.next(in: 0...1) < 0.06 { y -= rng.next(in: 7...13) }
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// One end of the map rolled up: a parchment cylinder with a wooden knob above and below.
struct ScrollRollerView: View {
    let height: CGFloat
    private let width: CGFloat = 30

    var body: some View {
        ZStack {
            // Its shadow on the table.
            Capsule()
                .fill(Color.black.opacity(0.35))
                .frame(width: width + 4, height: height + 8)
                .offset(x: 5, y: 9)
            ForEach([-1.0, 1.0], id: \.self) { side in
                knob.offset(y: side * (height / 2 + 9))
            }
            // The rolled paper: lit from the upper left, darker where it curves away.
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 0.50, green: 0.40, blue: 0.27), location: 0),
                    .init(color: Palette.parchmentShade, location: 0.18),
                    .init(color: Palette.parchment, location: 0.42),
                    .init(color: Palette.parchmentShade, location: 0.78),
                    .init(color: Color(red: 0.46, green: 0.36, blue: 0.24), location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: height)
            // The layers of paper wound around it.
            Canvas { ctx, size in
                for i in 0..<3 {
                    let inset = 4 + CGFloat(i) * 2.5
                    var curl = Path()
                    curl.move(to: CGPoint(x: size.width / 2 - 6 + CGFloat(i) * 5, y: inset))
                    curl.addLine(to: CGPoint(x: size.width / 2 - 6 + CGFloat(i) * 5, y: size.height - inset))
                    ctx.stroke(curl, with: .color(Palette.ink.opacity(0.16)), lineWidth: 1)
                }
                let rim = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 7)
                ctx.stroke(rim, with: .color(Palette.ink.opacity(0.45)), lineWidth: 1)
            }
            .frame(width: width, height: height)
        }
        .frame(width: width + 10, height: height + 36)
        .allowsHitTesting(false)
    }

    /// A turned walnut knob with a brass ring.
    private var knob: some View {
        ZStack {
            Capsule()
                .fill(Color(red: 0.28, green: 0.17, blue: 0.10))
                .frame(width: 10, height: 14)
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.20), Color(red: 0.22, green: 0.13, blue: 0.08)],
                                     center: UnitPoint(x: 0.35, y: 0.35), startRadius: 1, endRadius: 14))
                .overlay(Ellipse().strokeBorder(Palette.gold.opacity(0.7), lineWidth: 1.2))
                .frame(width: width * 0.72, height: 13)
        }
    }
}

/// A place painted onto the parchment in ink and watercolor — crossed swords, a skull for elites,
/// a crown for the boss, a market tent, an inked question mark, a campfire — not a game icon.
/// Visited places get a red check; places on roads no longer open fade out. Static: the gold
/// shimmer around open places is `OpenRoadShimmer`.
struct PaintedPlaceMark: View {
    let type: MapNodeType
    let isReachable: Bool
    let isVisited: Bool
    let isAlive: Bool

    static func size(for type: MapNodeType) -> CGFloat { type == .boss ? 84 : 60 }

    var body: some View {
        let size = Self.size(for: type)
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 100
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let ink = Color(red: 0.24, green: 0.17, blue: 0.11)
            func inkStroke(_ path: Path, _ width: CGFloat = 3) {
                ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
            }

            // Watercolor wash behind the drawing: an uneven blot, darker toward one side.
            var blot = Path()
            let seed = blotSeed
            for i in 0...36 {
                let a = Double(i) / 36 * 2 * .pi
                let r = 36 + 3 * sin(3 * a + seed) + 2 * cos(5 * a + seed * 0.7)
                let point = p(50 + CGFloat(cos(a) * r), 52 + CGFloat(sin(a) * r * 0.92))
                if i == 0 { blot.move(to: point) } else { blot.addLine(to: point) }
            }
            blot.closeSubpath()
            ctx.fill(blot, with: .color(washColor.opacity(isVisited ? 0.16 : 0.30)))
            ctx.fill(blot, with: .radialGradient(Gradient(colors: [.clear, washColor.opacity(0.22)]),
                                                 center: p(40, 40), startRadius: 0, endRadius: 46 * s))
            if isReachable {
                ctx.stroke(blot, with: .color(Palette.gold), style: StrokeStyle(lineWidth: 2.4 * s, lineJoin: .round))
            }

            switch type {
            case .fight:
                // Two crossed swords.
                for (hilt, tip, guardA, guardB) in [
                    (p(30, 74), p(74, 28), p(24, 64), p(40, 78)),
                    (p(70, 74), p(26, 28), p(60, 78), p(76, 64))
                ] {
                    var blade = Path(); blade.move(to: hilt); blade.addLine(to: tip)
                    inkStroke(blade, 6.5)
                    ctx.stroke(blade, with: .color(Color(red: 0.86, green: 0.87, blue: 0.88)), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
                    var guardBar = Path(); guardBar.move(to: guardA); guardBar.addLine(to: guardB)
                    inkStroke(guardBar, 4.5)
                    ctx.fill(Path(ellipseIn: CGRect(x: hilt.x - 4 * s, y: hilt.y - 1 * s, width: 8 * s, height: 8 * s)), with: .color(ink))
                }
            case .elite:
                // A skull.
                let bone = Color(red: 0.94, green: 0.90, blue: 0.81)
                let cranium = Path(ellipseIn: CGRect(x: 28 * s, y: 22 * s, width: 44 * s, height: 40 * s))
                let jaw = Path(roundedRect: CGRect(x: 37 * s, y: 54 * s, width: 26 * s, height: 18 * s), cornerRadius: 5 * s)
                ctx.fill(cranium, with: .color(bone)); ctx.fill(jaw, with: .color(bone))
                inkStroke(cranium); inkStroke(jaw)
                for x in [40.0, 60.0] {
                    ctx.fill(Path(ellipseIn: CGRect(x: (CGFloat(x) - 6.5) * s, y: 36 * s, width: 13 * s, height: 12 * s)), with: .color(ink))
                }
                var nose = Path(); nose.move(to: p(50, 49)); nose.addLine(to: p(46, 56)); nose.addLine(to: p(54, 56)); nose.closeSubpath()
                ctx.fill(nose, with: .color(ink))
                for x in [44.0, 50.0, 56.0] {
                    var tooth = Path(); tooth.move(to: p(CGFloat(x), 60)); tooth.addLine(to: p(CGFloat(x), 70))
                    inkStroke(tooth, 1.6)
                }
            case .boss:
                // A crown.
                var crown = Path()
                crown.move(to: p(22, 72)); crown.addLine(to: p(22, 40)); crown.addLine(to: p(34, 54))
                crown.addLine(to: p(42, 28)); crown.addLine(to: p(50, 48)); crown.addLine(to: p(58, 28))
                crown.addLine(to: p(66, 54)); crown.addLine(to: p(78, 40)); crown.addLine(to: p(78, 72))
                crown.closeSubpath()
                ctx.fill(crown, with: .linearGradient(Gradient(colors: [Palette.goldGlow, Palette.gold, Color(red: 0.62, green: 0.46, blue: 0.18)]),
                                                      startPoint: p(50, 28), endPoint: p(50, 72)))
                inkStroke(crown)
                var band = Path(); band.move(to: p(22, 62)); band.addLine(to: p(78, 62))
                inkStroke(band, 2)
                for x in [36.0, 50.0, 64.0] {
                    ctx.fill(Path(ellipseIn: CGRect(x: (CGFloat(x) - 3.5) * s, y: 63.5 * s, width: 7 * s, height: 7 * s)), with: .color(Palette.crimson))
                }
                for tip in [p(22, 40), p(42, 28), p(58, 28), p(78, 40)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 3 * s, y: tip.y - 3 * s, width: 6 * s, height: 6 * s)), with: .color(ink))
                }
            case .shop:
                // A striped market tent with a pennant.
                var pole = Path(); pole.move(to: p(50, 30)); pole.addLine(to: p(50, 13))
                inkStroke(pole, 2)
                var pennant = Path(); pennant.move(to: p(50, 13)); pennant.addLine(to: p(64, 17)); pennant.addLine(to: p(50, 21)); pennant.closeSubpath()
                ctx.fill(pennant, with: .color(Palette.crimson)); inkStroke(pennant, 1.6)
                let stall = Path(roundedRect: CGRect(x: 29 * s, y: 56 * s, width: 42 * s, height: 20 * s), cornerRadius: 1.5 * s)
                ctx.fill(stall, with: .color(Color(red: 0.90, green: 0.84, blue: 0.70)))
                inkStroke(stall, 2.5)
                var door = Path(); door.move(to: p(44, 76)); door.addLine(to: p(44, 66))
                door.addQuadCurve(to: p(56, 66), control: p(50, 59)); door.addLine(to: p(56, 76))
                ctx.fill(door, with: .color(ink.opacity(0.85)))
                var roof = Path(); roof.move(to: p(20, 58)); roof.addLine(to: p(50, 29)); roof.addLine(to: p(80, 58)); roof.closeSubpath()
                ctx.fill(roof, with: .color(Color(red: 0.70, green: 0.28, blue: 0.20)))
                for x in [32.0, 56.0] {
                    var stripe = Path(); stripe.move(to: p(50, 29))
                    stripe.addLine(to: p(CGFloat(x), 58)); stripe.addLine(to: p(CGFloat(x) + 12, 58)); stripe.closeSubpath()
                    ctx.fill(stripe, with: .color(Color(red: 0.93, green: 0.88, blue: 0.75)))
                }
                inkStroke(roof)
            case .event:
                // An inked question mark.
                ctx.draw(
                    Text("?")
                        .font(.system(size: 62 * s, weight: .black, design: .serif))
                        .italic()
                        .foregroundStyle(Color(red: 0.30, green: 0.22, blue: 0.48)),
                    at: p(51, 52))
            case .campfire:
                // Crossed logs and a flame.
                for (a, b) in [(p(28, 76), p(72, 64)), (p(28, 64), p(72, 76))] {
                    var log = Path(); log.move(to: a); log.addLine(to: b)
                    inkStroke(log, 8)
                    ctx.stroke(log, with: .color(Color(red: 0.55, green: 0.36, blue: 0.20)), style: StrokeStyle(lineWidth: 4.5 * s, lineCap: .round))
                }
                var flame = Path()
                flame.move(to: p(50, 68))
                flame.addCurve(to: p(50, 20), control1: p(28, 62), control2: p(36, 36))
                flame.addCurve(to: p(50, 68), control1: p(64, 36), control2: p(72, 62))
                ctx.fill(flame, with: .linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.80, blue: 0.30), Color(red: 0.88, green: 0.40, blue: 0.16)]),
                                                      startPoint: p(50, 64), endPoint: p(50, 22)))
                inkStroke(flame, 2.6)
                var inner = Path()
                inner.move(to: p(50, 66))
                inner.addCurve(to: p(50, 40), control1: p(41, 60), control2: p(44, 48))
                inner.addCurve(to: p(50, 66), control1: p(56, 48), control2: p(59, 60))
                ctx.fill(inner, with: .color(Color(red: 1.0, green: 0.93, blue: 0.62)))
            }

            if isVisited {
                // Ticked off in red ink.
                var check = Path(); check.move(to: p(62, 76)); check.addLine(to: p(70, 86)); check.addLine(to: p(90, 60))
                ctx.stroke(check, with: .color(Color(red: 0.62, green: 0.16, blue: 0.12)), style: StrokeStyle(lineWidth: 5 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .saturation(isAlive ? (isVisited ? 0.45 : 1) : 0)
        .opacity(isAlive ? 1 : 0.35)
        .contentShape(Circle())
    }

    /// Fixed per place type, so each kind of place always has the same blot shape.
    private var blotSeed: Double {
        switch type {
        case .fight: return 1
        case .elite: return 2
        case .boss: return 3
        case .shop: return 4
        case .event: return 5
        case .campfire: return 6
        }
    }

    private var washColor: Color {
        switch type {
        case .fight: return Color(red: 0.45, green: 0.40, blue: 0.33)
        case .elite: return Palette.crimson
        case .boss: return Palette.ember
        case .shop: return Color(red: 0.62, green: 0.48, blue: 0.24)
        case .event: return Color(red: 0.42, green: 0.36, blue: 0.62)
        case .campfire: return Color(red: 0.85, green: 0.50, blue: 0.20)
        }
    }
}

/// The roads you can walk next, gilded and alive: gold dashes marching toward each destination
/// with a bright glint running along them, and a soft gold pulse around the places they lead to.
/// A separate, small layer so the static map never redraws; paused under a covering screen.
struct OpenRoadShimmer: View {
    let roads: [(from: CGPoint, to: CGPoint)]
    let places: [(center: CGPoint, radius: CGFloat)]
    var tint: Color = Palette.gold
    var glint: Color = Color(red: 1.0, green: 0.95, blue: 0.75)
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused || reduceMotion || roads.isEmpty)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                for road in roads {
                    let path = RoadCurve.path(from: road.from, to: road.to)
                    ctx.stroke(path, with: .color(tint.opacity(0.22)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    ctx.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 3.4, lineCap: .round, dash: [9, 6], dashPhase: -CGFloat(t * 16)))
                    // A glint running from here to there, once every ~1.7 s.
                    let phase = CGFloat((t * 0.6).truncatingRemainder(dividingBy: 1)) * 1.2
                    let streak = path.trimmedPath(from: max(0, phase - 0.16), to: min(1, phase))
                    ctx.stroke(streak, with: .color(Palette.goldGlow.opacity(0.35)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    ctx.stroke(streak, with: .color(glint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                let pulse = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(t * 2.4)
                for place in places {
                    let r = place.radius + 3 + 4 * pulse
                    let ring = Path(ellipseIn: CGRect(x: place.center.x - r, y: place.center.y - r, width: r * 2, height: r * 2))
                    ctx.stroke(ring, with: .color(Palette.goldGlow.opacity(0.25 + 0.4 * pulse)), lineWidth: 2.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
