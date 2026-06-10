import AppKit
import AVFoundation

/// Manages image slideshow cycling for a single monitor.
/// Uses a timer to advance slides and a crossfade CAAnimation for smooth transitions.
/// Optional Ken Burns effect applies a slow cinematic pan/zoom to each still image.
@MainActor
final class SlideshowEngine {
    private var imagePaths: [String] = []
    private var interval: Double = 10
    private var transition: MonitorAssignment.SlideshowTransition = .fade
    private var kenBurnsEnabled: Bool = true
    private var currentIndex: Int = 0
    private var timer: Timer?
    private weak var hostLayer: CALayer?

    private var currentImageLayer: CALayer?
    private var slideShownAt: Date?
    private var pauseStartedAt: Date?
    private var pendingRemoval: DispatchWorkItem?
    private var isPaused = false

    /// Exposed for headless self-test validation of Ken Burns wiring.
    var hasActiveKenBurnsAnimation: Bool {
        currentImageLayer?.animation(forKey: "kenBurns") != nil
    }

    func configure(assignment: MonitorAssignment, hostLayer: CALayer) {
        configure(items: assignment.slideshowItems,
                  interval: assignment.slideshowInterval,
                  transition: assignment.slideshowTransition,
                  kenBurnsEnabled: assignment.slideshowKenBurnsEnabled,
                  hostLayer: hostLayer)
    }

    /// Direct configuration used by the renderer (no MonitorAssignment needed).
    func configure(items: [String],
                   interval: Double,
                   transition: MonitorAssignment.SlideshowTransition,
                   kenBurnsEnabled: Bool = true,
                   hostLayer: CALayer) {
        self.imagePaths   = items
        self.interval     = max(1, interval)
        self.transition   = transition
        self.kenBurnsEnabled = kenBurnsEnabled
        self.hostLayer    = hostLayer
        self.currentIndex = 0
        hostLayer.masksToBounds = true
        start()
    }

    /// Stops the slideshow and removes its layer from the host (full teardown).
    func teardown() {
        stop()
        cancelPendingRemoval()
        currentImageLayer?.removeFromSuperlayer()
        currentImageLayer = nil
        hostLayer = nil
        imagePaths = []
        slideShownAt = nil
        pauseStartedAt = nil
        isPaused = false
    }

    /// Resizes the current slide to match a new host-layer bounds (display reconfiguration).
    func relayout() {
        guard let host = hostLayer else { return }
        currentImageLayer?.frame = host.bounds
        currentImageLayer?.position = CGPoint(x: host.bounds.midX, y: host.bounds.midY)

        guard let layer = currentImageLayer else { return }
        if kenBurnsEnabled {
            let elapsed = currentSlideElapsed()
            let progress = slideProgress(forElapsed: elapsed)
            let remaining = max(0.1, interval - elapsed)
            applyKenBurns(to: layer, hostBounds: host.bounds, slideIndex: currentIndex,
                          duration: remaining, startProgress: progress)
            if isPaused { pauseKenBurns() }
        } else {
            layer.removeAnimation(forKey: "kenBurns")
            layer.transform = CATransform3DIdentity
        }
    }

    /// Full start — shows the current slide and begins the advance timer.
    func start() {
        isPaused = false
        cancelPendingRemoval()
        invalidateTimer()
        guard !imagePaths.isEmpty, let host = hostLayer else { return }

        showImage(at: currentIndex, in: host, animated: false)
        scheduleAdvanceTimer()
    }

    /// Stops only the advance timer (used by teardown and pending-removal cleanup).
    func stop() {
        invalidateTimer()
        cancelPendingRemoval()
    }

    /// Pauses slide advancement and the active Ken Burns animation (power-policy path).
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pauseStartedAt = Date()
        invalidateTimer()
        pauseKenBurns()
    }

    /// Resumes slide advancement and Ken Burns without restarting from slide 0.
    /// No-op when already running — avoids resetting the advance timer on routine
    /// `applyPolicy` calls that re-apply a non-paused policy.
    func resume() {
        guard isPaused else { return }
        guard !imagePaths.isEmpty, hostLayer != nil else { return }
        if let pauseStartedAt, let shownAt = slideShownAt {
            slideShownAt = shownAt.addingTimeInterval(Date().timeIntervalSince(pauseStartedAt))
        }
        pauseStartedAt = nil
        isPaused = false
        resumeKenBurns()
        scheduleAdvanceTimer()
    }

    /// Live toggle — updates Ken Burns on the current slide without a full slideshow restart.
    func setKenBurnsEnabled(_ enabled: Bool) {
        guard kenBurnsEnabled != enabled else { return }
        kenBurnsEnabled = enabled
        guard let host = hostLayer, let layer = currentImageLayer else { return }

        if enabled {
            let elapsed = currentSlideElapsed()
            let progress = slideProgress(forElapsed: elapsed)
            let remaining = max(0.1, interval - elapsed)
            applyKenBurns(to: layer, hostBounds: host.bounds, slideIndex: currentIndex,
                          duration: remaining, startProgress: progress)
            if isPaused { pauseKenBurns() }
        } else {
            layer.removeAnimation(forKey: "kenBurns")
            resetLayerAnimationState(layer)
            layer.transform = CATransform3DIdentity
        }
    }

    private func scheduleAdvanceTimer() {
        invalidateTimer()
        guard !imagePaths.isEmpty else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advance() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func cancelPendingRemoval() {
        pendingRemoval?.cancel()
        pendingRemoval = nil
    }

    private func advance() {
        guard !imagePaths.isEmpty, let host = hostLayer else { return }
        currentIndex = (currentIndex + 1) % imagePaths.count
        showImage(at: currentIndex, in: host, animated: transition == .fade)
    }

    private func showImage(at index: Int, in host: CALayer, animated: Bool) {
        guard index < imagePaths.count else { return }
        let path = (imagePaths[index] as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        // Decode at display resolution to avoid holding full-size photos in memory.
        let maxDim = max(host.bounds.width, host.bounds.height) * max(1, host.contentsScale)
        let maxPixel = maxDim > 1 ? maxDim : 3840
        guard let cgImage = CGImageSourceCreateWithURL(url as CFURL, nil)
                .flatMap({ AVVideoRenderer.downsampledImage(source: $0, index: 0, maxPixelSize: maxPixel) })
                ?? NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let newLayer = CALayer()
        newLayer.contents = cgImage
        newLayer.contentsGravity = .resizeAspectFill
        newLayer.frame = host.bounds
        newLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        newLayer.position = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
        host.addSublayer(newLayer)

        slideShownAt = Date()
        pauseStartedAt = nil

        if kenBurnsEnabled {
            applyKenBurns(to: newLayer, hostBounds: host.bounds, slideIndex: index, duration: interval)
        }

        if animated {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue   = 1.0
            fade.duration  = min(1.5, interval * 0.3)
            newLayer.opacity = 1.0
            newLayer.add(fade, forKey: "fadeIn")
        }

        // Remove the old layer after transition (cancel any prior pending removal first).
        cancelPendingRemoval()
        let old = currentImageLayer
        let delay = animated ? min(1.5, interval * 0.3) : 0
        if delay == 0 {
            old?.removeFromSuperlayer()
        } else {
            let work = DispatchWorkItem { [weak old] in old?.removeFromSuperlayer() }
            pendingRemoval = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        currentImageLayer = newLayer
    }

    private func currentSlideElapsed() -> TimeInterval {
        guard let slideShownAt else { return 0 }
        let now = Date()
        let pausedDuration: TimeInterval
        if isPaused, let pauseStartedAt {
            pausedDuration = now.timeIntervalSince(pauseStartedAt)
        } else {
            pausedDuration = 0
        }
        return max(0, now.timeIntervalSince(slideShownAt) - pausedDuration)
    }

    private func slideProgress(forElapsed elapsed: TimeInterval) -> CGFloat {
        min(1, max(0, CGFloat(elapsed / interval)))
    }

    // MARK: - Ken Burns

    private struct KenBurnsVariant {
        let startScale: CGFloat
        let endScale: CGFloat
        let startPan: CGPoint
        let endPan: CGPoint
    }

    private func kenBurnsVariant(for slideIndex: Int) -> KenBurnsVariant {
        switch slideIndex % 4 {
        case 0:
            return KenBurnsVariant(startScale: 1.0, endScale: 1.12,
                                   startPan: CGPoint(x: -0.05, y: 0), endPan: CGPoint(x: 0.05, y: 0))
        case 1:
            return KenBurnsVariant(startScale: 1.0, endScale: 1.10,
                                   startPan: CGPoint(x: 0, y: -0.04), endPan: CGPoint(x: 0, y: 0.04))
        case 2:
            return KenBurnsVariant(startScale: 1.0, endScale: 1.11,
                                   startPan: CGPoint(x: 0.05, y: 0.02), endPan: CGPoint(x: -0.05, y: -0.02))
        default:
            return KenBurnsVariant(startScale: 1.10, endScale: 1.0,
                                   startPan: CGPoint(x: 0.03, y: -0.02), endPan: CGPoint(x: -0.03, y: 0.02))
        }
    }

    private func makeTransform(scale: CGFloat, pan: CGPoint, hostBounds: CGRect) -> CATransform3D {
        let w = hostBounds.width
        let h = hostBounds.height
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, pan.x * w * 0.5, pan.y * h * 0.5, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return t
    }

    private func transform(for variant: KenBurnsVariant, progress: CGFloat, hostBounds: CGRect) -> CATransform3D {
        let p = min(1, max(0, progress))
        let scale = variant.startScale + (variant.endScale - variant.startScale) * p
        let pan = CGPoint(
            x: variant.startPan.x + (variant.endPan.x - variant.startPan.x) * p,
            y: variant.startPan.y + (variant.endPan.y - variant.startPan.y) * p
        )
        return makeTransform(scale: scale, pan: pan, hostBounds: hostBounds)
    }

    /// Applies a slow pan/zoom animation to a slide. Each slide picks a deterministic
    /// variant so the motion feels varied but repeatable across loops.
    private func applyKenBurns(to layer: CALayer,
                               hostBounds: CGRect,
                               slideIndex: Int,
                               duration: TimeInterval,
                               startProgress: CGFloat = 0) {
        layer.removeAnimation(forKey: "kenBurns")
        resetLayerAnimationState(layer)

        guard hostBounds.width > 0, hostBounds.height > 0 else { return }

        let variant = kenBurnsVariant(for: slideIndex)
        let from = transform(for: variant, progress: startProgress, hostBounds: hostBounds)
        let to   = transform(for: variant, progress: 1, hostBounds: hostBounds)

        if startProgress >= 1 || duration <= 0 {
            layer.transform = to
            return
        }

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = from
        anim.toValue   = to
        anim.duration  = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        layer.transform = from
        layer.add(anim, forKey: "kenBurns")
        layer.transform = to
    }

    private func pauseKenBurns() {
        guard let layer = currentImageLayer, layer.animation(forKey: "kenBurns") != nil else { return }
        guard layer.speed != 0 else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
    }

    private func resumeKenBurns() {
        guard let layer = currentImageLayer, layer.animation(forKey: "kenBurns") != nil else { return }
        guard layer.speed == 0 else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        layer.beginTime = timeSincePause
    }

    private func resetLayerAnimationState(_ layer: CALayer) {
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
    }
}
