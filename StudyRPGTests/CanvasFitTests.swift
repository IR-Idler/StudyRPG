import Testing
import CoreGraphics
@testable import StudyRPG

/// Where the 16:9 canvas sits and how big it lays out (game.md §15): iPhone fills, iPad and tall
/// windows get the tabletop above and below, wide Mac windows beside, big Mac windows scale up.
@Suite("Canvas fit")
struct CanvasFitTests {
    init() { Fixtures.isolateUserData() }

    private func aspect(_ size: CGSize) -> CGFloat { size.width / size.height }

    @Test("iPhone: a wider-than-16:9 screen fills edge to edge at its own size")
    func iPhoneFills() {
        let screen = CGSize(width: 874, height: 402)
        let fit = CanvasFit.fit(in: screen, pillarbox: false, scalesUp: false)
        #expect(fit.fillsContainer)
        #expect(fit.scale == 1)
        #expect(fit.layout == screen)
    }

    @Test("iPad: a squarer screen gets a full-width 16:9 canvas with the tabletop above and below")
    func iPadLetterboxes() {
        let screen = CGSize(width: 1180, height: 820)
        let fit = CanvasFit.fit(in: screen, pillarbox: false, scalesUp: false)
        #expect(!fit.fillsContainer)
        #expect(!fit.isPillarboxed)
        #expect(fit.canvas.width == screen.width)
        #expect(abs(aspect(fit.canvas) - CanvasFit.aspect) < 0.001)
        #expect(fit.scale == 1)
    }

    @Test("Mac: a window wider than iPhone landscape gets a full-height 16:9 canvas with the tabletop left and right")
    func macPillarboxes() {
        let window = CGSize(width: 540 * (CanvasFit.widestFillAspect + 0.2), height: 540)
        let fit = CanvasFit.fit(in: window, pillarbox: true, scalesUp: true)
        #expect(!fit.fillsContainer)
        #expect(fit.isPillarboxed)
        #expect(fit.canvas.height == window.height)
        #expect(abs(aspect(fit.canvas) - CanvasFit.aspect) < 0.001)
    }

    @Test("Mac: a window near 16:9 fills without a border")
    func macNearWidescreenFills() {
        let height: CGFloat = 600
        let window = CGSize(width: height * (CanvasFit.aspect + CanvasFit.aspectTolerance / 2), height: height)
        let fit = CanvasFit.fit(in: window, pillarbox: true, scalesUp: true)
        #expect(fit.fillsContainer)
        #expect(fit.canvas == window)
    }

    @Test("Mac: a window wider than 16:9 but no wider than iPhone landscape fills without side borders")
    func macWideWindowFills() {
        let height: CGFloat = 692
        for aspect in [CanvasFit.aspect + 0.1, CanvasFit.widestFillAspect] {
            let window = CGSize(width: height * aspect, height: height)
            let fit = CanvasFit.fit(in: window, pillarbox: true, scalesUp: true)
            #expect(fit.fillsContainer)
            #expect(fit.canvas == window)
        }
    }

    @Test("Mac: up to the largest layout size the canvas lays out at its real size")
    func macSmallWindowDoesNotScale() {
        let window = CGSize(width: CanvasFit.maxLayout.width * 0.7, height: CanvasFit.maxLayout.height * 0.7)
        let fit = CanvasFit.fit(in: window, pillarbox: true, scalesUp: true)
        #expect(fit.scale == 1)
        #expect(fit.layout == fit.canvas)
    }

    @Test("Mac: a bigger canvas lays out within the largest layout size and scales up evenly to fill")
    func macBigWindowScales() {
        for window in [CGSize(width: 2560, height: 1440), CGSize(width: 3008, height: 1692), CGSize(width: 2000, height: 1400)] {
            let fit = CanvasFit.fit(in: window, pillarbox: true, scalesUp: true)
            #expect(fit.scale > 1)
            #expect(fit.layout.width <= CanvasFit.maxLayout.width + 0.001)
            #expect(fit.layout.height <= CanvasFit.maxLayout.height + 0.001)
            #expect(abs(fit.layout.width * fit.scale - fit.canvas.width) < 0.001)
            #expect(abs(fit.layout.height * fit.scale - fit.canvas.height) < 0.001)
            #expect(fit.canvas.width <= window.width && fit.canvas.height <= window.height)
        }
    }
}
