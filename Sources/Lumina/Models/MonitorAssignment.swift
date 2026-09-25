import Foundation
import CoreGraphics
import QuartzCore
import UniformTypeIdentifiers
import LuminaCore

/// App-facing alias for the v1 wire record. Codable body lives in LuminaCore.
public typealias MonitorAssignment = MonitorAssignmentWire

// MARK: - Nested labels (UI)

extension LoopMode {
    public var label: String {
        switch self {
        case .loop: return "Loop"
        case .once: return "Play Once"
        case .bounce: return "Bounce"
        }
    }
    public var modeDescription: String {
        switch self {
        case .loop: return "Video plays continuously, restarting from the beginning each time it ends."
        case .once: return "Video plays once all the way through, then the display goes black."
        case .bounce: return "Video plays forward to the end, then reverses back to the start — alternating direction on each cycle."
        }
    }
}

extension FadeEasing {
    public var label: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeInOut: return "Ease In/Out"
        case .easeOut: return "Ease Out"
        }
    }

    var caTimingFunction: CAMediaTimingFunction {
        switch self {
        case .linear: return CAMediaTimingFunction(name: .linear)
        case .easeIn: return CAMediaTimingFunction(name: .easeIn)
        case .easeInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
        case .easeOut: return CAMediaTimingFunction(name: .easeOut)
        }
    }
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

// MARK: - Convenience Helpers

extension MonitorAssignmentWire {
    /// Returns a user-friendly name for the currently assigned media.
    public var displayName: String {
        guard let path = filePath else { return "No media" }
        return (path as NSString).lastPathComponent
    }

    /// Whether this assignment has any media assigned (single file or slideshow).
    public var hasMedia: Bool {
        return filePath != nil || !slideshowItems.isEmpty
    }

    /// Creates a clean copy with sensitive data cleared (useful for logging).
    public func sanitizedForLogging() -> MonitorAssignment {
        var copy = self
        copy.bookmarkData = nil
        return copy
    }

    /// Creates or updates the security-scoped bookmark from a local file URL.
    public mutating func updateBookmark(from url: URL) {
        self.filePath = Self.makeRelativePathIfPossible(url.path)

        do {
            let bookmark = try url.bookmarkData(
                options: FileAccess.bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            self.bookmarkData = bookmark
            self.lastError = nil
        } catch {
            self.lastError = "Failed to create bookmark: \(error.localizedDescription)"
            LuminaLog.persistence.error("Failed to create bookmark for \(url.path): \(error)")
        }
    }

    /// Attempts to resolve a usable URL from the stored bookmark or filePath.
    public func resolvedURL() -> URL? {
        if let data = bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: FileAccess.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                Self.startScopedAccessOnce(for: url)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        if let path = filePath {
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private nonisolated(unsafe) static var scopedAccessStartedPaths = Set<String>()
    private static let scopedAccessLock = NSLock()

    @discardableResult
    static func beginScopedAccess(for url: URL) -> Bool {
        scopedAccessLock.lock()
        defer { scopedAccessLock.unlock() }
        guard !scopedAccessStartedPaths.contains(url.path) else { return true }
        if url.startAccessingSecurityScopedResource() {
            scopedAccessStartedPaths.insert(url.path)
            return true
        }
        return !FileAccess.isSandboxed
    }

    static func hasActiveScopedAccess(for url: URL) -> Bool {
        scopedAccessLock.lock()
        defer { scopedAccessLock.unlock() }
        return scopedAccessStartedPaths.contains(url.path)
    }

    private static func startScopedAccessOnce(for url: URL) {
        beginScopedAccess(for: url)
    }

    public func bookmarkIsStale() -> Bool {
        guard let data = bookmarkData else { return false }
        var isStale = false
        _ = try? URL(resolvingBookmarkData: data,
                     options: [.withSecurityScope, .withoutUI],
                     relativeTo: nil,
                     bookmarkDataIsStale: &isStale)
        return isStale
    }

    static func makeRelativePathIfPossible(_ absolutePath: String) -> String {
        let home = NSHomeDirectory()
        if absolutePath.hasPrefix(home) {
            let relative = "~" + absolutePath.dropFirst(home.count)
            return String(relative)
        }
        return absolutePath
    }
}
