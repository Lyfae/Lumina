import AppKit
import Foundation

/// Security-scoped file access for user-picked media.
/// Non-sandboxed builds skip scope APIs; sandboxed releases use per-file bookmarks from NSOpenPanel.
enum FileAccess {
    private static let folderBookmarksKey = "Lumina.FolderBookmarks"
    /// Paths with an active folder-level scoped grant this launch. Guarded by `folderLock`.
    private nonisolated(unsafe) static var folderScopedPaths = Set<String>()
    private static let folderLock = NSLock()

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        isSandboxed ? [.withSecurityScope] : []
    }

    static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        isSandboxed ? [.withSecurityScope, .withoutUI] : [.withoutUI]
    }

    // MARK: - Per-file (open panel picks)

    /// Call immediately after `NSOpenPanel` returns a URL, before creating a bookmark.
    @discardableResult
    static func registerUserSelectedFile(_ url: URL) -> Bool {
        guard isSandboxed else { return true }
        return MonitorAssignment.beginScopedAccess(for: url)
    }

    // MARK: - Optional folder bookmarks (cleared when a Privacy location is unchecked)

    static func removeFolderGrant(for location: MediaAccessLocation) {
        var map = loadAllFolderBookmarkData()
        map.removeValue(forKey: location.rawValue)
        UserDefaults.standard.set(map, forKey: folderBookmarksKey)
        if let root = location.resolvedRootURL() {
            folderLock.lock()
            folderScopedPaths.remove(root.path)
            folderLock.unlock()
        }
    }

    private static func loadAllFolderBookmarkData() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: folderBookmarksKey) as? [String: Data] ?? [:]
    }
}

extension MediaAccessLocation {
    /// Whether `url` is the standard folder or inside it.
    func contains(_ url: URL) -> Bool {
        guard let root = resolvedRootURL() else { return false }
        let picked = url.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.path
        return picked == rootPath || picked.hasPrefix(rootPath + "/") || rootPath.hasPrefix(picked + "/")
    }
}
