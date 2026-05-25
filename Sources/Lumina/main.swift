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

import AppKit
import AVFoundation

@main
@MainActor
final class LuminaApp: NSObject, NSApplicationDelegate {

    // MARK: - Core Engine (Prototype)
    private var powerManager: PowerManager!
    private var fullscreenDetector: FullscreenDetector!
    private var wallpaperWindows: [DesktopWallpaperWindow] = []
    private var renderers: [AVVideoRenderer] = []

    // MARK: - UI
    private var statusItem: NSStatusItem!

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

        print("Lumina prototype started (menu-bar only). Use the 🌊 icon → Load Video…")
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

        // === Basic Persistence (Step A) ===
        // Try to restore the user's last chosen video automatically
        if let lastURL = WallpaperPersistence.restoreLastVideo() {
            print("Restoring last wallpaper: \(lastURL.path)")
            for renderer in renderers {
                renderer.load(url: lastURL, autoPlay: true)
            }
            let filename = lastURL.lastPathComponent
            statusItem.button?.toolTip = "Lumina – \(filename)"

            // Re-apply current power policy (in case Low Power Mode was already on)
            applyPolicyToRenderers(powerManager.currentPolicy)
        }
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

    private func loadVideo(url: URL) {
        for renderer in renderers {
            renderer.load(url: url, autoPlay: true)
        }

        // Persist so it comes back after restart / login
        WallpaperPersistence.saveLastVideo(url)

        // Update tooltip with the loaded file
        let filename = url.lastPathComponent
        statusItem.button?.toolTip = "Lumina – \(filename)"

        print("Loaded wallpaper video: \(url.path)")
    }

    // MARK: - Status Item & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItem(for: .normal)

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Load Video…", action: #selector(showLoadVideoPanel), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Reload Last Video", action: #selector(reloadLastVideo), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Clear Saved Wallpaper", action: #selector(clearSavedWallpaper), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit Lumina", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func updateStatusItem(for policy: WallpaperPlaybackPolicy) {
        let button = statusItem.button

        switch policy {
        case .normal:
            button?.title = "🌊"
            button?.toolTip = button?.toolTip ?? "Lumina – Low-power wallpapers (playing)"
        case .throttled:
            button?.title = "🌊⏱"
            button?.toolTip = "Lumina – Throttled for thermals / power"
        case .paused(let reason):
            button?.title = "🌊⏸"
            button?.toolTip = "Lumina – Paused (\(reason.rawValue))"
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
        print("Reloading saved wallpaper: \(url.path)")
        for renderer in renderers {
            renderer.load(url: url, autoPlay: true)
        }
        statusItem.button?.toolTip = "Lumina – \(url.lastPathComponent)"
    }

    @objc private func clearSavedWallpaper() {
        WallpaperPersistence.clearLastVideo()
        print("Cleared saved wallpaper. It will no longer auto-load on next launch.")
        // Optionally pause current playback
        for renderer in renderers {
            renderer.pause()
        }
        statusItem.button?.toolTip = "Lumina – Low-power wallpapers"
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
}
