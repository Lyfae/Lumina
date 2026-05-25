// Lumina
// WallpaperPersistence
//
// Very lightweight persistence for the prototype.
// Currently focused on remembering the last used wallpaper video so it
// automatically restores on launch / after login.
//
// We use security-scoped bookmarks so the app can re-access the file across launches
// even if the user moves the file (within reason) or reboots.

import Foundation

public struct WallpaperPersistence {
    private static let lastVideoBookmarkKey = "lastVideoBookmarkData"

    // MARK: - Last Video

    public static func saveLastVideo(_ url: URL) {
        // Always save the plain filesystem path as a reliable fallback.
        // This survives bookmark invalidation (file renames, etc.).
        UserDefaults.standard.set(url.path, forKey: "lastVideoPathFallback")

        do {
            // Use the most compatible bookmark options for broad macOS support
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: lastVideoBookmarkKey)
        } catch {
            print("[Persistence] Failed to create bookmark for \(url): \(error)")
            // Path fallback is already saved above — no further action needed.
        }
    }

    /// Attempts to restore the last video the user chose.
    /// Returns a URL (security-scoped if possible).
    ///
    /// Behavior:
    /// - Tries bookmark first.
    /// - On any failure or staleness, automatically clears the bad bookmark.
    /// - Falls back to the plain path saved during the last successful `saveLastVideo`.
    /// - As a final prototype convenience, falls back to `~/Movies/Lumina Samples/demo.mp4`
    ///   if it exists and nothing else is available.
    public static func restoreLastVideo() -> URL? {
        // Try bookmark first (preferred when valid)
        if let data = UserDefaults.standard.data(forKey: lastVideoBookmarkKey) {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    print("[Persistence] Bookmark is stale — clearing it and falling back.")
                    clearBookmarkOnly()
                    return tryFallbackPath() ?? tryDemoPath()
                }

                if url.startAccessingSecurityScopedResource() {
                    return url
                } else {
                    print("[Persistence] Could not start accessing security scoped resource — clearing bookmark.")
                    clearBookmarkOnly()
                }
            } catch {
                print("[Persistence] Failed to resolve bookmark: \(error) — clearing bad bookmark data.")
                clearBookmarkOnly()
            }
        }

        // Fallback to plain path (saved on every successful saveLastVideo)
        if let url = tryFallbackPath() {
            return url
        }

        // Prototype convenience fallback
        return tryDemoPath()
    }

    private static func tryFallbackPath() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: "lastVideoPathFallback") else { return nil }
        let url = URL(fileURLWithPath: path)

        // For non-sandboxed app this usually just works
        return url
    }

    public static func clearLastVideo() {
        UserDefaults.standard.removeObject(forKey: lastVideoBookmarkKey)
        UserDefaults.standard.removeObject(forKey: "lastVideoPathFallback")
    }

    // MARK: - Private Helpers

    private static func clearBookmarkOnly() {
        UserDefaults.standard.removeObject(forKey: lastVideoBookmarkKey)
    }

    /// Prototype convenience: returns the standard demo video location if the file exists.
    private static func tryDemoPath() -> URL? {
        let demoPath = NSString(string: "~/Movies/Lumina Samples/demo.mp4").expandingTildeInPath
        let url = URL(fileURLWithPath: demoPath)

        if FileManager.default.fileExists(atPath: url.path) {
            print("[Persistence] No saved video found — falling back to demo.mp4 for prototype convenience.")
            return url
        }
        return nil
    }
}
