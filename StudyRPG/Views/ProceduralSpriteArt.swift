import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Procedural sprite art (game.md §17)
//
// Bespoke vector art for every enemy/item/relic that has no hand-drawn PNG yet. Drawn on a
// normalized 100×100 grid so it scales cleanly from a 14pt potion icon to a 165pt boss. When a
// matching PNG is added to Assets.xcassets, `SpriteView` prefers it automatically.

private struct ArtGrid {
    let side: CGFloat
    let origin: CGPoint

    func p(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(x / 100) * side, y: origin.y + CGFloat(y / 100) * side)
    }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(x / 100) * side,
            y: origin.y + CGFloat(y / 100) * side,
            width: CGFloat(w / 100) * side,
            height: CGFloat(h / 100) * side
        )
    }

    func v(_ length: Double) -> CGFloat { CGFloat(length / 100) * side }
}

struct ProceduralSpriteArt: View {
    let spriteId: String

    private static let supported: Set<String> = ["troll", "witch", "dragon", "sentinel"]

    /// Enemies are drawn here; potions, relics and gear by `ItemArt`.
    static func hasArt(for id: String) -> Bool { supported.contains(id.lowercased()) || ItemArt.canDraw(id) }

    var body: some View {
        if ItemArt.canDraw(spriteId) {
            ItemArtView(spriteId: spriteId)
        } else {
            enemyArt
        }
    }

    private var enemyArt: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let grid = ArtGrid(side: side, origin: CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2))
            var ctx = context
            ctx.addFilter(.shadow(color: .black.opacity(0.35), radius: side * 0.02, x: 0, y: side * 0.015))

            switch spriteId.lowercased() {
            case "troll": Self.drawTroll(&ctx, grid)
            case "witch": Self.drawWitch(&ctx, grid)
            case "dragon": Self.drawDragon(&ctx, grid)
            case "sentinel": Self.drawSentinel(&ctx, grid)
            default: break
            }
        }
    }

    // MARK: Enemies

    /// Act II's laser robot (game.md §16): clean white armor plates over dark joints, a glowing
    /// cyan visor and chest core, and a laser cannon arm aimed left at the heroes.
    private static func drawSentinel(_ ctx: inout GraphicsContext, _ g: ArtGrid) {
        let plate = Color(red: 0.94, green: 0.96, blue: 0.98)
        let plateShade = Color(red: 0.70, green: 0.75, blue: 0.82)
        let joint = Color(red: 0.17, green: 0.19, blue: 0.24)
        let cyan = Color(red: 0.30, green: 0.90, blue: 1.0)
        let ink = Color(red: 0.12, green: 0.14, blue: 0.19)
        func platePath(_ path: Path) {
            ctx.fill(path, with: .linearGradient(Gradient(colors: [plate, plateShade]),
                                                 startPoint: CGPoint(x: path.boundingRect.minX, y: path.boundingRect.minY),
                                                 endPoint: CGPoint(x: path.boundingRect.maxX, y: path.boundingRect.maxY)))
            ctx.stroke(path, with: .color(ink.opacity(0.85)), lineWidth: g.v(0.9))
        }
        func glow(_ center: CGPoint, _ radius: Double) {
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - g.v(radius), y: center.y - g.v(radius), width: g.v(radius * 2), height: g.v(radius * 2))),
                     with: .radialGradient(Gradient(colors: [cyan.opacity(0.6), cyan.opacity(0)]), center: center, startRadius: 0, endRadius: g.v(radius)))
        }

        // Back arm (right side): upper arm, forearm, dark hand.
        ctx.fill(Path(roundedRect: g.rect(70, 36, 6, 22), cornerRadius: g.v(2)), with: .color(joint))
        platePath(Path(roundedRect: g.rect(69, 40, 9, 12), cornerRadius: g.v(3)))
        platePath(Path(roundedRect: g.rect(70, 54, 8, 12), cornerRadius: g.v(3)))
        ctx.fill(Path(ellipseIn: g.rect(70, 65, 8, 7)), with: .color(joint))

        // Legs: dark joints, white shin plates, wedge feet.
        for x in [37.0, 54.0] {
            ctx.fill(Path(roundedRect: g.rect(x + 1, 62, 7, 30), cornerRadius: g.v(2)), with: .color(joint))
            platePath(Path(roundedRect: g.rect(x - 1, 66, 11, 11), cornerRadius: g.v(3)))
            platePath(Path(roundedRect: g.rect(x, 79, 10, 12), cornerRadius: g.v(3)))
            ctx.fill(Path(ellipseIn: g.rect(x + 2, 75.5, 6, 5)), with: .color(joint))
            var foot = Path()
            foot.move(to: g.p(x - 4, 97)); foot.addLine(to: g.p(x + 13, 97)); foot.addLine(to: g.p(x + 10, 91)); foot.addLine(to: g.p(x - 1, 91)); foot.closeSubpath()
            ctx.fill(foot, with: .color(joint))
            ctx.fill(Path(CGRect(x: g.p(x, 95).x, y: g.p(x, 95).y, width: g.v(9), height: g.v(0.8))), with: .color(cyan.opacity(0.8)))
        }

        // Pelvis and torso with a glowing chest core.
        ctx.fill(Path(roundedRect: g.rect(38, 58, 24, 9), cornerRadius: g.v(3)), with: .color(joint))
        var torso = Path()
        torso.move(to: g.p(33, 32)); torso.addLine(to: g.p(67, 32)); torso.addLine(to: g.p(63, 60))
        torso.addQuadCurve(to: g.p(37, 60), control: g.p(50, 64)); torso.closeSubpath()
        platePath(torso)
        var seam = Path()
        seam.move(to: g.p(50, 34)); seam.addLine(to: g.p(50, 40))
        seam.move(to: g.p(38, 52)); seam.addQuadCurve(to: g.p(62, 52), control: g.p(50, 56))
        ctx.stroke(seam, with: .color(ink.opacity(0.35)), lineWidth: g.v(0.7))
        glow(g.p(50, 45), 9)
        ctx.fill(Path(ellipseIn: g.rect(45.5, 40.5, 9, 9)), with: .color(joint))
        ctx.fill(Path(ellipseIn: g.rect(47, 42, 6, 6)), with: .color(cyan))
        ctx.fill(Path(ellipseIn: g.rect(48, 43, 2, 2)), with: .color(.white))

        // Shoulders.
        platePath(Path(ellipseIn: g.rect(61, 27, 15, 13)))
        platePath(Path(ellipseIn: g.rect(23, 27, 15, 13)))

        // Head: a rounded helm with a glowing visor band and a small antenna.
        ctx.fill(Path(roundedRect: g.rect(45, 25, 10, 6), cornerRadius: g.v(1)), with: .color(joint))
        platePath(Path(roundedRect: g.rect(39, 9, 22, 18), cornerRadius: g.v(6)))
        var antenna = Path()
        antenna.move(to: g.p(56, 10)); antenna.addLine(to: g.p(59, 3))
        ctx.stroke(antenna, with: .color(joint), style: StrokeStyle(lineWidth: g.v(1.2), lineCap: .round))
        ctx.fill(Path(ellipseIn: g.rect(57.6, 1.6, 3, 3)), with: .color(cyan))
        glow(g.p(46, 17), 9)
        ctx.fill(Path(roundedRect: g.rect(37.5, 14.5, 20, 6), cornerRadius: g.v(3)), with: .color(joint))
        ctx.fill(Path(roundedRect: g.rect(38.5, 15.5, 18, 4), cornerRadius: g.v(2)), with: .linearGradient(
            Gradient(colors: [.white, cyan]), startPoint: g.p(38, 16), endPoint: g.p(57, 19)))

        // Front arm: the laser cannon, aimed left at the heroes.
        ctx.fill(Path(roundedRect: g.rect(26, 36, 6, 14), cornerRadius: g.v(2)), with: .color(joint))
        platePath(Path(roundedRect: g.rect(22, 38, 11, 11), cornerRadius: g.v(3)))
        var cannon = Path()
        cannon.addRoundedRect(in: g.rect(6, 45, 26, 10), cornerSize: CGSize(width: g.v(3), height: g.v(3)))
        platePath(cannon)
        ctx.fill(Path(roundedRect: g.rect(3, 46.5, 6, 7), cornerRadius: g.v(1.5)), with: .color(joint))
        for x in [14.0, 19.0, 24.0] {
            ctx.fill(Path(CGRect(x: g.p(x, 47).x, y: g.p(x, 47).y, width: g.v(1.2), height: g.v(6))), with: .color(cyan.opacity(0.85)))
        }
        glow(g.p(3, 50), 6)
        ctx.fill(Path(ellipseIn: g.rect(1.5, 48.5, 3, 3)), with: .color(.white))
    }

    private static func drawTroll(_ ctx: inout GraphicsContext, _ g: ArtGrid) {
        let stone = Color(red: 0.45, green: 0.47, blue: 0.42)
        let stoneDark = Color(red: 0.30, green: 0.33, blue: 0.30)
        let belly = Color(red: 0.58, green: 0.58, blue: 0.50)
        let wood = Color(red: 0.34, green: 0.25, blue: 0.18)
        let ivory = Color(red: 0.93, green: 0.89, blue: 0.78)

        // Spiked club, behind the body.
        var club = Path()
        club.move(to: g.p(72, 64))
        club.addLine(to: g.p(87, 30))
        ctx.stroke(club, with: .color(wood), style: StrokeStyle(lineWidth: g.v(6), lineCap: .round))
        let clubHead = g.p(88, 25)
        for step in 0..<8 {
            let angle = Double(step) * .pi / 4
            var spike = Path()
            spike.move(to: CGPoint(x: clubHead.x + CGFloat(cos(angle)) * g.v(4), y: clubHead.y + CGFloat(sin(angle)) * g.v(4)))
            spike.addLine(to: CGPoint(x: clubHead.x + CGFloat(cos(angle)) * g.v(10), y: clubHead.y + CGFloat(sin(angle)) * g.v(10)))
            ctx.stroke(spike, with: .color(stoneDark), style: StrokeStyle(lineWidth: g.v(2.4), lineCap: .round))
        }
        ctx.fill(Path(ellipseIn: g.rect(83, 20, 10, 10)), with: .color(wood))

        // Legs and feet.
        ctx.fill(Path(roundedRect: g.rect(33, 68, 18, 30), cornerRadius: g.v(7)), with: .color(stoneDark))
        ctx.fill(Path(roundedRect: g.rect(53, 68, 18, 30), cornerRadius: g.v(7)), with: .color(stoneDark))
        ctx.fill(Path(ellipseIn: g.rect(29, 92, 24, 8)), with: .color(stoneDark))
        ctx.fill(Path(ellipseIn: g.rect(51, 92, 24, 8)), with: .color(stoneDark))

        // Hunched torso.
        ctx.fill(Path(ellipseIn: g.rect(24, 36, 52, 44)), with: .color(stone))
        ctx.fill(Path(ellipseIn: g.rect(35, 52, 32, 25)), with: .color(belly.opacity(0.55)))

        // Arms.
        var leftArm = Path()
        leftArm.move(to: g.p(30, 48)); leftArm.addLine(to: g.p(21, 76))
        ctx.stroke(leftArm, with: .color(stone), style: StrokeStyle(lineWidth: g.v(10), lineCap: .round))
        ctx.fill(Path(ellipseIn: g.rect(15, 71, 14, 14)), with: .color(stoneDark))
        var rightArm = Path()
        rightArm.move(to: g.p(72, 48)); rightArm.addLine(to: g.p(82, 60))
        ctx.stroke(rightArm, with: .color(stone), style: StrokeStyle(lineWidth: g.v(9), lineCap: .round))
        ctx.fill(Path(ellipseIn: g.rect(76, 55, 13, 13)), with: .color(stoneDark))

        // Head.
        ctx.fill(Path(ellipseIn: g.rect(36, 16, 32, 30)), with: .color(stone))
        var brow = Path()
        brow.move(to: g.p(40, 27)); brow.addLine(to: g.p(48, 25))
        brow.move(to: g.p(56, 25)); brow.addLine(to: g.p(64, 27))
        ctx.stroke(brow, with: .color(stoneDark), style: StrokeStyle(lineWidth: g.v(2.2), lineCap: .round))
        for x in [46.0, 58.0] {
            ctx.fill(Path(ellipseIn: g.rect(x - 2.4, 28, 4.8, 4.8)), with: .color(Palette.goldGlow))
            ctx.fill(Path(ellipseIn: g.rect(x - 0.9, 29.4, 1.8, 1.8)), with: .color(.black.opacity(0.8)))
        }
        var nose = Path()
        nose.move(to: g.p(50, 32)); nose.addLine(to: g.p(54, 38)); nose.addLine(to: g.p(47, 38)); nose.closeSubpath()
        ctx.fill(nose, with: .color(stoneDark.opacity(0.7)))
        for x in [43.0, 57.0] {
            var tusk = Path()
            tusk.move(to: g.p(x - 2, 41)); tusk.addLine(to: g.p(x, 34)); tusk.addLine(to: g.p(x + 2, 41)); tusk.closeSubpath()
            ctx.fill(tusk, with: .color(ivory))
        }

        // Stone cracks.
        var cracks = Path()
        cracks.move(to: g.p(36, 46)); cracks.addLine(to: g.p(42, 52)); cracks.addLine(to: g.p(38, 58))
        cracks.move(to: g.p(62, 44)); cracks.addLine(to: g.p(68, 50))
        ctx.stroke(cracks, with: .color(stoneDark.opacity(0.8)), style: StrokeStyle(lineWidth: g.v(1.2), lineCap: .round))
    }

    private static func drawWitch(_ ctx: inout GraphicsContext, _ g: ArtGrid) {
        let cloak = Color(red: 0.34, green: 0.26, blue: 0.41)
        let cloakDark = Color(red: 0.21, green: 0.15, blue: 0.28)
        let skin = Color(red: 0.64, green: 0.71, blue: 0.52)
        let wood = Color(red: 0.36, green: 0.26, blue: 0.18)
        let orb = Color(red: 0.56, green: 0.88, blue: 0.48)

        // Staff and glowing orb.
        var staff = Path()
        staff.move(to: g.p(79, 24)); staff.addLine(to: g.p(67, 96))
        ctx.stroke(staff, with: .color(wood), style: StrokeStyle(lineWidth: g.v(4), lineCap: .round))
        ctx.fill(Path(ellipseIn: g.rect(70, 10, 18, 18)), with: .color(orb.opacity(0.18)))
        ctx.fill(Path(ellipseIn: g.rect(74, 14, 10, 10)), with: .color(orb))
        ctx.fill(Path(ellipseIn: g.rect(76.5, 16.5, 3, 3)), with: .color(.white.opacity(0.75)))

        // Sparkles around the orb.
        for spark in [(86.0, 7.0, 2.0), (91.0, 22.0, 1.4), (69.0, 5.0, 1.6), (63.0, 15.0, 1.2)] {
            var path = Path()
            path.move(to: g.p(spark.0, spark.1 - spark.2)); path.addLine(to: g.p(spark.0, spark.1 + spark.2))
            path.move(to: g.p(spark.0 - spark.2, spark.1)); path.addLine(to: g.p(spark.0 + spark.2, spark.1))
            ctx.stroke(path, with: .color(orb.opacity(0.9)), style: StrokeStyle(lineWidth: g.v(0.9), lineCap: .round))
        }

        // Ragged cloak.
        var cloakPath = Path()
        cloakPath.move(to: g.p(50, 24))
        cloakPath.addLine(to: g.p(32, 95))
        cloakPath.addLine(to: g.p(40, 88))
        cloakPath.addLine(to: g.p(45, 96))
        cloakPath.addLine(to: g.p(50, 89))
        cloakPath.addLine(to: g.p(55, 96))
        cloakPath.addLine(to: g.p(60, 88))
        cloakPath.addLine(to: g.p(68, 95))
        cloakPath.closeSubpath()
        ctx.fill(cloakPath, with: .linearGradient(
            Gradient(colors: [cloak, cloakDark]),
            startPoint: g.p(50, 24), endPoint: g.p(50, 96)))
        ctx.fill(Path(ellipseIn: g.rect(38, 20, 24, 11)), with: .color(cloakDark))

        // Face and hooked nose.
        ctx.fill(Path(ellipseIn: g.rect(44, 18, 14, 16)), with: .color(skin))
        var nose = Path()
        nose.move(to: g.p(57, 25)); nose.addLine(to: g.p(64, 30)); nose.addLine(to: g.p(56, 31)); nose.closeSubpath()
        ctx.fill(nose, with: .color(skin))
        ctx.fill(Path(ellipseIn: g.rect(53, 23, 3, 3)), with: .color(Palette.goldGlow))

        // Crooked hat with gold buckle.
        var hat = Path()
        hat.move(to: g.p(50, 2))
        hat.addQuadCurve(to: g.p(34, 19), control: g.p(60, 10))
        hat.addLine(to: g.p(66, 21))
        hat.addQuadCurve(to: g.p(50, 2), control: g.p(54, 12))
        hat.closeSubpath()
        ctx.fill(hat, with: .color(cloakDark))
        ctx.fill(Path(ellipseIn: g.rect(32, 17, 36, 7)), with: .color(cloakDark))
        ctx.fill(Path(roundedRect: g.rect(47, 12, 6, 5), cornerRadius: g.v(1)), with: .color(Palette.gold))
    }

    private static func drawDragon(_ ctx: inout GraphicsContext, _ g: ArtGrid) {
        let red = Color(red: 0.56, green: 0.20, blue: 0.18)
        let redDark = Color(red: 0.38, green: 0.12, blue: 0.12)
        let membrane = Color(red: 0.45, green: 0.15, blue: 0.15)
        let belly = Color(red: 0.78, green: 0.48, blue: 0.32)
        let horn = Color(red: 0.85, green: 0.80, blue: 0.68)

        // Tail.
        var tail = Path()
        tail.move(to: g.p(36, 74))
        tail.addQuadCurve(to: g.p(10, 90), control: g.p(20, 88))
        ctx.stroke(tail, with: .color(redDark), style: StrokeStyle(lineWidth: g.v(7), lineCap: .round))
        var tailTip = Path()
        tailTip.move(to: g.p(10, 90)); tailTip.addLine(to: g.p(5, 81)); tailTip.addLine(to: g.p(16, 84)); tailTip.closeSubpath()
        ctx.fill(tailTip, with: .color(redDark))

        // Wings behind the body.
        var leftWing = Path()
        leftWing.move(to: g.p(42, 46)); leftWing.addLine(to: g.p(8, 20))
        leftWing.addLine(to: g.p(16, 50)); leftWing.addLine(to: g.p(30, 62)); leftWing.closeSubpath()
        ctx.fill(leftWing, with: .color(membrane))
        ctx.stroke(leftWing, with: .color(redDark), lineWidth: g.v(1.6))
        var rightWing = Path()
        rightWing.move(to: g.p(58, 44)); rightWing.addLine(to: g.p(92, 18))
        rightWing.addLine(to: g.p(86, 48)); rightWing.addLine(to: g.p(70, 60)); rightWing.closeSubpath()
        ctx.fill(rightWing, with: .color(membrane))
        ctx.stroke(rightWing, with: .color(redDark), lineWidth: g.v(1.6))

        // Legs and claws.
        for x in [36.0, 56.0] {
            ctx.fill(Path(roundedRect: g.rect(x, 76, 10, 18), cornerRadius: g.v(4)), with: .color(redDark))
            for claw in 0..<3 {
                var path = Path()
                let cx = x + 2 + Double(claw) * 3
                path.move(to: g.p(cx, 93)); path.addLine(to: g.p(cx + 1, 98))
                ctx.stroke(path, with: .color(horn), style: StrokeStyle(lineWidth: g.v(1.4), lineCap: .round))
            }
        }

        // Body, belly and neck.
        ctx.fill(Path(ellipseIn: g.rect(30, 54, 38, 32)), with: .color(red))
        ctx.fill(Path(ellipseIn: g.rect(36, 66, 24, 16)), with: .color(belly.opacity(0.9)))
        var neck = Path()
        neck.move(to: g.p(58, 62)); neck.addQuadCurve(to: g.p(70, 38), control: g.p(72, 54))
        ctx.stroke(neck, with: .color(red), style: StrokeStyle(lineWidth: g.v(14), lineCap: .round))

        // Head, snout, horns and eye.
        ctx.fill(Path(ellipseIn: g.rect(62, 26, 26, 16)), with: .color(red))
        var snout = Path()
        snout.move(to: g.p(84, 30)); snout.addLine(to: g.p(94, 34)); snout.addLine(to: g.p(84, 38)); snout.closeSubpath()
        ctx.fill(snout, with: .color(red))
        var horns = Path()
        horns.move(to: g.p(64, 27)); horns.addLine(to: g.p(59, 15)); horns.addLine(to: g.p(68, 24))
        horns.move(to: g.p(72, 25)); horns.addLine(to: g.p(74, 13)); horns.addLine(to: g.p(78, 24))
        ctx.fill(horns, with: .color(horn))
        ctx.fill(Path(ellipseIn: g.rect(76, 31, 4.5, 4.5)), with: .color(Palette.goldGlow))
        ctx.fill(Path(ellipseIn: g.rect(77.4, 32.4, 1.8, 1.8)), with: .color(.black.opacity(0.85)))

        // Embers escaping the snout.
        for ember in [(97.0, 30.0, 1.4), (98.0, 36.0, 1.0), (94.0, 41.0, 0.8)] {
            ctx.fill(Path(ellipseIn: g.rect(ember.0 - ember.2, ember.1 - ember.2, ember.2 * 2, ember.2 * 2)),
                     with: .color(Palette.ember.opacity(0.85)))
        }

        // Back spikes.
        var spikes = Path()
        for i in 0..<4 {
            let x = 40.0 + Double(i) * 6
            let y = 54.0 - Double(i) * 1.2
            spikes.move(to: g.p(x, y)); spikes.addLine(to: g.p(x + 2, y - 6)); spikes.addLine(to: g.p(x + 4, y))
        }
        ctx.fill(spikes, with: .color(horn.opacity(0.9)))
    }
}

struct LinearCongruentialGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = (state &* 6364136223846793005) &+ 1442695040888963407
        return state
    }
    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let normalized = CGFloat(next() % 10000) / 10000.0
        return range.lowerBound + normalized * (range.upperBound - range.lowerBound)
    }
}
