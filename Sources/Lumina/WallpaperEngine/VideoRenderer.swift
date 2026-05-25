// Lumina
// VideoRenderer — AVFoundation based implementation for the MVP prototype.
//
// Uses AVQueuePlayer + AVPlayerLooper for perfectly seamless looping (the gold standard
// for wallpaper video playback, same technique used by the best Mac video wallpaper apps).
//
// Designed to be extremely cheap on Apple Silicon (hardware decode by default for H.264/H.265).
// The renderer reacts to PowerManager policies by pausing or changing effective rate.

import AppKit
import AVFoundation

public protocol VideoRenderer: AnyObject {
    /// Installs the renderer's visual layer into the provided view.
    /// The view must already be layer-backed (wantsLayer = true).
    func install(into view: NSView)

    /// Begin or resume playback (subject to current policy).
    func play()

    /// Pause playback.
    func pause()

    /// Apply a new playback policy from PowerManager (pause, throttle, normal).
    func applyPolicy(_ policy: WallpaperPlaybackPolicy)

    /// Clean up players / loopers / layers. Call before releasing.
    func cleanup()
}

/// Concrete AVFoundation implementation for the prototype.
/// One instance per screen/window is typical (allows independent playback state if needed later).
public final class AVVideoRenderer: VideoRenderer {

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    private var currentURL: URL?
    private var currentPolicy: WallpaperPlaybackPolicy = .normal

    /// Creates a renderer ready to load a video.
    public init() {}

    // MARK: - VideoRenderer

    public func install(into view: NSView) {
        guard view.wantsLayer else {
            assertionFailure("Hosting view must have wantsLayer = true before installing AVVideoRenderer")
            return
        }

        if playerLayer == nil {
            playerLayer = AVPlayerLayer()
            playerLayer?.videoGravity = .resizeAspectFill   // Good default for wallpapers (fills screen, may crop)
            // .resizeAspect is safer for some content if you prefer letterboxing
        }

        if let layer = playerLayer {
            // Remove any previous
            layer.removeFromSuperlayer()
            view.layer?.addSublayer(layer)
            layer.frame = view.bounds
            // (Bounds observation removed for prototype simplicity — wallpaper windows are fullscreen)
        }
    }

    public func play() {
        guard let player else { return }
        if case .paused = currentPolicy {
            return // Respect policy
        }
        player.play()
        if let rate = effectiveRateForCurrentPolicy() {
            player.rate = rate
        }
    }

    public func pause() {
        player?.pause()
    }

    public func applyPolicy(_ policy: WallpaperPlaybackPolicy) {
        currentPolicy = policy

        guard let player else { return }

        switch policy {
        case .normal:
            player.rate = 1.0
            if player.timeControlStatus != .playing {
                player.play()
            }

        case .throttled(let fps):
            // Simple but effective for prototype: lower rate or pause periodically.
            // For very low cost we can just use a reduced rate (e.g. 0.5x looks like ~15-20 fps on 30/60 content).
            let rate = max(0.25, min(1.0, Double(fps) / 60.0))
            player.rate = Float(rate)
            if player.timeControlStatus != .playing {
                player.play()
            }

        case .paused:
            player.pause()
        }
    }

    public func cleanup() {
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }

    // MARK: - Loading

    /// Loads a video file and prepares it for seamless looping.
    /// Call this before or after `install(into:)`.
    public func load(url: URL, autoPlay: Bool = true) {
        cleanup()

        currentURL = url

        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.actionAtItemEnd = .none   // We control looping via AVPlayerLooper
        queuePlayer.isMuted = true            // Wallpapers should usually be silent by default (user can opt-in later)

        // The magic for seamless infinite loop
        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        self.player = queuePlayer
        self.looper = playerLooper

        // Attach to existing playerLayer if install() was already called
        playerLayer?.player = queuePlayer

        if autoPlay {
            // Will respect currentPolicy in play()
            play()
        }
    }

    // MARK: - Private

    private func effectiveRateForCurrentPolicy() -> Float? {
        switch currentPolicy {
        case .normal: return 1.0
        case .throttled(let fps):
            return Float(max(0.25, min(1.0, Double(fps) / 60.0)))
        case .paused:
            return nil
        }
    }

    deinit {
        cleanup()
    }
}
