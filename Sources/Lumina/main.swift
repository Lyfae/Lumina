// Lumina
// Native, battery-friendly live wallpaper engine for macOS (Tahoe+ target)
//
// Entry point: menu-bar-only accessory application.
// We deliberately avoid a Dock icon and any foreground windows by default.
//
// Native live wallpaper engine. Menu-bar accessory app (no Dock icon).
// Per-monitor video / GIF / image wallpapers with live preview, slideshows (Ken Burns),
// crop, effects, ambient audio, power-aware pausing, and launch-at-login support.
//
// Icon: Uses a proper NSImage (SF Symbol "water.waves" + fallback) for correct vertical
// alignment instead of emoji titles (fixes shift-up bug on Tahoe and other macOS releases).

import AppKit
import AVFoundation
import SwiftUI

@main
@MainActor
final class LuminaApp: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Core Engine
    var powerManager: PowerManager!           // Made internal so window controllers can notify about activity
    private var fullscreenDetector: FullscreenDetector!
    private var wallpaperWindows: [DesktopWallpaperWindow] = []
    private var renderers: [AVVideoRenderer] = []
    /// CGDirectDisplayIDs parallel to `wallpaperWindows` / `renderers`, used to reconcile
    /// the window/renderer set across display hot-plug, rearrange, and sleep/wake.
    private var screenDisplayIDs: [CGDirectDisplayID] = []
    /// Debounces bursts of screen-parameter notifications (macOS often fires several in a row).
    private var reconcileWorkItem: DispatchWorkItem?
    /// Display IDs whose wallpaper window is currently occluded (covered by a fullscreen app
    /// or other windows). Those renderers are paused for power until they become visible again.
    private var occludedDisplayIDs: Set<CGDirectDisplayID> = []
    /// Periodically re-aligns video playback positions while "Sync playback across displays"
    /// is on, correcting the small drift that accumulates between independent AVQueuePlayers.
    private var syncDriftTimer: Timer?
    
    // New per-monitor state management (Phase 1+)
    let assignmentStore = AssignmentStore()   // Made internal so WallpaperManagerStore can access it

    // MARK: - UX / State (prototype enhancements for B + C)
    private var currentVideoURL: URL?
    private var currentWallpaperMenuItem: NSMenuItem!

    // MARK: - UI
    private var statusItem: NSStatusItem!
    private var wallpaperManagerWindow: WallpaperManagerWindowController?

    static func main() {
        // Headless self-test path: validate engine logic and exit without starting the UI
        // (so no desktop wallpaper windows are created). Run with: Lumina --self-test
        if CommandLine.arguments.contains("--self-test") {
            _ = NSApplication.shared   // AppKit must be initialized for NSView/NSImage
            exit(SelfTest.run())
        }

        // On-device window/occlusion validation (needs a live WindowServer). Briefly creates a
        // real desktop window, verifies compositing + occlusion API, then tears it down.
        if CommandLine.arguments.contains("--window-test") {
            SelfTest.runWindowTest()   // sets up NSApp + delegate, runs, exits when done
            return
        }

        // Full occlusion-cycle validation: covers the wallpaper window and checks the pause trigger.
        if CommandLine.arguments.contains("--occlusion-test") {
            SelfTest.runOcclusionTest()
            return
        }

        let app = NSApplication.shared
        let delegate = LuminaApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // Critical: no Dock icon, menu-bar only
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Purge any legacy global-persistence keys so the app always starts clean (black displays).
        WallpaperPersistence.clearLastVideo()

        // Apply the saved UI appearance (light / dark / match system) before any windows open.
        AppearanceManager.shared.apply()

        // Release splash: borderless floating card with the animated cursive LS monogram.
        // Non-activating (never steals focus), click-to-dismiss, auto-dismisses in ~4s.
        SplashWindowController.present()

        setupStatusItem()
        setupPowerManager()
        setupWallpaperWindowsAndRenderers()

        // Re-query occlusion once the window server has settled. Fail-open: never pause at launch
        // (occlusion may not be computed yet) — only clear pauses. Real coverage is caught by the
        // per-window occlusion notification + app/space-change re-checks while running.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.seedOcclusionStates(failOpen: true)
        }

        // Screen parameter changes are NSApplication notifications (default center).
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Workspace notifications (wake, app activation, space change) are delivered ONLY through
        // NSWorkspace's own notification center — NOT NotificationCenter.default. Observing them on
        // the default center (as before) silently never fired, so wake-from-sleep handling was dead.
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(wakeFromSleep),
            name: NSWorkspace.didWakeNotification, object: nil)
        // Re-check occlusion on app activation / space change so fullscreen transitions are caught
        // even if the per-window occlusion notification is delayed or missed.
        wsnc.addObserver(self, selector: #selector(activeContextChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(activeContextChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        LuminaLog.app.info("Lumina started (menu-bar only). Use the menu bar icon → Wallpaper Manager (⌘M)")

        // Show onboarding on first launch (unless user chose "never show again").
        // We also re-check when the Wallpaper Manager opens so it feels tied to the manager experience.
        if !UserDefaults.standard.bool(forKey: "Lumina.HasShownOnboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showOnboarding()
            }
        }
        
        // Optional update check on launch (Settings → General).
        if UserDefaults.standard.object(forKey: "Lumina.AutoCheckUpdates") == nil {
            UserDefaults.standard.set(true, forKey: "Lumina.AutoCheckUpdates")
        }
        if UserDefaults.standard.bool(forKey: "Lumina.AutoCheckUpdates") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.checkForUpdates(silent: true)
            }
        }

        // New-version changelog: open About & Status once per version.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.checkForNewVersionAndShowChangelogIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Single teardown path for every exit (menu Quit, ⌘Q, logout, system shutdown):
        // stop all playback and remove the desktop wallpaper windows so nothing lingers.
        powerManager?.pauseManually()
        stopDriftWatcher()
        reconcileWorkItem?.cancel()
        occlusionRescanWorkItem?.cancel()
        for renderer in renderers {
            renderer.cleanup()
        }
        for window in wallpaperWindows {
            window.hideAndRelease()
        }
        renderers.removeAll()
        wallpaperWindows.removeAll()
        LuminaLog.app.info("Shutdown complete — all renderers and wallpaper windows torn down.")
    }

    @objc private func wakeFromSleep() {
        // Displays can come back in a different configuration after sleep; reconcile and
        // re-assert desktop-level ordering so the wallpaper reliably reappears.
        scheduleReconcile()
        for window in wallpaperWindows { window.showOnDesktop() }
        fullscreenDetector?.checkNow()
    }

    @objc private func screensChanged() {
        scheduleReconcile()
        fullscreenDetector?.checkNow()
    }

    /// macOS often posts several `didChangeScreenParameters` notifications in quick succession
    /// during a single reconfiguration. Debounce so we rebuild the window/renderer set once.
    private func scheduleReconcile() {
        reconcileWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcileDisplays() }
        reconcileWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: - Engine Setup

    private func setupPowerManager() {
        powerManager = PowerManager()

        // Wire policy changes → renderers + UI
        powerManager.onPolicyChange = { [weak self] policy in
            self?.applyPolicyToRenderers(policy)
            self?.updateStatusItem(for: policy)
        }

        // Fullscreen / obscured handling is now done with native, event-driven per-window
        // occlusion (see windowOcclusionChanged) instead of the old CGWindowList polling.
        // Occlusion is accurate, needs no Screen Recording permission, costs nothing when
        // idle, and pauses ONLY the display a fullscreen app actually covers — so a second
        // monitor's wallpaper keeps playing while you game fullscreen on the first.
        fullscreenDetector = nil
    }

    private func setupWallpaperWindowsAndRenderers() {
        let screens = NSScreen.screens

        // Create one desktop-level window + renderer per screen, tracking display IDs.
        wallpaperWindows = []
        renderers = []
        screenDisplayIDs = []
        for screen in screens {
            let (window, renderer) = makeWindowAndRenderer(for: screen)
            wallpaperWindows.append(window)
            renderers.append(renderer)
            screenDisplayIDs.append(MonitorInfo.displayID(for: screen))
        }

        // Initial policy application
        applyPolicyToRenderers(powerManager.currentPolicy)

        // === Phase 1: Per-Monitor Restoration from AssignmentStore ===
        // Everything starts black (renderers are freshly created/cleared); only
        // assignments explicitly marked "Keep on startup" are restored here.
        var restoredCount = 0
        for index in screens.indices {
            if restoreAssignment(forScreenAt: index, requireKeepOnStartup: true) {
                restoredCount += 1
            }
        }

        if restoredCount > 0 {
            LuminaLog.app.info("Restored \(restoredCount) per-monitor assignment(s).")
        } else {
            // We deliberately do NOT fall back to the old global persistence here anymore.
            // Once the user has used the per-monitor system and cleared things,
            // we want a clean black start unless they explicitly re-enable "Keep on startup".
            LuminaLog.app.info("No per-monitor wallpapers set to keep on startup. Starting clean (black).")
        }

        // If the user has "Sync playback across displays" enabled, align them on launch and
        // start the continuous drift watcher so they stay aligned.
        if UserDefaults.standard.bool(forKey: "Lumina.SyncPlaybackAcrossDisplays") {
            setPlaybackSyncEnabled(true)
        }

        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)
    }

    /// Builds a properly configured desktop window + installed renderer for one screen.
    private func makeWindowAndRenderer(for screen: NSScreen) -> (DesktopWallpaperWindow, AVVideoRenderer) {
        let window = DesktopWallpaperWindow(screen: screen)
        window.showOnDesktop()

        // Observe this window's occlusion so we can pause its renderer when it's covered.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowOcclusionChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )

        let renderer = AVVideoRenderer()
        renderer.onLoadFailure = { [weak self] url, error in
            self?.recordLoadFailure(url: url, error: error)
        }
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            renderer.install(into: contentView)
        }
        renderer.applyPolicy(powerManager.currentPolicy)
        return (window, renderer)
    }

    /// Records a media load failure on the matching assignment so the UI/diagnostics can
    /// reflect it, and keeps the display black rather than appearing stuck.
    private func recordLoadFailure(url: URL, error: Error?) {
        let message = error?.localizedDescription ?? "The file could not be played (it may be corrupt or in an unsupported format)."
        for (id, var assignment) in assignmentStore.assignments
        where assignment.resolvedURL()?.path == url.path
            || assignment.filePath.map({ ($0 as NSString).expandingTildeInPath }) == url.path {
            assignment.lastError = message
            assignmentStore.updateAssignment(assignment)
            LuminaLog.wallpaper.warning("Recorded load failure for \(id): \(message)")
        }
    }

    /// Loads and applies the saved assignment for the screen at `index` onto its renderer.
    /// - Parameter requireKeepOnStartup: when true (launch), only restores assignments the
    ///   user pinned with "Keep on startup". When false (display reconnect mid-session),
    ///   restores whatever the user had assigned this session so the wallpaper comes back.
    /// - Returns: true if media was loaded.
    @discardableResult
    private func restoreAssignment(forScreenAt index: Int, requireKeepOnStartup: Bool) -> Bool {
        let screens = NSScreen.screens
        guard index < screens.count, index < renderers.count else { return false }
        return restoreAssignment(onto: renderers[index],
                                 forScreen: screens[index],
                                 index: index,
                                 requireKeepOnStartup: requireKeepOnStartup)
    }

    /// Core restore: loads the saved assignment for `screen` onto a specific `renderer`.
    @discardableResult
    private func restoreAssignment(onto renderer: AVVideoRenderer,
                                   forScreen screen: NSScreen,
                                   index: Int,
                                   requireKeepOnStartup: Bool) -> Bool {
        let monitorID = MonitorInfo.identifier(for: screen, index: index)

        // Migrate assignments saved under the old resolution-dependent identifier so
        // pinned wallpapers survive the key-format change (and resolution switches).
        if assignmentStore.assignment(for: monitorID) == nil {
            let legacyID = MonitorInfo.legacyIdentifier(for: screen, index: index)
            if legacyID != monitorID, var legacy = assignmentStore.assignment(for: legacyID) {
                legacy.monitorIdentifier = monitorID
                assignmentStore.updateAssignment(legacy)
                assignmentStore.removeAssignment(for: legacyID)
                LuminaLog.persistence.info("Migrated assignment \(legacyID) → \(monitorID)")
            }
        }

        guard let assignment = assignmentStore.assignment(for: monitorID),
              assignment.isEnabled else { return false }

        if requireKeepOnStartup && !assignment.keepOnStartup { return false }

        // Slideshow takes precedence over a single media file when items are present.
        let slideItems = assignment.slideshowItems.filter {
            FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath)
        }
        if !slideItems.isEmpty {
            renderer.loadSlideshow(items: slideItems,
                                   interval: assignment.slideshowInterval,
                                   transition: assignment.slideshowTransition,
                                   kenBurnsEnabled: assignment.slideshowKenBurnsEnabled)
            LuminaLog.app.info("Restored slideshow for \(monitorID) (\(slideItems.count) image(s))")
            return true
        }

        guard let path = assignment.filePath else { return false }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            LuminaLog.app.warning("File missing for \(monitorID): \(path)")
            return false
        }

        let bestURL = bestURLForCurrentPowerState(originalURL: url)
        renderer.load(url: bestURL, autoPlay: true)
        applyAssignmentSettings(assignment, to: renderer)

        // If the security-scoped bookmark went stale (file moved / OS update), recreate it now
        // that we have a valid URL so future restores keep working.
        if assignment.bookmarkIsStale() {
            var refreshed = assignment
            refreshed.updateBookmark(from: url)
            assignmentStore.updateAssignment(refreshed)
            LuminaLog.app.info("Refreshed stale bookmark for \(monitorID)")
        }

        LuminaLog.app.info("Restored \(monitorID) → \(url.lastPathComponent) (\(assignment.mediaType), speed: \(assignment.playbackSpeed)x)")
        return true
    }

    /// Applies every persisted visual/playback setting from an assignment onto a renderer.
    private func applyAssignmentSettings(_ assignment: MonitorAssignment, to renderer: AVVideoRenderer) {
        renderer.setScaling(mapModelToRendererScaling(assignment.scaling))
        renderer.setPlaybackSpeed(assignment.playbackSpeed)
        renderer.setMuted(assignment.isMuted)
        renderer.applyCropRect(assignment.cropRect)
        renderer.setOpacity(assignment.opacity)
        renderer.setVolume(assignment.audioVolume)
        renderer.setColorCorrection(saturation: assignment.saturation,
                                    hue: assignment.hue,
                                    grayscale: assignment.grayscale)
        renderer.setBrightness(assignment.brightness)
        renderer.setLoopFade(enabled: assignment.loopFadeEnabled,
                             duration: assignment.loopFadeDuration,
                             easing: assignment.loopFadeEasing)
        renderer.setLoopMode(assignment.loopMode)
    }

    // MARK: - Display Reconfiguration

    /// Reconciles the window/renderer set with the current set of screens after a display
    /// hot-plug, rearrange, resolution change, or sleep/wake. Reuses existing windows and
    /// renderers for displays that are still present (keyed by CGDirectDisplayID), creates
    /// them for newly attached displays, and tears down those whose display went away.
    private func reconcileDisplays() {
        let screens = NSScreen.screens
        let newIDs = screens.map { MonitorInfo.displayID(for: $0) }

        // If nothing actually changed (same displays, same order), only refresh geometry.
        if newIDs == screenDisplayIDs {
            for (index, screen) in screens.enumerated() where index < wallpaperWindows.count {
                wallpaperWindows[index].updateFrame(to: screen.frame)
                renderers[index].relayout()
            }
            return
        }

        print("[Lumina] Display configuration changed: \(screenDisplayIDs) → \(newIDs)")

        // Index existing windows/renderers by their display ID for reuse.
        var freeWindows: [CGDirectDisplayID: DesktopWallpaperWindow] = [:]
        var freeRenderers: [CGDirectDisplayID: AVVideoRenderer] = [:]
        for (i, id) in screenDisplayIDs.enumerated() {
            if i < wallpaperWindows.count { freeWindows[id] = wallpaperWindows[i] }
            if i < renderers.count { freeRenderers[id] = renderers[i] }
        }

        var newWindows: [DesktopWallpaperWindow] = []
        var newRenderers: [AVVideoRenderer] = []

        for (index, screen) in screens.enumerated() {
            let id = newIDs[index]
            if let window = freeWindows[id], let renderer = freeRenderers[id] {
                // Display still present — reuse and refresh geometry.
                window.updateFrame(to: screen.frame)
                renderer.relayout()
                newWindows.append(window)
                newRenderers.append(renderer)
                freeWindows[id] = nil
                freeRenderers[id] = nil
            } else {
                // Newly attached display — create fresh surfaces and restore any
                // assignment the user set for it this session.
                let (window, renderer) = makeWindowAndRenderer(for: screen)
                newWindows.append(window)
                newRenderers.append(renderer)
                restoreAssignment(onto: renderer, forScreen: screen, index: index, requireKeepOnStartup: false)
            }
        }

        // Tear down windows/renderers for displays that were removed.
        for (_, renderer) in freeRenderers { renderer.cleanup() }
        for (_, window) in freeWindows {
            NotificationCenter.default.removeObserver(self,
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
            window.hideAndRelease()
        }

        wallpaperWindows = newWindows
        renderers = newRenderers
        screenDisplayIDs = newIDs
        // Drop occlusion entries for displays that no longer exist.
        occludedDisplayIDs.formIntersection(Set(newIDs))

        applyPolicyToRenderers(powerManager.currentPolicy)

        if UserDefaults.standard.bool(forKey: "Lumina.SyncPlaybackAcrossDisplays") {
            syncAllRenderers()
        }
        updateStatusItem(for: powerManager.currentPolicy)
    }

    func applyPolicyToRenderers(_ policy: WallpaperPlaybackPolicy) {
        for index in renderers.indices {
            applyEffectivePolicy(policy, toRendererAt: index)
        }
    }

    /// Re-evaluates the power policy AND re-applies it to every renderer. Called when the user
    /// changes a power preference (toggle / profile) so the change takes effect immediately —
    /// even when the recomputed policy value is unchanged (e.g. toggling "pause behind
    /// fullscreen apps" only affects the per-display occlusion gating in applyEffectivePolicy,
    /// which would otherwise never re-run).
    func reapplyPowerPolicy() {
        powerManager.recomputePolicy()
        applyPolicyToRenderers(powerManager.currentPolicy)
    }

    /// Applies the global power policy to one renderer, except that an occluded display is
    /// always paused (when the user keeps "Pause on Fullscreen Apps" enabled).
    private func applyEffectivePolicy(_ policy: WallpaperPlaybackPolicy, toRendererAt index: Int) {
        guard index < renderers.count else { return }
        let displayID = index < screenDisplayIDs.count ? screenDisplayIDs[index] : 0
        let occluded = powerManager.respectFullscreenApps && occludedDisplayIDs.contains(displayID)
        if occluded {
            renderers[index].pause()
        } else {
            renderers[index].applyPolicy(policy)
        }
    }

    // MARK: - Per-Window Occlusion (native fullscreen / cover detection)

    /// Called when a wallpaper window's visibility changes. We pause the renderer for any
    /// display whose wallpaper is fully covered (e.g. a fullscreen game or video on that
    /// monitor) and resume it the instant the desktop is visible again.
    @objc private func windowOcclusionChanged(_ note: Notification) {
        guard let window = note.object as? DesktopWallpaperWindow,
              let index = wallpaperWindows.firstIndex(of: window),
              index < screenDisplayIDs.count else { return }

        let displayID = screenDisplayIDs[index]
        let isVisible = window.occlusionState.contains(.visible)
        if isVisible {
            occludedDisplayIDs.remove(displayID)
        } else {
            occludedDisplayIDs.insert(displayID)
        }
        applyEffectivePolicy(powerManager.currentPolicy, toRendererAt: index)
    }

    /// Fired when the frontmost app or active Space changes. Occlusion notifications can lag a
    /// fullscreen/space transition, so we re-query each window's occlusion shortly after.
    /// Debounces occlusion re-scans: rapid ⌘-tabbing / space flips fire this notification many
    /// times in a row, and each un-debounced scan re-applied policy to every renderer.
    private var occlusionRescanWorkItem: DispatchWorkItem?

    @objc private func activeContextChanged() {
        // App/Space changed: the app has been running so occlusion is reliable here — do a full
        // re-query (may pause a now-covered display or resume a newly-revealed one).
        occlusionRescanWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.seedOcclusionStates(failOpen: false) }
        occlusionRescanWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Re-queries occlusion for every wallpaper window.
    ///
    /// `failOpen` matters because AppKit may not have computed occlusion yet right after launch:
    /// an uncomputed state lacks `.visible` and is indistinguishable from "covered". When
    /// `failOpen` is true we therefore ONLY clear pauses, never add them — guaranteeing
    /// wallpapers play by default and can never get stuck paused because occlusion wasn't ready.
    /// The reliable per-window `didChangeOcclusionStateNotification` handles real coverage while
    /// the app is running (validated on-device: occlusionState reports `.visible` correctly under
    /// the live app lifecycle).
    private func seedOcclusionStates(failOpen: Bool) {
        for (index, window) in wallpaperWindows.enumerated() where index < screenDisplayIDs.count {
            let displayID = screenDisplayIDs[index]
            if window.occlusionState.contains(.visible) {
                occludedDisplayIDs.remove(displayID)
            } else if !failOpen {
                occludedDisplayIDs.insert(displayID)
            }
            applyEffectivePolicy(powerManager.currentPolicy, toRendererAt: index)
        }
    }
    
    /// Synchronizes playback across all active renderers so identical wallpapers
    /// on multiple monitors play at the same position and start at the same instant.
    ///
    /// Uses `AVQueuePlayer.setRate(_:time:atHostTime:)` with a shared future host-clock
    /// time so all players begin in lockstep, eliminating the seek→play timing skew of
    /// the old pause→seek→play approach.
    func syncAllRenderers() {
        guard !renderers.isEmpty else { return }

        let activeRenderers = renderers.filter { $0.isLoaded }
        guard !activeRenderers.isEmpty else { return }

        // Use renderer 0's current position as the reference seek point.
        let referenceTime = activeRenderers.first?.currentPlaybackTime() ?? 0
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        // Give every player 80 ms to seek before we tell them all to start.
        let startAt = CMTimeAdd(hostTime, CMTime(value: 8, timescale: 100))

        for renderer in activeRenderers {
            renderer.syncStart(to: referenceTime, atHostTime: startAt)
        }

        LuminaLog.wallpaper.info("Synced \(activeRenderers.count) renderer(s) to \(String(format: "%.2f", referenceTime))s")
    }

    /// One-shot "Sync Displays": restarts every active video/GIF wallpaper from the beginning
    /// at a shared start instant, so the same media on multiple monitors plays in lockstep.
    /// This is the simple, on-demand fix for "they drifted / started at different times."
    func restartDisplaysInSync() {
        let active = renderers.filter { $0.isLoaded }
        guard !active.isEmpty else { return }

        // A small shared lead so every renderer is armed before the common start moment.
        let layerBegin = CACurrentMediaTime() + 0.1
        let videoHostTime = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()),
                                      CMTime(value: 10, timescale: 100))   // ~100 ms

        for renderer in active {
            renderer.restartInSync(videoHostTime: videoHostTime, layerBeginTime: layerBegin)
        }
        LuminaLog.wallpaper.info("Restarted \(active.count) renderer(s) in sync")

        // Verification: sample the video positions once playback has settled and report the
        // spread between displays, so the alignment is observable rather than a guess.
        let videoRenderers = active.filter { $0.currentItemDuration() > 0 }
        guard videoRenderers.count >= 2 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let times = videoRenderers.map { $0.currentPlaybackTime() }
            guard let lo = times.min(), let hi = times.max() else { return }
            let spreadMs = (hi - lo) * 1000
            let positions = times.map { String(format: "%.3f", $0) }.joined(separator: ", ")
            LuminaLog.wallpaper.info(String(format: "Sync check: %d videos at [%@]s — spread %.0f ms %@",
                         videoRenderers.count, positions, spreadMs,
                         spreadMs < 50 ? "✅ aligned" : "⚠️ drifting"))
        }
    }

    /// Turns continuous playback sync on or off. When on, performs an immediate hard sync and
    /// then starts a low-frequency drift watcher; when off, stops the watcher. The setting's
    /// persistence is owned by the store — this only drives the engine.
    func setPlaybackSyncEnabled(_ enabled: Bool) {
        if enabled {
            syncAllRenderers()
            startDriftWatcher()
        } else {
            stopDriftWatcher()
        }
    }

    /// Maximum tolerated drift before we re-seek. Below this, players are perceptually in sync
    /// and re-seeking would cause a visible hitch, so we leave them alone.
    private static let syncDriftToleranceSeconds: TimeInterval = 0.15

    private func startDriftWatcher() {
        stopDriftWatcher()
        // 3s cadence keeps overhead negligible while bounding worst-case visible skew.
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.correctDriftIfNeeded() }
        }
        // .common so it keeps firing during window resizing / menu tracking.
        RunLoop.main.add(timer, forMode: .common)
        syncDriftTimer = timer
    }

    private func stopDriftWatcher() {
        syncDriftTimer?.invalidate()
        syncDriftTimer = nil
    }

    /// Measures loop-aware drift between active video renderers and hard-syncs only when it
    /// exceeds the tolerance. Paused/occluded renderers (rate 0) are skipped so we don't fight
    /// the power policy or restart playback the user deliberately stopped.
    private func correctDriftIfNeeded() {
        // Only compare renderers playing the *same* media as the reference — circular drift
        // math is meaningless across clips of different lengths and would cause spurious
        // re-sync hitches (or mask real drift).
        let loaded = renderers.filter { $0.isLoaded && $0.currentPlaybackRate > 0 }
        guard let referenceRenderer = loaded.first else { return }
        let active = loaded.filter { $0.loadedURL == referenceRenderer.loadedURL }
        guard active.count >= 2 else { return }

        let reference = active[0].currentPlaybackTime()
        // Loop period from the reference item; used to measure distance across the wrap boundary.
        let period = active[0].currentItemDuration()

        let maxDrift = active.dropFirst().reduce(0.0) { worst, r in
            max(worst, circularDrift(reference, r.currentPlaybackTime(), period: period))
        }

        if maxDrift > Self.syncDriftToleranceSeconds {
            LuminaLog.wallpaper.info("Drift \(String(format: "%.3f", maxDrift))s exceeds tolerance — re-syncing")
            syncAllRenderers()
        }
    }

    /// Shortest distance between two positions on a loop of length `period`. Falls back to the
    /// plain absolute difference when the period is unknown (0).
    private func circularDrift(_ a: TimeInterval, _ b: TimeInterval, period: TimeInterval) -> TimeInterval {
        let raw = abs(a - b)
        guard period > 0 else { return raw }
        return min(raw, period - raw)
    }

    /// Immediately clears the renderer for a specific monitor (makes that display go black).
    /// Used when the user turns off "Keep on startup" for instant feedback.
    func clearRenderer(for monitorID: String) {
        guard let index = monitorIndex(for: monitorID) else { return }
        guard index < renderers.count else { return }
        renderers[index].clear()
        LuminaLog.app.info("Cleared renderer for \(monitorID) (keep on startup turned off)")
    }

    /// Fully removes a monitor's wallpaper: blanks the display (to black) and deletes its
    /// assignment. This is the correct "clear" path — previously callers loaded an empty-path
    /// URL, which wrote a bogus assignment (filePath="") and relied on the load failing.
    func clearMonitor(monitorID: String) {
        clearRenderer(for: monitorID)
        assignmentStore.removeAssignment(for: monitorID)
        if monitorID == currentVideoURLMonitorID { currentVideoURL = nil }
        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)
        LuminaLog.app.info("Cleared wallpaper for \(monitorID)")
    }

    /// Tracks which monitor the legacy `currentVideoURL` status field refers to, so clearing
    /// the right monitor also resets the menu-bar status text.
    private var currentVideoURLMonitorID: String?

    // MARK: - Video Loading (Prototype)

    @objc private func showLoadVideoPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose wallpaper media"
        panel.message = "Best results with H.264 / HEVC (H.265) videos at 24-30 fps. Also supports GIFs and static images."
        panel.allowedContentTypes = [.movie, .image, .gif]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        loadVideo(url: url)
    }

    @objc private func openWallpaperManager() {
        if wallpaperManagerWindow == nil {
            wallpaperManagerWindow = WallpaperManagerWindowController(appDelegate: self)
        }
        
        wallpaperManagerWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Tie onboarding to the Wallpaper Manager experience (as requested)
        self.maybeShowOnboardingForManager()
        
        // Also check for changelog / new version notes when the user opens the manager
        self.checkForNewVersionAndShowChangelogIfNeeded()
        
        // Automatically open the Choose Display window so the user can pick a screen first
        wallpaperManagerWindow?.openChooseDisplayWindowIfNeeded()
    }

    private var onboardingWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?
    private var updateWindowController: NSWindowController?

    private func showOnboarding(forced: Bool = false) {
        // For normal (non-forced) shows, respect the "never show again" flag.
        if !forced && UserDefaults.standard.bool(forKey: "Lumina.HasShownOnboarding") {
            return
        }

        let hosting = NSHostingController(
            rootView: OnboardingView { neverShowAgain in
                // Only mark as "shown forever" if the user explicitly checked "Don't show this again".
                // If they left it unchecked, we will show it again on next launch / next manager open.
                if neverShowAgain {
                    UserDefaults.standard.set(true, forKey: "Lumina.HasShownOnboarding")
                }
                self.onboardingWindowController?.close()
                self.onboardingWindowController = nil
            }
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = forced ? "Welcome to Lumina" : "Welcome to Lumina"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()

        let controller = NSWindowController(window: window)
        self.onboardingWindowController = controller

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Called from WallpaperManagerWindowController when the manager opens.
    /// Shows onboarding (if not permanently dismissed) in the context of using the manager.
    func maybeShowOnboardingForManager() {
        if !UserDefaults.standard.bool(forKey: "Lumina.HasShownOnboarding") {
            // Small delay so the manager window has time to appear first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.showOnboarding()
            }
        }
    }
    
    /// Opens About & Status (welcome copy, live status, full changelog).
    @objc func showAboutStatus() {
        if let existing = aboutWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: AboutStatusView(
                appVersion: currentVersion,
                buildNumber: currentBuildNumber,
                statusSummary: buildStatusSummary(),
                onPrintDebug: { [weak self] in self?.printDebugStatus() },
                onOpenTestingGuide: { [weak self] in self?.openTestingDocInFinder() },
                onClose: { [weak self] in
                    UserDefaults.standard.set(self?.currentVersion ?? "", forKey: self?.lastShownChangelogKey ?? "")
                    self?.aboutWindowController?.close()
                    self?.aboutWindowController = nil
                }
            )
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "About Lumina Studio"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setFrameAutosaveName("Lumina.AboutStatus")
        window.center()

        let controller = NSWindowController(window: window)
        aboutWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Checks GitHub for a newer release. When `silent` is true, only prompts if an update exists.
    func checkForUpdates(silent: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            let result = await UpdateChecker.check(currentVersion: currentVersion)
            await MainActor.run {
                switch result {
                case .upToDate:
                    if !silent {
                        let alert = NSAlert()
                        alert.messageText = "You're Up to Date"
                        alert.informativeText = "Lumina \(self.currentVersion) is the latest release on GitHub."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                case .updateAvailable(let info):
                    self.presentUpdateSheet(info)
                case .error(let message):
                    if !silent {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = message
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Open Releases")
                        alert.addButton(withTitle: "Cancel")
                        if alert.runModal() == .alertFirstButtonReturn {
                            UpdateChecker.openReleasesPage()
                        }
                    } else {
                        LuminaLog.app.info("Silent update check failed: \(message)")
                    }
                }
            }
        }
    }

    private func presentUpdateSheet(_ info: UpdateChecker.ReleaseInfo) {
        if let existing = updateWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: UpdateAvailableView(
                currentVersion: currentVersion,
                newVersion: info.version,
                downloadURL: info.downloadURL,
                onInstall: { dmgURL in
                    NSWorkspace.shared.open(dmgURL)
                },
                onLater: { [weak self] in
                    self?.updateWindowController?.close()
                    self?.updateWindowController = nil
                }
            )
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "Update Available"
        window.styleMask = [.titled, .closable]
        window.center()

        let controller = NSWindowController(window: window)
        updateWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func buildStatusSummary() -> String {
        let loaded = currentVideoURL?.lastPathComponent ?? "None"
        let policyStr = describePolicy(powerManager?.currentPolicy ?? .normal)
        let lpm = powerManager?.pauseOnLowPowerMode ?? true
        let thermal = powerManager?.pauseOnHighThermal ?? true
        let fullscreen = powerManager?.respectFullscreenApps ?? true

        return """
        Video loaded: \(loaded)
        Current policy: \(policyStr)

        Power settings:
        • Pause on Low Power Mode: \(lpm ? "ON" : "OFF")
        • Pause on High Thermal: \(thermal ? "ON" : "OFF")
        • Pause on Fullscreen Apps: \(fullscreen ? "ON" : "OFF")

        Displays: \(NSScreen.screens.count) • Renderers: \(renderers.count)
        """
    }

    // MARK: - Version & Changelog

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    private let lastShownChangelogKey = "Lumina.LastShownChangelogVersion"

    /// Opens About & Status once when the app version changes since the user last viewed it.
    func checkForNewVersionAndShowChangelogIfNeeded() {
        let lastShown = UserDefaults.standard.string(forKey: lastShownChangelogKey) ?? "0.0"
        guard UpdateChecker.compareVersions(currentVersion, lastShown) == .orderedDescending else { return }

        LuminaLog.app.info("New version detected: \(currentVersion) (previously saw \(lastShown))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.showAboutStatus()
        }
    }

    // MARK: - Per-Monitor Assignment (Phase 1)
    func assignVideoToMonitor(monitorID: String, url: URL) {
        guard let index = monitorIndex(for: monitorID) else {
            print("Could not find renderer for monitor \(monitorID)")
            return
        }

        // Choose best version for current power state (low-power variant swapping)
        let bestURL = bestURLForCurrentPowerState(originalURL: url)

        // Ensure we have the correct renderer type for this media (video vs image/GIF)
        let renderer = ensureCorrectRenderer(at: index, for: bestURL)
        let isNewMedia = renderer.currentMediaURL?.path != bestURL.path
        renderer.load(url: bestURL, autoPlay: true)

        if isNewMedia {
            renderer.crossfadeToNewContent(duration: 0.35)   // Pleasant, low-cost transition
        }

        // Update legacy global for menu compatibility
        currentVideoURL = url
        currentVideoURLMonitorID = monitorID
        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)

        // Create or update the assignment with correct media type.
        // IMPORTANT: preserve the existing keep-on-startup choice. Brand-new assignments
        // default to false (via MonitorAssignment), but re-applying media to an already-pinned
        // monitor must NOT silently un-pin it — that was causing pinned wallpapers to vanish
        // (come up black) after relaunch.
        var assignment = assignmentStore.assignment(for: monitorID) ?? MonitorAssignment(monitorIdentifier: monitorID)
        assignment.filePath = url.path
        assignment.mediaType = MediaType.from(url: url)
        // One mode per monitor: choosing a single video/image ends any slideshow on this
        // display (and frees its image cycling), so the two modes never run at once.
        assignment.slideshowItems = []
        assignment.lastError = nil   // fresh load; recordLoadFailure will re-set this if it fails
        assignment.updateBookmark(from: url)

        // Re-apply every previously saved setting for this monitor (scaling, speed, mute, crop,
        // opacity, volume, color correction, brightness, loop fade) so changing the media never
        // silently resets the user's adjustments.
        applyAssignmentSettings(assignment, to: renderer)

        assignmentStore.updateAssignment(assignment)

        print("Assigned \(assignment.mediaType) to monitor \(monitorID): \(url.lastPathComponent)")
    }

    // Backward compatible version (used by older call sites during transition)
    func assignVideoToMonitor(index: Int, url: URL) {
        guard index < renderers.count else { return }
        let monitorID = monitorIDForIndex(index)
        assignVideoToMonitor(monitorID: monitorID, url: url)
    }

    private func monitorIndex(for monitorID: String) -> Int? {
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            if MonitorInfo.identifier(for: screen, index: index) == monitorID {
                // NSScreen.screens can briefly disagree with the (debounce-reconciled)
                // renderers array after hot-plug/wake — an unchecked index would crash.
                guard index < renderers.count else {
                    scheduleReconcile()
                    return nil
                }
                return index
            }
        }
        return nil
    }

    private func monitorIDForIndex(_ index: Int) -> String {
        let screens = NSScreen.screens
        guard index < screens.count else { return "unknown-\(index)" }
        return MonitorInfo.identifier(for: screens[index], index: index)
    }

    /// Returns the best URL to play for the current power state.
    /// Supports automatic low-power variant swapping using a simple naming convention:
    ///   myvideo.mov  → myvideo-low.mov or myvideo-battery.mov
    private func bestURLForCurrentPowerState(originalURL: URL) -> URL {
        let fm = FileManager.default
        let powerInfo = ProcessInfo.processInfo

        let shouldUseLowPower = powerInfo.isLowPowerModeEnabled ||
                                powerInfo.thermalState == .serious ||
                                powerInfo.thermalState == .critical

        guard shouldUseLowPower else {
            return originalURL
        }

        let dir = originalURL.deletingLastPathComponent()
        let base = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension

        let lowPowerCandidates = [
            dir.appendingPathComponent("\(base)-low.\(ext)"),
            dir.appendingPathComponent("\(base)-battery.\(ext)"),
            dir.appendingPathComponent("\(base)-lp.\(ext)"),
        ]

        for candidate in lowPowerCandidates {
            if fm.fileExists(atPath: candidate.path) {
                print("[Lumina] Auto-switched to low-power variant: \(candidate.lastPathComponent)")
                return candidate
            }
        }

        return originalURL
    }

    /// For now we are using concrete AVVideoRenderer for the main path to keep things stable for testing.
    /// (Image/Metal dispatch will be re-enabled cleanly after the protocol is fully stabilized.)
    private func ensureCorrectRenderer(at index: Int, for url: URL) -> AVVideoRenderer {
        // Currently always returning/using the video renderer at the index.
        return renderers[index]
    }

    /// Small mapping helper between the persistent model enum and the renderer's enum.
    private func mapModelToRendererScaling(_ modelScaling: VideoScaling) -> AVVideoRenderer.VideoScaling {
        switch modelScaling {
        case .fit:      return .fit
        case .fill:     return .fill
        case .stretch:  return .stretch
        }
    }

    // MARK: - Live Settings Application (from Wallpaper Manager)

    /// Applies a new scaling mode live to the renderer for this monitor and updates the assignment.
    func applyScalingToMonitor(monitorID: String, scaling: VideoScaling) {
        guard let index = monitorIndex(for: monitorID) else {
            print("Could not find renderer for monitor \(monitorID) when applying scaling")
            return
        }

        let internalScaling: AVVideoRenderer.VideoScaling
        switch scaling {
        case .fit: internalScaling = .fit
        case .fill: internalScaling = .fill
        case .stretch: internalScaling = .stretch
        }
        renderers[index].setScaling(internalScaling)

        // Also keep the central assignment in sync (in case the change came from outside the normal panel flow)
        if var assignment = assignmentStore.assignment(for: monitorID) {
            assignment.scaling = scaling
            assignmentStore.updateAssignment(assignment)
        }
    }

    /// Applies a new playback speed live to the renderer for this monitor.
    func applyPlaybackSpeedToMonitor(monitorID: String, speed: Double) {
        guard let index = monitorIndex(for: monitorID) else {
            print("Could not find renderer for monitor \(monitorID) when applying speed")
            return
        }

        renderers[index].setPlaybackSpeed(speed)

        if var assignment = assignmentStore.assignment(for: monitorID) {
            assignment.playbackSpeed = speed
            assignmentStore.updateAssignment(assignment)
        }
    }

    /// Applies loop crossfade settings live to the renderer for this monitor.
    func applyLoopFadeToMonitor(monitorID: String, enabled: Bool, duration: Double,
                                easing: MonitorAssignment.FadeEasing = .easeInOut) {
        guard let index = monitorIndex(for: monitorID) else { return }
        renderers[index].setLoopFade(enabled: enabled, duration: duration, easing: easing)

        if var assignment = assignmentStore.assignment(for: monitorID) {
            assignment.loopFadeEnabled = enabled
            assignment.loopFadeDuration = duration
            assignment.loopFadeEasing = easing
            assignmentStore.updateAssignment(assignment)
        }
    }

    /// Reconfigures the looping strategy (loop / once / bounce) on the running renderer.
    func applyLoopModeToMonitor(monitorID: String, mode: MonitorAssignment.LoopMode) {
        guard let index = monitorIndex(for: monitorID), index < renderers.count else {
            print("Could not find renderer for monitor \(monitorID) when applying loop mode")
            return
        }
        renderers[index].setLoopMode(mode)
    }

    /// Applies a brightness adjustment live to the renderer for this monitor.
    func applyBrightnessToMonitor(monitorID: String, brightness: Double) {
        guard let index = monitorIndex(for: monitorID) else { return }
        renderers[index].setBrightness(brightness)

        if var assignment = assignmentStore.assignment(for: monitorID) {
            assignment.brightness = brightness
            assignmentStore.updateAssignment(assignment)
        }
    }

    /// Applies a live opacity adjustment to the renderer for this monitor.
    func applyOpacityToMonitor(monitorID: String, opacity: Double) {
        guard let index = monitorIndex(for: monitorID) else { return }
        renderers[index].setOpacity(opacity)

        if var assignment = assignmentStore.assignment(for: monitorID) {
            assignment.opacity = opacity
            assignmentStore.updateAssignment(assignment)
        }
    }

    /// Applies color correction settings live to the renderer for this monitor.
    func applyColorCorrectionToMonitor(monitorID: String, saturation: Double, hue: Double, grayscale: Bool) {
        guard let index = monitorIndex(for: monitorID) else { return }
        renderers[index].setColorCorrection(saturation: saturation, hue: hue, grayscale: grayscale)

        if var assignment = assignmentStore.assignment(for: monitorID) {
            assignment.saturation = saturation
            assignment.hue = hue
            assignment.grayscale = grayscale
            assignmentStore.updateAssignment(assignment)
        }
    }

    /// Applies a volume level live to the renderer for this monitor.
    func applyVolumeToMonitor(monitorID: String, volume: Double) {
        guard let index = monitorIndex(for: monitorID) else { return }
        renderers[index].setVolume(volume)

        if var assignment = assignmentStore.assignment(for: monitorID) {
            assignment.audioVolume = volume
            assignmentStore.updateAssignment(assignment)
        }
    }

    /// Live Ken Burns toggle — updates the running slideshow without restarting from slide 0.
    func applySlideshowKenBurnsToMonitor(monitorID: String, enabled: Bool) {
        guard let index = monitorIndex(for: monitorID), index < renderers.count else { return }
        renderers[index].setSlideshowKenBurnsEnabled(enabled)
    }

    /// Starts/updates (or stops) an image slideshow on a monitor based on its assignment's
    /// slideshow fields. Called whenever the user edits the slideshow in the manager.
    func applySlideshowToMonitor(monitorID: String) {
        guard let index = monitorIndex(for: monitorID), index < renderers.count,
              let assignment = assignmentStore.assignment(for: monitorID) else { return }

        // Keep only images that still exist on disk.
        let items = assignment.slideshowItems.filter {
            FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath)
        }

        if items.isEmpty {
            // No slideshow — revert to single media if one is set, otherwise go black.
            renderers[index].clear()
            if assignment.filePath != nil {
                restoreAssignment(forScreenAt: index, requireKeepOnStartup: false)
            }
            return
        }

        renderers[index].loadSlideshow(items: items,
                                       interval: assignment.slideshowInterval,
                                       transition: assignment.slideshowTransition,
                                       kenBurnsEnabled: assignment.slideshowKenBurnsEnabled)
        currentVideoURL = URL(fileURLWithPath: (items[0] as NSString).expandingTildeInPath)
        currentVideoURLMonitorID = monitorID
        updateCurrentWallpaperDisplay()
    }

    /// Applies a live crop rectangle to the renderer for this monitor.
    func applyCropRectToMonitor(monitorID: String, cropRect: CGRect) {
        guard let index = monitorIndex(for: monitorID) else {
            print("Could not find renderer for monitor \(monitorID) when applying crop")
            return
        }
        renderers[index].applyCropRect(cropRect)

        if var assignment = assignmentStore.assignment(for: monitorID) {
            assignment.cropRect = cropRect
            assignmentStore.updateAssignment(assignment)
        }
    }

    private func loadVideo(url: URL) {
        currentVideoURL = url
        for renderer in renderers {
            renderer.load(url: url, autoPlay: true)
        }

        // Persist so it comes back after restart / login
        WallpaperPersistence.saveLastVideo(url)

        // Update tooltip with the loaded file
        let filename = url.lastPathComponent
        statusItem.button?.toolTip = "Lumina – \(filename)"

        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)

        LuminaLog.wallpaper.info("Loaded wallpaper video: \(url.path)")
    }

    // MARK: - Status Item & Menu (enhanced for B: UX + C: debug)

    /// The LS menu-bar icon, rendered once from the cursive monogram path.
    /// Programmatic rendering avoids brittle bundle path lookups in the packaged .app.
    private lazy var statusBarIcon: NSImage = LuminaMenuIcon.make()

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = statusBarIcon
            button.title = ""
        }
        
        updateStatusItem(for: .normal)

        // Minimal menu bar: open the app, or quit. Everything else (power toggles,
        // performance profile, about/welcome/what's new) now lives in Settings inside
        // Lumina Studio, so we don't duplicate it here.
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Lumina Studio", action: #selector(openWallpaperManager), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Lumina", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func updateStatusItem(for policy: WallpaperPlaybackPolicy) {
        let button = statusItem.button
        let hasVideo = currentVideoURL != nil

        button?.image = statusBarIcon   // cached — no disk I/O on policy changes
        button?.title = ""  // Critical: prevent any residual title text from causing alignment shift

        // All dynamic state now lives in the tooltip (hover) and the top menu item ("Wallpaper: ...").
        // This produces a clean, correctly aligned, native-looking menu bar icon at all times.
        let filename = currentVideoURL?.lastPathComponent ?? "none"
        switch policy {
        case .normal:
            let tip = hasVideo ? "Lumina – \(filename) (playing)" : "Lumina – ready (no wallpaper loaded)"
            button?.toolTip = tip
        case .throttled:
            let tip = hasVideo ? "Lumina – Throttled (\(filename))" : "Lumina – Throttled (no wallpaper)"
            button?.toolTip = tip
        case .paused(let reason):
            let tip = hasVideo ? "Lumina – Paused (\(reason.rawValue)) – \(filename)" : "Lumina – Paused (\(reason.rawValue))"
            button?.toolTip = tip
        }
    }

    /// Updates the disabled "current wallpaper" menu row and related UI.
    private func updateCurrentWallpaperDisplay() {
        guard let item = currentWallpaperMenuItem else { return }
        if let url = currentVideoURL {
            item.title = "Wallpaper: \(url.lastPathComponent)"
        } else {
            item.title = "No video loaded — use 'Load Video…' below"
        }
    }

    private func describePolicy(_ policy: WallpaperPlaybackPolicy) -> String {
        switch policy {
        case .normal: return "Normal (full speed)"
        case .throttled(let fps): return "Throttled (~\(fps) fps effective)"
        case .paused(let reason): return "Paused (\(reason.rawValue))"
        }
    }

    @objc private func togglePause() {
        guard let pm = powerManager else { return }

        if case .paused = pm.currentPolicy {
            pm.resumeManually()
        } else {
            pm.pauseManually()
        }
    }

    @objc private func reloadLastVideo() {
        guard let url = WallpaperPersistence.restoreLastVideo() else {
            print("No saved wallpaper to reload.")
            return
        }
        currentVideoURL = url
        print("Reloading saved wallpaper: \(url.path)")
        for renderer in renderers {
            renderer.load(url: url, autoPlay: true)
        }
        statusItem.button?.toolTip = "Lumina – \(url.lastPathComponent)"
        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)
    }

    @objc private func clearSavedWallpaper() {
        WallpaperPersistence.clearLastVideo()
        print("Cleared saved wallpaper. It will no longer auto-load on next launch.")
        // Optionally pause current playback
        for renderer in renderers {
            renderer.pause()
        }
        currentVideoURL = nil
        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)
        statusItem.button?.toolTip = "Lumina – Low-power wallpapers"
    }

    /// B: Stop playback immediately but leave the saved wallpaper in persistence (user can "Reload Last Video" later).
    @objc private func clearCurrentWallpaper() {
        for renderer in renderers {
            renderer.pause()
        }
        currentVideoURL = nil
        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)
        statusItem.button?.toolTip = "Lumina – ready (no wallpaper)"
        print("Current wallpaper cleared from playback (persisted bookmark preserved). Use Reload Last Video to restore.")
    }

    @objc private func quit() {
        // Ask AppKit to terminate; applicationWillTerminate performs the actual teardown so
        // the same cleanup runs for menu Quit, ⌘Q, logout, and system shutdown alike.
        NSApplication.shared.terminate(nil)
    }

    // MARK: - About / Status + Debug

    @objc private func printDebugStatus() {
        print("═══════════════════════════════════════")
        print("LUMINA DEBUG STATUS @ \(Date())")
        print("Video loaded: \(currentVideoURL?.path ?? "None")")
        if let pm = powerManager {
            print("Policy: \(pm.currentPolicy)")
            print("  pauseOnLPM: \(pm.pauseOnLowPowerMode)")
            print("  pauseOnHighThermal: \(pm.pauseOnHighThermal)")
            print("  throttleOnMediumThermal: \(pm.throttleOnMediumThermal)")
            print("  respectFullscreen: \(pm.respectFullscreenApps)")
        }
        let screens = NSScreen.screens
        print("Displays: \(screens.count) | Windows: \(wallpaperWindows.count) | Renderers: \(renderers.count)")
        print("Occluded display IDs (paused): \(occludedDisplayIDs.sorted())")
        print("Respect fullscreen apps: \(powerManager?.respectFullscreenApps ?? true)")
        for (i, r) in renderers.enumerated() {
            let displayID = i < screenDisplayIDs.count ? screenDisplayIDs[i] : 0
            let name = i < screens.count ? screens[i].localizedName : "?"
            let occluded = occludedDisplayIDs.contains(displayID) ? "OCCLUDED→paused" : "visible"
            let visible = i < wallpaperWindows.count ? wallpaperWindows[i].occlusionState.contains(.visible) : false
            print("  [\(i)] \(name) (id \(displayID)) [\(occluded), window.visible=\(visible)]")
            print("        → \(r.statusSummary)")
        }
        print("═══════════════════════════════════════")
    }

    private func openTestingDocInFinder() {
        let docsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/PROTOTYPE_TESTING.md")
        // Fallback to workspace root if needed
        let fm = FileManager.default
        if fm.fileExists(atPath: docsURL.path) {
            NSWorkspace.shared.selectFile(docsURL.path, inFileViewerRootedAtPath: docsURL.deletingLastPathComponent().path)
        } else {
            // Open the project folder
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            NSWorkspace.shared.open(root)
            print("Note: docs/PROTOTYPE_TESTING.md may need to be created/visible after first build.")
        }
    }



}
