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

/// Unified protocol for all wallpaper renderers (video, images, GIFs, future scenes).
/// This is the foundation for production-grade per-monitor media support.
public protocol MediaRenderer: AnyObject {
    func install(into view: NSView)

    // Preferred new API
    func load(assignment: MonitorAssignment, autoPlay: Bool)

    // Convenience for legacy / global paths
    func load(url: URL, autoPlay: Bool)

    func applyScaling(_ scaling: VideoScaling)
    func applyPlaybackSpeed(_ speed: Double)
    func applyCropRect(_ rect: CGRect)
    func applyMuted(_ muted: Bool)
    func applyPolicy(_ policy: WallpaperPlaybackPolicy)

    // Keep old setter names for compatibility during transition
    func setScaling(_ scaling: VideoScaling)
    func setPlaybackSpeed(_ speed: Double)
    func setMuted(_ muted: Bool)

    func pause()
    func play()
    func cleanup()

    /// Performs a short, low-cost crossfade to the new content (if supported by the renderer).
    func crossfadeToNewContent(duration: TimeInterval)

    /// Seeks the current media to the given time in seconds (no-op for images).
    func seek(to time: TimeInterval)

    /// Returns the current playback time in seconds (0 for images/static content).
    func currentPlaybackTime() -> TimeInterval

    /// Completely clears the current content (black/transparent background).
    func clear()

    var currentMediaURL: URL? { get }
    var loadedURL: URL? { get }           // For debug printing
    var currentPlaybackRate: Float { get }
}

// Note: We keep the concrete class working with the existing renderers array for now.
// Full migration to MediaRenderer protocol across the app will happen when ImageRenderer is production-ready.

/// Concrete AVFoundation implementation for the prototype.
/// One instance per screen/window is typical (allows independent playback state if needed later).
/// @unchecked Sendable: all access is on the main thread; the internal closures only dispatch back to main.
public final class AVVideoRenderer: @unchecked Sendable {

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    // MARK: - Image / GIF support
    // AVPlayer cannot render static images or animate GIFs, so those formats use a
    // CALayer-based path that lives alongside the video player layer in the same view.
    private var imageLayer: CALayer?
    private weak var hostLayer: CALayer?
    private var mediaKind: MediaType = .video

    // MARK: - Slideshow support
    private var slideshow: SlideshowEngine?
    public var isSlideshow: Bool { slideshow != nil }

    /// One-line human-readable summary of what this renderer is currently showing.
    /// Used by the in-app diagnostics so the user can verify rendering without a debugger.
    public var statusSummary: String {
        let kind: String
        if isSlideshow {
            kind = "slideshow"
        } else {
            switch mediaKind {
            case .video:         kind = "video"
            case .image:         kind = "image"
            case .animatedImage: kind = "gif"
            case .unknown:       kind = "none"
            }
        }
        let file = loadedURL?.lastPathComponent ?? "—"
        return "\(kind) | rate \(String(format: "%.2f", currentPlaybackRate)) | \(file)"
    }

    /// The layer currently presenting visible content.
    private var activeLayer: CALayer? {
        switch mediaKind {
        case .video:                 return playerLayer
        case .image, .animatedImage: return imageLayer
        case .unknown:               return playerLayer ?? imageLayer
        }
    }

    private var currentURL: URL?
    private var currentPolicy: WallpaperPlaybackPolicy = .normal

    // Public debug / status accessors (added for prototype testing & UX)
    public private(set) var loadedURL: URL?
    public var currentPlaybackRate: Float { player?.rate ?? 0.0 }
    public var isLoaded: Bool { loadedURL != nil }

    // MediaRenderer requirement
    public var currentMediaURL: URL? { loadedURL }

    // MARK: - Loop Crossfade
    private var loopFadeEnabled: Bool = false
    private var loopFadeDuration: Double = 1.5
    private var loopBoundaryObserver: Any?

    // MARK: - Loop Mode (loop / once / bounce)
    private var loopMode: MonitorAssignment.LoopMode = .loop
    private var endTimeObserver: NSObjectProtocol?

    // MARK: - Brightness
    private var brightnessLayer: CALayer?

    // MARK: - Opacity / Color Correction
    private var currentOpacity: Double = 1.0
    private var currentSaturation: Double = 1.0
    private var currentHue: Double = 0.0
    private var grayscaleEnabled: Bool = false
    private var userVolume: Double = 0.0

    /// Creates a renderer ready to load a video.
    public init() {}

    // MARK: - Scaling / Video Gravity

    public enum VideoScaling {
        case fit      // Letterbox / pillarbox (preserves aspect ratio)
        case fill     // Crop to fill (most common for wallpapers)
        case stretch  // Distort to fill the entire area
    }

    private var currentScaling: VideoScaling = .fill
    private var currentCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Changes how the video is scaled to fit the screen.
    /// This has virtually zero impact on CPU/GPU or battery life — it's just a compositing instruction.
    public func setScaling(_ scaling: VideoScaling) {
        currentScaling = scaling
        // Re-apply crop so that the frame geometry and videoGravity stay consistent.
        // When no crop is active this just sets the gravity on the full-frame layer.
        applyCurrentCrop()
    }

    // MARK: - Crop (live from manager)

    /// Applies a normalized crop rectangle (0–1, top-left origin).
    ///
    /// AVPlayerLayer ignores `contentsRect` because it owns its own rendering pipeline.
    /// Instead we expand the layer's frame beyond the parent bounds so that the requested
    /// crop region exactly fills the visible area. The parent view/window clips the overflow.
    ///
    /// Math (macOS CALayer has bottom-left origin, crop uses top-left origin):
    ///   fullW = parentW / crop.width
    ///   fullH = parentH / crop.height
    ///   originX = -crop.minX * fullW
    ///   originY = crop.maxY * fullH - fullH          (Y-axis flip)
    public func setCropRect(_ rect: CGRect) {
        currentCropRect = rect
        applyCurrentCrop()
    }

    private func applyCurrentCrop() {
        // Images and GIFs crop cleanly via the layer's normalized contentsRect.
        if mediaKind == .image || mediaKind == .animatedImage {
            applyImageCrop()
            return
        }

        guard let pl = playerLayer else { return }
        let parent = pl.superlayer?.bounds ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        guard parent.width > 0, parent.height > 0 else { return }

        let crop = currentCropRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        let isFull = abs(crop.minX) < 0.001 && abs(crop.minY) < 0.001
                  && abs(crop.width  - 1) < 0.001 && abs(crop.height - 1) < 0.001

        if isFull || crop.width < 0.001 || crop.height < 0.001 {
            // Restore user's chosen scaling and fill parent
            pl.frame = parent
            updateVideoGravity(pl)
            return
        }

        pl.frame = Self.expandedVideoFrame(parent: parent, crop: crop)
        pl.videoGravity = .resizeAspectFill  // fill the (expanded) frame
    }

    /// Pure geometry: expands a player layer's frame beyond `parent` so the normalized
    /// top-left-origin `crop` region exactly fills the parent (which clips the overflow).
    /// CALayer uses a bottom-left origin, hence the Y flip on the origin.
    static func expandedVideoFrame(parent: CGRect, crop: CGRect) -> CGRect {
        let fullW = parent.width  / crop.width
        let fullH = parent.height / crop.height
        let originX = parent.minX - crop.minX * fullW
        let originY = parent.minY + crop.maxY * fullH - fullH   // flip Y
        return CGRect(x: originX, y: originY, width: fullW, height: fullH)
    }

    /// Pure geometry: the layer `contentsRect` (bottom-left-origin, normalized) for a
    /// top-left-origin `crop`. Returns the full rect when the crop is the whole image.
    static func imageContentsRect(crop: CGRect) -> CGRect {
        let clamped = crop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let isFull = abs(clamped.minX) < 0.001 && abs(clamped.minY) < 0.001
                  && abs(clamped.width - 1) < 0.001 && abs(clamped.height - 1) < 0.001
        if isFull || clamped.width < 0.001 || clamped.height < 0.001 {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(x: clamped.minX, y: 1 - clamped.maxY, width: clamped.width, height: clamped.height)
    }

    /// Crop + scaling for the CALayer-based image/GIF path.
    private func applyImageCrop() {
        guard let layer = imageLayer else { return }
        let parent = layer.superlayer?.bounds ?? hostLayer?.bounds ?? .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = parent
        layer.contentsGravity = contentsGravityForScaling(currentScaling)
        layer.contentsRect = Self.imageContentsRect(crop: currentCropRect)
        CATransaction.commit()
    }

    private func updateVideoGravity(_ pl: AVPlayerLayer) {
        switch currentScaling {
        case .fit:     pl.videoGravity = .resizeAspect
        case .fill:    pl.videoGravity = .resizeAspectFill
        case .stretch: pl.videoGravity = .resize
        }
    }

    private func contentsGravityForScaling(_ scaling: VideoScaling) -> CALayerContentsGravity {
        switch scaling {
        case .fit:     return .resizeAspect
        case .fill:    return .resizeAspectFill
        case .stretch: return .resize
        }
    }

    // MARK: - Playback Speed (live from manager)

    private var userPlaybackSpeed: Double = 1.0

    /// Sets the user's desired playback speed (0.25x – 4.0x).
    /// This is applied on top of the current PowerManager policy.
    /// Safe to call even when no video is loaded (value is stored for next load).
    public func setPlaybackSpeed(_ speed: Double) {
        userPlaybackSpeed = max(0.25, min(4.0, speed))

        guard let player else { return }

        // Respect current policy: if paused, stay paused.
        if case .paused = currentPolicy {
            return
        }

        // When in normal policy, use the user's speed directly.
        // When throttled, we let applyPolicy re-evaluate (it will use its own reduced rate).
        // For a quick live response from the manager, we apply the user speed now
        // and let the next policy change correct it if needed.
        if case .normal = currentPolicy {
            player.rate = Float(userPlaybackSpeed)
        }
    }

    // MARK: - Mute / Volume (live from manager)

    /// Sets whether the wallpaper audio is muted.
    /// Videos are muted by default for a peaceful experience.
    public func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    public func crossfadeToNewContent(duration: TimeInterval) {
        // Simple low-cost crossfade using layer opacity — works for both video and images.
        guard let layer = activeLayer, duration > 0 else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.0
        animation.toValue = Float(currentOpacity)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        layer.opacity = Float(currentOpacity)
        layer.add(animation, forKey: "crossfade")
    }

    // MARK: - MediaRenderer Protocol Conformance (new unified API)

    public func applyScaling(_ scaling: VideoScaling) {
        setScaling(scaling)
    }

    public func applyPlaybackSpeed(_ speed: Double) {
        setPlaybackSpeed(speed)
    }

    public func applyCropRect(_ rect: CGRect) {
        setCropRect(rect)
    }

    public func applyMuted(_ muted: Bool) {
        setMuted(muted)
    }

    // MARK: - VideoRenderer (legacy names kept for compatibility during transition)

    public func install(into view: NSView) {
        // NSView's layer/bounds/wantsLayer are main-actor isolated. This renderer is
        // documented main-thread-only (see @unchecked Sendable note), and all callers
        // install from the main thread, so assert isolation rather than hop threads.
        MainActor.assumeIsolated {
            guard view.wantsLayer else {
                assertionFailure("Hosting view must have wantsLayer = true before installing AVVideoRenderer")
                return
            }

            hostLayer = view.layer

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

                // Robustness: if load() was called before install(), attach the existing player now.
                if let existingPlayer = player {
                    layer.player = existingPlayer
                }

                // Re-apply crop geometry now that the layer has a real superlayer and bounds.
                applyCurrentCrop()
            }
        }
    }

    /// Re-applies layer geometry after the hosting view's bounds change (display
    /// reconfiguration). CALayer sublayers don't autoresize with an NSView, so the
    /// player layer must be re-sized to its superlayer and the crop re-derived.
    public func relayout() {
        if let slideshow {
            MainActor.assumeIsolated { slideshow.relayout() }
            return
        }
        guard let layer = activeLayer, let superlayer = layer.superlayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = superlayer.bounds
        applyCurrentCrop()
        brightnessLayer?.frame = superlayer.bounds
        CATransaction.commit()
    }

    public func play() {
        if mediaKind == .animatedImage, let layer = imageLayer {
            if case .paused = currentPolicy { return }
            resumeLayerAnimation(layer)
            return
        }
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
        if mediaKind == .animatedImage, let layer = imageLayer {
            pauseLayerAnimation(layer)
            return
        }
        player?.pause()
    }

    public func seek(to time: TimeInterval) {
        guard let player else { return }
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seeks to `time` then schedules playback to begin at a shared host-clock instant.
    /// Call this on all renderers with the same `hostTime` to achieve frame-precise sync.
    public func syncStart(to time: TimeInterval, atHostTime hostTime: CMTime) {
        guard let player else { return }
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] _ in
            guard let player else { return }
            player.setRate(1.0, time: .invalid, atHostTime: hostTime)
        }
    }

    public func currentPlaybackTime() -> TimeInterval {
        guard let player else { return 0 }
        return player.currentTime().seconds
    }

    /// Duration of the currently playing item, or 0 if unknown/indefinite.
    /// Used by the sync coordinator to measure drift across a looping boundary.
    public func currentItemDuration() -> TimeInterval {
        guard let d = player?.currentItem?.duration, d.isNumeric else { return 0 }
        let seconds = d.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    public func clear() {
        if let slideshow {
            MainActor.assumeIsolated { slideshow.teardown() }
        }
        slideshow = nil
        player?.replaceCurrentItem(with: nil)
        imageLayer?.removeAnimation(forKey: "gif")
        imageLayer?.contents = nil
        imageLayer?.isHidden = true
        loadedURL = nil
        currentURL = nil
        // The layer will show black/transparent
    }

    public func applyPolicy(_ policy: WallpaperPlaybackPolicy) {
        currentPolicy = policy

        // Slideshow: stop the timer when paused, resume cycling otherwise.
        if let slideshow {
            MainActor.assumeIsolated {
                if case .paused = policy { slideshow.stop() } else { slideshow.start() }
            }
            return
        }

        // GIFs: pause/resume the keyframe animation (static images need nothing).
        if mediaKind == .animatedImage, let layer = imageLayer {
            if case .paused = policy { pauseLayerAnimation(layer) }
            else { resumeLayerAnimation(layer) }
            return
        }
        if mediaKind == .image { return }

        guard let player else { return }

        switch policy {
        case .normal:
            // Respect the user's chosen speed when in normal playback
            player.rate = Float(userPlaybackSpeed)
            if player.timeControlStatus != .playing {
                player.play()
            }

        case .throttled(let fps):
            // Throttling takes precedence over user speed for power reasons.
            // We use a reduced rate; user speed can be re-applied when policy returns to normal.
            let rate = max(0.25, min(1.0, Double(fps) / 60.0))
            player.rate = Float(rate)
            if player.timeControlStatus != .playing {
                player.play()
            }

        case .paused:
            player.pause()
        }
    }

    // MARK: - Loop Crossfade

    private var currentFadeEasing: MonitorAssignment.FadeEasing = .easeInOut

    // KVO observer token for item readiness
    private var itemStatusObserver: NSKeyValueObservation?

    // KVO observer for detecting load failures (corrupt / unsupported files)
    private var loadStatusObserver: NSKeyValueObservation?

    /// Called on the main thread when a video fails to load (so the app can blank the
    /// display and record the error on the assignment instead of silently showing nothing).
    public var onLoadFailure: ((URL, Error?) -> Void)?

    /// Configures loop-point crossfade behavior. Call after load().
    public func setLoopFade(enabled: Bool, duration: Double, easing: MonitorAssignment.FadeEasing = .easeInOut) {
        loopFadeEnabled = enabled
        loopFadeDuration = max(0.05, duration)
        currentFadeEasing = easing
        registerLoopBoundaryObserver()
    }

    /// Changes the end-of-playback behavior for the current (or next) video.
    /// .loop   → seamless AVPlayerLooper (current default)
    /// .once   → play to end, then visually go black (no looping)
    /// .bounce → forward then reverse (ping-pong) using rate reversal
    public func setLoopMode(_ mode: MonitorAssignment.LoopMode) {
        guard mode != loopMode else { return }
        loopMode = mode

        // If we have active video content, reconfigure it now with the new strategy.
        // For slideshows the mode is ignored (they have their own cycling).
        if !isSlideshow, let url = loadedURL, mediaKind == .video {
            let wasPlaying = (player?.rate ?? 0) > 0.01
            // Full cleanup is safe here (we are in video mode, not slideshow).
            // It removes player+looper+observers; loadVideo will rebuild.
            cleanup()
            // Recreate using the (newly stored) loopMode
            loadVideo(url: url)
            if wasPlaying { play() }
        }
    }

    private func registerLoopBoundaryObserver() {
        // Remove any existing observers first
        if let observer = loopBoundaryObserver {
            player?.removeTimeObserver(observer)
            loopBoundaryObserver = nil
        }
        itemStatusObserver = nil

        guard loopFadeEnabled, let player = player,
              let currentItem = player.currentItem else { return }

        // Use KVO to observe when the item becomes ready to play.
        // We read duration synchronously from the item once it's ready.
        itemStatusObserver = currentItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            // Read duration synchronously — it's available once status is readyToPlay
            let durationSeconds = item.duration.seconds
            guard durationSeconds.isFinite && durationSeconds > 0 else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.itemStatusObserver = nil
                self.addBoundaryObserver(videoDuration: durationSeconds)
            }
        }
    }

    private func addBoundaryObserver(videoDuration: Double) {
        guard loopFadeEnabled, let player = player else { return }

        // Remove previous boundary observer if any
        if let obs = loopBoundaryObserver {
            player.removeTimeObserver(obs)
            loopBoundaryObserver = nil
        }

        let fadeHalf = loopFadeDuration / 2.0
        let triggerTime = max(0, videoDuration - fadeHalf)
        let cmTrigger = CMTime(seconds: triggerTime, preferredTimescale: 600)

        let observer = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: cmTrigger)],
            queue: .main
        ) { [weak self] in
            guard let self, let pl = self.playerLayer else { return }
            let half = self.loopFadeDuration / 2.0
            let timingFn = self.currentFadeEasing.caTimingFunction

            // Fade out
            CATransaction.begin()
            CATransaction.setAnimationDuration(half)
            CATransaction.setAnimationTimingFunction(timingFn)
            pl.opacity = 0.0
            CATransaction.commit()

            // Fade back in after half duration
            DispatchQueue.main.asyncAfter(deadline: .now() + half) { [weak self] in
                guard let self, let pl = self.playerLayer else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(self.loopFadeDuration / 2.0)
                CATransaction.setAnimationTimingFunction(self.currentFadeEasing.caTimingFunction)
                pl.opacity = 1.0
                CATransaction.commit()
            }
        }
        loopBoundaryObserver = observer
    }

    // MARK: - Brightness

    /// Adjusts brightness by overlaying a translucent black (darken) or white (lighten) layer.
    /// value range: -0.5 (darker) to +0.5 (lighter), 0.0 = no adjustment.
    public func setBrightness(_ value: Double) {
        // Remove existing brightness layer
        brightnessLayer?.removeFromSuperlayer()
        brightnessLayer = nil

        guard let superlayer = activeLayer?.superlayer ?? hostLayer, abs(value) > 0.001 else { return }

        let overlay = CALayer()
        overlay.frame = superlayer.bounds
        overlay.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        if value < 0 {
            overlay.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(-value * 2)).cgColor
        } else {
            overlay.backgroundColor = NSColor.white.withAlphaComponent(CGFloat(value * 2)).cgColor
        }

        superlayer.addSublayer(overlay)
        brightnessLayer = overlay
    }

    // MARK: - Opacity

    public func setOpacity(_ value: Double) {
        currentOpacity = max(0, min(1, value))
        activeLayer?.opacity = Float(currentOpacity)
        brightnessLayer?.opacity = Float(currentOpacity)  // keep brightness overlay in sync
    }

    // MARK: - Volume

    public func setVolume(_ volume: Double) {
        userVolume = max(0, min(1, volume))
        player?.isMuted = (userVolume <= 0.001)
        player?.volume = Float(userVolume)
    }

    // MARK: - Color Correction

    public func setColorCorrection(saturation: Double, hue: Double, grayscale: Bool) {
        currentSaturation = saturation
        currentHue = hue
        grayscaleEnabled = grayscale
        applyColorFilters()
    }

    private func applyColorFilters() {
        guard let pl = activeLayer else { return }
        var filters: [CIFilter] = []

        let sat = grayscaleEnabled ? 0.0 : currentSaturation
        if abs(sat - 1.0) > 0.01 || abs(currentHue) > 0.5 {
            if let cc = CIFilter(name: "CIColorControls") {
                cc.setValue(NSNumber(value: sat), forKey: kCIInputSaturationKey)
                filters.append(cc)
            }
            if abs(currentHue) > 0.5, let ha = CIFilter(name: "CIHueAdjust") {
                ha.setValue(NSNumber(value: currentHue * Double.pi / 180), forKey: kCIInputAngleKey)
                filters.append(ha)
            }
        } else if grayscaleEnabled {
            if let cc = CIFilter(name: "CIColorControls") {
                cc.setValue(NSNumber(value: 0.0), forKey: kCIInputSaturationKey)
                filters.append(cc)
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pl.filters = filters.isEmpty ? nil : filters
        CATransaction.commit()
    }

    public func cleanup() {
        // Remove loop boundary observer
        if let observer = loopBoundaryObserver {
            player?.removeTimeObserver(observer)
            loopBoundaryObserver = nil
        }
        itemStatusObserver = nil
        loadStatusObserver = nil

        if let obs = endTimeObserver {
            NotificationCenter.default.removeObserver(obs)
            endTimeObserver = nil
        }

        // Remove brightness overlay
        brightnessLayer?.removeFromSuperlayer()
        brightnessLayer = nil

        // Tear down any running slideshow.
        if let slideshow {
            MainActor.assumeIsolated { slideshow.teardown() }
        }
        slideshow = nil

        // Tear down any image/GIF content (keep the layer object for reuse).
        imageLayer?.removeAnimation(forKey: "gif")
        imageLayer?.contents = nil
        imageLayer?.isHidden = true
        // Make sure CALayer timing is reset in case a GIF was paused via speed=0.
        if let layer = imageLayer { layer.speed = 1; layer.timeOffset = 0; layer.beginTime = 0 }
        mediaKind = .video

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

        // Reset effect state
        currentOpacity = 1.0
        currentSaturation = 1.0
        currentHue = 0.0
        grayscaleEnabled = false
        userVolume = 0.0
    }

    // MARK: - MediaRenderer Protocol

    public func load(assignment: MonitorAssignment, autoPlay: Bool = true) {
        guard let url = assignment.resolvedURL() ??
                        (assignment.filePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }) else {
            print("[AVVideoRenderer] Could not resolve URL from assignment")
            return
        }
        load(url: url, autoPlay: autoPlay)

        let internalScaling: VideoScaling
        switch assignment.scaling {
        case .fit:      internalScaling = .fit
        case .fill:     internalScaling = .fill
        case .stretch:  internalScaling = .stretch
        }
        setScaling(internalScaling)
        setPlaybackSpeed(assignment.playbackSpeed)
        setMuted(assignment.isMuted)
        setCropRect(assignment.cropRect)
        setOpacity(assignment.opacity)
        setVolume(assignment.audioVolume)
        setColorCorrection(saturation: assignment.saturation, hue: assignment.hue, grayscale: assignment.grayscale)
    }

    public func load(url: URL, autoPlay: Bool = true) {
        // Dispatch by media type — AVPlayer handles video (and is the wrong tool for
        // stills/GIFs, which would render black). Images and GIFs use the CALayer path.
        let kind = MediaType.from(url: url)
        switch kind {
        case .image, .animatedImage:
            loadImage(url: url, kind: kind, autoPlay: autoPlay)
        default:
            loadVideo(url: url)
            if autoPlay { play() }
        }
    }

    private func loadVideo(url: URL) {
        cleanup()
        mediaKind = .video

        // Hide any leftover image content; show the video layer.
        imageLayer?.isHidden = true
        playerLayer?.isHidden = false

        currentURL = url
        loadedURL = url

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // Surface load failures (corrupt/unsupported media) instead of a silent black screen.
        loadStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self, item.status == .failed else { return }
            let failedURL = url
            let error = item.error
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                print("[AVVideoRenderer] Failed to load \(failedURL.lastPathComponent): \(error?.localizedDescription ?? "unknown error")")
                self.clear()
                self.onLoadFailure?(failedURL, error)
            }
        }

        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.actionAtItemEnd = .none
        queuePlayer.isMuted = true
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        queuePlayer.allowsExternalPlayback = false

        self.player = queuePlayer

        // Mode-aware looping setup (the heart of the "Loop Mode" dropdown)
        switch loopMode {
        case .loop:
            let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            self.looper = playerLooper

        case .once, .bounce:
            // No looper — we handle end ourselves for one-shot or ping-pong
            self.looper = nil
            attachEndOfItemHandler(for: item, player: queuePlayer, mode: loopMode)
        }

        if let pl = playerLayer {
            pl.player = queuePlayer
            // setScaling calls applyCurrentCrop internally so both gravity and frame are in sync.
            setScaling(currentScaling)
        }

        // Re-register loop boundary observer for the new content (crossfade at loop points only makes sense for .loop)
        if loopFadeEnabled && loopMode == .loop {
            registerLoopBoundaryObserver()
        }
    }

    private func attachEndOfItemHandler(for item: AVPlayerItem, player: AVQueuePlayer, mode: MonitorAssignment.LoopMode) {
        // Clean previous
        if let obs = endTimeObserver {
            NotificationCenter.default.removeObserver(obs)
            endTimeObserver = nil
        }

        endTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            switch mode {
            case .once:
                // Play to end → visually black the display (as documented in the model)
                player.pause()
                // Gentle fade to black instead of hard cut
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.6)
                self.playerLayer?.opacity = 0.0
                CATransaction.commit()

            case .bounce:
                // Reverse direction
                player.seek(to: .zero) { _ in
                    player.rate = -1.0   // play backwards
                }
                // When we hit the beginning while reversing, flip back to forward
                self.installReverseBoundaryFlip(player: player, item: item)

            case .loop:
                break // should never happen here
            }
        }
    }

    private func installReverseBoundaryFlip(player: AVQueuePlayer, item: AVPlayerItem) {
        // Remove any prior boundary observer for reverse
        // (We reuse the same pattern as loop crossfade observers)
        // For simplicity we add a time observer near t=0 while rate is negative.
        // Lightweight periodic check while reversing. We intentionally do *not* capture
        // the observer token inside the closure (would be declared-before-use error).
        // The timer is extremely short-lived and will be released after the flip.
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        _ = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let p = player, p.rate < 0 else { return }
            if time.seconds <= 0.05 {
                p.rate = 1.0
                // The observer will naturally be deallocated shortly after rate changes.
            }
        }
    }

    /// Runs an image slideshow on this display. The slideshow draws its own layers on the
    /// host layer; the video/image layers are hidden while it's active.
    public func loadSlideshow(items: [String], interval: Double, transition: MonitorAssignment.SlideshowTransition) {
        cleanup()
        guard let host = hostLayer ?? playerLayer?.superlayer else {
            print("[AVVideoRenderer] No host layer available for slideshow")
            return
        }
        mediaKind = .image           // image-like: power policy shouldn't drive the AVPlayer
        playerLayer?.isHidden = true
        imageLayer?.isHidden = true

        // SlideshowEngine is @MainActor; this renderer is documented main-thread-only.
        slideshow = MainActor.assumeIsolated {
            let engine = SlideshowEngine()
            engine.configure(items: items, interval: interval, transition: transition, hostLayer: host)
            return engine
        }
        loadedURL = items.first.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    /// Loads a static image (PNG/JPEG/HEIC…) or animated GIF via a CALayer, which is
    /// far cheaper than a video player and the only correct way to render these formats.
    private func loadImage(url: URL, kind: MediaType, autoPlay: Bool) {
        cleanup()
        mediaKind = kind
        currentURL = url
        loadedURL = url

        // Tear down the video layer's content but keep playerLayer attached for reuse;
        // just hide it so the image shows.
        playerLayer?.isHidden = true

        // Ensure an image layer exists, attached to the same superlayer as the video layer.
        guard let superlayer = playerLayer?.superlayer ?? hostLayer else {
            print("[AVVideoRenderer] No host layer available for image content")
            return
        }
        let layer = imageLayer ?? CALayer()
        if imageLayer == nil {
            layer.masksToBounds = true
            superlayer.addSublayer(layer)
            imageLayer = layer
        }
        layer.isHidden = false
        layer.frame = superlayer.bounds
        // Match the backing scale so the display-resolution image maps 1:1 (crisp on Retina).
        layer.contentsScale = superlayer.contentsScale

        if kind == .animatedImage {
            applyGIFAnimation(url: url, to: layer, autoPlay: autoPlay)
        } else {
            layer.removeAnimation(forKey: "gif")
            let maxPixel = targetMaxPixelSize()
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = Self.downsampledImage(source: source, index: 0, maxPixelSize: maxPixel) {
                layer.contents = cg
            } else if let image = NSImage(contentsOf: url),
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                layer.contents = cg   // fallback for anything ImageIO can't open
            } else {
                print("[AVVideoRenderer] Failed to decode image at \(url.path)")
            }
        }

        applyCurrentCrop()
    }

    /// The largest pixel dimension worth decoding for this display — the host layer's longest
    /// side in backing pixels. Decoding larger than this just wastes memory/bandwidth.
    private func targetMaxPixelSize() -> CGFloat {
        let layer = playerLayer?.superlayer ?? hostLayer
        let bounds = layer?.bounds ?? .zero
        let scale = layer?.contentsScale ?? 2.0
        let maxDim = max(bounds.width, bounds.height) * max(1, scale)
        return maxDim > 1 ? maxDim : 3840   // 4K fallback before the layer is laid out
    }

    /// Decodes a single image (or frame) downsampled so its longest side ≤ `maxPixelSize`.
    /// Never upscales beyond the source. Returns nil if decoding fails.
    static func downsampledImage(source: CGImageSource, index: Int, maxPixelSize: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded())
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// Decodes a GIF with ImageIO and drives it with a discrete keyframe animation on the
    /// layer's `contents` — native, hardware-composited, and very low power.
    private func applyGIFAnimation(url: URL, to layer: CALayer, autoPlay: Bool) {
        layer.removeAnimation(forKey: "gif")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(source)

        let maxPixel = targetMaxPixelSize()

        guard count > 1 else {
            if let cg = Self.downsampledImage(source: source, index: 0, maxPixelSize: maxPixel)
                     ?? CGImageSourceCreateImageAtIndex(source, 0, nil) {
                layer.contents = cg
            }
            return
        }

        // Decode every frame downsampled to display resolution — a large/high-res GIF would
        // otherwise hold every full-size frame in memory simultaneously.
        var frames: [CGImage] = []
        var delays: [Double] = []
        var total = 0.0
        for i in 0..<count {
            guard let cg = Self.downsampledImage(source: source, index: i, maxPixelSize: maxPixel)
                        ?? CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(cg)
            let delay = Self.gifFrameDelay(source: source, index: i)
            delays.append(delay)
            total += delay
        }
        guard !frames.isEmpty, total > 0 else { return }

        var keyTimes: [NSNumber] = []
        var acc = 0.0
        for delay in delays {
            keyTimes.append(NSNumber(value: acc / total))
            acc += delay
        }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = keyTimes
        animation.duration = total / max(0.05, userPlaybackSpeed)   // honor playback speed
        animation.repeatCount = .infinity
        animation.calculationMode = .discrete
        animation.isRemovedOnCompletion = false
        layer.contents = frames.last
        layer.add(animation, forKey: "gif")

        if !autoPlay { pauseLayerAnimation(layer) }
    }

    private static func gifFrameDelay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? 0.1
        // Browsers floor very short delays; match that so speed feels natural.
        return delay < 0.011 ? 0.1 : delay
    }

    // MARK: - CALayer animation pause/resume (for GIFs under power policy)

    private func pauseLayerAnimation(_ layer: CALayer) {
        guard layer.speed != 0 else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
    }

    private func resumeLayerAnimation(_ layer: CALayer) {
        guard layer.speed == 0 else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        layer.beginTime = timeSincePause
    }

    // MARK: - Private

    private func mapModelToRendererScaling(_ model: VideoScaling) -> VideoScaling {
        // Both enums have the same cases, so direct mapping
        switch model {
        case .fit:      return .fit
        case .fill:     return .fill
        case .stretch:  return .stretch
        }
    }

    private func effectiveRateForCurrentPolicy() -> Float? {
        switch currentPolicy {
        case .normal:
            // Use the user's chosen speed (default 1.0) when policy allows full playback
            return Float(userPlaybackSpeed)
        case .throttled(let fps):
            // Policy throttling takes priority over user speed for power saving
            return Float(max(0.25, min(1.0, Double(fps) / 60.0)))
        case .paused:
            return nil
        }
    }

    deinit {
        cleanup()
    }
}
