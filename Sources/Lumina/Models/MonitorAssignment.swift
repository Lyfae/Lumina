import Foundation
import CoreGraphics
import QuartzCore
import UniformTypeIdentifiers

/// Represents the complete configuration for one monitor's wallpaper.
/// Designed to be robust, versioned, and safe to persist across restarts.
public struct MonitorAssignment: Codable, Equatable {
    
    // MARK: - Versioning (Critical for fail-safes and migrations)
    public var schemaVersion: Int = 1
    
    // MARK: - Monitor Identity
    /// Stable identifier for this physical monitor.
    /// Format example: "Built-in Retina Display-2560x1440"
    public var monitorIdentifier: String
    
    // MARK: - Media Source (Local files only)
    /// Human-readable path. Stored as relative (~/) when possible for portability.
    public var filePath: String?
    
    /// Security-scoped bookmark data. This is the primary way we access the file reliably.
    public var bookmarkData: Data?
    
    // MARK: - Media Type
    public var mediaType: MediaType = .unknown
    
    // MARK: - Visual Settings
    public var scaling: VideoScaling = .fill
    public var brightness: Double = 0.0   // -0.5 (darker) to +0.5 (lighter)
    public var opacity: Double = 1.0          // 0.0–1.0
    public var saturation: Double = 1.0       // 0 = grayscale, 1 = normal, 2 = vivid
    public var hue: Double = 0.0              // degrees, -180 to 180
    public var audioVolume: Double = 0.0      // 0 = muted, 1 = full
    public var grayscale: Bool = false
    public var loopMode: LoopMode = .loop

    public enum LoopMode: String, Codable, CaseIterable {
        case loop, once, bounce
        var label: String {
            switch self {
            case .loop:   return "Loop"
            case .once:   return "Play Once"
            case .bounce: return "Bounce"
            }
        }
        public var modeDescription: String {
            switch self {
            case .loop:   return "Video plays continuously, restarting from the beginning each time it ends."
            case .once:   return "Video plays once all the way through, then the display goes black."
            case .bounce: return "Video plays forward to the end, then reverses back to the start — alternating direction on each cycle."
            }
        }
    }
    
    /// Normalized crop rectangle (0.0–1.0).
    /// Origin is top-left. (0,0,1,1) = no cropping.
    public var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    
    // MARK: - Playback Settings
    public var playbackSpeed: Double = 1.0
    public var isMuted: Bool = true
    public var loopFadeEnabled: Bool = false
    public var loopFadeDuration: Double = 1.5   // seconds total (fade-out + fade-in)
    public var loopFadeEasing: FadeEasing = .easeInOut

    // MARK: - Crossfade Settings (newer fields)
    public var crossfadeDuration: Double = 0.35
    public var crossfadeEasing: FadeEasing = .easeInOut

    public enum FadeEasing: String, Codable, CaseIterable {
        case linear, easeIn, easeInOut, easeOut
        var label: String {
            switch self {
            case .linear:    return "Linear"
            case .easeIn:    return "Ease In"
            case .easeInOut: return "Ease In/Out"
            case .easeOut:   return "Ease Out"
            }
        }
    }
    
    // MARK: - Slideshow Settings
    public var slideshowItems: [String] = []        // file paths for slideshow
    public var slideshowInterval: Double = 10.0     // seconds between slides
    public var slideshowTransition: SlideshowTransition = .fade

    public enum SlideshowTransition: String, Codable, CaseIterable, Sendable {
        case fade, cut
    }

    // MARK: - Behavior
    /// If true, this assignment should be restored when Lumina launches.
    public var keepOnStartup: Bool = false
    
    /// Allows temporarily disabling a monitor without losing its settings.
    public var isEnabled: Bool = true
    
    // MARK: - Fail-Safe & Diagnostic Fields
    public var lastSuccessfulLoad: Date?
    public var lastError: String?
    
    public init(monitorIdentifier: String) {
        self.monitorIdentifier = monitorIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, monitorIdentifier, filePath, bookmarkData, mediaType,
             scaling, brightness, opacity, saturation, hue, audioVolume, grayscale,
             loopMode, cropRect, playbackSpeed, isMuted, keepOnStartup, isEnabled,
             lastSuccessfulLoad, lastError,
             loopFadeEnabled, loopFadeDuration, loopFadeEasing,
             crossfadeDuration, crossfadeEasing,
             slideshowItems, slideshowInterval, slideshowTransition
    }

    // MARK: - Custom Decoding (resilient to older saved data)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required
        monitorIdentifier = try container.decode(String.self, forKey: .monitorIdentifier)

        // Older fields with defaults
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        mediaType = try container.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .unknown
        scaling = try container.decodeIfPresent(VideoScaling.self, forKey: .scaling) ?? .fill
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1.0
        hue = try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0.0
        audioVolume = try container.decodeIfPresent(Double.self, forKey: .audioVolume) ?? 0.0
        grayscale = try container.decodeIfPresent(Bool.self, forKey: .grayscale) ?? false
        loopMode = try container.decodeIfPresent(LoopMode.self, forKey: .loopMode) ?? .loop
        cropRect = try container.decodeIfPresent(CGRect.self, forKey: .cropRect) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        playbackSpeed = try container.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? 1.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? true
        keepOnStartup = try container.decodeIfPresent(Bool.self, forKey: .keepOnStartup) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastSuccessfulLoad = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulLoad)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)

        // Newer crossfade fields (use defaults if missing)
        loopFadeEnabled = try container.decodeIfPresent(Bool.self, forKey: .loopFadeEnabled) ?? false
        loopFadeDuration = try container.decodeIfPresent(Double.self, forKey: .loopFadeDuration) ?? 1.5
        loopFadeEasing = try container.decodeIfPresent(FadeEasing.self, forKey: .loopFadeEasing) ?? .easeInOut
        crossfadeDuration = try container.decodeIfPresent(Double.self, forKey: .crossfadeDuration) ?? 0.35
        crossfadeEasing = try container.decodeIfPresent(FadeEasing.self, forKey: .crossfadeEasing) ?? .easeInOut

        slideshowItems = try container.decodeIfPresent([String].self, forKey: .slideshowItems) ?? []
        slideshowInterval = try container.decodeIfPresent(Double.self, forKey: .slideshowInterval) ?? 10.0
        slideshowTransition = try container.decodeIfPresent(SlideshowTransition.self, forKey: .slideshowTransition) ?? .fade

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

// MARK: - Supporting Types

public enum MediaType: String, Codable, CaseIterable {
    case unknown
    case image              // Static images (PNG, JPEG, etc.)
    case animatedImage      // GIFs and similar looping images
    case video
}

extension MediaType {
    /// Determines the media type from a file URL based on extension.
    public static func from(url: URL) -> MediaType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "mpg", "mpeg", "3gp", "ts":
            return .video
        case "gif":
            return .animatedImage
        case "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "webp":
            return .image
        default:
            if let type = UTType(filenameExtension: ext) {
                if type.conforms(to: .movie) { return .video }
                if type.conforms(to: .image) { return ext == "gif" ? .animatedImage : .image }
            }
            return .unknown
        }
    }
}

public enum VideoScaling: String, Codable, CaseIterable {
    case fit
    case fill
    case stretch
}

extension MonitorAssignment.FadeEasing {
    var caTimingFunction: CAMediaTimingFunction {
        switch self {
        case .linear:    return CAMediaTimingFunction(name: .linear)
        case .easeIn:    return CAMediaTimingFunction(name: .easeIn)
        case .easeInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
        case .easeOut:   return CAMediaTimingFunction(name: .easeOut)
        }
    }
}

// MARK: - Convenience Helpers

extension MonitorAssignment {
    
    /// Returns a user-friendly name for the currently assigned media.
    public var displayName: String {
        guard let path = filePath else { return "No media" }
        return (path as NSString).lastPathComponent
    }
    
    /// Whether this assignment has any media assigned.
    public var hasMedia: Bool {
        return filePath != nil && bookmarkData != nil
    }
    
    /// Creates a clean copy with sensitive data cleared (useful for logging).
    public func sanitizedForLogging() -> MonitorAssignment {
        var copy = self
        copy.bookmarkData = nil
        return copy
    }
    
    /// Creates or updates the security-scoped bookmark from a local file URL.
    /// This should be called whenever the user selects a new video/image for this monitor.
    public mutating func updateBookmark(from url: URL) {
        // Store a human-readable path (prefer relative ~ form when possible)
        self.filePath = Self.makeRelativePathIfPossible(url.path)
        
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            self.bookmarkData = bookmark
            self.lastError = nil
        } catch {
            self.lastError = "Failed to create bookmark: \(error.localizedDescription)"
            print("[MonitorAssignment] Failed to create bookmark for \(url.path): \(error)")
        }
    }
    
    /// Attempts to resolve a usable URL from the stored bookmark or filePath.
    public func resolvedURL() -> URL? {
        // Prefer bookmark (more reliable across restarts and file moves)
        if let data = bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                // A stale bookmark still resolves to a usable URL — staleness only signals that
                // the bookmark data *should* be recreated (callers can do that via updateBookmark).
                // Returning nil here was a bug: it made wallpapers silently fail to load after a
                // file move or OS update even when the file was perfectly reachable. We start
                // security-scoped access (best effort; a no-op for non-sandboxed builds) and use
                // the URL as long as the file actually exists.
                _ = url.startAccessingSecurityScopedResource()
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        // Fallback to stored path
        if let path = filePath {
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            // Note: We intentionally do not mutate `lastError` here because `resolvedURL()`
            // is not a mutating method. The caller handles missing files.
        }

        return nil
    }

    /// Whether the stored security-scoped bookmark is stale and should be recreated.
    /// Callers can use this to refresh the bookmark via `updateBookmark(from:)`.
    public func bookmarkIsStale() -> Bool {
        guard let data = bookmarkData else { return false }
        var isStale = false
        _ = try? URL(resolvingBookmarkData: data,
                     options: [.withSecurityScope, .withoutUI],
                     relativeTo: nil,
                     bookmarkDataIsStale: &isStale)
        return isStale
    }
    
    // MARK: - Private Helpers
    
    // MARK: - Private Helpers

    private static func makeRelativePathIfPossible(_ absolutePath: String) -> String {
        let home = NSHomeDirectory()
        if absolutePath.hasPrefix(home) {
            let relative = "~" + absolutePath.dropFirst(home.count)
            return String(relative)
        }
        return absolutePath
    }
}