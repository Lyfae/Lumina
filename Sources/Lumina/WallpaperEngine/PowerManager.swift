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

@Observable
public final class PowerManager {
    public private(set) var currentPolicy: WallpaperPlaybackPolicy = .normal

    // User-tunable aggressiveness (persisted later via Defaults or @AppStorage)
    public var pauseOnLowPowerMode: Bool = true
    public var pauseOnHighThermal: Bool = true
    public var throttleOnMediumThermal: Bool = true
    public var respectFullscreenApps: Bool = true   // Will integrate with FullscreenDetector

    private var observers: [NSObjectProtocol] = []

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
            self?.updatePolicy()
        })

        // Thermal state changes (very important on Apple Silicon laptops)
        observers.append(nc.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePolicy()
        })

        // Battery level / power source (optional future refinement)
        // We can also observe `NSProcessInfo.processInfo` properties directly if needed.
    }

    private func updatePolicy() {
        let processInfo = ProcessInfo.processInfo

        // Highest priority reasons first (most disruptive)
        if pauseOnLowPowerMode && processInfo.isLowPowerModeEnabled {
            setPolicy(.paused(reason: .lowPowerMode))
            return
        }

        let thermal = processInfo.thermalState
        if pauseOnHighThermal && (thermal == .critical || thermal == .serious) {
            setPolicy(.paused(reason: .thermalState))
            return
        }

        if throttleOnMediumThermal && thermal == .fair {
            setPolicy(.throttled(fps: 15))
            return
        }

        // Future: battery percentage check, user "critical only" mode, etc.

        // Default happy path
        setPolicy(.normal)
    }

    private func setPolicy(_ newPolicy: WallpaperPlaybackPolicy) {
        guard currentPolicy != newPolicy else { return }
        currentPolicy = newPolicy
        print("[PowerManager] Policy changed → \(newPolicy)")
        onPolicyChange?(newPolicy)
    }
}
