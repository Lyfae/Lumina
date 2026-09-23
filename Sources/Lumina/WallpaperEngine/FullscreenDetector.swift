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
    // nonisolated(unsafe): only ever touched on the main actor while alive; read once
    // from the (nonisolated) deinit, which is race-free for this access pattern.
    nonisolated(unsafe) private var timer: Timer?
    // Workspace / distributed observer tokens — removed from the centers that added them.
    nonisolated(unsafe) private var workspaceObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var distributedObservers: [NSObjectProtocol] = []
    private var isCurrentlyObscured: Bool = false
    // Independent flags so unlock-while-asleep (etc.) does not resume scanning early.
    private var screensAsleep = false
    private var sessionInactive = false
    private var screenLocked = false
    /// After sleep/lock we force one notify so a still-fullscreen desktop re-pauses
    /// (isCurrentlyObscured may be unchanged while policy was overwritten by displayInactive).
    private var forceNextNotify = false

    private var isScreenInactive: Bool { screensAsleep || sessionInactive || screenLocked }

    /// How often we do a full window list scan (seconds).
    /// App-activation triggers an immediate rescan, so the poll can stay infrequent.
    private let scanInterval: TimeInterval = 4.0

    public init(powerManager: PowerManager) {
        self.powerManager = powerManager
        startMonitoring()
    }

    deinit {
        // Timer and NotificationCenter observers strongly reference self / keep firing;
        // without cleanup a deallocated detector would leave a leaked timer behind.
        timer?.invalidate()
        let wsnc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { wsnc.removeObserver($0) }
        let dnc = DistributedNotificationCenter.default()
        distributedObservers.forEach { dnc.removeObserver($0) }
        NotificationCenter.default.removeObserver(self)
    }

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

        // Workspace notifications only arrive on NSWorkspace's own center.
        let wsnc = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(wsnc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationDidActivate() }
        })
        workspaceObservers.append(wsnc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = true
                self?.forceNextNotify = true
            }
        })
        workspaceObservers.append(wsnc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = false
                self?.performFullscreenCheck()
            }
        })
        workspaceObservers.append(wsnc.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionInactive = true
                self?.forceNextNotify = true
            }
        })
        workspaceObservers.append(wsnc.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionInactive = false
                self?.performFullscreenCheck()
            }
        })

        let dnc = DistributedNotificationCenter.default()
        distributedObservers.append(dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenLocked = true
                self?.forceNextNotify = true
            }
        })
        distributedObservers.append(dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenLocked = false
                self?.performFullscreenCheck()
            }
        })

        // When displays change (default center — NSApplication notification).
        NotificationCenter.default.addObserver(self, selector: #selector(screensDidChange),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        let wsnc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { wsnc.removeObserver($0) }
        workspaceObservers.removeAll()
        let dnc = DistributedNotificationCenter.default()
        distributedObservers.forEach { dnc.removeObserver($0) }
        distributedObservers.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    private func applicationDidActivate() {
        // Immediate rescan so the slower periodic poll does not delay fullscreen detection.
        // A short follow-up catches transitions that complete after activation.
        performFullscreenCheck()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.performFullscreenCheck()
        }
    }

    @objc private func screensDidChange() {
        performFullscreenCheck()
    }

    // MARK: - Core Detection Logic

    private func performFullscreenCheck() {
        guard !shouldSkipScan else { return }

        let obscured = isAnyScreenObscuredByFullscreenWindow()
        let force = forceNextNotify
        forceNextNotify = false

        guard force || obscured != isCurrentlyObscured else { return }
        isCurrentlyObscured = obscured

        powerManager?.updateFullscreenObscured(obscured)
    }

    /// Skip expensive CGWindowList work while asleep/locked, or when wallpapers are already
    /// paused for a non-fullscreen reason (manual / LPM / thermal / displayInactive).
    /// Still scan when paused for `.fullscreenApp` so we notice when fullscreen ends.
    private var shouldSkipScan: Bool {
        if isScreenInactive { return true }
        if powerManager?.isDisplayInactive == true { return true }
        guard let policy = powerManager?.currentPolicy else { return false }
        if case .paused(let reason) = policy, reason != .fullscreenApp {
            return true
        }
        return false
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
                // Parenthesized explicitly: `A || B && C` parses as `A || (B && C)`, and the
                // near-fullscreen branch must also require near-full *width* — otherwise any
                // tall window (side panel, split view) triggers a global pause.
                if windowFrame.contains(screenFrame.insetBy(dx: 8, dy: 8)) ||
                   (windowFrame.intersects(screenFrame)
                    && windowFrame.size.height >= screenFrame.height * 0.92
                    && windowFrame.size.width  >= screenFrame.width  * 0.92) {
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
