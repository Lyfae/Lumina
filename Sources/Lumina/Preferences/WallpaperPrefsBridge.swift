// Helpers bridging DisplayWallpaper ↔ MonitorAssignmentWire for Studio UI.
import Foundation
import LuminaCore

extension PreferencesStore {
    /// Session + pinned wallpapers keyed like the old AssignmentStore.
    func wallpaperAssignment(for monitorID: String) -> MonitorAssignment? {
        let key = DisplayKey(monitorID)
        guard wallpapers.byDisplay[key] != nil else { return nil }
        return LegacyMigration.wire(from: wallpapers[display: key], key: key)
    }

    func upsertWallpaperAssignment(_ assignment: MonitorAssignment) {
        var next = wallpapers
        let key = DisplayKey(assignment.monitorIdentifier)
        if assignment.monitorIdentifier.hasPrefix("library-import-") {
            let wp = LegacyMigration.wallpaper(from: assignment)
            if case .media(let ref) = wp.content {
                if let idx = next.library.firstIndex(where: { $0.id == assignment.monitorIdentifier }) {
                    next.library[idx].media = ref
                } else {
                    next.library.append(LibraryItem(id: assignment.monitorIdentifier, media: ref))
                }
            }
        } else {
            next[display: key] = LegacyMigration.wallpaper(from: assignment)
        }
        wallpapers = next
    }

    func removeWallpaperAssignment(for monitorID: String) {
        var next = wallpapers
        if monitorID.hasPrefix("library-import-") {
            next.library.removeAll { $0.id == monitorID }
        } else {
            var map = next.byDisplay
            map.removeValue(forKey: DisplayKey(monitorID))
            next.replaceAll(assignments: map, library: next.library)
        }
        wallpapers = next
    }

    func mediaReference(from url: URL) -> MediaReference {
        let kind: MediaKind
        switch MediaType.from(url: url) {
        case .image: kind = .image
        case .animatedImage: kind = .animatedImage
        case .video: kind = .video
        case .unknown: kind = .video
        }
        var bookmark: Data?
        if let data = try? url.bookmarkData(
            options: FileAccess.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmark = data
        }
        let displayPath = MonitorAssignmentWire.makeRelativePathIfPossible(url.path)
        return MediaReference(
            identity: MediaIdentity(normalizing: url.path),
            displayPath: displayPath,
            bookmark: bookmark,
            kind: kind
        )
    }
}
