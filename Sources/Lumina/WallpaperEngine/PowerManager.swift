// Lumina
// PowerManager — the heart of the "does not affect other tasks / battery" promise.
//
// Responsibilities:
// - Observe system power, thermal, and low-power mode state
// - Decide the appropriate playback policy for wallpapers (normal / throttled / paused)
// - Publish changes so renderers and windows can react instantly
// - Provide hooks for future FullscreenDetector and user overrides
//
// Designed to be extremely cheap to run (KVO / NotificationCenter only, no polling).

import Foundation
import AppKit   // For future: workspace / screen state if needed

public enum WallpaperPlaybackPolicy: Equatable, Sendable {
    case normal
    case throttled(fps: Int)
    case paused(reason: PauseReason)

    public enum PauseReason: String, Sendable, Equatable {
        case lowPowerMode
        case thermalState
        case fullscreenApp
        case userPaused
        case batteryCritical
        case manual
    }
}

@MainActor
@Observable
public final class PowerManager {
    public private(set) var currentPolicy: WallpaperPlaybackPolicy = .normal

    // User-tunable aggressiveness (persisted later via Defaults or @AppStorage)
    public var pauseOnLowPowerMode: Bool = true
    public var pauseOnHighThermal: Bool = true
    public var throttleOnMediumThermal: Bool = true
    public var respectFullscreenApps: Bool = true

    // New: Performance profiles for users who want to tune the balance
    public enum PerformanceProfile: String, CaseIterable {
        case maximumBattery   // Most aggressive pausing/throttling
        case balanced         // Default good experience
        case highQuality      // Allow more playback, less aggressive saving
    }

    public var performanceProfile: PerformanceProfile = .balanced {
        didSet { recomputePolicy() }
    }

    // Appended once on the main actor during init; read once in deinit. Excluded from
    // Observation (internal state) and marked nonisolated(unsafe) so the (nonisolated) deinit
    // can remove them — the access pattern (init-on-main, read-once-at-dealloc) is race-free.
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    public init() {
        observeSystemNotifications()
        // Seed initial policy from current state
        updatePolicy()
    }

    /// Optional callback for easy wiring in the prototype (called on main actor when policy changes).
    public var onPolicyChange: ((WallpaperPlaybackPolicy) -> Void)?

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Public API for other components

    /// Temporarily force a pause (e.g. from menu bar or hotkey). User can resume.
    public func pauseManually() {
        setPolicy(.paused(reason: .manual))
    }

    public func resumeManually() {
        // Re-evaluate from real system state instead of blindly going to .normal
        updatePolicy()
    }

    /// Public hook for prototype menu toggles & debug: immediately re-evaluate policy from current system state.
    public func recomputePolicy() {
        updatePolicy()
    }

    /// Called by FullscreenDetector when the desktop is (or is no longer) obscured by a fullscreen window.
    public func updateFullscreenObscured(_ isObscured: Bool) {
        guard respectFullscreenApps else { return }
        if isObscured {
            setPolicy(.paused(reason: .fullscreenApp))
        } else {
            updatePolicy() // re-evaluate other conditions
        }
    }

    // MARK: - Observation

    private func observeSystemNotifications() {
        let nc = NotificationCenter.default

        // Low Power Mode (macOS 12+ / very reliable)
        observers.append(nc.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees main-thread delivery, so assumeIsolated is safe.
            MainActor.assumeIsolated { self?.updatePolicy() }
        })

        // Thermal state changes (very important on Apple Silicon laptops)
        observers.append(nc.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePolicy() }
        })

        // Battery level / power source (optional future refinement)
        // We can also observe `NSProcessInfo.processInfo` properties directly if needed.
    }

    private func updatePolicy() {
        let processInfo = ProcessInfo.processInfo

        // Highest priority reasons first
        if pauseOnLowPowerMode && processInfo.isLowPowerModeEnabled {
            setPolicy(.paused(reason: .lowPowerMode))
            return
        }

        let thermal = processInfo.thermalState
        if pauseOnHighThermal && (thermal == .critical || thermal == .serious) {
            setPolicy(.paused(reason: .thermalState))
            return
        }

        // Profile-aware throttling
        let profile = performanceProfile
        if throttleOnMediumThermal && thermal == .fair {
            let fps = profile == .maximumBattery ? 8 : (profile == .highQuality ? 20 : 15)
            setPolicy(.throttled(fps: fps))
            return
        }

        // Be much more lenient when the user is actively using Lumina's manager windows.
        // This prevents the wallpaper video from freezing/pausing while configuring.
        if luminaManagerWindowsAreActive {
            setPolicy(.normal)
            return
        }

        setPolicy(.normal)
    }

    // MARK: - Manager Window Awareness (to avoid pausing video while user is configuring)
    private var luminaManagerWindowsAreActive: Bool = false

    /// Call this from the manager windows when they become key or resign key.
    public func setManagerWindowsActive(_ active: Bool) {
        luminaManagerWindowsAreActive = active
        updatePolicy()
    }

    private func setPolicy(_ newPolicy: WallpaperPlaybackPolicy) {
        guard currentPolicy != newPolicy else { return }
        currentPolicy = newPolicy
        print("[PowerManager] Policy changed → \(newPolicy)")
        onPolicyChange?(newPolicy)
    }
}
