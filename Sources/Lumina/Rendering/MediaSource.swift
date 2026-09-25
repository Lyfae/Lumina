// Lumina/Rendering/MediaSource — dumb sources (one decode) that fan out to N layers.
import AppKit
import AVFoundation
import QuartzCore
import LuminaCore

@MainActor
protocol MediaSource: AnyObject {
    var key: SourceKey { get }
    func makeLayer() -> CALayer
    func releaseLayer(_ layer: CALayer)
    func retune(_ spec: SourcePlan)
    func retime(to newKey: SourceKey, plan: SourcePlan)
    func setRunning(_ running: Bool)
    func restart(atHostTime: CMTime, layerBeginTime: CFTimeInterval)
    var onLoopBoundaryApproaching: ((_ secondsUntilLoop: Double) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func teardown()
    func playbackHealthSnapshot() -> PlaybackHealthSnapshot
    /// Underlying player for secondary AVPlayerLayers (video only).
    var sharedPlayer: AVQueuePlayer? { get }
    /// Latest frame for surface-level freeze when a consumer pauses while others play.
    func snapshotImage() -> CGImage?
}

/// One AVQueuePlayer fan-out. Frame caps never change `rate` — only variants / optional FramePump.
@MainActor
final class VideoSource: MediaSource {
    private(set) var key: SourceKey
    private let renderer = AVVideoRenderer()
    private var extraLayers: [AVPlayerLayer] = []
    private var pump: FramePump?
    private var pumpLayers: [CALayer] = []
    private var experimentalRenderCap = false
    private var currentItem: AVPlayerItem?
    var onLoopBoundaryApproaching: ((Double) -> Void)?
    var onFailure: ((String) -> Void)? {
        get { nil }
        set {
            renderer.onLoadFailure = { _, error in
                newValue?(error?.localizedDescription ?? "Load failed")
            }
        }
    }

    var sharedPlayer: AVQueuePlayer? { renderer.exposePlayer() }

    init(spec: SourcePlan, experimentalRenderCap: Bool = false) {
        self.key = spec.key
        self.experimentalRenderCap = experimentalRenderCap
        load(spec)
    }

    func makeLayer() -> CALayer {
        if let pump, experimentalRenderCap {
            let layer = CALayer()
            layer.contentsGravity = .resizeAspectFill
            pump.add(layer)
            pumpLayers.append(layer)
            return layer
        }
        if let player = sharedPlayer {
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            extraLayers.append(layer)
            return layer
        }
        return CALayer()
    }

    func installPrimary(into view: NSView) {
        view.wantsLayer = true
        renderer.install(into: view)
    }

    func releaseLayer(_ layer: CALayer) {
        extraLayers.removeAll { $0 === layer }
        pumpLayers.removeAll { $0 === layer }
        pump?.remove(layer)
        layer.removeFromSuperlayer()
        if let pl = layer as? AVPlayerLayer {
            pl.player = nil
        }
    }

    func retune(_ spec: SourcePlan) {
        renderer.setMuted(spec.audio.muted)
        renderer.setVolume(spec.audio.volume)
        // GIF / slideshow presentation caps — never AVPlayer.rate.
        renderer.setPresentationMaxFPS(spec.budget.maxFPS)

        if case let .video(_, timing) = spec.key {
            switch timing {
            case .playing(let speed, let loop):
                renderer.setPlaybackSpeed(speed)
                renderer.setLoopMode(loop)
            case .frozen, .scrub:
                renderer.pause()
            }
        }

        applyBudget(spec.budget)
        swapVariantIfNeeded(spec)
    }

    func retime(to newKey: SourceKey, plan: SourcePlan) {
        key = newKey
        retune(plan)
    }

    func setRunning(_ running: Bool) {
        if running { renderer.play() } else { renderer.pause() }
        if running { pump?.start() } else { pump?.stop() }
    }

    func restart(atHostTime: CMTime, layerBeginTime: CFTimeInterval) {
        renderer.restartInSync(videoHostTime: atHostTime, layerBeginTime: layerBeginTime)
    }

    func teardown() {
        for layer in extraLayers + pumpLayers { releaseLayer(layer) }
        pump?.teardown(item: currentItem)
        pump = nil
        renderer.cleanup()
    }

    func playbackHealthSnapshot() -> PlaybackHealthSnapshot {
        renderer.playbackHealthSnapshot()
    }

    func snapshotImage() -> CGImage? {
        guard let player = sharedPlayer,
              let item = player.currentItem else { return nil }
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = player.currentTime()
        return copyVideoFrame(with: generator, at: time)
    }

    func setExperimentalRenderCap(_ enabled: Bool) {
        experimentalRenderCap = enabled
    }

    private func load(_ spec: SourcePlan) {
        let url = URL(fileURLWithPath: spec.variant.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            onFailure?("Media missing")
            return
        }
        renderer.load(url: url, autoPlay: false)
        currentItem = sharedPlayer?.currentItem
        retune(spec)
        if let start = spec.startFrame {
            renderer.applyVideoFrame(normalizedTime: start, useStatic: false)
        }
    }

    private func swapVariantIfNeeded(_ spec: SourcePlan) {
        let path = spec.variant.path
        guard let loaded = renderer.loadedURL?.path, loaded != path,
              FileManager.default.fileExists(atPath: path) else { return }
        let time = renderer.currentPlaybackTime()
        let duration = renderer.currentItemDuration()
        renderer.load(url: URL(fileURLWithPath: path), autoPlay: false)
        currentItem = sharedPlayer?.currentItem
        if duration > 0 {
            let normalized = (time / duration).truncatingRemainder(dividingBy: 1)
            renderer.applyVideoFrame(normalizedTime: normalized, useStatic: false)
        }
        applyBudget(spec.budget)
    }

    /// `.renderCap` uses FramePump only when the experimental preference is on.
    /// Otherwise video caps are variants/decode targets only (no AVPlayer.rate, no composition).
    private func applyBudget(_ budget: FrameBudget) {
        pump?.teardown(item: currentItem)
        pump = nil
        guard experimentalRenderCap,
              budget.enforcement == .renderCap,
              let maxFPS = budget.maxFPS,
              let item = sharedPlayer?.currentItem
        else { return }
        currentItem = item
        let framePump = FramePump(item: item, maxFPS: maxFPS)
        for layer in pumpLayers { framePump.add(layer) }
        framePump.start()
        pump = framePump
    }
}

/// Still image or a single video frame (`.frozen(at:)` → AVAssetImageGenerator, no paused player).
@MainActor
final class StillImageSource: MediaSource {
    private(set) var key: SourceKey
    private var layers: [CALayer] = []
    private var image: CGImage?
    private var decodedTarget: PixelSize?
    var onLoopBoundaryApproaching: ((Double) -> Void)?
    var onFailure: ((String) -> Void)?
    var sharedPlayer: AVQueuePlayer? { nil }

    init(spec: SourcePlan) {
        self.key = spec.key
        load(spec)
    }

    func installPrimary(into view: NSView) {
        view.wantsLayer = true
        guard let host = view.layer else { return }
        let layer = makeLayer()
        layer.frame = host.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        host.addSublayer(layer)
    }

    func makeLayer() -> CALayer {
        let layer = CALayer()
        layer.contentsGravity = .resizeAspectFill
        layer.contents = image
        layers.append(layer)
        return layer
    }

    func releaseLayer(_ layer: CALayer) {
        layers.removeAll { $0 === layer }
        layer.removeFromSuperlayer()
    }

    func retune(_ spec: SourcePlan) {
        let grew: Bool = {
            guard let current = decodedTarget, let next = spec.decodeTarget else {
                return spec.decodeTarget != nil && decodedTarget == nil
            }
            return next.longestSide > current.longestSide
        }()
        if grew || image == nil || spec.variant.path != currentPath {
            load(spec)
        }
    }

    func retime(to newKey: SourceKey, plan: SourcePlan) {
        key = newKey
        retune(plan)
    }

    func setRunning(_ running: Bool) { _ = running }
    func restart(atHostTime: CMTime, layerBeginTime: CFTimeInterval) {}
    func teardown() {
        for layer in layers { releaseLayer(layer) }
        image = nil
    }

    func playbackHealthSnapshot() -> PlaybackHealthSnapshot {
        PlaybackHealthSnapshot(isActiveVideo: false, isStruggling: false, filename: (currentPath as NSString).lastPathComponent)
    }

    func snapshotImage() -> CGImage? { image }

    private var currentPath: String = ""

    private func load(_ spec: SourcePlan) {
        currentPath = spec.variant.path
        decodedTarget = spec.decodeTarget
        let url = URL(fileURLWithPath: spec.variant.path)
        let maxPixel = CGFloat(spec.decodeTarget?.longestSide ?? 3840)

        switch spec.key {
        case .video(_, .frozen(let at)):
            Task { await self.loadVideoFrame(url: url, normalizedTime: at, maxPixel: maxPixel) }
        case .still, .video, .animated, .slideshow:
            Task { await self.loadStill(url: url, maxPixel: maxPixel) }
        }
    }

    private func loadStill(url: URL, maxPixel: CGFloat) async {
        let cg: CGImage? = await Task.detached(priority: .userInitiated) {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                return AVVideoRenderer.downsampledImage(source: source, index: 0, maxPixelSize: maxPixel)
            }
            return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }.value
        await MainActor.run {
            guard url.path == self.currentPath else { return }
            if let cg {
                self.image = cg
                for layer in self.layers { layer.contents = cg }
            } else {
                self.onFailure?("Failed to decode image")
            }
        }
    }

    private func loadVideoFrame(url: URL, normalizedTime: Double, maxPixel: CGFloat) async {
        let cg: CGImage? = await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let duration = (try? await asset.load(.duration)) ?? .zero
            let seconds = max(0, min(1, normalizedTime)) * (duration.seconds.isFinite ? duration.seconds : 0)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            return copyVideoFrame(with: generator, at: time)
        }.value
        await MainActor.run {
            guard url.path == self.currentPath else { return }
            if let cg {
                self.image = cg
                for layer in self.layers { layer.contents = cg }
            } else {
                self.onFailure?("Failed to extract video frame")
            }
        }
    }
}

@MainActor
final class AnimatedImageSource: MediaSource {
    private(set) var key: SourceKey
    private let renderer = AVVideoRenderer()
    private var mediaPath: String
    private var didLoad = false
    var onLoopBoundaryApproaching: ((Double) -> Void)?
    var onFailure: ((String) -> Void)?
    var sharedPlayer: AVQueuePlayer? { nil }

    init(spec: SourcePlan) {
        self.key = spec.key
        self.mediaPath = spec.variant.path
        retune(spec)
    }

    func installPrimary(into view: NSView) {
        view.wantsLayer = true
        renderer.install(into: view)
        if !didLoad {
            didLoad = true
            renderer.load(url: URL(fileURLWithPath: mediaPath), autoPlay: false)
        }
    }

    func makeLayer() -> CALayer { CALayer() }
    func releaseLayer(_ layer: CALayer) { layer.removeFromSuperlayer() }
    func retune(_ spec: SourcePlan) {
        mediaPath = spec.variant.path
        if case let .animated(_, speed) = spec.key {
            renderer.setPlaybackSpeed(speed)
        }
        renderer.setPresentationMaxFPS(spec.budget.maxFPS)
        if didLoad, renderer.loadedURL?.path != mediaPath {
            renderer.load(url: URL(fileURLWithPath: mediaPath), autoPlay: false)
        }
    }
    func retime(to newKey: SourceKey, plan: SourcePlan) { key = newKey; retune(plan) }
    func setRunning(_ running: Bool) { if running { renderer.play() } else { renderer.pause() } }
    func restart(atHostTime: CMTime, layerBeginTime: CFTimeInterval) {
        renderer.restartInSync(videoHostTime: atHostTime, layerBeginTime: layerBeginTime)
    }
    func teardown() { renderer.cleanup() }
    func playbackHealthSnapshot() -> PlaybackHealthSnapshot {
        renderer.playbackHealthSnapshot()
    }
    func snapshotImage() -> CGImage? { nil }

    nonisolated static func decimate(delays: [Double], maxFPS: Int?) -> [(index: Int, delay: Double)] {
        FrameDecimation.decimate(delays: delays, maxFPS: maxFPS)
    }
}

@MainActor
final class SlideshowSource: MediaSource {
    private(set) var key: SourceKey
    private let renderer = AVVideoRenderer()
    var onLoopBoundaryApproaching: ((Double) -> Void)?
    var onFailure: ((String) -> Void)?
    var sharedPlayer: AVQueuePlayer? { nil }

    init(spec: SourcePlan) {
        self.key = spec.key
        if case let .slideshow(s) = spec.key {
            let items = s.items.map(\.identity.path)
            renderer.loadSlideshow(
                items: items,
                interval: s.interval,
                transition: s.transition,
                kenBurnsEnabled: s.kenBurns
            )
        }
        retune(spec)
    }

    func installPrimary(into view: NSView) {
        view.wantsLayer = true
        renderer.install(into: view)
    }

    func makeLayer() -> CALayer { CALayer() }
    func releaseLayer(_ layer: CALayer) { layer.removeFromSuperlayer() }
    func retune(_ spec: SourcePlan) {
        renderer.setPresentationMaxFPS(spec.budget.maxFPS)
    }
    func retime(to newKey: SourceKey, plan: SourcePlan) { key = newKey; retune(plan) }
    func setRunning(_ running: Bool) { if running { renderer.play() } else { renderer.pause() } }
    func restart(atHostTime: CMTime, layerBeginTime: CFTimeInterval) {}
    func teardown() { renderer.cleanup() }
    func playbackHealthSnapshot() -> PlaybackHealthSnapshot {
        renderer.playbackHealthSnapshot()
    }
    func snapshotImage() -> CGImage? { nil }
}

// MARK: - Surfaces

@MainActor
class Surface {
    let host: CALayer
    private(set) var attached: (source: any MediaSource, layer: CALayer)?
    private var look: SurfaceLook?
    private var primaryHostView: NSView?
    private var freezeOverlay: CALayer?
    private var lastBoundKey: SourceKey?
    private var lastCrossfade: Double = 0

    init(host: CALayer, primaryHostView: NSView? = nil) {
        self.host = host
        self.primaryHostView = primaryHostView
    }

    func attach(_ source: any MediaSource, crossfade: Double, asPrimary: Bool = true) {
        clearFreezeOverlay()
        detach()
        lastBoundKey = source.key
        lastCrossfade = crossfade
        if asPrimary, let view = primaryHostView {
            if let video = source as? VideoSource {
                video.installPrimary(into: view)
            } else if let still = source as? StillImageSource {
                still.installPrimary(into: view)
            } else if let anim = source as? AnimatedImageSource {
                anim.installPrimary(into: view)
            } else if let slide = source as? SlideshowSource {
                slide.installPrimary(into: view)
            }
            attached = (source, host)
        } else {
            let layer = source.makeLayer()
            layer.frame = host.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            host.addSublayer(layer)
            attached = (source, layer)
        }
        if crossfade > 0 {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0
            anim.toValue = 1
            anim.duration = crossfade
            (attached?.layer ?? host).add(anim, forKey: "crossfade")
        }
        if let look { setLook(look) }
    }

    func detach() {
        if let attached {
            if attached.layer !== host {
                attached.source.releaseLayer(attached.layer)
            }
        }
        self.attached = nil
    }

    func setLook(_ look: SurfaceLook) {
        self.look = look
        let crop = CGRect(x: look.crop.x, y: look.crop.y, width: look.crop.width, height: look.crop.height)
        if let video = attached?.source as? VideoSource {
            video.applyLook(look, crop: crop)
        } else if let still = attached?.source as? StillImageSource {
            still.applyLook(look, crop: crop)
        } else if let anim = attached?.source as? AnimatedImageSource {
            anim.applyLook(look, crop: crop)
        }
        SurfaceLayer.apply(look: look, to: attached?.layer ?? host, brightnessOverlay: nil)
    }

    /// Paused-while-others-play: snapshot freeze + detach live layer so shared sources keep running.
    /// `.covered` leaves the live layer attached (WindowServer skips occluded windows).
    func setRun(_ run: SurfaceRun) {
        switch run {
        case .playing:
            if freezeOverlay != nil, let key = lastBoundKey, let source = attached?.source, source.key == key {
                clearFreezeOverlay()
            } else if freezeOverlay != nil {
                // Will be reattached by a subsequent bind; clear overlay only.
                clearFreezeOverlay()
            }
        case .paused(let reasons):
            if reasons.contains(.covered) { return }
            freezeWithSnapshot()
        case .idle:
            clearFreezeOverlay()
            detach()
        }
    }

    func setGeometry(_ geometry: SurfaceGeometry) {
        if let frame = geometry.frame, let window = (self as? DesktopSurface)?.window {
            window.updateFrame(to: frame)
        }
    }

    func showFailure(_ message: String?) { _ = message }
    func teardown() {
        clearFreezeOverlay()
        detach()
        if let desktop = self as? DesktopSurface {
            desktop.window.hideAndRelease()
        }
    }

    private func freezeWithSnapshot() {
        guard freezeOverlay == nil else { return }
        let image = attached?.source.snapshotImage()
        let overlay = CALayer()
        overlay.frame = host.bounds
        overlay.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        overlay.contentsGravity = .resizeAspectFill
        overlay.contents = image
        host.addSublayer(overlay)
        freezeOverlay = overlay
        // Detach live layer without tearing down the shared source.
        if let attached, attached.layer !== host {
            attached.source.releaseLayer(attached.layer)
        }
        // Keep source reference for reattach metadata, but drop live layer.
        if let source = attached?.source {
            self.attached = (source, overlay)
        }
    }

    private func clearFreezeOverlay() {
        freezeOverlay?.removeFromSuperlayer()
        freezeOverlay = nil
    }
}

@MainActor
final class DesktopSurface: Surface {
    let window: DesktopWallpaperWindow
    let displayKey: DisplayKey
    let runtimeID: UInt32

    init(screen: NSScreen, displayKey: DisplayKey, runtimeID: UInt32) {
        self.window = DesktopWallpaperWindow(screen: screen)
        self.displayKey = displayKey
        self.runtimeID = runtimeID
        window.showOnDesktop()
        let host = window.contentView?.layer ?? CALayer()
        window.contentView?.wantsLayer = true
        super.init(host: host, primaryHostView: window.contentView)
    }
}

@MainActor
final class PreviewSurface: Surface {
    init(hostView: NSView) {
        hostView.wantsLayer = true
        super.init(host: hostView.layer ?? CALayer(), primaryHostView: hostView)
    }
}

// Look helpers on sources that wrap AVVideoRenderer
extension VideoSource {
    func applyLook(_ look: SurfaceLook, crop: CGRect) {
        let scaling: AVVideoRenderer.VideoScaling
        switch look.scaling {
        case .fit: scaling = .fit
        case .fill: scaling = .fill
        case .stretch: scaling = .stretch
        }
        renderer.setScaling(scaling)
        renderer.applyCropRect(crop)
        renderer.setBrightness(look.brightness)
        renderer.setOpacity(look.opacity)
        renderer.setColorCorrection(saturation: look.saturation, hue: look.hue, grayscale: look.grayscale)
        renderer.setLoopFade(enabled: look.loopFade.enabled, duration: look.loopFade.duration, easing: look.loopFade.easing)
        let gravity: AVLayerVideoGravity = {
            switch look.scaling {
            case .fit: return .resizeAspect
            case .fill: return .resizeAspectFill
            case .stretch: return .resize
            }
        }()
        for layer in extraLayers {
            layer.videoGravity = gravity
        }
    }
}

extension StillImageSource {
    func applyLook(_ look: SurfaceLook, crop: CGRect) {
        for layer in layers {
            layer.contentsGravity = look.scaling == .fit ? .resizeAspect
                : look.scaling == .stretch ? .resize : .resizeAspectFill
            layer.contentsRect = WallpaperGeometry.contentsRect(crop: crop)
            layer.opacity = Float(look.opacity)
        }
    }
}

extension AnimatedImageSource {
    func applyLook(_ look: SurfaceLook, crop: CGRect) {
        let scaling: AVVideoRenderer.VideoScaling
        switch look.scaling {
        case .fit: scaling = .fit
        case .fill: scaling = .fill
        case .stretch: scaling = .stretch
        }
        renderer.setScaling(scaling)
        renderer.applyCropRect(crop)
        renderer.setBrightness(look.brightness)
        renderer.setOpacity(look.opacity)
        renderer.setColorCorrection(saturation: look.saturation, hue: look.hue, grayscale: look.grayscale)
    }
}

/// One frame from a video, off the deprecated synchronous generator API.
private func copyVideoFrame(with generator: AVAssetImageGenerator, at time: CMTime) -> CGImage? {
    final class Box: @unchecked Sendable { var image: CGImage? }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    generator.generateCGImageAsynchronously(for: time) { image, _, _ in
        box.image = image
        done.signal()
    }
    done.wait()
    return box.image
}
