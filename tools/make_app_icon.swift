import AppKit
import CoreGraphics

// Study RPG app icon (game.md §17 palette): night sky, warm glow, a parchment flashcard with a
// gilded "?", a gold-hilted sword behind it and a red enemy die in front. Full-bleed square —
// the system applies the icon shape on every platform.
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)   // top-left origin
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)! }

let night = rgb(0.07, 0.09, 0.13), dusk = rgb(0.13, 0.16, 0.23), horizon = rgb(0.30, 0.25, 0.36)
let parchment = rgb(0.93, 0.89, 0.79), parchmentShade = rgb(0.78, 0.71, 0.58), ink = rgb(0.19, 0.16, 0.13)
let gold = rgb(0.86, 0.72, 0.44), goldLight = rgb(0.99, 0.88, 0.62), goldDark = rgb(0.55, 0.42, 0.20)
let glow = rgb(0.98, 0.78, 0.48)

// 1. Sky
ctx.drawLinearGradient(gradient([night, dusk, horizon], [0, 0.55, 1]), start: .zero, end: CGPoint(x: 0, y: S), options: [])
// Stars (seeded, upper part)
var seed: UInt64 = 7
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) }
for _ in 0..<46 {
    let x = rnd() * S, y = rnd() * S * 0.62, r = 1.5 + rnd() * 3.2
    ctx.setFillColor(rgb(1, 0.96, 0.88, 0.35 + rnd() * 0.5))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
// 2. Warm glow behind the card
ctx.drawRadialGradient(gradient([rgb(0.98, 0.78, 0.48, 0.55), rgb(0.98, 0.78, 0.48, 0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 540), startRadius: 0, endCenter: CGPoint(x: 512, y: 540), endRadius: 470, options: [])

// 3. Sword, behind the card: hilt bottom-left, tip top-right
ctx.saveGState()
ctx.translateBy(x: 512, y: 512); ctx.rotate(by: .pi / 4)   // blade along -y after rotation → points top-right
let bladeW: CGFloat = 78, bladeTop: CGFloat = -470, bladeBottom: CGFloat = 250
let blade = CGMutablePath()
blade.move(to: CGPoint(x: 0, y: bladeTop))
blade.addLine(to: CGPoint(x: bladeW / 2, y: bladeTop + 90))
blade.addLine(to: CGPoint(x: bladeW / 2, y: bladeBottom))
blade.addLine(to: CGPoint(x: -bladeW / 2, y: bladeBottom))
blade.addLine(to: CGPoint(x: -bladeW / 2, y: bladeTop + 90))
blade.closeSubpath()
ctx.saveGState(); ctx.addPath(blade); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0.62, 0.68, 0.76), rgb(0.96, 0.97, 0.99), rgb(0.55, 0.60, 0.70)], [0, 0.5, 1]),
                       start: CGPoint(x: -bladeW / 2, y: 0), end: CGPoint(x: bladeW / 2, y: 0), options: [])
ctx.restoreGState()
ctx.addPath(blade); ctx.setStrokeColor(rgb(0.16, 0.17, 0.22)); ctx.setLineWidth(7); ctx.strokePath()
ctx.setStrokeColor(rgb(0.45, 0.50, 0.58, 0.8)); ctx.setLineWidth(5)   // fuller (center ridge)
ctx.move(to: CGPoint(x: 0, y: bladeTop + 110)); ctx.addLine(to: CGPoint(x: 0, y: bladeBottom - 10)); ctx.strokePath()
// Crossguard
let guardRect = CGRect(x: -150, y: bladeBottom, width: 300, height: 52)
let guardPath = CGPath(roundedRect: guardRect, cornerWidth: 24, cornerHeight: 24, transform: nil)
ctx.saveGState(); ctx.addPath(guardPath); ctx.clip()
ctx.drawLinearGradient(gradient([goldLight, gold, goldDark], [0, 0.5, 1]), start: CGPoint(x: 0, y: guardRect.minY), end: CGPoint(x: 0, y: guardRect.maxY), options: [])
ctx.restoreGState()
ctx.addPath(guardPath); ctx.setStrokeColor(rgb(0.25, 0.17, 0.08)); ctx.setLineWidth(7); ctx.strokePath()
// Grip
let grip = CGRect(x: -30, y: bladeBottom + 52, width: 60, height: 150)
ctx.setFillColor(rgb(0.35, 0.20, 0.12)); ctx.fill(grip)
ctx.setStrokeColor(rgb(0.22, 0.12, 0.07)); ctx.setLineWidth(6)
for i in 0..<5 { let y = grip.minY + 18 + CGFloat(i) * 28; ctx.move(to: CGPoint(x: grip.minX, y: y)); ctx.addLine(to: CGPoint(x: grip.maxX, y: y + 14)); ctx.strokePath() }
ctx.stroke(grip, width: 6)
// Pommel
let pommel = CGRect(x: -50, y: grip.maxY - 6, width: 100, height: 100)
ctx.saveGState(); ctx.addEllipse(in: pommel); ctx.clip()
ctx.drawRadialGradient(gradient([goldLight, gold, goldDark], [0, 0.55, 1]), startCenter: CGPoint(x: -15, y: pommel.minY + 35), startRadius: 0,
                       endCenter: CGPoint(x: 0, y: pommel.midY), endRadius: 60, options: [])
ctx.restoreGState()
ctx.addEllipse(in: pommel); ctx.setStrokeColor(rgb(0.25, 0.17, 0.08)); ctx.setLineWidth(7); ctx.strokePath()
ctx.restoreGState()

// 4. Flashcard, tilted, with shadow
ctx.saveGState()
ctx.translateBy(x: 500, y: 545); ctx.rotate(by: -0.16)
let cardW: CGFloat = 450, cardH: CGFloat = 590
let card = CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH)
let cardPath = CGPath(roundedRect: card, cornerWidth: 44, cornerHeight: 44, transform: nil)
ctx.setShadow(offset: CGSize(width: 0, height: 26), blur: 46, color: rgb(0, 0, 0, 0.6))
ctx.addPath(cardPath); ctx.setFillColor(parchment); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.saveGState(); ctx.addPath(cardPath); ctx.clip()
ctx.drawRadialGradient(gradient([parchment, rgb(0.90, 0.85, 0.74), parchmentShade], [0, 0.6, 1]),
                       startCenter: CGPoint(x: -40, y: -80), startRadius: 0, endCenter: .zero, endRadius: 400, options: [])
ctx.restoreGState()
// Gold double rule
ctx.addPath(cardPath); ctx.setStrokeColor(gold); ctx.setLineWidth(14); ctx.strokePath()
let inner = card.insetBy(dx: 30, dy: 30)
ctx.addPath(CGPath(roundedRect: inner, cornerWidth: 24, cornerHeight: 24, transform: nil))
ctx.setStrokeColor(rgb(0.70, 0.55, 0.28, 0.85)); ctx.setLineWidth(5); ctx.strokePath()
// Corner diamonds
for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
    let c = CGPoint(x: CGFloat(dx) * (inner.width / 2 - 34), y: CGFloat(dy) * (inner.height / 2 - 34))
    let d = CGMutablePath(); let r: CGFloat = 15
    d.move(to: CGPoint(x: c.x, y: c.y - r)); d.addLine(to: CGPoint(x: c.x + r, y: c.y)); d.addLine(to: CGPoint(x: c.x, y: c.y + r)); d.addLine(to: CGPoint(x: c.x - r, y: c.y)); d.closeSubpath()
    ctx.addPath(d); ctx.setFillColor(gold); ctx.fillPath()
}
// The "?"
let font = NSFont(name: "Georgia-Bold", size: 400) ?? NSFont.systemFont(ofSize: 400, weight: .heavy)
let shadow = NSShadow(); shadow.shadowColor = NSColor(cgColor: goldDark)!.withAlphaComponent(0.55); shadow.shadowOffset = NSSize(width: 0, height: 8); shadow.shadowBlurRadius = 2
let q = NSAttributedString(string: "?", attributes: [.font: font, .foregroundColor: NSColor(cgColor: ink)!, .shadow: shadow])
let qs = q.size()
q.draw(at: CGPoint(x: -qs.width / 2, y: -qs.height / 2 - 6))
ctx.restoreGState()

// 5. Red enemy die, front bottom-right
ctx.saveGState()
ctx.translateBy(x: 800, y: 812); ctx.rotate(by: 0.32)
let dieS: CGFloat = 210
let die = CGRect(x: -dieS / 2, y: -dieS / 2, width: dieS, height: dieS)
let diePath = CGPath(roundedRect: die, cornerWidth: 40, cornerHeight: 40, transform: nil)
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 30, color: rgb(0, 0, 0, 0.6))
ctx.addPath(diePath); ctx.setFillColor(rgb(0.50, 0.19, 0.16)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.saveGState(); ctx.addPath(diePath); ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0.72, 0.30, 0.24), rgb(0.50, 0.19, 0.16), rgb(0.32, 0.11, 0.10)], [0, 0.6, 1]),
                       startCenter: CGPoint(x: -40, y: -50), startRadius: 0, endCenter: .zero, endRadius: 160, options: [])
ctx.restoreGState()
ctx.addPath(diePath); ctx.setStrokeColor(rgb(0.20, 0.07, 0.06)); ctx.setLineWidth(7); ctx.strokePath()
ctx.setFillColor(rgb(0.95, 0.91, 0.83))
for (px, py) in [(-0.27, -0.27), (0.27, -0.27), (0.0, 0.0), (-0.27, 0.27), (0.27, 0.27)] {
    let r: CGFloat = 21
    ctx.fillEllipse(in: CGRect(x: CGFloat(px) * dieS - r, y: CGFloat(py) * dieS - r, width: r * 2, height: r * 2))
}
ctx.restoreGState()

// 6. Soft vignette
ctx.drawRadialGradient(gradient([rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.45)], [0.55, 1]),
                       startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 760, options: [])

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("ok")
