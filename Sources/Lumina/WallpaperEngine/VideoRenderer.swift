// Lumina
// VideoRenderer — AVFoundation based implementation for the MVP prototype.
//
// Uses AVQueuePlayer + AVPlayerLooper for perfectly seamless looping (the gold standard
// for wallpaper video playback, same technique used by the best Mac video wallpaper apps).
//
// Designed to be extremely cheap on Apple Silicon (hardware decode by default for H.264/H.265).
// The renderer reacts to PowerManager policies by pausing or changing effective rate.
//
// FIX (2026-05): load() + cleanup() previously removed/niled the playerLayer after install(),
// detaching the only visual from the desktop window's layer tree. This (plus pre-install load
// case and multi-monitor NSView frame bugs in the window) caused "Loaded the video, nothing happened"
// despite non-zero playback rate. Now the layer stays attached for the renderer's life; only player
// content is swapped. Install also handles load-before-install. See DesktopWallpaperWindow for related fixes.

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

    // Public debug / status accessors (added for prototype testing & UX)
    public private(set) var loadedURL: URL?
    public var currentPlaybackRate: Float { player?.rate ?? 0.0 }
    public var isLoaded: Bool { loadedURL != nil }

    /// Creates a renderer ready to load a video.
    public init() {}

    // MARK: - Scaling / Video Gravity

    public enum VideoScaling {
        case fit      // Letterbox / pillarbox (preserves aspect ratio)
        case fill     // Crop to fill (most common for wallpapers)
        case stretch  // Distort to fill the entire area
    }

    private var currentScaling: VideoScaling = .fill

    /// Changes how the video is scaled to fit the screen.
    /// This has virtually zero impact on CPU/GPU or battery life — it's just a compositing instruction.
    public func setScaling(_ scaling: VideoScaling) {
        currentScaling = scaling

        let gravity: AVLayerVideoGravity
        switch scaling {
        case .fit:      gravity = .resizeAspect
        case .fill:     gravity = .resizeAspectFill
        case .stretch:  gravity = .resize
        }

        playerLayer?.videoGravity = gravity
    }

    // MARK: - VideoRenderer

    public func install(into view: NSView) {
        guard view.wantsLayer else {
            assertionFailure("Hosting view must have wantsLayer = true before installing AVVideoRenderer")
            return
        }

        if playerLayer == nil {
            playerLayer = AVPlayerLayer()
            // Apply the user's chosen scaling (or default .fill)
            setScaling(currentScaling)
        }

        if let layer = playerLayer {
            // Remove any previous (supports re-install into a different view)
            layer.removeFromSuperlayer()
            view.layer?.addSublayer(layer)
            layer.frame = view.bounds
            // (Bounds observation removed for prototype simplicity — wallpaper windows are fullscreen)

            // Robustness: if load() was called before install(), attach the existing player now.
            if let existingPlayer = player {
                layer.player = existingPlayer
            }
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
        // CRITICAL: Do NOT remove or nil the playerLayer here.
        // The layer is created in install() and must remain attached to the
        // hosting view's layer tree across load() / cleanup() cycles (new videos
        // just swap the .player). Removing it was the root cause of
        // "loaded the video, nothing happened" (layer detached, no visual).
        // We only detach the player content; the layer object stays for reuse.
        playerLayer?.player = nil
        // playerLayer and its superlayer attachment are intentionally preserved.
        loadedURL = nil
        currentURL = nil
    }

    // MARK: - Loading

    /// Loads a video file and prepares it for seamless looping.
    /// Call this before or after `install(into:)`.
    public func load(url: URL, autoPlay: Bool = true) {
        cleanup()

        currentURL = url
        loadedURL = url

        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.actionAtItemEnd = .none                    // Controlled by AVPlayerLooper
        queuePlayer.isMuted = true
        queuePlayer.automaticallyWaitsToMinimizeStalling = false   // Better for continuous wallpaper playback

        // The magic for seamless infinite loop.
        // AVPlayerLooper is the recommended, efficient way to loop without glitches.
        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        self.player = queuePlayer
        self.looper = playerLooper

        // Attach (or re-attach) to the playerLayer.
        if let pl = playerLayer {
            pl.player = queuePlayer
            // Re-apply current scaling in case it was reset
            setScaling(currentScaling)
        }

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
