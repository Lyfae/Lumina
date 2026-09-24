import SwiftUI
import AppKit
import Combine

/// Observable store for the Wallpaper Manager (Studio).
/// Settings bind into PreferencesStore; this type keeps side-effect commands and UI snapshots.
@MainActor
final class WallpaperManagerStore: ObservableObject {

    @Published var monitors: [MonitorInfo] = []
    @Published var persistAssignments: Bool = true
    @Published var selectedMonitorID: String? = nil
    /// Kept for Settings UI; shared sources make continuous sync unnecessary (step 8).
    @Published var syncPlaybackAcrossDisplays: Bool = false
    @Published private(set) var recentMedia: [RecentMedia] = []

    weak var appDelegate: LuminaApp? {
        didSet { rebuildRecentMedia(); syncPersistencePreference() }
    }

    init() {
        refreshDisplays()
        syncPersistencePreference()
    }

    func rebuildRecentMedia() {
        guard let prefs = appDelegate?.preferencesStore else {
            recentMedia = []
            return
        }
        var seenPaths = Set<String>()
        var result: [RecentMedia] = []

        for item in prefs.wallpapers.library {
            let path = item.media.identity.path
            if seenPaths.contains(path) { continue }
            seenPaths.insert(path)
            let url = URL(fileURLWithPath: path)
            let mediaType: MediaType
            switch item.media.kind {
            case .image: mediaType = .image
            case .animatedImage: mediaType = .animatedImage
            case .video: mediaType = .video
            }
            result.append(RecentMedia(
                id: path,
                url: url,
                mediaType: mediaType,
                displayName: url.lastPathComponent
            ))
        }
        for (_, wallpaper) in prefs.wallpapers.byDisplay {
            if case .media(let ref) = wallpaper.content {
                let path = ref.identity.path
                if seenPaths.contains(path) { continue }
                seenPaths.insert(path)
                let url = URL(fileURLWithPath: path)
                let mediaType: MediaType
                switch ref.kind {
                case .image: mediaType = .image
                case .animatedImage: mediaType = .animatedImage
                case .video: mediaType = .video
                }
                result.append(RecentMedia(
                    id: path,
                    url: url,
                    mediaType: mediaType,
                    displayName: url.lastPathComponent
                ))
            }
        }
        recentMedia = result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func refreshDisplays() {
        syncPersistencePreference()
        let screens = NSScreen.screens
        monitors = screens.enumerated().map { index, screen in
            let resolution = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
            let isPrimary = screen == NSScreen.main
            let id = MonitorInfo.identifier(for: screen, index: index)
            var assignedName: String? = nil
            if let assignment = assignment(for: id), let path = assignment.filePath {
                assignedName = URL(fileURLWithPath: path).lastPathComponent
            } else if case .slideshow(let spec) = appDelegate?.preferencesStore.wallpapers[display: DisplayKey(id)].content,
                      let first = spec.items.first {
                assignedName = URL(fileURLWithPath: first.identity.path).lastPathComponent
            }
            return MonitorInfo(
                id: id,
                name: screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName,
                resolution: resolution,
                isPrimary: isPrimary,
                assignedVideoName: assignedName
            )
        }
        rebuildRecentMedia()
    }

    func getMonitorLayout() -> MonitorLayout { MonitorLayout() }

    func chooseVideo(for monitor: MonitorInfo) {
        guard let index = monitors.firstIndex(where: { $0.id == monitor.id }) else { return }
        guard let url = MediaAccessPolicy.runWallpaperPicker(
            title: "Choose wallpaper for \(monitor.name)",
            message: "This will change the wallpaper on the currently selected display."
        ).first else { return }
        appDelegate?.assignVideoToMonitor(monitorID: monitor.id, url: url)
        monitors[index].assignedVideoName = url.lastPathComponent
        rebuildRecentMedia()
    }

    func clearAssignment(for monitor: MonitorInfo) {
        guard let index = monitors.firstIndex(where: { $0.id == monitor.id }) else { return }
        appDelegate?.clearMonitor(monitorID: monitor.id)
        monitors[index].assignedVideoName = nil
        rebuildRecentMedia()
    }

    func chooseVideoForMonitorID(monitorID: String, url: URL) {
        appDelegate?.assignVideoToMonitor(monitorID: monitorID, url: url)
        if let index = monitors.firstIndex(where: { $0.id == monitorID }) {
            monitors[index].assignedVideoName = url.lastPathComponent
        }
        rebuildRecentMedia()
    }

    func clearAssignmentForMonitorID(monitorID: String) {
        appDelegate?.clearMonitor(monitorID: monitorID)
        if let index = monitors.firstIndex(where: { $0.id == monitorID }) {
            monitors[index].assignedVideoName = nil
        }
        rebuildRecentMedia()
    }

    func setKeepOnStartup(for monitor: MonitorInfo, enabled: Bool) {
        guard let prefs = appDelegate?.preferencesStore else { return }
        var wallpaper = prefs.wallpapers[display: DisplayKey(monitor.id)]
        wallpaper.pinned = enabled
        var next = prefs.wallpapers
        next[display: DisplayKey(monitor.id)] = wallpaper
        prefs.wallpapers = next
        LuminaLog.wallpaper.info("Keep on startup for \(monitor.name) set to \(enabled)")
    }

    func assignment(for monitorID: String) -> MonitorAssignment? {
        appDelegate?.preferencesStore.wallpaperAssignment(for: monitorID)
    }

    struct RecentMedia: Identifiable {
        let id: String
        let url: URL
        let mediaType: MediaType
        let displayName: String
    }

    func applyRecentMedia(to monitorID: String, url: URL) {
        appDelegate?.assignVideoToMonitor(monitorID: monitorID, url: url)
        if let index = monitors.firstIndex(where: { $0.id == monitorID }) {
            monitors[index].assignedVideoName = url.lastPathComponent
        }
        rebuildRecentMedia()
    }

    func removeFromLibrary(id: String) {
        guard let prefs = appDelegate?.preferencesStore else { return }
        // Remove library entries matching path, and clear monitors using it.
        for (key, wallpaper) in prefs.wallpapers.byDisplay {
            if case .media(let ref) = wallpaper.content, ref.identity.path == id {
                appDelegate?.clearMonitor(monitorID: key.rawValue)
                if let index = monitors.firstIndex(where: { $0.id == key.rawValue }) {
                    monitors[index].assignedVideoName = nil
                }
            }
        }
        var next = prefs.wallpapers
        next.library.removeAll { $0.media.identity.path == id || $0.id == id }
        prefs.wallpapers = next
        refreshDisplays()
    }

    func addMediaToLibrary(url: URL, enforceAccessPolicy: Bool = true) {
        if enforceAccessPolicy {
            guard MediaAccessPolicy.accept(url) else { return }
        } else {
            _ = FileAccess.registerUserSelectedFile(url)
        }
        guard let prefs = appDelegate?.preferencesStore else { return }
        if prefs.wallpapers.library.contains(where: { $0.media.identity.path == url.path }) {
            return
        }
        let ref = prefs.mediaReference(from: url)
        var next = prefs.wallpapers
        next.library.append(LibraryItem(id: "library-import-\(UUID().uuidString)", media: ref))
        prefs.wallpapers = next
        rebuildRecentMedia()
        refreshDisplays()
    }

    // MARK: - Live settings → prefs (engine replans)

    private func mutateWallpaper(for monitor: MonitorInfo, _ body: (inout DisplayWallpaper) -> Void) {
        guard let prefs = appDelegate?.preferencesStore else { return }
        var wallpaper = prefs.wallpapers[display: DisplayKey(monitor.id)]
        body(&wallpaper)
        var next = prefs.wallpapers
        next[display: DisplayKey(monitor.id)] = wallpaper
        prefs.wallpapers = next
    }

    func setScaling(for monitor: MonitorInfo, scaling: VideoScaling) {
        mutateWallpaper(for: monitor) { $0.look.scaling = scaling }
    }

    func setPlaybackSpeed(for monitor: MonitorInfo, speed: Double) {
        mutateWallpaper(for: monitor) { $0.timing.speed = speed }
    }

    func setLoopMode(for monitor: MonitorInfo, mode: LoopMode) {
        mutateWallpaper(for: monitor) { $0.timing.loopMode = mode }
    }

    func setLoopFade(for monitor: MonitorInfo, enabled: Bool, duration: Double,
                     easing: FadeEasing = .easeInOut) {
        mutateWallpaper(for: monitor) {
            $0.look.loopFade.enabled = enabled
            $0.look.loopFade.duration = duration
            $0.look.loopFade.easing = easing
        }
    }

    func setBrightness(for monitor: MonitorInfo, brightness: Double) {
        mutateWallpaper(for: monitor) { $0.look.brightness = brightness }
    }

    func setSlideshowItems(for monitor: MonitorInfo, items: [String]) {
        mutateWallpaper(for: monitor) { wallpaper in
            if items.isEmpty {
                if case .slideshow = wallpaper.content { wallpaper.content = .none }
            } else {
                let refs = items.map { path -> MediaReference in
                    MediaReference(
                        identity: MediaIdentity(normalizing: path),
                        displayPath: path,
                        bookmark: nil,
                        kind: .image
                    )
                }
                let interval: Double
                let transition: SlideshowTransition
                let kenBurns: Bool
                if case .slideshow(let existing) = wallpaper.content {
                    interval = existing.interval
                    transition = existing.transition
                    kenBurns = existing.kenBurns
                } else {
                    interval = 10
                    transition = .fade
                    kenBurns = true
                }
                wallpaper.content = .slideshow(SlideshowSpec(
                    items: refs, interval: interval, transition: transition, kenBurns: kenBurns
                ))
            }
        }
    }

    func setSlideshowInterval(for monitor: MonitorInfo, interval: Double) {
        mutateWallpaper(for: monitor) { wallpaper in
            if case .slideshow(var spec) = wallpaper.content {
                spec.interval = interval
                wallpaper.content = .slideshow(spec)
            }
        }
    }

    func setSlideshowTransition(for monitor: MonitorInfo, transition: SlideshowTransition) {
        mutateWallpaper(for: monitor) { wallpaper in
            if case .slideshow(var spec) = wallpaper.content {
                spec.transition = transition
                wallpaper.content = .slideshow(spec)
            }
        }
    }

    func setSlideshowKenBurns(for monitor: MonitorInfo, enabled: Bool) {
        mutateWallpaper(for: monitor) { wallpaper in
            if case .slideshow(var spec) = wallpaper.content {
                spec.kenBurns = enabled
                wallpaper.content = .slideshow(spec)
            }
        }
    }

    func setOpacity(for monitor: MonitorInfo, opacity: Double) {
        mutateWallpaper(for: monitor) { $0.look.opacity = opacity }
    }

    func setColorCorrection(for monitor: MonitorInfo, saturation: Double, hue: Double, grayscale: Bool) {
        mutateWallpaper(for: monitor) {
            $0.look.saturation = saturation
            $0.look.hue = hue
            $0.look.grayscale = grayscale
        }
    }

    func setVolume(for monitor: MonitorInfo, volume: Double) {
        mutateWallpaper(for: monitor) {
            $0.audio.volume = volume
            $0.audio.muted = volume <= 0.001
        }
    }

    func setCropRect(for monitor: MonitorInfo, cropRect: CGRect) {
        mutateWallpaper(for: monitor) {
            $0.look.crop = NormalizedRect(
                x: cropRect.origin.x, y: cropRect.origin.y,
                width: cropRect.size.width, height: cropRect.size.height
            ) ?? .full
        }
    }

    func setVideoFrameTime(for monitor: MonitorInfo, time: Double?, useStatic: Bool = false) {
        mutateWallpaper(for: monitor) {
            $0.timing.startFrame = time
            $0.timing.freezeAtStartFrame = useStatic
        }
    }

    private func syncPersistencePreference() {
        if let prefs = appDelegate?.preferencesStore {
            persistAssignments = prefs.startup.restoreAtLaunch
        }
    }

    func savePersistencePreference(_ enabled: Bool) {
        guard let prefs = appDelegate?.preferencesStore else { return }
        prefs.startup.restoreAtLaunch = enabled
        persistAssignments = enabled
        refreshDisplays()
    }

    func showAboutStatus() { appDelegate?.showAboutStatus() }
    func checkForUpdates() { appDelegate?.checkForUpdates(silent: false) }
    func reapplyPowerPolicy() { appDelegate?.reapplyPowerPolicy() }
    func restartDisplaysInSync() { appDelegate?.restartDisplaysInSync() }

    func setSyncPlayback(_ enabled: Bool) {
        // Shared sources make continuous sync a no-op; keep the preference key for downgrade.
        syncPlaybackAcrossDisplays = enabled
        UserDefaults.standard.set(enabled, forKey: "Lumina.SyncPlaybackAcrossDisplays")
    }
}
