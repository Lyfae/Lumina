// Lumina
// DesktopWallpaperWindow
//
// The actual "wallpaper" surface: a borderless, non-activating, stationary NSWindow
// positioned at the desktop window level so it sits behind all normal windows and (ideally)
// behind desktop icons.
//
// Key requirements for a great experience:
// - One window per physical display (NSScreen)
// - Survives display reconfiguration, sleep/wake, spaces changes
// - Never becomes key, never activates the app
// - Ignores mouse events (the desktop should remain clickable)
// - Correct collectionBehavior so it appears on all spaces and doesn't participate in Mission Control / Exposé in annoying ways
//
// Heavily informed by public implementations (LiveDesk, Wallspace writeups) and real-world testing.

import AppKit

public final class DesktopWallpaperWindow: NSWindow {

    // MARK: - Init

    public init(screen: NSScreen, contentView: NSView? = nil) {
        let rect = screen.frame

        // Call the *designated* 4-argument initializer (the only one marked designated).
        // Then we size/position the window to the exact screen frame we want.
        // This pattern is used successfully by multiple open-source live wallpaper projects.
        super.init(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Ensure the window is exactly the size and position of the target physical display
        self.setFrame(rect, display: true)

        self.isReleasedWhenClosed = false
        self.backgroundColor = .black   // Safe default; renderers can override with transparent layers
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.canHide = false
        self.acceptsMouseMovedEvents = false

        // === The magic configuration ===
        let desktopLevel = CGWindowLevelForKey(.desktopWindow)
        self.level = NSWindow.Level(rawValue: Int(desktopLevel))

        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,        // Do not move with the active space in unexpected ways
            .ignoresCycle       // Not in window cycle (Cmd+`)
        ]

        // Hosting view for the actual wallpaper content (AVPlayerLayer, CALayer, SpriteKit, WKWebView, etc.)
        if let contentView {
            self.contentView = contentView
        } else {
            // Provide a minimal layer-backed view that subclasses can replace or add sublayers to
            let hosting = NSView(frame: rect)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.black.cgColor
            self.contentView = hosting
        }

        // Make sure it is visible on the correct screen
        self.setFrame(rect, display: true)
    }

    // MARK: - Behavior overrides

    /// Never let this window become the key window (prevents app activation and focus stealing)
    public override var canBecomeKey: Bool { false }

    public override var canBecomeMain: Bool { false }

    // Prevent accidental activation when clicking "through" (even though mouse events are ignored)
    public override func mouseDown(with event: NSEvent) {
        // Intentionally empty — we ignore everything
    }

    // MARK: - Lifecycle helpers

    /// Show the window (usually called after creation or after the system reconfigures displays).
    public func showOnDesktop() {
        self.orderFrontRegardless()
        // Some configurations also benefit from:
        // self.orderBack(nil)
    }

    /// Cleanly close and release the window (used on display removal or app termination).
    public func hideAndRelease() {
        self.orderOut(nil)
        self.contentView = nil
    }
}

// MARK: - Multi-monitor convenience

public extension DesktopWallpaperWindow {

    /// Factory that creates one properly configured wallpaper window for every current screen.
    static func createForAllScreens(contentViewProvider: (NSScreen) -> NSView? = { _ in nil }) -> [DesktopWallpaperWindow] {
        NSScreen.screens.map { screen in
            let win = DesktopWallpaperWindow(
                screen: screen,
                contentView: contentViewProvider(screen)
            )
            win.showOnDesktop()
            return win
        }
    }
}
