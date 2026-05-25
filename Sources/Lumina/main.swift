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

        print("Lumina prototype started (menu-bar only). Use the 🌊 icon → Load Video…")
    }

    // MARK: - Engine Setup

    private func setupPowerManager() {
        powerManager = PowerManager()

        // Wire policy changes → renderers + UI
        powerManager.onPolicyChange = { [weak self] policy in
            self?.applyPolicyToRenderers(policy)
            self?.updateStatusItem(for: policy)
        }
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

        menu.addItem(NSMenuItem(title: "Reload Current Video", action: #selector(reloadCurrentVideo), keyEquivalent: "r"))
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

    @objc private func reloadCurrentVideo() {
        // For prototype we just re-apply the last policy to current renderers.
        // A full implementation would remember the last URL per renderer.
        print("Reload not fully implemented in prototype – use Load Video… again.")
    }

    @objc private func quit() {
        // Clean shutdown
        for renderer in renderers {
            renderer.cleanup()
        }
        for window in wallpaperWindows {
            window.hideAndRelease()
        }
        NSApplication.shared.terminate(nil)
    }
}
