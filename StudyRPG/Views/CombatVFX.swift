import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Attack Visual Animations

enum AttackVFXKind {
    case bladeSlash(CGPoint)
    case clawSlash(CGPoint)
    case magicMissile(from: CGPoint, to: CGPoint)
    /// A big burning comet with a tail, embers and an explosive impact.
    case fireball(from: CGPoint, to: CGPoint)
    case fireBurst(CGPoint)
    /// Act II robots: a charged cyan laser beam from the enemy to the hero.
    case laserBeam(from: CGPoint, to: CGPoint)
    case shieldPulse(CGPoint)
    case healBurst(CGPoint)
    case manaBurst(CGPoint)
    case strengthBurst(CGPoint)
    /// Stun / weaken / vulnerable landing on an enemy.
    case controlBurst(CGPoint)
    /// A single strong colored glow, used when drinking a potion.
    case potionGlow(CGPoint, Color)
}

struct AttackVFXInstance: Identifiable {
    let id = UUID()
    let kind: AttackVFXKind
}

struct AttackVFXOverlay: View {
    let effects: [AttackVFXInstance]

    var body: some View {
        ZStack {
            ForEach(effects) { effect in
                switch effect.kind {
                case .bladeSlash(let pt):
                    BladeSlashAnimationView(point: pt)
                case .clawSlash(let pt):
                    ClawSlashAnimationView(point: pt)
                case .magicMissile(let from, let to):
                    MagicMissileAnimationView(from: from, to: to)
                case .fireball(let from, let to):
                    FireballCometAnimationView(from: from, to: to)
                case .fireBurst(let pt):
                    FireBurstAnimationView(point: pt)
                case .laserBeam(let from, let to):
                    LaserBeamAnimationView(from: from, to: to)
                case .shieldPulse(let pt):
                    ShieldPulseAnimationView(point: pt)
                case .healBurst(let pt):
                    AuraBurstAnimationView(point: pt, tint: Palette.health, icon: "plus")
                case .manaBurst(let pt):
                    AuraBurstAnimationView(point: pt, tint: Palette.mana, icon: "diamond.fill")
                case .strengthBurst(let pt):
                    AuraBurstAnimationView(point: pt, tint: Palette.strength, icon: "die.face.5.fill")
                case .controlBurst(let pt):
                    AuraBurstAnimationView(point: pt, tint: Palette.control, icon: "moon.zzz.fill")
                case .potionGlow(let pt, let tint):
                    PotionGlowAnimationView(point: pt, tint: tint)
                }
            }
        }
    }
}

/// Two crossing crescent sword slashes with a white impact flash and a spray of sparks. Drawn
/// in one time-driven Canvas (cheap, smooth, and much punchier than a stroked path).
struct BladeSlashAnimationView: View {
    let point: CGPoint
    @State private var start = Date()

    private static let duration: Double = 0.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, _ in
                guard t < Self.duration else { return }
                ctx.blendMode = .plusLighter
                // Slash 1: top-left → bottom-right. Slash 2: top-right → bottom-left, a beat later.
                drawCrescent(&ctx, t: t, begin: 0.0, angleFrom: -150, angleTo: -20, radius: 62, offset: CGSize(width: -10, height: 18))
                drawCrescent(&ctx, t: t, begin: 0.11, angleFrom: -30, angleTo: -160, radius: 56, offset: CGSize(width: 12, height: 22))
                drawImpact(&ctx, t: t - 0.08)
                drawSparks(&ctx, t: t - 0.08)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            start = Date()
            Haptics.impact(.rigid)
        }
    }

    private func drawCrescent(_ ctx: inout GraphicsContext, t: Double, begin: Double, angleFrom: Double, angleTo: Double, radius: CGFloat, offset: CGSize) {
        let local = t - begin
        let swing = 0.14, fade = 0.26
        guard local > 0, local < swing + fade else { return }
        let reveal = min(1, local / swing)
        let alpha = local < swing ? 1 : max(0, 1 - (local - swing) / fade)
        let center = CGPoint(x: point.x + offset.width, y: point.y + offset.height)
        let samples = 26
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for i in 0...samples {
            let u = Double(i) / Double(samples) * reveal
            let angle = (angleFrom + (angleTo - angleFrom) * u) * .pi / 180
            // Thick in the middle, razor-thin at both tips.
            let thickness = CGFloat(sin(.pi * u)) * 16 * CGFloat(alpha) + 1
            outer.append(CGPoint(x: center.x + CGFloat(cos(angle)) * (radius + thickness / 2), y: center.y + CGFloat(sin(angle)) * (radius + thickness / 2)))
            inner.append(CGPoint(x: center.x + CGFloat(cos(angle)) * (radius - thickness / 2), y: center.y + CGFloat(sin(angle)) * (radius - thickness / 2)))
        }
        var path = Path()
        path.addLines(outer)
        path.addLines(inner.reversed())
        path.closeSubpath()
        // Soft blue-steel bloom (wide translucent strokes — no per-frame blur filter), then the
        // white-hot edge.
        let steel = Color(red: 0.55, green: 0.75, blue: 1.0)
        ctx.stroke(path, with: .color(steel.opacity(0.22 * alpha)), style: StrokeStyle(lineWidth: 14, lineJoin: .round))
        ctx.stroke(path, with: .color(steel.opacity(0.45 * alpha)), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
        ctx.fill(path, with: .color(.white.opacity(alpha)))
    }

    private func drawImpact(_ ctx: inout GraphicsContext, t: Double) {
        guard t > 0, t < 0.3 else { return }
        let k = t / 0.3
        let r = CGFloat(18 + 70 * k)
        ctx.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.9 * (1 - k)), Palette.goldGlow.opacity(0.5 * (1 - k)), .clear]),
            center: point, startRadius: 0, endRadius: r))
    }

    private func drawSparks(_ ctx: inout GraphicsContext, t: Double) {
        guard t > 0, t < 0.45 else { return }
        let k = t / 0.45
        for i in 0..<16 {
            let angle = Double(i) / 16 * 2 * .pi + Double(i % 3) * 0.3
            let speed = 90 + Double((i * 37) % 60)
            let dist = CGFloat(speed * t * (1.2 - k * 0.6))
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            let head = CGPoint(x: point.x + dir.x * dist, y: point.y + dir.y * dist + CGFloat(120 * t * t))
            let tail = CGPoint(x: head.x - dir.x * 12 * CGFloat(1 - k), y: head.y - dir.y * 12 * CGFloat(1 - k))
            var streak = Path()
            streak.move(to: tail)
            streak.addLine(to: head)
            ctx.stroke(streak, with: .color((i.isMultiple(of: 2) ? Color.white : Palette.goldGlow).opacity(1 - k)),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }
}

/// Three raking claw gashes torn diagonally across the hero (enemies attack from the right),
/// with a dark-red glow, a hot core and flying droplets. One time-driven Canvas.
struct ClawSlashAnimationView: View {
    let point: CGPoint
    @State private var start = Date()

    private static let duration: Double = 0.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, _ in
                guard t < Self.duration else { return }
                for (index, offset) in [-17.0, 0.0, 17.0].enumerated() {
                    drawGash(&ctx, t: t - Double(index) * 0.035, offset: CGFloat(offset))
                }
                drawDroplets(&ctx, t: t - 0.08)
            }
            .allowsHitTesting(false)
        }
        .onAppear { start = Date() }
    }

    private func drawGash(_ ctx: inout GraphicsContext, t: Double, offset: CGFloat) {
        let swing = 0.11, fade = 0.3
        guard t > 0, t < swing + fade else { return }
        let reveal = min(1, t / swing)
        let alpha = t < swing ? 1 : max(0, 1 - (t - swing) / fade)
        // A slightly curved stroke from upper right to lower left.
        let a = CGPoint(x: point.x + 34 + offset, y: point.y - 40 + offset * 0.3)
        let b = CGPoint(x: point.x - 30 + offset, y: point.y + 38 + offset * 0.3)
        let control = CGPoint(x: (a.x + b.x) / 2 + 14, y: (a.y + b.y) / 2 + 6)
        func at(_ u: Double) -> CGPoint {
            let u = CGFloat(u), v = 1 - u
            return CGPoint(x: v * v * a.x + 2 * v * u * control.x + u * u * b.x,
                           y: v * v * a.y + 2 * v * u * control.y + u * u * b.y)
        }
        func ribbon(width: CGFloat) -> Path {
            let samples = 18
            var left: [CGPoint] = [], right: [CGPoint] = []
            for i in 0...samples {
                let u = Double(i) / Double(samples) * reveal
                let p = at(u), q = at(min(1, u + 0.02))
                let dx = q.x - p.x, dy = q.y - p.y
                let len = max(0.001, sqrt(dx * dx + dy * dy))
                let w = CGFloat(sin(.pi * min(1, u / max(reveal, 0.01)))) * width + 0.5
                left.append(CGPoint(x: p.x - dy / len * w, y: p.y + dx / len * w))
                right.append(CGPoint(x: p.x + dy / len * w, y: p.y - dx / len * w))
            }
            var path = Path()
            path.addLines(left)
            path.addLines(right.reversed())
            path.closeSubpath()
            return path
        }
        ctx.fill(ribbon(width: 9), with: .color(Palette.crimson.opacity(0.35 * alpha)))
        ctx.fill(ribbon(width: 4.5), with: .color(Color(red: 0.9, green: 0.15, blue: 0.12).opacity(0.9 * alpha)))
        var hot = ctx
        hot.blendMode = .plusLighter
        hot.fill(ribbon(width: 1.6), with: .color(Color(red: 1, green: 0.8, blue: 0.7).opacity(alpha)))
    }

    private func drawDroplets(_ ctx: inout GraphicsContext, t: Double) {
        guard t > 0, t < 0.45 else { return }
        let k = t / 0.45
        for i in 0..<12 {
            let angle = Double.pi * (0.55 + Double(i) / 12 * 0.9) + Double(i % 3) * 0.2
            let speed = 70 + Double((i * 29) % 70)
            let p = CGPoint(x: point.x + CGFloat(cos(angle) * speed * t),
                            y: point.y + CGFloat(sin(angle) * speed * t + 240 * t * t))
            let r = CGFloat(2.6 * (1 - k) + 0.6)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(Palette.crimson.opacity(1 - k)))
        }
    }
}

/// An arcane orb: a bright core with a fading trail of motes and two orbiting sparks, flying on
/// a shallow arc, then a starburst + ring on impact (at 0.32s, matching the fight's timing).
struct MagicMissileAnimationView: View {
    let from: CGPoint
    let to: CGPoint
    @State private var start = Date()

    private static let travel: Double = 0.32
    private static let burst: Double = 0.4

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, _ in
                guard t < Self.travel + Self.burst else { return }
                ctx.blendMode = .plusLighter
                if t < Self.travel {
                    drawOrb(&ctx, t: t)
                } else {
                    drawImpact(&ctx, t: t - Self.travel)
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear { start = Date() }
    }

    private func arc(_ u: Double) -> CGPoint {
        let lift = -min(60, abs(to.x - from.x) * 0.12)
        return CGPoint(x: from.x + (to.x - from.x) * CGFloat(u),
                       y: from.y + (to.y - from.y) * CGFloat(u) + lift * CGFloat(4 * u * (1 - u)))
    }

    private func blob(_ ctx: inout GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ colors: [Color]) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: colors), center: p, startRadius: 0, endRadius: r))
    }

    private func drawOrb(_ ctx: inout GraphicsContext, t: Double) {
        let u = pow(t / Self.travel, 1.25)
        for i in stride(from: 16, through: 1, by: -1) {
            let su = max(0, u - Double(i) * 0.03)
            guard su > 0 else { continue }
            let fade = 1 - Double(i) / 16
            blob(&ctx, arc(su), CGFloat(3 + 9 * fade), [Palette.mana.opacity(0.7 * fade), Palette.control.opacity(0.25 * fade), .clear])
        }
        let head = arc(u)
        let pulse = CGFloat(1 + 0.12 * sin(t * 60))
        blob(&ctx, head, 26 * pulse, [Palette.mist.opacity(0.55), Palette.mana.opacity(0.25), .clear])
        blob(&ctx, head, 9 * pulse, [.white, Palette.mist, .clear])
        for k in 0..<2 {
            let angle = t * 28 + Double(k) * .pi
            let spark = CGPoint(x: head.x + CGFloat(cos(angle)) * 13, y: head.y + CGFloat(sin(angle)) * 7)
            blob(&ctx, spark, 4, [.white, Palette.control.opacity(0.6), .clear])
        }
    }

    private func drawImpact(_ ctx: inout GraphicsContext, t: Double) {
        let k = t / Self.burst
        blob(&ctx, to, CGFloat(16 + 46 * min(1, k * 2.5)), [.white.opacity(max(0, 1 - k * 2)), Palette.mist.opacity(0.7 * (1 - k)), .clear])
        let ring = CGFloat(10 + 60 * k)
        ctx.stroke(Path(ellipseIn: CGRect(x: to.x - ring, y: to.y - ring, width: ring * 2, height: ring * 2)),
                   with: .color(Palette.mana.opacity(0.85 * (1 - k))), lineWidth: CGFloat(3 * (1 - k)) + 0.5)
        for i in 0..<10 {
            let angle = Double(i) / 10 * 2 * .pi + 0.3
            let inner = CGFloat(8 + 30 * k), outer = CGFloat(18 + 58 * k)
            var ray = Path()
            ray.move(to: CGPoint(x: to.x + CGFloat(cos(angle)) * inner, y: to.y + CGFloat(sin(angle)) * inner))
            ray.addLine(to: CGPoint(x: to.x + CGFloat(cos(angle)) * outer, y: to.y + CGFloat(sin(angle)) * outer))
            ctx.stroke(ray, with: .color((i.isMultiple(of: 2) ? Color.white : Palette.mist).opacity(1 - k)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// Dragon fire engulfing a hero: flame tongues licking up around them, a hot base glow, rising
/// embers and a brief heat flash. One time-driven Canvas.
/// A robot's laser (game.md §16): a charge-up glow at the emitter, then a flickering beam with a
/// white-hot core, an impact flare and sparks on the hero, fading out. One time-driven Canvas.
struct LaserBeamAnimationView: View {
    let from: CGPoint
    let to: CGPoint
    @State private var start = Date()

    private static let duration: Double = 0.75
    private static let cyan = Color(red: 0.30, green: 0.90, blue: 1.0)

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, _ in
                guard t < Self.duration else { return }
                ctx.blendMode = .plusLighter
                // The emitter sits at the robot's front (left of its center).
                let origin = CGPoint(x: from.x - 34, y: from.y + 4)
                let charge = min(1, t / 0.14)
                let fire = t >= 0.14 ? 1.0 : 0.0
                let fade = t < 0.45 ? 1 : max(0, 1 - (t - 0.45) / 0.3)
                ctx.fill(Path(ellipseIn: CGRect(x: origin.x - 22, y: origin.y - 22, width: 44, height: 44)),
                         with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9 * charge * fade), Self.cyan.opacity(0.6 * charge * fade), .clear]),
                                               center: origin, startRadius: 0, endRadius: 22))
                guard fire > 0 else { return }
                let flicker = 0.85 + 0.15 * sin(t * 90)
                var beam = Path()
                beam.move(to: origin)
                beam.addLine(to: to)
                ctx.stroke(beam, with: .color(Self.cyan.opacity(0.35 * fade)), style: StrokeStyle(lineWidth: 18 * flicker, lineCap: .round))
                ctx.stroke(beam, with: .color(Self.cyan.opacity(0.85 * fade)), style: StrokeStyle(lineWidth: 7 * flicker, lineCap: .round))
                ctx.stroke(beam, with: .color(Color.white.opacity(fade)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                // Impact flare and sparks.
                ctx.fill(Path(ellipseIn: CGRect(x: to.x - 34, y: to.y - 34, width: 68, height: 68)),
                         with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9 * fade), Self.cyan.opacity(0.5 * fade), .clear]),
                                               center: to, startRadius: 0, endRadius: 34))
                let k = (t - 0.14) / (Self.duration - 0.14)
                for i in 0..<14 {
                    let angle = Double(i) / 14 * 2 * .pi + 0.4
                    let reach = CGFloat(18 + 46 * k) * CGFloat(0.6 + 0.4 * sin(Double(i) * 1.7))
                    let p = CGPoint(x: to.x + CGFloat(cos(angle)) * reach, y: to.y + CGFloat(sin(angle)) * reach)
                    let r = CGFloat(2.2 * (1 - k) + 0.4)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color((i.isMultiple(of: 2) ? Color.white : Self.cyan).opacity(1 - k)))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { Haptics.impact(.medium) }
    }
}

struct FireBurstAnimationView: View {
    let point: CGPoint
    @State private var start = Date()

    private static let duration: Double = 0.9

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, _ in
                guard t < Self.duration else { return }
                let k = t / Self.duration
                let grow = min(1, t / 0.15)
                let fade = t < 0.5 ? 1 : max(0, 1 - (t - 0.5) / 0.4)
                ctx.blendMode = .plusLighter
                // Base glow at the hero's feet/body.
                let base = CGPoint(x: point.x, y: point.y + 26)
                ctx.fill(Path(ellipseIn: CGRect(x: base.x - 70, y: base.y - 40, width: 140, height: 80)),
                         with: .radialGradient(Gradient(colors: [Palette.goldGlow.opacity(0.7 * fade), Palette.ember.opacity(0.45 * fade), .clear]),
                                               center: base, startRadius: 0, endRadius: 70))
                // Flame tongues.
                for i in 0..<13 {
                    let fx = (Double(i) / 12 - 0.5) * 2
                    let x = point.x + CGFloat(fx * 46)
                    let centerWeight: Double = 1 - abs(fx)
                    let flicker: Double = 0.8 + 0.2 * sin(t * 30 + Double(i) * 1.9)
                    let heightValue: Double = (60 + 40 * centerWeight) * grow * fade * flicker
                    let height = CGFloat(heightValue)
                    let width = CGFloat(12 + 6 * centerWeight)
                    let bottom = CGPoint(x: x, y: base.y + 8)
                    let sway = CGFloat(sin(t * 18 + Double(i))) * 8
                    var tongue = Path()
                    tongue.move(to: CGPoint(x: bottom.x - width, y: bottom.y))
                    tongue.addQuadCurve(to: CGPoint(x: bottom.x + sway, y: bottom.y - height),
                                        control: CGPoint(x: bottom.x - width * 0.9, y: bottom.y - height * 0.55))
                    tongue.addQuadCurve(to: CGPoint(x: bottom.x + width, y: bottom.y),
                                        control: CGPoint(x: bottom.x + width * 0.9, y: bottom.y - height * 0.5))
                    tongue.closeSubpath()
                    ctx.fill(tongue, with: .linearGradient(
                        Gradient(colors: [Color.white.opacity(0.9 * fade), Palette.goldGlow.opacity(0.85 * fade), Palette.ember.opacity(0.6 * fade), .clear]),
                        startPoint: bottom, endPoint: CGPoint(x: bottom.x, y: bottom.y - height)))
                }
                // Embers rising.
                for i in 0..<18 {
                    let seed = Double(i)
                    let p = CGPoint(x: point.x + CGFloat(sin(seed * 2.3) * 50 + sin(t * 6 + seed) * 6),
                                    y: base.y - CGFloat(t * (90 + seed.truncatingRemainder(dividingBy: 5) * 25)))
                    let r = CGFloat(2.2 * (1 - k) + 0.5)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color((i.isMultiple(of: 3) ? Color.white : Palette.goldGlow).opacity(1 - k)))
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            start = Date()
            Haptics.impact(.heavy)
        }
    }
}

struct ShieldPulseAnimationView: View {
    let point: CGPoint
    @State private var scale: CGFloat = 0.55
    @State private var opacity: Double = 1.0
    @State private var ringScale: CGFloat = 0.4
    @State private var ringOpacity: Double = 0.9

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.goldGlow.opacity(0.85), lineWidth: 2.5)
                .frame(width: 84, height: 84)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            Image(systemName: "shield.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Palette.goldGlow)
                .shadow(color: Palette.goldGlow, radius: 16)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .position(point)
        .onAppear {
            // Pop in, hold long enough to read, then fade while expanding.
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                scale = 1.15
            }
            withAnimation(.easeOut(duration: 0.85).delay(0.35)) {
                scale = 1.5
                ringScale = 1.55
                ringOpacity = 0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.7)) {
                opacity = 0
            }
        }
    }
}

/// A proper fireball: a charge-up glow at the caster, a flickering comet with a flame-and-smoke
/// trail along an arc, then an explosion with a shockwave, flying flames, embers and a screen
/// flash. One time-driven Canvas, so it stays smooth.
struct FireballCometAnimationView: View {
    let from: CGPoint
    let to: CGPoint
    @State private var start = Date()

    private static let charge: Double = 0.14
    private static let travel: Double = 0.38
    private static let blast: Double = 0.75
    private var impactTime: Double { Self.charge + Self.travel }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard t < impactTime + Self.blast else { return }
                if t < impactTime {
                    drawCharge(&ctx, t: t)
                    drawComet(&ctx, t: t)
                } else {
                    drawExplosion(&ctx, t: t - impactTime, size: size)
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
        .onAppear {
            start = Date()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(impactTime * 1000)))
                Haptics.impact(.heavy)
            }
        }
    }

    /// Point along a gentle upward arc from caster to target; `u` 0…1.
    private func arc(_ u: Double) -> CGPoint {
        let lift = -min(120, abs(to.x - from.x) * 0.25)
        let x = from.x + (to.x - from.x) * CGFloat(u)
        let y = from.y + (to.y - from.y) * CGFloat(u) + lift * CGFloat(4 * u * (1 - u))
        return CGPoint(x: x, y: y)
    }

    private func blob(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, colors: [Color]) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: colors), center: p, startRadius: 0, endRadius: r))
    }

    private func drawCharge(_ ctx: inout GraphicsContext, t: Double) {
        let k = min(1, t / Self.charge)
        let fade = t > Self.charge ? max(0, 1 - (t - Self.charge) / 0.2) : 1
        ctx.blendMode = .plusLighter
        blob(&ctx, at: from, radius: CGFloat(20 + 40 * k), colors: [Palette.goldGlow.opacity(0.9 * fade), Palette.ember.opacity(0.5 * fade), .clear])
    }

    private func drawComet(_ ctx: inout GraphicsContext, t: Double) {
        let local = t - Self.charge
        guard local > 0 else { return }
        let u = min(1, pow(local / Self.travel, 1.6))   // accelerates into the target
        // Smoke (normal blend), then fire (additive) on top.
        for i in stride(from: 26, through: 1, by: -1) {
            let back = Double(i) * 0.022
            let su = max(0, u - back)
            guard su > 0 else { continue }
            let p = arc(su)
            let wobble = CGFloat(sin(t * 40 + Double(i) * 1.7)) * CGFloat(i) * 0.35
            let r = CGFloat(10 + Double(i) * 0.9)
            blob(&ctx, at: CGPoint(x: p.x, y: p.y + wobble - CGFloat(i) * 0.6), radius: r,
                 colors: [Color(white: 0.15).opacity(0.35 * (1 - Double(i) / 26)), .clear])
        }
        ctx.blendMode = .plusLighter
        for i in stride(from: 22, through: 0, by: -1) {
            let back = Double(i) * 0.016
            let su = max(0, u - back)
            let p = arc(su)
            let flicker = CGFloat(0.85 + 0.15 * sin(t * 55 + Double(i)))
            let r = CGFloat(30 - Double(i) * 1.1) * flicker
            let jitter = CGPoint(x: CGFloat(sin(t * 33 + Double(i) * 2.1)) * CGFloat(i) * 0.5,
                                 y: CGFloat(cos(t * 29 + Double(i) * 1.3)) * CGFloat(i) * 0.5)
            let heat = Double(i) / 22
            let core = Color(red: 1, green: 1 - heat * 0.55, blue: 0.75 - heat * 0.7)
            blob(&ctx, at: CGPoint(x: p.x + jitter.x, y: p.y + jitter.y), radius: max(4, r),
                 colors: [core.opacity(0.95 - heat * 0.5), Palette.ember.opacity(0.6 - heat * 0.4), .clear])
        }
        // White-hot core.
        let head = arc(u)
        blob(&ctx, at: head, radius: 14, colors: [.white, Palette.goldGlow.opacity(0.9), .clear])
    }

    private func drawExplosion(_ ctx: inout GraphicsContext, t: Double, size: CGSize) {
        let k = t / Self.blast
        // Screen flash.
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.orange.opacity(max(0, 0.30 * (1 - k * 3)))))
        ctx.blendMode = .plusLighter
        // Fireball burst.
        let burst = CGFloat(30 + 110 * min(1, k * 2.2))
        blob(&ctx, at: to, radius: burst, colors: [Color.white.opacity(max(0, 1 - k * 1.6)),
                                                    Palette.goldGlow.opacity(max(0, 0.9 - k)),
                                                    Palette.ember.opacity(max(0, 0.7 - k)), .clear])
        // Shockwave ring.
        let ring = CGFloat(20 + 170 * k)
        ctx.stroke(Path(ellipseIn: CGRect(x: to.x - ring, y: to.y - ring * 0.55, width: ring * 2, height: ring * 1.1)),
                   with: .color(Palette.goldGlow.opacity(max(0, 0.9 - k))), lineWidth: CGFloat(6 * (1 - k)) + 0.5)
        // Flames thrown outward, falling with gravity.
        for i in 0..<26 {
            let angle = Double(i) / 26 * 2 * .pi + Double(i % 4) * 0.21
            let speed = 140 + Double((i * 53) % 120)
            let p = CGPoint(x: to.x + CGFloat(cos(angle) * speed * t),
                            y: to.y + CGFloat(sin(angle) * speed * t * 0.8 + 260 * t * t))
            let r = CGFloat(max(1.5, 9 * (1 - k)))
            blob(&ctx, at: p, radius: r * 2, colors: [(i.isMultiple(of: 3) ? Color.white : Palette.goldGlow).opacity(1 - k),
                                                       Palette.ember.opacity(0.7 * (1 - k)), .clear])
        }
        // Rising smoke after the flash.
        ctx.blendMode = .normal
        if k > 0.3 {
            for i in 0..<6 {
                let p = CGPoint(x: to.x + CGFloat((i - 3) * 18), y: to.y - CGFloat(60 * (k - 0.3)) - CGFloat(i % 2) * 12)
                blob(&ctx, at: p, radius: 28, colors: [Color(white: 0.12).opacity(0.45 * (1 - k)), .clear])
            }
        }
    }
}

/// Strong, short-lived colored glow used for potion feedback.
struct PotionGlowAnimationView: View {
    let point: CGPoint
    let tint: Color

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [tint.opacity(0.85), tint.opacity(0.30), .clear],
                    center: .center, startRadius: 6, endRadius: 96))
                .frame(width: 200, height: 200)
                .scaleEffect(0.55 + progress * 0.7)
                .opacity(1 - Double(progress))
                .position(point)

            Circle()
                .strokeBorder(tint.opacity(0.9), lineWidth: 3)
                .frame(width: 96, height: 96)
                .scaleEffect(0.45 + progress * 1.45)
                .opacity(1 - Double(progress))
                .position(point)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) { progress = 1 }
        }
    }
}

/// Generic rising aura for heals, mana, strength and control effects: a soft column of light,
/// an expanding ring and the effect's symbol drifting upward as motes. One time-driven Canvas.
struct AuraBurstAnimationView: View {
    let point: CGPoint
    let tint: Color
    let icon: String
    @State private var start = Date()

    private static let duration: Double = 1.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, _ in
                guard t < Self.duration else { return }
                let k = t / Self.duration
                let fade = 1 - k
                var glow = ctx
                glow.blendMode = .plusLighter
                // Column of light rising through the character.
                let columnHeight = CGFloat(150 * min(1, t / 0.25))
                glow.fill(Path(CGRect(x: point.x - 26, y: point.y + 40 - columnHeight, width: 52, height: columnHeight)),
                          with: .linearGradient(Gradient(colors: [tint.opacity(0.4 * fade), tint.opacity(0.12 * fade), .clear]),
                                                startPoint: CGPoint(x: point.x, y: point.y + 40),
                                                endPoint: CGPoint(x: point.x, y: point.y + 40 - columnHeight)))
                glow.fill(Path(ellipseIn: CGRect(x: point.x - 55, y: point.y - 55, width: 110, height: 110)),
                          with: .radialGradient(Gradient(colors: [tint.opacity(0.35 * fade), .clear]), center: point, startRadius: 0, endRadius: 55))
                // Expanding ring.
                let ring = CGFloat(20 + 52 * min(1, k * 1.6))
                ctx.stroke(Path(ellipseIn: CGRect(x: point.x - ring, y: point.y + 30 - ring * 0.32, width: ring * 2, height: ring * 0.64)),
                           with: .color(tint.opacity(0.8 * max(0, 1 - k * 1.4))), lineWidth: 2)
                // Rising symbols.
                var symbol = ctx.resolve(Image(systemName: icon))
                symbol.shading = .color(tint)
                for i in 0..<9 {
                    let seed = Double(i)
                    let delay = seed * 0.045
                    let local = t - delay
                    guard local > 0 else { continue }
                    let rise = CGFloat(local * (70 + seed.truncatingRemainder(dividingBy: 3) * 18))
                    let x = point.x + CGFloat(sin(seed * 2.4) * 34) + CGFloat(sin(local * 7 + seed) * 5)
                    let y = point.y + 30 - rise
                    let alpha = max(0, min(1, local / 0.1)) * max(0, 1 - local / (Self.duration - delay))
                    var mote = ctx
                    mote.opacity = alpha
                    let size = CGFloat(9 + (i % 3) * 3)
                    mote.draw(symbol, in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear { start = Date() }
    }
}

struct BattleFloater: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
    let point: CGPoint
    var icon: String? = nil
}

struct FloatingNumberView: View {
    let item: BattleFloater
    @State private var rise = false
    @State private var fade = false

    var body: some View {
        styled
            .scaleEffect(rise ? 1.0 : 0.6)
            .offset(y: rise ? -50 : 0)
            .opacity(fade ? 0 : 1)
            .position(item.point)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { rise = true }
                withAnimation(.easeIn(duration: 0.5).delay(0.7)) { fade = true }
            }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
            }
            if !item.text.isEmpty {
                Text(item.text)
                    .font(.serif(24, .bold))
            }
        }
    }

    private var styled: some View {
        label
            .foregroundStyle(item.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .overlay(Capsule().strokeBorder(item.color.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.9), radius: 4, y: 2)
    }
}

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 6
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travel * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

struct HPBarView: View {
    var current: Int
    var max: Int
    var width: CGFloat = 60
    var height: CGFloat = 6
    var isEnemy: Bool = false

    @State private var trailFraction: CGFloat = 1

    private var fraction: CGFloat {
        max > 0 ? CGFloat(Swift.max(0, Swift.min(current, max))) / CGFloat(max) : 0
    }

    private var fill: Color {
        if isEnemy { return Palette.crimson }
        return fraction > 0.3 ? Palette.moss : Palette.crimson
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.black.opacity(0.6))

            // Delayed "damage trail" (game.md §7.6): lingers at the old value, then catches up.
            Capsule()
                .fill(Palette.goldGlow.opacity(0.55))
                .frame(width: width * Swift.max(fraction, trailFraction))

            Capsule()
                .fill(fill)
                .frame(width: width * fraction)
        }
        .frame(width: width, height: height)
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(Palette.gold.opacity(0.4), lineWidth: 0.5)
        }
        .onAppear { trailFraction = fraction }
        .onChange(of: fraction) { _, newValue in
            if newValue > trailFraction {
                trailFraction = newValue
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(.easeOut(duration: 0.35)) {
                        trailFraction = newValue
                    }
                }
            }
        }
    }
}

/// What a won run fight is worth in experience, and who levels up (game.md §5 "Levels").
struct VictoryExperience {
    struct Hero: Identifiable {
        var id: String
        var spriteId: String
        var xpBefore: Int
        var xpAfter: Int
    }
    var gain: Int
    var heroes: [Hero]
    var leveling: LevelingConfig
}

struct CombatVictoryOverlay: View {
    var reward: NodeReward
    /// Run fights only; Test Fight gives no experience.
    var experience: VictoryExperience? = nil
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 16) {
                VictoryTreasureIllustration()
                    .frame(width: 84, height: 84)
                    .padding(.bottom, -6)

                Text("VICTORY")
                    .font(.serif(32, .bold))
                    .foregroundStyle(Palette.goldGlow)
                    .shadow(color: Palette.goldGlow, radius: 10)

                HStack(spacing: 14) {
                    if reward.gold > 0 {
                        RewardChip { GoldCoin(size: 22) } label: { Text("+\(reward.gold)") }
                    }
                    if let relic = reward.relic {
                        RewardChip { SpriteView(spriteId: relic.spriteId, kind: .relic, size: 30) } label: { RelicEffectLabel(effect: relic.effect) }
                    }
                    if let potion = reward.potion {
                        RewardChip { SpriteView(spriteId: potion.spriteId, kind: .consumable, size: 30) } label: { ItemEffectLabel(effect: potion.effect) }
                    }
                    if let gear = reward.gear {
                        RewardChip { GearArt(gear: gear, size: 30) } label: { GearEffectLabel(gear: gear) }
                    }
                    if reward.skillOffer != nil {
                        // A new skill to choose waits on the map (game.md §5).
                        RewardChip {
                            Image(systemName: "sparkles").font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.goldGlow)
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Palette.strength)
                        }
                        .accessibilityLabel("New skill")
                    }
                }

                if let experience {
                    experienceRow(experience)
                }

                Button(action: onContinue) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 60)
                }
                .buttonStyle(QuestButtonStyle(kind: .primary))
            }
            .parchment()
        }
    }
}

extension CombatVictoryOverlay {
    /// One large XP bar per hero; the gained XP is a number that drains into its bar.
    fileprivate func experienceRow(_ experience: VictoryExperience) -> some View {
        HStack(spacing: 14) {
            ForEach(experience.heroes) { hero in
                VictoryExperienceBar(hero: hero, leveling: experience.leveling)
            }
        }
    }
}

/// A hero's experience on the victory screen (game.md §7.5): `+N` counts down while the bar
/// fills by the same amount. Passing a level threshold fills the bar, restarts it at the new
/// level and shows LEVEL UP with a die (an upgrade to pick waits on the map).
private struct VictoryExperienceBar: View {
    let hero: VictoryExperience.Hero
    let leveling: LevelingConfig

    @State private var shownXP: Int?
    @State private var leveledUp = false

    private let barWidth: CGFloat = 130
    private let barHeight: CGFloat = 12

    var body: some View {
        let xp = shownXP ?? hero.xpBefore
        let level = leveling.level(forXP: xp)
        let bounds = leveling.bounds(forXP: xp)
        let fraction: CGFloat = bounds.next.map { CGFloat(xp - bounds.current) / CGFloat(max(1, $0 - bounds.current)) } ?? 1
        let remaining = hero.xpAfter - xp

        HStack(spacing: 8) {
            SpriteView(spriteId: hero.spriteId, kind: .hero, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LevelBadge(level: level, size: 20)
                    if leveledUp {
                        Text("LEVEL UP")
                            .font(.serif(12, .heavy))
                            .foregroundStyle(Palette.gold)
                            .transition(.scale.combined(with: .opacity))
                        // A die upgrade to pick waits on the map (game.md §5 "Levels").
                        DieGlyph(sides: DiceExpr.standardSides, tint: Palette.gold, size: 16)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    // The XP still to pour into the bar.
                    Text("+\(remaining)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .opacity(remaining > 0 ? 1 : 0.25)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.75))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.goldGlow, Palette.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(1, fraction)) * barWidth)
                }
                .frame(width: barWidth, height: barHeight)
                .overlay(Capsule().strokeBorder(Palette.gold, lineWidth: 1))
            }
            .frame(width: barWidth)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(leveledUp ? Palette.gold.opacity(0.18) : Palette.ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(leveledUp ? Palette.gold : .clear, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(leveling.level(forXP: hero.xpAfter)), plus \(hero.xpAfter - hero.xpBefore) experience")
        .task { await fill() }
    }

    /// Steps the shown XP from before to after (~1.2 s), so number, bar and level stay in sync.
    private func fill() async {
        let gain = hero.xpAfter - hero.xpBefore
        guard gain > 0 else { return }
        try? await Task.sleep(for: .milliseconds(450))
        let steps = min(gain, 40)
        var level = leveling.level(forXP: hero.xpBefore)
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(1200 / steps))
            let xp = hero.xpBefore + gain * step / steps
            shownXP = xp
            if leveling.level(forXP: xp) > level {
                level = leveling.level(forXP: xp)
                Sound.play(.skillLearn)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { leveledUp = true }
            }
        }
    }
}

struct CombatDefeatOverlay: View {
    var onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("DEFEAT")
                    .font(.serif(32, .bold))
                    .foregroundStyle(Palette.crimson)
                    .shadow(color: Palette.crimson, radius: 10)

                Button(action: onRetry) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 60)
                }
                .buttonStyle(QuestButtonStyle(kind: .primary))
            }
            .parchment()
        }
    }
}
