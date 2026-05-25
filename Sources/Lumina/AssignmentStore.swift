import Foundation
import AppKit

/// Central store for managing per-monitor wallpaper assignments.
/// Handles persistence, loading with fallbacks, and fail-safe behavior.
@MainActor
final class AssignmentStore: ObservableObject {
    
    @Published private(set) var assignments: [String: MonitorAssignment] = [:]
    @Published var persistAssignments: Bool = true
    
    private let persistenceKey = "Lumina.MonitorAssignments.v1"
    private let preferenceKey = "Lumina.PersistAssignments"
    
    init() {
        loadPersistencePreference()
        loadAssignments()
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
        
        if persistAssignments && assignment.keepOnStartup {
            saveAssignments()
        }
    }
    
    func removeAssignment(for monitorIdentifier: String) {
        assignments.removeValue(forKey: monitorIdentifier)
        if persistAssignments {
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
    
    // MARK: - Persistence
    
    private func loadPersistencePreference() {
        if UserDefaults.standard.object(forKey: preferenceKey) == nil {
            persistAssignments = true
            UserDefaults.standard.set(true, forKey: preferenceKey)
        } else {
            persistAssignments = UserDefaults.standard.bool(forKey: preferenceKey)
        }
    }
    
    private func loadAssignments() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return }
        
        do {
            let decoded = try JSONDecoder().decode([String: MonitorAssignment].self, from: data)
            self.assignments = decoded
        } catch {
            print("[AssignmentStore] Failed to decode assignments: \(error)")
            // Fail-safe: start fresh rather than crashing
            self.assignments = [:]
        }
    }
    
    private func saveAssignments() {
        // Only persist assignments that have "keepOnStartup" enabled
        let toSave = assignments.filter { $0.value.keepOnStartup }
        
        do {
            let data = try JSONEncoder().encode(toSave)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            print("[AssignmentStore] Failed to save assignments: \(error)")
        }
    }
    
    // MARK: - Fail-Safe Helpers
    
    /// Validates an assignment and returns a cleaned version (or nil if unrecoverable).
    func validateAndRepair(_ assignment: MonitorAssignment) -> MonitorAssignment? {
        guard let path = assignment.filePath else { return nil }
        
        let expandedPath = (path as NSString).expandingTildeInPath
        
        // Basic existence check
        if !FileManager.default.fileExists(atPath: expandedPath) {
            var repaired = assignment
            repaired.lastError = "File no longer exists"
            repaired.filePath = nil
            repaired.bookmarkData = nil
            return repaired
        }
        
        // TODO: In a future version we can try resolving the bookmark here
        return assignment
    }
    
    /// Resets all assignments (nuclear option for users).
    func resetAll() {
        assignments.removeAll()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }
}