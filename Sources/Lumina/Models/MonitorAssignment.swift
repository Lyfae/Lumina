import Foundation
import CoreGraphics

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
    
    /// Normalized crop rectangle (0.0–1.0).
    /// Origin is top-left. (0,0,1,1) = no cropping.
    public var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    
    // MARK: - Playback Settings
    public var playbackSpeed: Double = 1.0
    public var isMuted: Bool = true
    
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
}

// MARK: - Supporting Types

public enum MediaType: String, Codable, CaseIterable {
    case unknown
    case image              // Static images (PNG, JPEG, etc.)
    case animatedImage      // GIFs and similar looping images
    case video
}

public enum VideoScaling: String, Codable, CaseIterable {
    case fit
    case fill
    case stretch
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
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if isStale {
                    // Cannot mutate here. Caller can decide what to do with stale bookmarks.
                    return nil
                }
                
                if url.startAccessingSecurityScopedResource() {
                    return url
                } else {
                    return nil
                }
            } catch {
                // Error is not recorded here (method is non-mutating).
                // Callers should handle resolution failures.
            }
        }
        
        // Fallback to stored path
        if let path = filePath {
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            } else {
                // Note: We intentionally do not mutate `lastError` here because 
                // `resolvedURL()` is not a mutating method. The caller can handle missing files.
            }
        }
        
        return nil
    }
    
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