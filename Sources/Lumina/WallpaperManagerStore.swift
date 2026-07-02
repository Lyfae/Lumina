import SwiftUI
import AppKit

/// Observable store for the Wallpaper Manager.
/// Manages monitor detection and per-monitor video assignments.
///
/// This is intentionally a thin presenter / view model layer.
/// AssignmentStore (owned by LuminaApp) is the single source of truth for
/// all per-monitor assignments and the global "persist assignments" preference.
@MainActor
final class WallpaperManagerStore: ObservableObject {
    
    @Published var monitors: [MonitorInfo] = []
    @Published var persistAssignments: Bool = true
    
    /// The monitor the user has chosen to configure in the main Wallpaper Manager.
    /// This is the single source of truth for "which display the right panel is editing".
    @Published var selectedMonitorID: String? = nil
    
    /// When enabled, all active wallpapers will attempt to start playback at the same time
    /// (useful for multi-monitor setups so videos don't drift or start at different times).
    @Published var syncPlaybackAcrossDisplays: Bool = false
    
    weak var appDelegate: LuminaApp?
    
    init() {
        refreshDisplays()
        syncPersistencePreference()
        loadSyncPlaybackSetting()
    }
    
    // MARK: - Display Detection (with better identification)
    
    func refreshDisplays() {
        // Always pull the authoritative preference from the central store
        syncPersistencePreference()
        
        let screens = NSScreen.screens
        
        monitors = screens.enumerated().map { index, screen in
            let resolution = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
            let isPrimary = screen == NSScreen.main
            let id = MonitorInfo.identifier(for: screen, index: index)
            
            // Show assigned name only when persistence is enabled in the central store
            var assignedName: String? = nil
            if persistAssignments,
               let assignment = self.assignment(for: id),
               let path = assignment.filePath {
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
        panel.title = "Choose wallpaper for \(monitor.name)"
        panel.message = "This will change the wallpaper on the currently selected display."
        panel.allowedContentTypes = [.movie, .image, .gif] // .image covers png/jpg, .gif for animated
        panel.canChooseFiles = true
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        // The app delegate path is the single source of truth for assignment creation,
        // bookmark handling, persistence (when keepOnStartup is set), and renderer loading.
        appDelegate?.assignVideoToMonitor(monitorID: monitor.id, url: url)
        
        // Update only the local UI snapshot. The real data lives in AssignmentStore.
        monitors[index].assignedVideoName = url.lastPathComponent
        
        LuminaLog.app.info("Assigned media to \(monitor.id) via central store")
    }
    
    func clearAssignment(for monitor: MonitorInfo) {
        guard let index = monitors.firstIndex(where: { $0.id == monitor.id }) else { return }

        // Blank the display and remove the assignment cleanly.
        appDelegate?.clearMonitor(monitorID: monitor.id)
        monitors[index].assignedVideoName = nil

        // Also clear legacy global persistence so it doesn't leak back on next launch.
        WallpaperPersistence.clearLastVideo()
    }
    
    /// Convenience for the floating Physical Setup window.
    func chooseVideoForMonitorID(monitorID: String, url: URL) {
        appDelegate?.assignVideoToMonitor(monitorID: monitorID, url: url)
        
        if let index = monitors.firstIndex(where: { $0.id == monitorID }) {
            monitors[index].assignedVideoName = url.lastPathComponent
        }
    }
    
    func clearAssignmentForMonitorID(monitorID: String) {
        appDelegate?.clearMonitor(monitorID: monitorID)

        if let index = monitors.firstIndex(where: { $0.id == monitorID }) {
            monitors[index].assignedVideoName = nil
        }

        // Nuke legacy global persistence to prevent old paths from leaking on restart
        WallpaperPersistence.clearLastVideo()
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

        // When the user explicitly turns the toggle OFF, force a save so the
        // filtered persistence immediately drops this monitor (prevents stale keep-on-startup entries).
        if !enabled {
            appDelegate?.assignmentStore.forceSaveAssignments()
        }
        
        print("Keep on startup for \(monitor.name) set to \(enabled)")
    }
    
    /// Helper used by the detail panel to read the current full assignment
    func assignment(for monitorID: String) -> MonitorAssignment? {
        return appDelegate?.assignmentStore.assignment(for: monitorID)
    }
    
    // MARK: - Recent Videos Canvas (for quick re-use across displays)
    
    /// Lightweight representation of a previously used wallpaper for the "recent canvas".
    /// Uses a stable ID based on the file path so SwiftUI ForEach can correctly track
    /// selection/highlighting when the user clicks different items in the grid.
    struct RecentMedia: Identifiable {
        let id: String   // stable path-based identity
        let url: URL
        let mediaType: MediaType
        let displayName: String
    }
    
    /// Returns a de-duplicated list of recently used wallpapers from the current assignments.
    /// Users can click these to instantly apply the same media to another selected display.
    ///
    /// Uses resolvedURL() (with security-scoped bookmark access) when available so that
    /// ThumbnailService can successfully open the file for AVAssetImageGenerator.
    var recentMedia: [RecentMedia] {
        var seenPaths = Set<String>()
        var result: [RecentMedia] = []
        
        for (_, assignment) in appDelegate?.assignmentStore.assignments ?? [:] {
            // Show all used wallpapers in the left grid/library, regardless of the
            // "Keep on startup" flag. The keep flag only controls auto-restoration on launch.
            // This way newly loaded wallpapers immediately appear in the canvas for easy re-use.
            
            // Use the plain file path here (cheap). `recentMedia` is recomputed on every SwiftUI
            // render pass, so resolving a security-scoped bookmark per item per render was a real
            // performance drain AND leaked access counts. ThumbnailService starts/stops its own
            // security-scoped access on the URL it's given, and the actual render path
            // (assignVideoToMonitor) re-resolves bookmarks, so the grid only needs a path. We fall
            // back to bookmark resolution only when no file path is stored (rare).
            let url: URL? = {
                if let path = assignment.filePath {
                    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                }
                return assignment.resolvedURL()
            }()

            guard let url else { continue }
            
            let expandedPath = url.path
            if seenPaths.contains(expandedPath) { continue }
            seenPaths.insert(expandedPath)
            
            let name = url.lastPathComponent
            let mt = assignment.mediaType
            
            result.append(RecentMedia(id: expandedPath, url: url, mediaType: mt, displayName: name))
        }
        
        // Sort by name for stable, predictable order
        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    /// Applies an existing media file (from the recent canvas or any known URL) to a specific monitor.
    /// This is the key action behind "click a previous video to change the screensaver on the selected display".
    func applyRecentMedia(to monitorID: String, url: URL) {
        // Re-use the central assignment path — it handles renderer swap, low-power variants,
        // bookmark creation, persistence, and live application.
        appDelegate?.assignVideoToMonitor(monitorID: monitorID, url: url)
        
        // Refresh the local snapshot so the UI (pills, names) updates immediately
        if let index = monitors.firstIndex(where: { $0.id == monitorID }) {
            monitors[index].assignedVideoName = url.lastPathComponent
        }
        
        print("Applied recent media \(url.lastPathComponent) to \(monitorID)")
    }
    
    /// Removes a media entry from the library grid by its stable path-based ID.
    /// Clears the renderer for any monitor that was actively using this file.
    func removeFromLibrary(id: String) {
        guard let central = appDelegate?.assignmentStore else { return }

        // Remove every assignment (library-import or monitor) that references this path
        let toRemove = central.assignments.filter { (_, assignment) in
            let path = assignment.resolvedURL()?.path
                ?? assignment.filePath.map { ($0 as NSString).expandingTildeInPath }
            return path == id
        }.map { $0.key }

        for key in toRemove {
            // If it's a real monitor, black out the renderer first
            if !key.hasPrefix("library-import-") {
                appDelegate?.clearRenderer(for: key)
                if let index = monitors.firstIndex(where: { $0.id == key }) {
                    monitors[index].assignedVideoName = nil
                }
            }
            central.removeAssignment(for: key)
        }

        refreshDisplays()
    }

    /// Adds a media file to the local library so it appears in the left "Wallpapers" grid.
    /// This does **not** assign it to any display — it is purely for the collection/library.
    func addMediaToLibrary(url: URL) {
        // Deduplicate by file path — re-importing the same file used to add another
        // library-import entry every time, growing the persisted library without bound.
        if let central = appDelegate?.assignmentStore {
            let alreadyInLibrary = central.assignments.contains { key, assignment in
                key.hasPrefix("library-import-")
                    && assignment.filePath.map { ($0 as NSString).expandingTildeInPath } == url.path
            }
            if alreadyInLibrary {
                print("Media already in library: \(url.lastPathComponent)")
                return
            }
        }

        // We create a minimal record in the central store so it shows up in recentMedia.
        // We do not call assignVideoToMonitor here, so nothing changes on the actual displays.
        let tempMonitorID = "library-import-\(UUID().uuidString)"
        
        var assignment = MonitorAssignment(monitorIdentifier: tempMonitorID)
        assignment.filePath = url.path
        assignment.keepOnStartup = false
        assignment.mediaType = MediaType.from(url: url)
        assignment.updateBookmark(from: url)
        
        // Store it under a library key so recentMedia can pick it up.
        // For simplicity we reuse the normal assignment path but mark it clearly.
        // A cleaner long-term solution would be a dedicated library array.
        appDelegate?.assignmentStore.updateAssignment(assignment)
        
        // Force a refresh so the left grid updates immediately
        refreshDisplays()
        
        print("Imported media to library: \(url.lastPathComponent)")
    }

    // MARK: - Live Settings (scaling, speed) — wired to central store + engine

    func setScaling(for monitor: MonitorInfo, scaling: VideoScaling) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.scaling = scaling
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.scaling = scaling
            // Do not persist by default — user must explicitly enable "Keep this wallpaper on startup"
            newAssignment.keepOnStartup = false
            central.updateAssignment(newAssignment)
        }

        // Tell the engine to apply the change live on the desktop wallpaper
        appDelegate?.applyScalingToMonitor(monitorID: monitor.id, scaling: scaling)

        print("Scaling for \(monitor.name) set to \(scaling)")
    }

    func setPlaybackSpeed(for monitor: MonitorInfo, speed: Double) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.playbackSpeed = speed
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.playbackSpeed = speed
            // Do not persist by default — user must explicitly enable "Keep this wallpaper on startup"
            newAssignment.keepOnStartup = false
            central.updateAssignment(newAssignment)
        }

        // Live apply to the running renderer
        appDelegate?.applyPlaybackSpeedToMonitor(monitorID: monitor.id, speed: speed)

        print("Playback speed for \(monitor.name) set to \(speed)x")
    }

    func setLoopMode(for monitor: MonitorInfo, mode: MonitorAssignment.LoopMode) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.loopMode = mode
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.loopMode = mode
            central.updateAssignment(newAssignment)
        }

        // Live apply to the running renderer (will reconfigure looping strategy)
        appDelegate?.applyLoopModeToMonitor(monitorID: monitor.id, mode: mode)

        print("Loop mode for \(monitor.name) set to \(mode)")
    }

    func setLoopFade(for monitor: MonitorInfo, enabled: Bool, duration: Double,
                     easing: MonitorAssignment.FadeEasing = .easeInOut) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.loopFadeEnabled = enabled
            assignment.loopFadeDuration = duration
            assignment.loopFadeEasing = easing
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.loopFadeEnabled = enabled
            newAssignment.loopFadeDuration = duration
            newAssignment.loopFadeEasing = easing
            central.updateAssignment(newAssignment)
        }

        appDelegate?.applyLoopFadeToMonitor(monitorID: monitor.id, enabled: enabled, duration: duration, easing: easing)
    }

    func setBrightness(for monitor: MonitorInfo, brightness: Double) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.brightness = brightness
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.brightness = brightness
            central.updateAssignment(newAssignment)
        }

        appDelegate?.applyBrightnessToMonitor(monitorID: monitor.id, brightness: brightness)
    }

    func setSlideshowItems(for monitor: MonitorInfo, items: [String]) {
        guard let central = appDelegate?.assignmentStore else { return }

        var assignment = central.assignment(for: monitor.id) ?? MonitorAssignment(monitorIdentifier: monitor.id)
        assignment.slideshowItems = items
        // One mode per monitor: a non-empty slideshow means this display is a *still-image
        // slideshow*, so drop any single video/image reference (the renderer also frees the
        // video player) — no mp4 is kept loaded or restored.
        if !items.isEmpty {
            assignment.filePath = nil
            assignment.bookmarkData = nil
            assignment.mediaType = .image
        }
        central.updateAssignment(assignment)
        appDelegate?.applySlideshowToMonitor(monitorID: monitor.id)
    }

    func setSlideshowInterval(for monitor: MonitorInfo, interval: Double) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.slideshowInterval = interval
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.slideshowInterval = interval
            central.updateAssignment(newAssignment)
        }
        appDelegate?.applySlideshowToMonitor(monitorID: monitor.id)
    }

    func setSlideshowTransition(for monitor: MonitorInfo, transition: MonitorAssignment.SlideshowTransition) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.slideshowTransition = transition
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.slideshowTransition = transition
            central.updateAssignment(newAssignment)
        }
        appDelegate?.applySlideshowToMonitor(monitorID: monitor.id)
    }

    func setSlideshowKenBurns(for monitor: MonitorInfo, enabled: Bool) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.slideshowKenBurnsEnabled = enabled
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.slideshowKenBurnsEnabled = enabled
            central.updateAssignment(newAssignment)
        }
        appDelegate?.applySlideshowKenBurnsToMonitor(monitorID: monitor.id, enabled: enabled)
    }

    func setOpacity(for monitor: MonitorInfo, opacity: Double) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.opacity = opacity
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.opacity = opacity
            central.updateAssignment(newAssignment)
        }

        appDelegate?.applyOpacityToMonitor(monitorID: monitor.id, opacity: opacity)
    }

    func setColorCorrection(for monitor: MonitorInfo, saturation: Double, hue: Double, grayscale: Bool) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.saturation = saturation
            assignment.hue = hue
            assignment.grayscale = grayscale
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.saturation = saturation
            newAssignment.hue = hue
            newAssignment.grayscale = grayscale
            central.updateAssignment(newAssignment)
        }

        appDelegate?.applyColorCorrectionToMonitor(monitorID: monitor.id, saturation: saturation, hue: hue, grayscale: grayscale)
    }

    func setVolume(for monitor: MonitorInfo, volume: Double) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.audioVolume = volume
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.audioVolume = volume
            central.updateAssignment(newAssignment)
        }

        appDelegate?.applyVolumeToMonitor(monitorID: monitor.id, volume: volume)
    }

    func setCropRect(for monitor: MonitorInfo, cropRect: CGRect) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.cropRect = cropRect
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.cropRect = cropRect
            // Do not persist by default — user must explicitly enable "Keep this wallpaper on startup"
            newAssignment.keepOnStartup = false
            central.updateAssignment(newAssignment)
        }

        // Live apply to desktop wallpaper
        appDelegate?.applyCropRectToMonitor(monitorID: monitor.id, cropRect: cropRect)

        print("Crop rect updated for \(monitor.name)")
    }

    func setVideoFrameTime(for monitor: MonitorInfo, time: Double?, useStatic: Bool = false) {
        guard let central = appDelegate?.assignmentStore else { return }

        if var assignment = central.assignment(for: monitor.id) {
            assignment.videoFrameTime = time
            assignment.useStaticVideoFrame = useStatic
            central.updateAssignment(assignment)
        } else {
            var newAssignment = MonitorAssignment(monitorIdentifier: monitor.id)
            newAssignment.videoFrameTime = time
            newAssignment.useStaticVideoFrame = useStatic
            central.updateAssignment(newAssignment)
        }

        // Live seek on desktop if possible
        // appDelegate?.seekWallpaper(for: monitor.id, to: time ?? 0)  // TODO: wire to actual renderer seek
        print("Video frame time updated for \(monitor.name): \(time ?? 0) (static: \(useStatic))")
    }
    
    // MARK: - Persistence Preference (delegated to central AssignmentStore)

    /// Syncs the local published flag from the authoritative central store.
    /// Call this on init and after any refresh so the Toggle binding stays correct.
    private func syncPersistencePreference() {
        if let central = appDelegate?.assignmentStore {
            persistAssignments = central.persistAssignments
        }
        // If no delegate yet (early init), the default true is fine.
    }

    /// Called from the manager view when the user toggles "Remember these assignments".
    /// This is the single path that should mutate the preference.
    func savePersistencePreference(_ enabled: Bool) {
        // Route through the central store (it owns the UD key and the @Published value).
        appDelegate?.assignmentStore.setPersistenceEnabled(enabled)
        
        // Keep our local published value in sync for the Toggle binding.
        persistAssignments = enabled
        
        // Refresh the displayed assigned names (they depend on this flag).
        refreshDisplays()
    }
    
    /// Exposes the user-facing Welcome / What's New screen from the UI layer.
    func showWelcomeScreen() {
        // appDelegate?.showWelcomeScreen(force: true)
    }
    
    /// Shows the changelog for the current version (used by the prominent button + menu).
    func showCurrentChangelog() {
        // appDelegate?.showWhatsNew()
    }

    /// Triggers a check for newer versions of Lumina (opens release notes or update UI).
    func checkForUpdates() {
        // appDelegate?.checkForUpdates()
    }

    /// Shows the About / Status panel (moved from the menu bar into Settings).
    func showAboutStatus() {
        appDelegate?.showAboutStatus()
    }

    /// Re-applies the power policy to all renderers after a power preference changes,
    /// so Settings toggles/profile take effect on the live wallpaper immediately.
    func reapplyPowerPolicy() {
        appDelegate?.reapplyPowerPolicy()
    }

    /// One-shot "Sync Displays": restart all matching video/GIF wallpapers together so they
    /// play in lockstep. Used by the header button — the simple, on-demand alignment.
    func restartDisplaysInSync() {
        appDelegate?.restartDisplaysInSync()
    }

    // MARK: - Playback Sync Setting

    private let syncPlaybackKey = "Lumina.SyncPlaybackAcrossDisplays"
    
    private func loadSyncPlaybackSetting() {
        syncPlaybackAcrossDisplays = UserDefaults.standard.bool(forKey: syncPlaybackKey)
    }
    
    /// Called from the UI when the user toggles "Sync playback across displays".
    func setSyncPlayback(_ enabled: Bool) {
        syncPlaybackAcrossDisplays = enabled
        UserDefaults.standard.set(enabled, forKey: syncPlaybackKey)

        // Drive the engine: an immediate hard sync plus the continuous drift watcher when on,
        // or tear the watcher down when off.
        appDelegate?.setPlaybackSyncEnabled(enabled)
    }
}