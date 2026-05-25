// Lumina
// Native, battery-friendly live wallpaper engine for macOS (Tahoe+ target)
//
// Entry point: menu-bar-only accessory application.
// We deliberately avoid a Dock icon and any foreground windows by default.
//
// PROTOTYPE STATUS: Working video wallpaper engine with PowerManager integration.
// Use the menu bar icon → "Load Video..." to select any .mp4/.mov file.
// The video will appear as a live wallpaper behind all windows on every display.
// It automatically pauses on Low Power Mode, high thermal load, etc.
//
// Icon: Uses a proper NSImage (SF Symbol "water.waves" + fallback) for correct vertical
// alignment instead of emoji titles (fixes shift-up bug on Tahoe and other macOS releases).

import AppKit
import AVFoundation

@main
@MainActor
final class LuminaApp: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Core Engine
    private var powerManager: PowerManager!
    private var fullscreenDetector: FullscreenDetector!
    private var wallpaperWindows: [DesktopWallpaperWindow] = []
    private var renderers: [AVVideoRenderer] = []
    
    // New per-monitor state management (Phase 1+)
    let assignmentStore = AssignmentStore()   // Made internal so WallpaperManagerStore can access it

    // MARK: - UX / State (prototype enhancements for B + C)
    private var currentVideoURL: URL?
    private var currentWallpaperMenuItem: NSMenuItem!
    private var lpmToggleMenuItem: NSMenuItem!
    private var thermalToggleMenuItem: NSMenuItem!

    // MARK: - UI
    private var statusItem: NSStatusItem!
    private var wallpaperManagerWindow: WallpaperManagerWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = LuminaApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // Critical: no Dock icon, menu-bar only
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPowerManager()
        setupWallpaperWindowsAndRenderers()

        // Extra triggers for fullscreen detection
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(wakeFromSleep), name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        print("Lumina prototype started (menu-bar only). Use the menu bar icon (Lumina wave) → Load Video…")
    }

    @objc private func wakeFromSleep() {
        fullscreenDetector?.checkNow()
    }

    @objc private func screensChanged() {
        fullscreenDetector?.checkNow()
    }

    // MARK: - Engine Setup

    private func setupPowerManager() {
        powerManager = PowerManager()

        // Wire policy changes → renderers + UI
        powerManager.onPolicyChange = { [weak self] policy in
            self?.applyPolicyToRenderers(policy)
            self?.updateStatusItem(for: policy)
        }

        // Fullscreen / obscured detection (critical for not interfering with user work)
        fullscreenDetector = FullscreenDetector(powerManager: powerManager)
    }

    private func setupWallpaperWindowsAndRenderers() {
        // Create one desktop-level window per screen
        wallpaperWindows = DesktopWallpaperWindow.createForAllScreens()

        // Create a renderer for each window and install it
        renderers = wallpaperWindows.map { window in
            let renderer = AVVideoRenderer()
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                renderer.install(into: contentView)
            }
            return renderer
        }

        // Initial policy application
        applyPolicyToRenderers(powerManager.currentPolicy)

        // === Phase 1: Per-Monitor Restoration from AssignmentStore ===
        let screens = NSScreen.screens
        var restoredCount = 0

        for (index, screen) in screens.enumerated() {
            guard index < renderers.count else { break }

            let monitorID = MonitorInfo.identifier(for: screen, index: index)

            if let assignment = assignmentStore.assignment(for: monitorID),
               assignment.keepOnStartup,
               let path = assignment.filePath {
                
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                
                if FileManager.default.fileExists(atPath: url.path) {
                    renderers[index].load(url: url, autoPlay: true)
                    
                    // Apply scaling if stored (map between the two VideoScaling types)
                    let rendererScaling: AVVideoRenderer.VideoScaling
                    switch assignment.scaling {
                    case .fit:      rendererScaling = .fit
                    case .fill:     rendererScaling = .fill
                    case .stretch:  rendererScaling = .stretch
                    }
                    renderers[index].setScaling(rendererScaling)
                    
                    restoredCount += 1
                    print("Restored \(monitorID) → \(url.lastPathComponent)")
                } else {
                    print("File missing for \(monitorID): \(path)")
                    // Optional: Clear the bad assignment
                    // assignmentStore.removeAssignment(for: monitorID)
                }
            }
        }

        if restoredCount > 0 {
            print("Restored \(restoredCount) per-monitor assignment(s).")
        } else {
            // Fallback to old global persistence (temporary during transition)
            if let lastURL = WallpaperPersistence.restoreLastVideo() {
                print("Using global fallback: \(lastURL.lastPathComponent)")
                currentVideoURL = lastURL
                for renderer in renderers {
                    renderer.load(url: lastURL, autoPlay: true)
                }
            } else {
                print("No wallpaper assignments found. Use the Wallpaper Manager (⌘M).")
            }
        }

        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)
    }

    private func applyPolicyToRenderers(_ policy: WallpaperPlaybackPolicy) {
        for renderer in renderers {
            renderer.applyPolicy(policy)
        }
    }

    // MARK: - Video Loading (Prototype)

    @objc private func showLoadVideoPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a video for your wallpaper"
        panel.message = "Lumina works best with smooth, looping 1080p or 4K videos (H.264/H.265). Muted audio is recommended."
        panel.allowedContentTypes = [.movie]          // .mp4, .mov, .m4v etc.
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
    }

    // MARK: - Per-Monitor Assignment (Phase 1)
    func assignVideoToMonitor(monitorID: String, url: URL) {
        guard let index = monitorIndex(for: monitorID) else {
            print("Could not find renderer for monitor \(monitorID)")
            return
        }

        let renderer = renderers[index]
        renderer.load(url: url, autoPlay: true)

        // Update legacy global for menu compatibility
        currentVideoURL = url
        updateCurrentWallpaperDisplay()
        updateStatusItem(for: powerManager.currentPolicy)

        // Also save to the AssignmentStore so the manager can see it and it persists
        var assignment = MonitorAssignment(monitorIdentifier: monitorID)
        assignment.filePath = url.path
        assignment.keepOnStartup = true   // Default to keeping it on startup when assigned from manager
        assignment.mediaType = .video
        assignment.updateBookmark(from: url)
        
        assignmentStore.updateAssignment(assignment)

        print("Assigned video to monitor \(monitorID): \(url.lastPathComponent)")
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

        print("Loaded wallpaper video: \(url.path)")
    }

    // MARK: - Status Item & Menu (enhanced for B: UX + C: debug)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItem(for: .normal)

        let menu = NSMenu()
        menu.delegate = self   // For dynamic title updates on open (lightweight)

        // Prominent current wallpaper status (disabled item, updated live)
        let currentItem = NSMenuItem(title: "No video loaded — use Load Video…", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        self.currentWallpaperMenuItem = currentItem

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Load Video…", action: #selector(showLoadVideoPanel), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Clear Current Wallpaper", action: #selector(clearCurrentWallpaper), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())

        // Main management UI
        menu.addItem(NSMenuItem(title: "Wallpaper Manager…", action: #selector(openWallpaperManager), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Reload Last Video", action: #selector(reloadLastVideo), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Clear Saved Wallpaper", action: #selector(clearSavedWallpaper), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Simple power toggles (live state updated via delegate)
        let lpmItem = NSMenuItem(title: "Pause on Low Power Mode", action: #selector(togglePauseOnLPM), keyEquivalent: "")
        self.lpmToggleMenuItem = lpmItem
        menu.addItem(lpmItem)

        let thermalItem = NSMenuItem(title: "Pause on High Thermal", action: #selector(togglePauseOnThermal), keyEquivalent: "")
        self.thermalToggleMenuItem = thermalItem
        menu.addItem(thermalItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "About / Status…", action: #selector(showAboutStatus), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Debug: Print Status to Console", action: #selector(printDebugStatus), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit Lumina", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    /// Returns a properly aligned, template NSImage for the menu bar status item.
    /// Using an image (SF Symbol when available, with drawing fallback) fixes the
    /// vertical "shifted up" misalignment that occurs when using emoji strings in
    /// statusItem.button?.title (a long-standing AppKit quirk on multiple macOS releases
    /// including Tahoe). The image is square-friendly for NSStatusItem.squareLength.
    private func makeLuminaStatusImage() -> NSImage {
        // Preferred: SF Symbol (thematic "water wave" for Lumina; auto-tinted for light/dark menu bar)
        if let symbol = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "Lumina") {
            symbol.isTemplate = true
            return symbol
        }

        // Fallback: simple, reliable, template-compatible drawn icon (no external assets needed)
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        // Draw a filled circle (monochrome; system tints when .isTemplate)
        NSColor.black.set()
        let inset = NSRect(x: 1, y: 1, width: 14, height: 14)
        NSBezierPath(ovalIn: inset).fill()
        // Minimal wave accent line (still tinted correctly)
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: 4, y: 8))
        wave.curve(to: NSPoint(x: 8, y: 5), controlPoint1: NSPoint(x: 5, y: 9), controlPoint2: NSPoint(x: 6, y: 4))
        wave.curve(to: NSPoint(x: 12, y: 8), controlPoint1: NSPoint(x: 10, y: 6), controlPoint2: NSPoint(x: 11, y: 9))
        NSColor.white.set()
        wave.lineWidth = 1.2
        wave.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func updateStatusItem(for policy: WallpaperPlaybackPolicy) {
        let button = statusItem.button
        let hasVideo = currentVideoURL != nil

        // Set (or ensure) the proper NSImage icon. Never use .title with emoji for the glyph.
        if button?.image == nil {
            button?.image = makeLuminaStatusImage()
        }
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
        // Clean shutdown
        for renderer in renderers {
            renderer.cleanup()
        }
        for window in wallpaperWindows {
            window.hideAndRelease()
        }
        // FullscreenDetector will be deallocated; it stops its own timer
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuDelegate (for live-updating dynamic menu items like toggles + current name)

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Update toggle checkmarks from live PowerManager state
        lpmToggleMenuItem?.state = (powerManager?.pauseOnLowPowerMode ?? true) ? .on : .off
        thermalToggleMenuItem?.state = (powerManager?.pauseOnHighThermal ?? true) ? .on : .off

        // Ensure current wallpaper display is fresh (in case of external changes)
        updateCurrentWallpaperDisplay()
    }

    // MARK: - Simple Settings Toggles (B: minimal power preferences exposed in menu)

    @objc private func togglePauseOnLPM() {
        guard let pm = powerManager else { return }
        pm.pauseOnLowPowerMode.toggle()
        print("[Settings] Pause on Low Power Mode = \(pm.pauseOnLowPowerMode)")
        pm.recomputePolicy()
    }

    @objc private func togglePauseOnThermal() {
        guard let pm = powerManager else { return }
        pm.pauseOnHighThermal.toggle()
        print("[Settings] Pause on High Thermal = \(pm.pauseOnHighThermal)")
        pm.recomputePolicy()
    }

    // MARK: - About / Status (B) + Debug (C)

    @objc private func showAboutStatus() {
        let loaded = currentVideoURL?.lastPathComponent ?? "None"
        let policyStr = describePolicy(powerManager?.currentPolicy ?? .normal)
        let lpm = powerManager?.pauseOnLowPowerMode ?? true
        let thermal = powerManager?.pauseOnHighThermal ?? true

        let info = """
        Lumina Prototype — Native Low-Power Live Wallpaper

        Video loaded: \(loaded)
        Current policy: \(policyStr)

        Power settings:
        • Pause on Low Power Mode: \(lpm ? "ON" : "OFF")
        • Pause on High Thermal: \(thermal ? "ON" : "OFF")

        Quick instructions:
        • Load Video… (⌘O) to pick any MP4/MOV.
        • Wallpapers run at desktop level behind icons.
        • Auto-pauses intelligently on Low Power Mode, fullscreen apps, thermals.
        • Use menu for manual Pause/Resume, Clear, Reload.

        For hardware testing & Instruments guide see docs/PROTOTYPE_TESTING.md

        This is early prototype software. Feedback welcome!
        """

        let alert = NSAlert()
        alert.messageText = "Lumina — About / Status"
        alert.informativeText = info
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Print Full Debug")
        alert.addButton(withTitle: "Open Testing Guide (in Finder)")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            printDebugStatus()
        } else if response == .alertThirdButtonReturn {
            openTestingDocInFinder()
        }
    }

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
        print("Renderers: \(renderers.count)")
        for (i, r) in renderers.enumerated() {
            let url = r.loadedURL?.lastPathComponent ?? "nil"
            print("  [\(i)] loaded=\(url) rate=\(r.currentPlaybackRate)")
        }
        print("Windows: \(wallpaperWindows.count)")
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
