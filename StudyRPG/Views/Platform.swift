import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Platform bridge (game.md §15)
//
// The game runs natively on iPhone, iPad and Mac from one target. Everything that differs between
// UIKit and AppKit lives here, so the rest of the code uses one set of names.

#if canImport(UIKit)
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#else
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#endif

nonisolated enum PlatformGraphics {
    /// Pixel scale art is rendered at. Mac: 2 (every current Mac screen is Retina; on an older
    /// external display the art is just a little sharper than needed).
    static var displayScale: CGFloat {
        #if canImport(UIKit)
        UIGraphicsImageRendererFormat.preferred().scale
        #else
        2
        #endif
    }

    /// Draws into a new bitmap image of `size` points at `scale` (default: `displayScale`). The
    /// context has UIKit's top-left origin on every platform, and `PlatformColor.setFill()`,
    /// `NSAttributedString.draw` and `PlatformImage.draw(in:)` draw into it.
    static func image(size: CGSize, scale: CGFloat? = nil, draw: (CGContext) -> Void) -> PlatformImage {
        let scale = scale ?? displayScale
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        #else
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: size) }
        // Flip to a top-left origin and work in points, like UIGraphicsImageRenderer.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(context)
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = context.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: cgImage, size: size)
        #endif
    }

    /// `image` decoded at `pixels` (downsampling, never full size first where the platform can).
    static func downsampled(_ image: PlatformImage, toPixels pixels: CGSize, scale: CGFloat) -> PlatformImage {
        #if canImport(UIKit)
        if let thumb = image.preparingThumbnail(of: pixels), let cgImage = thumb.cgImage {
            return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        }
        #endif
        let size = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        return Self.image(size: size, scale: scale) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The image's height in pixels (its point size × its own scale).
    static func pixelHeight(of image: PlatformImage) -> CGFloat {
        #if canImport(UIKit)
        image.size.height * image.scale
        #else
        CGFloat(image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height))
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension Color {
    /// sRGB components (0…1) of this color, resolved through the platform color.
    nonisolated var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        (NSColor(self).usingColorSpace(.sRGB) ?? .black).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b, a)
    }
}

#if os(macOS)
/// The UIImage API the game's code relies on, for NSImage.
nonisolated extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func pngData() -> Data? {
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
#endif

extension View {
    /// Hides the bar a pushed screen would show (screens with their own chrome: map, fight).
    /// iOS: the navigation bar. Mac: the toolbar items — the window keeps its title bar (§15).
    func hiddenNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        toolbar(.hidden, for: .automatic)
        #endif
    }

    /// Tight spacing between list sections (iOS only; Mac lists are already compact).
    func compactListSections() -> some View {
        #if os(iOS)
        listSectionSpacing(.compact)
        #else
        self
        #endif
    }

    /// The size of a sheet (settings, party, character info, card editor). iOS: the system's.
    /// Mac sheets shrink to their content, so they get 90% of the canvas, within limits (§15).
    /// `fitting`: the size the sheet's content needs (Mac); still kept within the canvas.
    func gameSheetFrame(fitting: CGSize? = nil) -> some View {
        modifier(GameSheetFrame(fitting: fitting))
    }

    /// Mac: brightens slightly and shows the pointing hand while the pointer is over it, so
    /// everything clickable reads as clickable (game.md §15). iOS: nothing.
    func hoverHighlight(_ isEnabled: Bool = true, amount: Double = 0.07) -> some View {
        modifier(HoverHighlight(isEnabled: isEnabled, amount: amount))
    }

    /// A keyboard shortcut on Mac only (game.md §15 keys); nil or `isEnabled: false` = none.
    /// iOS keeps its touch-only behavior.
    func macKeyboardShortcut(_ shortcut: KeyboardShortcut?, isEnabled: Bool = true) -> some View {
        #if os(macOS)
        keyboardShortcut(isEnabled ? shortcut : nil)
        #else
        self
        #endif
    }

    /// `ignoresSafeArea` on iOS only. On Mac the top inset is the window's title bar, and
    /// content placed under it gets hidden or clipped (game.md §15).
    func ignoresSafeAreaOnIOS(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View {
        #if os(iOS)
        ignoresSafeArea(regions, edges: edges)
        #else
        self
        #endif
    }

    /// No automatic capitalization in text fields (iOS only; Mac fields never auto-capitalize).
    func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

private struct GameSheetFrame: ViewModifier {
    var fitting: CGSize?
    @Environment(\.canvasSize) private var canvasSize

    func body(content: Content) -> some View {
        #if os(macOS)
        let canvas = canvasSize == .zero ? CGSize(width: 1000, height: 660) : canvasSize
        let wanted = fitting ?? CGSize(width: min(1100, max(720, canvas.width * 0.9)),
                                      height: min(800, max(480, canvas.height * 0.9)))
        content.frame(
            width: min(wanted.width, max(480, canvas.width - 40)),
            height: min(wanted.height, max(360, canvas.height - 40))
        )
        #else
        content
        #endif
    }
}

private struct HoverHighlight: ViewModifier {
    var isEnabled: Bool
    var amount: Double
    @State private var isHovered = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .brightness(isEnabled && isHovered ? amount : 0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
            .pointerStyle(isEnabled ? .link : nil)
        #else
        content
        #endif
    }
}

// MARK: - Plain buttons

#if os(macOS)
/// Mac stand-in for `.plain`: the same undecorated look, plus hover feedback on every button
/// it styles (game.md §15).
struct GamePlainButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.5))
            .contentShape(Rectangle())
            .hoverHighlight(isEnabled)
    }
}

extension ButtonStyle where Self == GamePlainButtonStyle {
    /// `.plain` with hover feedback on Mac; exactly `.plain` on iOS.
    static var gamePlain: GamePlainButtonStyle { GamePlainButtonStyle() }
}
#else
extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    /// `.plain` with hover feedback on Mac; exactly `.plain` on iOS.
    static var gamePlain: PlainButtonStyle { .plain }
}
#endif
