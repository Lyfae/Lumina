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

    // User-tunable aggressiveness. The three user-facing toggles persist to UserDefaults
    // (seeded from the stored value in init, written back when changed via the setters).
    public var pauseOnLowPowerMode: Bool = true {
        didSet { UserDefaults.standard.set(pauseOnLowPowerMode, forKey: Self.kPauseLowPower) }
    }
    public var pauseOnHighThermal: Bool = true {
        didSet { UserDefaults.standard.set(pauseOnHighThermal, forKey: Self.kPauseThermal) }
    }
    public var throttleOnMediumThermal: Bool = true
    public var respectFullscreenApps: Bool = true {
        didSet { UserDefaults.standard.set(respectFullscreenApps, forKey: Self.kRespectFullscreen) }
    }

    private static let kPauseLowPower      = "Lumina.Power.PauseOnLowPowerMode"
    private static let kPauseThermal       = "Lumina.Power.PauseOnHighThermal"
    private static let kRespectFullscreen  = "Lumina.Power.RespectFullscreenApps"

    // New: Performance profiles for users who want to tune the balance
    public enum PerformanceProfile: String, CaseIterable, Identifiable {
        case maximumBattery   // Most aggressive pausing/throttling
        case balanced         // Default good experience
        case highQuality      // Allow more playback, less aggressive saving

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .maximumBattery: return "Max Battery"
            case .balanced:       return "Balanced"
            case .highQuality:    return "High Quality"
            }
        }
    }

    public var performanceProfile: PerformanceProfile = .balanced {
        didSet {
            UserDefaults.standard.set(performanceProfile.rawValue, forKey: Self.kPerformanceProfile)
            recomputePolicy()
        }
    }

    private static let kPerformanceProfile = "Lumina.Power.PerformanceProfile"

    // Appended once on the main actor during init; read once in deinit. Excluded from
    // Observation (internal state) and marked nonisolated(unsafe) so the (nonisolated) deinit
    // can remove them — the access pattern (init-on-main, read-once-at-dealloc) is race-free.
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    public init() {
        // Seed user toggles from persisted preferences (default true when unset).
        // `object(forKey:) == nil` distinguishes "never set" from an explicit false.
        let ud = UserDefaults.standard
        if ud.object(forKey: Self.kPauseLowPower) != nil     { pauseOnLowPowerMode = ud.bool(forKey: Self.kPauseLowPower) }
        if ud.object(forKey: Self.kPauseThermal) != nil      { pauseOnHighThermal = ud.bool(forKey: Self.kPauseThermal) }
        if ud.object(forKey: Self.kRespectFullscreen) != nil { respectFullscreenApps = ud.bool(forKey: Self.kRespectFullscreen) }
        if let raw = ud.string(forKey: Self.kPerformanceProfile),
           let profile = PerformanceProfile(rawValue: raw) { performanceProfile = profile }

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

        // Profile-aware throttling on moderate ("fair") thermal pressure.
        // High Quality intentionally does NOT throttle here — it keeps full playback until
        // the system reaches a serious/critical state (handled above). Max Battery throttles
        // hardest; Balanced sits in between.
        let profile = performanceProfile
        if throttleOnMediumThermal && thermal == .fair && profile != .highQuality {
            let fps = profile == .maximumBattery ? 8 : 15
            setPolicy(.throttled(fps: fps))
            return
        }

        // While the user is actively configuring in the manager, always play at full quality
        // so the preview/desktop look right (overrides the Max Battery baseline below).
        if luminaManagerWindowsAreActive {
            setPolicy(.normal)
            return
        }

        // Baseline per profile when there's no thermal/power pressure. This is what makes the
        // profile observably "do something" in everyday use:
        //   • Max Battery  → cap the wallpaper to ~30 fps-equivalent (halves decode/GPU work).
        //   • Balanced     → full quality.
        //   • High Quality → full quality.
        if profile == .maximumBattery {
            setPolicy(.throttled(fps: 30))
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
