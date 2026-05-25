// Lumina
// Native, battery-friendly live wallpaper engine for macOS (Tahoe+ target)
//
// Entry point: menu-bar-only accessory application.
// We deliberately avoid a Dock icon and any foreground windows by default.

import AppKit

@main
@MainActor
final class LuminaApp: NSObject, NSApplicationDelegate {
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
        print("Lumina started as menu-bar accessory (no Dock icon).")
        // TODO (next steps): Initialize PowerManager, DesktopWallpaperWindow, etc.
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🌊"   // Placeholder icon (will be proper asset later)
        statusItem.button?.toolTip = "Lumina – Low-power wallpapers"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Open Library…", action: #selector(openLibrary), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Lumina", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func togglePause() {
        print("TODO: Toggle pause via PowerManager")
    }

    @objc private func openLibrary() {
        print("TODO: Show library window / popover")
    }

    @objc private func openSettings() {
        print("TODO: Show SwiftUI Settings scene")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
