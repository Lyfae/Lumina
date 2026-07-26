import Foundation
import AppKit
import Combine

extension Notification.Name {
    /// Posted on the main thread when wallpaper playback health changes.
    static let luminaPlaybackHealthDidChange = Notification.Name("Lumina.PlaybackHealthDidChange")
}

/// Watches live wallpaper playback for sustained stalls / thermal pressure and
/// surfaces a user-facing warning when wallpapers are straining the Mac.
@MainActor
final class PlaybackHealthMonitor: ObservableObject {
    static let shared = PlaybackHealthMonitor()

    /// True when wallpapers appear to be causing stutter or the Mac is thermally warm.
    @Published private(set) var isStruggling: Bool = false
    /// Short reason for UI / tooltip.
    @Published private(set) var reason: String = ""
    /// Studio banner dismissed for this struggle episode (resets when health recovers).
    @Published var bannerDismissed: Bool = false

    /// Provide snapshots from the app’s renderers (set by `LuminaApp`).
    var snapshotProvider: (() -> [PlaybackHealthSnapshot])?

    private var timer: Timer?
    private var consecutiveUnhealthySamples: Int = 0
    private var consecutiveHealthySamples: Int = 0

    /// ~2.5s × 2 = ~5s before warning; ~2.5s × 3 ≈ 7.5s before clearing.
    private let unhealthyThreshold = 2
    private let healthyThreshold = 3
    private let sampleInterval: TimeInterval = 2.5

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func dismissBanner() {
        bannerDismissed = true
    }

    // MARK: - Sampling

    private func sample() {
        let snapshots = snapshotProvider?() ?? []
        let thermal = ProcessInfo.processInfo.thermalState
        let activeVideos = snapshots.filter(\.isActiveVideo)

        var stallNames: [String] = []
        for snap in activeVideos where snap.isStruggling {
            if let name = snap.filename { stallNames.append(name) }
        }

        let thermalHot = thermal == .fair || thermal == .serious || thermal == .critical
        let hasStall = !stallNames.isEmpty
        let unhealthy = hasStall || (thermalHot && !activeVideos.isEmpty)

        if unhealthy {
            consecutiveUnhealthySamples += 1
            consecutiveHealthySamples = 0
        } else {
            consecutiveHealthySamples += 1
            consecutiveUnhealthySamples = 0
        }

        if !isStruggling, consecutiveUnhealthySamples >= unhealthyThreshold {
            let message: String
            if hasStall {
                let names = stallNames.prefix(2).joined(separator: ", ")
                message = stallNames.count > 2
                    ? "“\(names)” and other wallpapers are stuttering"
                    : "“\(names)” is stuttering on the desktop"
            } else if thermal == .critical || thermal == .serious {
                message = "This Mac is running hot while wallpapers play"
            } else {
                message = "This Mac is warming up under wallpaper load"
            }
            setStruggling(true, reason: message)
        } else if isStruggling, consecutiveHealthySamples >= healthyThreshold {
            setStruggling(false, reason: "")
        }
    }

    private func setStruggling(_ value: Bool, reason: String) {
        guard isStruggling != value || self.reason != reason else { return }
        isStruggling = value
        self.reason = reason
        if !value { bannerDismissed = false }
        LuminaLog.power.info("Playback health → \(value ? "struggling: \(reason)" : "ok")")
        NotificationCenter.default.post(name: .luminaPlaybackHealthDidChange, object: nil)
    }
}

/// One renderer’s health sample for the monitor.
struct PlaybackHealthSnapshot: Sendable {
    var isActiveVideo: Bool
    var isStruggling: Bool
    var filename: String?
}
