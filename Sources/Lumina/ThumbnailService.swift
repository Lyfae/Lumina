import Foundation
import AppKit
import AVFoundation

/// Lightweight, cached thumbnail generator for the Wallpaper Manager.
/// Used for both the side-panel live preview and the small thumbnails inside the monitor layout.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let maxCacheSize = 80
    private var failedKeys = Set<String>()   // Avoid spamming logs on repeated failures (e.g. permission issues with bookmarks)

    init() {
        cache.countLimit = maxCacheSize
        cache.totalCostLimit = 80 * 1024 * 1024 // ~80 MB rough limit
    }

    /// Returns a thumbnail for the given URL, using cache when available.
    /// For videos, picks a more representative frame (around 15% into the clip) unless a specific normalized time is provided.
    @preconcurrency
    func thumbnail(for url: URL, mediaType: MediaType, maxSize: CGSize = CGSize(width: 320, height: 180), previewTime: Double? = nil) async -> NSImage? {
        let key = cacheKey(for: url, maxSize: maxSize, time: previewTime)
        let nsKey = key as NSString

        if let cached = cache.object(forKey: nsKey) {
            return cached
        }

        if failedKeys.contains(key) {
            return nil   // We already tried and failed — don't spam the console
        }

        let image: NSImage?
        switch mediaType {
        case .video:
            image = await generateVideoThumbnail(url: url, maxSize: maxSize, normalizedTime: previewTime)
        case .animatedImage, .image:
            image = generateImageThumbnail(url: url, maxSize: maxSize)
        case .unknown:
            image = generateImageThumbnail(url: url, maxSize: maxSize)
        }

        if let image {
            cache.setObject(image, forKey: nsKey)
        } else {
            failedKeys.insert(key)
        }
        return image
    }

    func clearCache() {
        cache.removeAllObjects()
        failedKeys.removeAll()
    }

    /// Convenience for very small thumbnails used inside the monitor layout.
    /// These are generated at lower resolution and lower priority.
    @preconcurrency
    func smallThumbnail(for url: URL, mediaType: MediaType) async -> NSImage? {
        await thumbnail(for: url, mediaType: mediaType, maxSize: CGSize(width: 160, height: 90))
    }

    // MARK: - Private

    private func cacheKey(for url: URL, maxSize: CGSize, time: Double? = nil) -> String {
        let timeStr = time.map { String(format: "%.3f", $0) } ?? "default"
        return "\(url.path)-\(Int(maxSize.width))x\(Int(maxSize.height))-\(timeStr)"
    }

    private func generateVideoThumbnail(url: URL, maxSize: CGSize, normalizedTime: Double? = nil) async -> NSImage? {
        // Best-effort: start security-scoped access if this is a plain file URL.
        // Callers (recentMedia etc.) should already provide a resolved URL, but this helps on early launch.
        let didStartAccess = url.startAccessingSecurityScopedResource()

        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize

        let durationSeconds = (try? await asset.load(.duration))?.seconds ?? 0
        let preferredTime: CMTime

        if let t = normalizedTime, durationSeconds > 0.1 {
            let clamped = max(0.0, min(1.0, t))
            preferredTime = CMTime(seconds: durationSeconds * clamped, preferredTimescale: 600)
        } else if durationSeconds > 1.0 {
            // Default to ~15% for a nicer representative frame
            preferredTime = CMTime(seconds: durationSeconds * 0.15, preferredTimescale: 600)
        } else {
            preferredTime = .zero
        }

        do {
            let cgImage = try await generator.image(at: preferredTime).image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return nsImage
        } catch {
            // Only log the first time (failures are cached in thumbnail(for:))
            if !failedKeys.contains(cacheKey(for: url, maxSize: maxSize, time: normalizedTime)) {
                print("[ThumbnailService] Video thumbnail failed: \(error)")
            }
            return nil
        }
    }

    private func generateImageThumbnail(url: URL, maxSize: CGSize) -> NSImage? {
        // Decode a downsampled thumbnail directly via ImageIO — never loads the full-resolution
        // image into memory (a big win when the library has large photos / GIFs).
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        let maxPixel = Int((max(maxSize.width, maxSize.height) * 2).rounded())  // ~retina
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        // Fallback for anything ImageIO can't open.
        return NSImage(contentsOf: url)
    }
}
