import Foundation

/// Security-scoped file access for user-picked media.
/// Non-sandboxed dev builds skip scope APIs; sandboxed releases use bookmarks + single access grants.
enum FileAccess {
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        isSandboxed ? [.withSecurityScope] : []
    }

    static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        isSandboxed ? [.withSecurityScope, .withoutUI] : [.withoutUI]
    }

    /// Call immediately after `NSOpenPanel` returns a URL, before creating a bookmark.
    @discardableResult
    static func registerUserSelectedFile(_ url: URL) -> Bool {
        guard isSandboxed else { return true }
        return MonitorAssignment.beginScopedAccess(for: url)
    }
}
