import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

/// Right-sized copies of catalog art (game.md §17 "Art sizing"). Every PNG the game shows goes
/// through here, so the artist can export at any resolution: only a copy at the size it's actually
/// displayed (× the screen's pixel scale) stays in memory. Never upscales.
enum ArtCache {
    /// NSCache is thread-safe; the map terrain Canvas may paint off the main thread.
    nonisolated(unsafe) private static let cache = NSCache<NSString, PlatformImage>()

    /// The largest landscape canvas in points (covers up to iPad Pro 13" 16:9 canvas, 1366×768).
    /// Bigger Mac windows lay out at this size too and scale up (game.md §15).
    static let largestScreen = CanvasFit.maxLayout

    /// Mac: how far the canvas can be scaled up on this Mac's largest screen, so art cached at its
    /// layout size stays sharp in a full-screen window. Set once at launch; 1 on iPhone and iPad.
    nonisolated(unsafe) static var canvasUpscale: CGFloat = 1

    /// Names with no art in the catalog (most items and backdrops are still placeholders), and
    /// every known art's point size — so views re-rendering never re-query the catalog.
    nonisolated(unsafe) private static var missing = Set<String>()
    nonisolated(unsafe) private static var sizes: [String: CGSize] = [:]
    private static let lock = NSLock()

    /// The catalog image, or nil (remembered) when there's no such art.
    private static func source(_ name: String) -> PlatformImage? {
        if lock.withLock({ missing.contains(name) }) { return nil }
        guard let image = PlatformImage(named: name), image.size.height > 0 else {
            lock.withLock { _ = missing.insert(name) }
            return nil
        }
        lock.withLock { sizes[name] = image.size }
        return image
    }

    private static func size(_ name: String) -> CGSize? {
        if let known = lock.withLock({ sizes[name] }) { return known }
        return source(name)?.size
    }

    /// `name` scaled to `height` *points* (rendered at the screen's pixel scale).
    static func thumbnail(_ name: String, height: CGFloat) -> PlatformImage? {
        guard height > 0 else { return nil }
        let key = "\(name)@\(Int(height.rounded(.up)))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = source(name) else { return nil }
        let scale = PlatformGraphics.displayScale * canvasUpscale
        let image: PlatformImage
        if PlatformGraphics.pixelHeight(of: source) <= height * scale {
            // Already at or below the needed resolution — keep the original.
            image = source
        } else {
            // Downsampling decode: much faster and lighter than drawing the full-size image.
            let pixels = CGSize(width: (source.size.width * height / source.size.height * scale).rounded(),
                                height: (height * scale).rounded())
            image = PlatformGraphics.downsampled(source, toPixels: pixels, scale: scale)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// `name` scaled just large enough to fill `area` (points) with aspect-fill.
    static func thumbnail(_ name: String, covering area: CGSize) -> PlatformImage? {
        guard let size = size(name), size.width > 0 else { return nil }
        let height = max(area.height, area.width * size.height / size.width)
        return thumbnail(name, height: height)
    }

    /// Width ÷ height of `name`'s art, without making a scaled copy.
    static func aspect(_ name: String) -> CGFloat? {
        guard let size = size(name), size.height > 0 else { return nil }
        return size.width / size.height
    }
}
