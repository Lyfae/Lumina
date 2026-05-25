import SwiftUI
import AppKit

/// Observable store for the Wallpaper Manager.
/// Manages monitor detection and per-monitor video assignments.
@MainActor
final class WallpaperManagerStore: ObservableObject {
    
    @Published var monitors: [MonitorInfo] = []
    @Published var persistAssignments: Bool = true
    
    weak var appDelegate: LuminaApp?
    
    init() {
        refreshDisplays()
        loadPersistencePreference()
    }
    
    // MARK: - Display Detection (with better identification)
    
    func refreshDisplays() {
        let screens = NSScreen.screens
        
        monitors = screens.enumerated().map { index, screen in
            let resolution = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
            let isPrimary = screen == NSScreen.main
            let id = MonitorInfo.identifier(for: screen, index: index)
            
            // Try to restore previous assignment name if persistence is on
            var assignedName: String? = nil
            if persistAssignments, let assignment = self.assignment(for: id), let path = assignment.filePath {
                assignedName = URL(fileURLWithPath: path).lastPathComponent
            }
            
            return MonitorInfo(
                id: id,
                name: screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName,
                resolution: resolution,
                isPrimary: isPrimary,
                assignedVideoName: assignedName
            )
        }
    }
    
    /// Returns layout information for visual monitor arrangement.
    func getMonitorLayout() -> MonitorLayout {
        return MonitorLayout()
    }
    
    // MARK: - Video Assignment
    
    func chooseVideo(for monitor: MonitorInfo) {
        guard let index = monitors.firstIndex(where: { $0.id == monitor.id }) else { return }
        
        let panel = NSOpenPanel()
        panel.title = "Choose video for \(monitor.name)"
        panel.allowedContentTypes = [.movie]
        panel.canChooseFiles = true
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        // Assign via app delegate using stable monitor ID
        appDelegate?.assignVideoToMonitor(monitorID: monitor.id, url: url)
        
        // Update local UI state
        monitors[index].assignedVideoName = url.lastPathComponent
        
        // Create and persist a real MonitorAssignment via the central store
        var assignment = MonitorAssignment(monitorIdentifier: monitor.id)
        assignment.filePath = url.path
        assignment.keepOnStartup = true
        assignment.mediaType = .video
        assignment.updateBookmark(from: url)
        
        appDelegate?.assignmentStore.updateAssignment(assignment)
        
        print("Saved assignment for \(monitor.id) with keepOnStartup = true")
    }
    
    func clearAssignment(for monitor: MonitorInfo) {
        guard let index = monitors.firstIndex(where: { $0.id == monitor.id }) else { return }
        
        appDelegate?.assignVideoToMonitor(monitorID: monitor.id, url: URL(fileURLWithPath: ""))
        monitors[index].assignedVideoName = nil
        
        if persistAssignments {
            appDelegate?.assignmentStore.removeAssignment(for: monitor.id)
        }
    }
    
    /// Called from the detail panel when toggling "Keep on startup"
    func setKeepOnStartup(for monitor: MonitorInfo, enabled: Bool) {
        // Update the central AssignmentStore
        if var assignment = appDelegate?.assignmentStore.assignment(for: monitor.id) {
            assignment.keepOnStartup = enabled
            appDelegate?.assignmentStore.updateAssignment(assignment)
        } else {
            // Create a minimal assignment if none exists yet
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.keepOnStartup = enabled
            appDelegate?.assignmentStore.updateAssignment(newAssignment)
        }
        
        print("Keep on startup for \(monitor.name) set to \(enabled)")
    }
    
    /// Helper used by the detail panel to read the current full assignment
    func assignment(for monitorID: String) -> MonitorAssignment? {
        return appDelegate?.assignmentStore.assignment(for: monitorID)
    }
    
    // MARK: - Persistence as Config Option

    func savePersistencePreference(_ enabled: Bool) {
        persistAssignments = enabled
        UserDefaults.standard.set(enabled, forKey: "Lumina.PersistAssignments")
    }

    private func loadPersistencePreference() {
        if UserDefaults.standard.object(forKey: "Lumina.PersistAssignments") == nil {
            persistAssignments = true
            UserDefaults.standard.set(true, forKey: "Lumina.PersistAssignments")
        } else {
            persistAssignments = UserDefaults.standard.bool(forKey: "Lumina.PersistAssignments")
        }
    }
}