import SwiftUI

// MARK: - Stage Framing for iPad (game.md §17)

/// Rich dark wood-grain tabletop surface with plank seams, wood grain lines,
/// and a warm candlelit vignette. Used on the world map and as the letterbox frame on iPad.
struct TabletopSurfaceView: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let rect = CGRect(origin: .zero, size: size)

            // Base dark walnut/mahogany wood tone
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.14, green: 0.09, blue: 0.06),
                        Color(red: 0.21, green: 0.13, blue: 0.08),
                        Color(red: 0.13, green: 0.08, blue: 0.05)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: h)
                )
            )

            // Horizontal wood planks (scales with viewport height)
            let plankCount = max(3, Int((h / 70).rounded()))
            let plankH = h / CGFloat(plankCount)
            var rng = LinearCongruentialGenerator(seed: 42)
            for p in 0..<plankCount {
                let y0 = CGFloat(p) * plankH
                let plankRect = CGRect(x: 0, y: y0, width: w, height: plankH)
                let tint = (p % 2 == 0) ? Color.black.opacity(0.08) : Color(red: 0.32, green: 0.20, blue: 0.12).opacity(0.08)
                ctx.fill(Path(plankRect), with: .color(tint))

                // Wood grain lines along each plank
                for _ in 0..<10 {
                    let gy = y0 + rng.next(in: 4...(max(6, plankH - 4)))
                    var grain = Path()
                    grain.move(to: CGPoint(x: 0, y: gy))
                    let wave = rng.next(in: -3...3)
                    grain.addQuadCurve(
                        to: CGPoint(x: w, y: gy + rng.next(in: -2...2)),
                        control: CGPoint(x: w * rng.next(in: 0.3...0.7), y: gy + wave)
                    )
                    ctx.stroke(grain, with: .color(Color.black.opacity(0.18)), lineWidth: rng.next(in: 0.6...1.4))
                }

                // Plank seam groove
                if p > 0 {
                    var seam = Path()
                    seam.move(to: CGPoint(x: 0, y: y0))
                    seam.addLine(to: CGPoint(x: w, y: y0))
                    ctx.stroke(seam, with: .color(Color.black.opacity(0.65)), lineWidth: 2)
                    var highlight = Path()
                    highlight.move(to: CGPoint(x: 0, y: y0 + 1.5))
                    highlight.addLine(to: CGPoint(x: w, y: y0 + 1.5))
                    ctx.stroke(highlight, with: .color(Color(red: 0.45, green: 0.30, blue: 0.18).opacity(0.22)), lineWidth: 1)
                }
            }

            // Warm candlelight table vignette
            ctx.fill(
                Path(rect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.95, green: 0.72, blue: 0.38).opacity(0.08),
                        Color.black.opacity(0.55)
                    ]),
                    center: CGPoint(x: w * 0.5, y: h * 0.5),
                    startRadius: min(w, h) * 0.18,
                    endRadius: max(w, h) * 0.72
                )
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Where the game's 16:9 canvas sits in a window or screen, and the size it lays out at
/// (game.md §15). Pure math, so it's tested without a view.
nonisolated struct CanvasFit: Equatable {
    /// On-screen size of the canvas.
    var canvas: CGSize
    /// Size the content lays out at; `canvas` = `layout` × `scale`.
    var layout: CGSize
    var scale: CGFloat
    /// The canvas fills the whole container (no tabletop border).
    var fillsContainer: Bool
    /// Tabletop on the left and right instead of top and bottom.
    var isPillarboxed: Bool

    static let aspect: CGFloat = 16.0 / 9.0
    /// Shapes this close to 16:9 fill edge to edge instead of showing a thin border.
    static let aspectTolerance: CGFloat = 0.05
    /// The widest shape that fills edge to edge (iPhone landscape, 19.5:9 — layouts already
    /// handle it); only wider Mac windows get the tabletop left and right.
    static let widestFillAspect: CGFloat = 19.5 / 9
    /// Largest layout size; bigger canvases are scaled up evenly (iPad Pro 13" canvas).
    static let maxLayout = CGSize(width: 1366, height: 768)

    /// - Parameters:
    ///   - pillarbox: containers wider than `widestFillAspect` get side borders (Mac). Off: they
    ///     always fill (iPhone).
    ///   - scalesUp: canvases bigger than `maxLayout` lay out at `maxLayout` and scale (Mac).
    static func fit(in container: CGSize, pillarbox: Bool, scalesUp: Bool) -> CanvasFit {
        let currentAspect = container.height > 0 ? container.width / container.height : aspect
        var canvas = container
        var fills = true
        var pillarboxed = false
        if currentAspect < aspect - aspectTolerance {
            // Squarer (iPad 4:3, a tall Mac window): tabletop above and below.
            let width = min(container.width, container.height * aspect)
            canvas = CGSize(width: width, height: width / aspect)
            fills = false
        } else if pillarbox, currentAspect > widestFillAspect {
            // Wider (an ultra-wide Mac window): tabletop left and right.
            canvas = CGSize(width: container.height * aspect, height: container.height)
            fills = false
            pillarboxed = true
        }
        var scale: CGFloat = 1
        if scalesUp {
            scale = max(1, canvas.width / maxLayout.width, canvas.height / maxLayout.height)
        }
        let layout = CGSize(width: canvas.width / scale, height: canvas.height / scale)
        return CanvasFit(canvas: canvas, layout: layout, scale: scale, fillsContainer: fills, isPillarboxed: pillarboxed)
    }
}

/// The "study desk" behind the reading screens — decks, card editor, history, Glossary,
/// Bestiary, settings (game.md §17): the candlelit wooden table the map lies on. The night
/// mountains stay for the main menu and the run's own screens.
struct DeskBackground: View {
    var body: some View {
        ZStack {
            Palette.night
            TabletopSurfaceView()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Wraps content in a 16:9 widescreen canvas centered on screens with a narrower aspect ratio (such as iPad's 4:3).
/// On native widescreen devices (such as iPhone landscape ~16:9 to 19.5:9), content fills edge-to-edge with zero letterboxing.
/// On iPad, top and bottom margins are filled with the game's rich candlelit wood tabletop texture
/// bordered by subtle gilded filigree rules. On Mac, very wide windows get the tabletop left and
/// right, and canvases bigger than `CanvasFit.maxLayout` are scaled up evenly (game.md §15).
struct WidescreenCanvas<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.displayScale) private var displayScale

    #if os(macOS)
    private let pillarbox = true, scalesUp = true
    #else
    private let pillarbox = false, scalesUp = false
    #endif

    var body: some View {
        GeometryReader { proxy in
            let fit = CanvasFit.fit(in: proxy.size, pillarbox: pillarbox, scalesUp: scalesUp)
            if fit.fillsContainer && fit.scale == 1 {
                // Native widescreen (iPhone landscape): full-bleed edge-to-edge
                content()
                    .environment(\.canvasSize, fit.canvas)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    if !fit.fillsContainer {
                        // Outer decorative wooden tabletop filling the rest of the display
                        TabletopSurfaceView()
                            .ignoresSafeArea()
                    }

                    content()
                        .frame(width: fit.layout.width, height: fit.layout.height)
                        // Anything rasterized inside (map terrain, drawing groups) renders at
                        // the scaled-up resolution, not the layout's.
                        .environment(\.displayScale, displayScale * fit.scale)
                        .environment(\.canvasSize, fit.canvas)
                        .scaleEffect(fit.scale)
                        .frame(width: fit.canvas.width, height: fit.canvas.height)
                        .clipped()
                        // Subtle gold borders casting depth onto the table
                        .overlay {
                            if !fit.fillsContainer {
                                GildedCanvasEdges(vertical: fit.isPillarboxed)
                                    .allowsHitTesting(false)
                            }
                        }
                        .shadow(color: Color.black.opacity(fit.fillsContainer ? 0 : 0.6), radius: 14, y: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The two thin gold rules where the canvas meets the tabletop: top and bottom, or left and right.
private struct GildedCanvasEdges: View {
    var vertical: Bool

    var body: some View {
        let rule = LinearGradient(
            colors: [Palette.gold.opacity(0.35), Palette.gold.opacity(0.8), Palette.gold.opacity(0.35)],
            startPoint: vertical ? .top : .leading,
            endPoint: vertical ? .bottom : .trailing
        )
        if vertical {
            HStack(spacing: 0) {
                rule.frame(width: 1.5)
                Spacer()
                rule.frame(width: 1.5)
            }
        } else {
            VStack(spacing: 0) {
                rule.frame(height: 1.5)
                Spacer()
                rule.frame(height: 1.5)
            }
        }
    }
}

extension EnvironmentValues {
    /// The canvas's on-screen size in window points (game.md §15); Mac sheets size from it.
    @Entry var canvasSize: CGSize = .zero
}
