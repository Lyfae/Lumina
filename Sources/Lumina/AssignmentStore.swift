import Foundation
import AppKit

/// Central store for managing per-monitor wallpaper assignments.
/// Handles persistence, loading with fallbacks, and fail-safe behavior.
///
/// Two separate persistence buckets:
///   • `Lumina.MonitorAssignments.v1`  — only assignments where the user explicitly enabled
///     "Keep this wallpaper on startup" are persisted here and auto-restored on launch.
///   • `Lumina.LibraryItems.v1`        — user's wallpaper library (always persisted and restored
///     so the library survives app restarts without replaying any wallpapers).
@MainActor
final class AssignmentStore: ObservableObject {

    @Published private(set) var assignments: [String: MonitorAssignment] = [:]
    @Published var persistAssignments: Bool = true

    private let persistenceKey = "Lumina.MonitorAssignments.v1"
    private let libraryKey     = "Lumina.LibraryItems.v1"
    private let preferenceKey  = "Lumina.PersistAssignments"

    init() {
        loadPersistencePreference()
        // Load any pinned (keepOnStartup) per-monitor assignments.
        // This is what makes the "Keep this wallpaper on startup" toggle actually work.
        loadAssignments()
        // Library items are always restored (they don't auto-play anything).
        loadLibraryItems()
    }

    // MARK: - Public API

    func assignment(for monitorIdentifier: String) -> MonitorAssignment? {
        return assignments[monitorIdentifier]
    }

    /// Returns the saved video path for a monitor (used for restoration on launch).
    func savedVideoPath(for monitorIdentifier: String) -> String? {
        guard let assignment = assignments[monitorIdentifier],
              assignment.keepOnStartup,
              let path = assignment.filePath else {
            return nil
        }
        return (path as NSString).expandingTildeInPath
    }

    func updateAssignment(_ assignment: MonitorAssignment) {
        assignments[assignment.monitorIdentifier] = assignment

        if assignment.monitorIdentifier.hasPrefix("library-import-") {
            saveLibraryItems()
        } else if assignment.keepOnStartup {
            // A pinned wallpaper must always persist — that is the entire purpose of the
            // "Keep this wallpaper on startup" toggle. It must work regardless of the separate
            // global "Remember wallpapers on startup" preference (which gates the un-pinned UI).
            saveAssignments()
        }
    }

    func removeAssignment(for monitorIdentifier: String) {
        assignments.removeValue(forKey: monitorIdentifier)

        if monitorIdentifier.hasPrefix("library-import-") {
            saveLibraryItems()
        } else {
            // Always rewrite the pinned bucket — gating this on `persistAssignments` left
            // removed assignments in UserDefaults, so they came back on the next launch.
            saveAssignments()
        }
    }

    func setPersistenceEnabled(_ enabled: Bool) {
        persistAssignments = enabled
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        if enabled {
            saveAssignments()
        }
    }

    /// Public helper so the UI layer can force a filtered save (e.g. when user turns
    /// "Keep on startup" off so we immediately drop the entry from persistence).
    /// Not gated on `persistAssignments`: un-pinning must always drop the stale entry
    /// from UserDefaults, or it silently reloads on next launch.
    func forceSaveAssignments() {
        saveAssignments()
    }

    // MARK: - Per-Monitor Persistence (clean-start; only written, never auto-read on launch)

    private func loadPersistencePreference() {
        if UserDefaults.standard.object(forKey: preferenceKey) == nil {
            persistAssignments = true
            UserDefaults.standard.set(true, forKey: preferenceKey)
        } else {
            persistAssignments = UserDefaults.standard.bool(forKey: preferenceKey)
        }
    }

    private func saveAssignments() {
        let toSave = assignments.filter { $0.value.keepOnStartup && !$0.key.hasPrefix("library-import-") }
        do {
            let data = try JSONEncoder().encode(toSave)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            LuminaLog.app.error("Failed to save assignments: \(error)")
        }
    }

    /// Loads per-monitor assignments that the user explicitly pinned with "Keep on startup".
    /// Only items with `keepOnStartup == true` and whose media still exists on disk are restored.
    private func loadAssignments() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return }
        do {
            let saved = try JSONDecoder().decode([String: MonitorAssignment].self, from: data)

            for (key, item) in saved where item.keepOnStartup && !key.hasPrefix("library-import-") {
                // Verify the media (or at least one slideshow image) still exists
                let hasValidMedia: Bool = {
                    if !item.slideshowItems.isEmpty {
                        return item.slideshowItems.contains { path in
                            FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
                        }
                    }
                    guard let path = item.filePath else { return false }
                    return FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
                }()

                if hasValidMedia {
                    assignments[key] = item
                } else {
                    LuminaLog.app.warning("Skipping pinned assignment for \(key) — media no longer exists on disk.")
                }
            }
            LuminaLog.persistence.info("Loaded \(assignments.filter { $0.value.keepOnStartup }.count) pinned per-monitor assignment(s).")
        } catch {
            LuminaLog.persistence.error("Failed to decode pinned assignments: \(error)")
        }
    }

    // MARK: - Library Persistence (always saved and restored)

    private func loadLibraryItems() {
        guard let data = UserDefaults.standard.data(forKey: libraryKey) else { return }
        do {
            let items = try JSONDecoder().decode([String: MonitorAssignment].self, from: data)
            // Merge into assignments — library items only, filtered to those whose files still exist
            for (key, item) in items {
                let path = item.resolvedURL()?.path
                    ?? item.filePath.map { ($0 as NSString).expandingTildeInPath }
                if let path, FileManager.default.fileExists(atPath: path) {
                    assignments[key] = item
                }
            }
            LuminaLog.persistence.info("Loaded \(items.count) library item(s).")
        } catch {
            LuminaLog.persistence.error("Failed to decode library: \(error)")
            // Do not crash the app — just start with an empty library this time.
            // The custom decoder on MonitorAssignment should prevent most future decode failures.
        }
    }

    private func saveLibraryItems() {
        let items = assignments.filter { $0.key.hasPrefix("library-import-") }
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: libraryKey)
        } catch {
            LuminaLog.persistence.error("Failed to save library: \(error)")
        }
    }

    // MARK: - Fail-Safe Helpers

    /// Validates an assignment and returns a cleaned version (or nil if unrecoverable).
    func validateAndRepair(_ assignment: MonitorAssignment) -> MonitorAssignment? {
        guard let path = assignment.filePath else { return nil }
        let expandedPath = (path as NSString).expandingTildeInPath
        if !FileManager.default.fileExists(atPath: expandedPath) {
            var repaired = assignment
            repaired.lastError = "File no longer exists"
            repaired.filePath = nil
            repaired.bookmarkData = nil
            return repaired
        }
        return assignment
    }

    /// Resets all assignments and clears both persistence buckets.
    func resetAll() {
        assignments.removeAll()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        UserDefaults.standard.removeObject(forKey: libraryKey)
    }
}
