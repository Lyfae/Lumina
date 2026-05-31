import Foundation
import AppKit

/// Central store for managing per-monitor wallpaper assignments.
/// Handles persistence, loading with fallbacks, and fail-safe behavior.
///
/// Two separate persistence buckets:
///   • `Lumina.MonitorAssignments.v1`  — per-monitor assignments (cleared on every launch; only
///     items with keepOnStartup=true are written here, and they are currently not auto-restored
///     so displays always start black).
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
        // Wipe per-monitor assignments so displays always start black.
        UserDefaults.standard.removeObject(forKey: persistenceKey)
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
        } else if persistAssignments && assignment.keepOnStartup {
            saveAssignments()
        }
    }

    func removeAssignment(for monitorIdentifier: String) {
        assignments.removeValue(forKey: monitorIdentifier)

        if monitorIdentifier.hasPrefix("library-import-") {
            saveLibraryItems()
        } else if persistAssignments {
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
            print("[AssignmentStore] Failed to save assignments: \(error)")
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
            print("[AssignmentStore] Loaded \(items.count) library item(s).")
        } catch {
            print("[AssignmentStore] Failed to decode library: \(error)")
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
            print("[AssignmentStore] Failed to save library: \(error)")
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
