// Lumina
// FullscreenDetector
//
// Uses CGWindowList to detect when a fullscreen or near-fullscreen app is active
// on any screen. When detected, it tells PowerManager to pause the wallpapers.
//
// This is one of the most important features for "does not affect my other tasks":
// - Gaming in fullscreen
// - Watching YouTube / video in full screen
// - Coding in full-screen Xcode / Terminal
// - Zoom / presentation mode
//
// Gracefully handles the case where CGWindowList requires Screen Recording permission.

import AppKit

@MainActor
public final class FullscreenDetector {

    private weak var powerManager: PowerManager?
    private var timer: Timer?
    private var isCurrentlyObscured: Bool = false

    /// How often we do a full window list scan (seconds).
    /// We also react to app activation, so we can keep this relatively infrequent.
    private let scanInterval: TimeInterval = 2.5

    public init(powerManager: PowerManager) {
        self.powerManager = powerManager
        startMonitoring()
    }

    // Note: In a long-lived app we rely on explicit stop or app termination.
    // Deinit cleanup is intentionally light to satisfy strict concurrency in the prototype.

    // MARK: - Public API

    /// Manually trigger a check (useful after waking from sleep, display changes, etc.)
    public func checkNow() {
        performFullscreenCheck()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Periodic scan using a main-actor safe timer
        timer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performFullscreenCheck()
            }
        }

        // React quickly when the user switches apps or goes fullscreen
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(applicationDidActivate),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // When displays change or we wake up
        nc.addObserver(self, selector: #selector(screensDidChange),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        // Small delay so the fullscreen transition can complete
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.performFullscreenCheck()
        }
    }

    @objc private func screensDidChange() {
        performFullscreenCheck()
    }

    // MARK: - Core Detection Logic

    private func performFullscreenCheck() {
        // TEMPORARILY DISABLED for development (see todo list)
        // We want the wallpaper to keep running even when fullscreen apps are detected.
        // This will be re-enabled once we have proper per-monitor pause configuration.
        return

        // --- Original logic (kept for later) ---
        /*
        let obscured = isAnyScreenObscuredByFullscreenWindow()

        guard obscured != isCurrentlyObscured else { return }
        isCurrentlyObscured = obscured

        powerManager?.updateFullscreenObscured(obscured)
        */
    }

    private func isAnyScreenObscuredByFullscreenWindow() -> Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            // Permission issue or error — fail open (don't pause) to avoid annoying the user
            return false
        }

        let screens = NSScreen.screens

        for windowInfo in windowInfoList {
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? Int else {
                continue
            }

            // We only care about normal application windows that can be fullscreen
            // (layer 0 is normal windows, negative layers are desktop / system UI)
            guard windowLayer >= 0 else { continue }

            let windowFrame = NSRect(x: boundsDict["X"] ?? 0,
                                     y: boundsDict["Y"] ?? 0,
                                     width: boundsDict["Width"] ?? 0,
                                     height: boundsDict["Height"] ?? 0)

            // Check against each screen
            for screen in screens {
                let screenFrame = screen.frame

                // Heuristic: window covers most or all of the screen
                // (allows small tolerance for menu bar, notch, etc.)
                if windowFrame.contains(screenFrame.insetBy(dx: 8, dy: 8)) ||
                   windowFrame.intersects(screenFrame) && windowFrame.size.height >= screenFrame.height * 0.92 {
                    // Additional check: make sure it's not our own windows or Finder desktop
                    if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                       ownerName.contains("Finder") || ownerName.contains("Lumina") {
                        continue
                    }
                    return true
                }
            }
        }

        return false
    }
}
