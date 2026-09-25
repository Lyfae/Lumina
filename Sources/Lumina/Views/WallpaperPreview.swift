import SwiftUI
import AppKit
import AVFoundation

/// A reusable, high-quality preview component for the Lumina Wallpaper Manager.
/// Shows a real thumbnail (or video frame) with the current crop, scaling, and aspect applied.
/// Designed to feel live and accurate so users understand exactly what will appear on their desktop.
struct WallpaperPreview: View {
    let assignment: MonitorAssignment?
    let liveCropRect: CGRect?          // Optional override for live editing
    let liveScaling: VideoScaling?     // Optional override for live editing
    let targetAspect: CGFloat          // e.g. 16/9 or the monitor's actual aspect

    /// When true, videos will play on loop instead of showing a static frame.
    /// GIFs will attempt to animate. Static images are unaffected.
    var isLivePlayback: Bool = false

    /// Only used when `isLivePlayback == false` (for the crop scrubber)
    var previewTime: Double? = nil

    /// When true, skip applying the outer aspectRatio modifier. Use when the caller
    /// is already forcing an exact frame size that matches the desired aspect
    /// (e.g. the full-source background inside CropRectangle).
    var ignoreAspectRatio: Bool = false

    /// When false, omit the black card chrome — used when embedded inside CropRectangle.
    var showsChrome: Bool = true

    // Live visual-effect overlays so the preview is true WYSIWYG (matches what "Apply to
    // Wallpaper" will push to the desktop). Defaults are no-ops.
    var brightness: Double = 0      // -0.5...0.5
    var previewOpacity: Double = 1  // 0...1
    var saturation: Double = 1      // 0...2
    var hueDegrees: Double = 0      // -180...180
    var grayscale: Bool = false
    var playbackSpeed: Double = 1.0

    @State private var thumbnail: NSImage?
    @State private var isLoading = false
    @State private var player: AVPlayer? = nil
    @State private var playerLooper: AVPlayerLooper? = nil
    @State private var scrubDurationSeconds: Double = 0

    private var effectiveCrop: CGRect {
        liveCropRect ?? assignment?.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private var effectiveScaling: VideoScaling {
        liveScaling ?? assignment?.scaling ?? .fill
    }

    /// Crop / Pick-a-frame mode: show a paused player and seek as the scrubber moves.
    private var isFrameScrubMode: Bool {
        !isLivePlayback && previewTime != nil && assignment?.mediaType == .video
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if showsChrome {
                    RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                        .fill(LuminaBrand.previewBackdrop)
                        .overlay(
                            RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                                .stroke(Color.luminaBorder, lineWidth: 1)
                        )
                }

                if let assign = assignment {
                    Group {
                        // Live video only for actual videos; images & GIFs use the thumbnail/image
                        // path so the preview shows the picture, never a stale video frame.
                        if isLivePlayback && assign.mediaType == .video {
                            liveVideoView(assignment: assign, size: geometry.size)
                        } else if isLivePlayback && assign.mediaType == .animatedImage {
                            liveGIFView(assignment: assign, size: geometry.size)
                        } else if isFrameScrubMode {
                            scrubVideoView(assignment: assign, size: geometry.size)
                        } else if let thumb = thumbnail {
                            thumbnailView(thumb, assignment: assign, size: geometry.size)
                        } else if isLoading {
                            LuminaLoadingView(label: "Loading preview…", onMedia: true)
                        } else {
                            LuminaLoadingView(label: "Loading preview…", onMedia: true)
                        }
                    }
                    // WYSIWYG effect overlays — mirror the per-monitor adjustments so the preview
                    // matches what gets pushed to the desktop on Apply.
                    .saturation(saturation)
                    .grayscale(grayscale ? 1 : 0)
                    .hueRotation(.degrees(hueDegrees))
                    .brightness(brightness)
                    .opacity(previewOpacity)
                } else {
                    LuminaEmptyState(icon: "display", title: "No wallpaper yet", compact: true)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .aspectRatioIfNeeded(targetAspect: targetAspect, ignore: ignoreAspectRatio)
        .onAppear {
            setupLivePlaybackIfNeeded()
            setupScrubPlayerIfNeeded()
            // Live looping AVPlayer covers video previews — skip a parallel thumbnail.
            // Live GIF uses NSImageView animation — skip a static thumbnail too.
            // Scrub mode still loads one as a placeholder until the first seek paints a frame.
            let liveMedia = isLivePlayback && (assignment?.mediaType == .video || assignment?.mediaType == .animatedImage)
            if !liveMedia {
                loadThumbnailIfNeeded()
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: assignment?.filePath) { _, _ in
            cleanupPlayer()
            thumbnail = nil
            scrubDurationSeconds = 0
            setupLivePlaybackIfNeeded()
            setupScrubPlayerIfNeeded()
            loadThumbnailIfNeeded()
        }
        .onChange(of: previewTime) { _, newValue in
            guard !(isLivePlayback && (assignment?.mediaType == .video || assignment?.mediaType == .animatedImage)) else { return }
            if isFrameScrubMode {
                setupScrubPlayerIfNeeded()
                seekScrubPlayer(to: newValue)
            } else {
                // Keep the previous frame visible while the next thumbnail loads.
                loadThumbnailIfNeeded(force: true)
            }
        }
    }

    @ViewBuilder
    private func thumbnailView(_ image: NSImage, assignment: MonitorAssignment, size: CGSize) -> some View {
        let mediaSize = mediaPixelSize(of: image)
        let layout = WallpaperGeometry.layout(
            mediaSize: mediaSize,
            displaySize: size,
            scaling: effectiveScaling,
            crop: effectiveCrop
        )
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: layout.mediaFrame.width, height: layout.mediaFrame.height)
            .offset(x: layout.mediaFrame.minX, y: layout.mediaFrame.minY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if showsChrome {
                    LuminaOverlayChip(text: assignment.displayName)
                        .padding(LuminaSpace.sm)
                        .accessibilityHidden(true)
                }
            }
    }

    private func mediaPixelSize(of image: NSImage) -> CGSize {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cg.width, height: cg.height)
        }
        return image.size
    }

    // MARK: - Live Video Playback

    @ViewBuilder
    private func liveVideoView(assignment: MonitorAssignment, size: CGSize) -> some View {
        if let player = player {
            PlayerLayerView(
                player: player,
                scaling: effectiveScaling,
                crop: effectiveCrop,
                playbackSpeed: playbackSpeed
            )
            .frame(width: size.width, height: size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
        } else {
            Color.black.opacity(0.7)
                .overlay(LuminaLoadingView(label: "Loading preview…", onMedia: true))
        }
    }

    @ViewBuilder
    private func liveGIFView(assignment: MonitorAssignment, size: CGSize) -> some View {
        let url = assignment.resolvedURL()
            ?? assignment.filePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        Group {
            if let url {
                MatchedMediaLayerView(
                    url: url,
                    scaling: effectiveScaling,
                    crop: effectiveCrop,
                    speed: playbackSpeed
                )
                .frame(width: size.width, height: size.height)
            } else {
                LuminaLoadingView(label: "Loading preview…", onMedia: true)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if showsChrome {
                LuminaOverlayChip(text: assignment.displayName)
                    .padding(LuminaSpace.sm)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Paused player that seeks with the frame scrubber — keeps the last frame visible
    /// while the next seek lands (no black flash).
    @ViewBuilder
    private func scrubVideoView(assignment: MonitorAssignment, size: CGSize) -> some View {
        ZStack {
            if let thumb = thumbnail {
                thumbnailView(thumb, assignment: assignment, size: size)
            }
            if let player {
                PlayerLayerView(
                    player: player,
                    scaling: effectiveScaling,
                    crop: effectiveCrop,
                    playbackSpeed: 0
                )
                .frame(width: size.width, height: size.height)
                .clipped()
            } else if thumbnail == nil {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if showsChrome {
                LuminaOverlayChip(text: assignment.displayName)
                    .padding(LuminaSpace.sm)
                    .accessibilityHidden(true)
            }
        }
    }

    private struct PlayerLayerView: NSViewRepresentable {
        let player: AVPlayer
        var scaling: VideoScaling = .fill
        var crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        var playbackSpeed: Double = 1

        func makeNSView(context: Context) -> PlayerHostingView {
            let view = PlayerHostingView()
            view.playerLayer.player = player
            view.scaling = scaling
            view.crop = crop
            view.wantsLayer = true
            applyRate()
            return view
        }

        func updateNSView(_ nsView: PlayerHostingView, context: Context) {
            nsView.playerLayer.player = player
            nsView.scaling = scaling
            nsView.crop = crop
            nsView.needsLayout = true
            applyRate()
        }

        private func applyRate() {
            guard playbackSpeed > 0 else {
                player.pause()
                return
            }
            player.rate = Float(max(0.25, min(4, playbackSpeed)))
        }

        static func dismantleNSView(_ nsView: PlayerHostingView, coordinator: ()) {
            nsView.playerLayer.player?.pause()
            nsView.playerLayer.player = nil
        }

        final class PlayerHostingView: NSView {
            let playerLayer = AVPlayerLayer()
            var scaling: VideoScaling = .fill
            var crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                wantsLayer = true
                layer = CALayer()
                layer?.masksToBounds = true
                layer?.addSublayer(playerLayer)
            }

            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func layout() {
                super.layout()
                let parent = bounds
                let isFull = abs(crop.minX) < 0.001 && abs(crop.minY) < 0.001
                    && abs(crop.width - 1) < 0.001 && abs(crop.height - 1) < 0.001
                if isFull || crop.width < 0.001 || crop.height < 0.001 {
                    playerLayer.frame = parent
                    switch scaling {
                    case .fit: playerLayer.videoGravity = .resizeAspect
                    case .fill: playerLayer.videoGravity = .resizeAspectFill
                    case .stretch: playerLayer.videoGravity = .resize
                    }
                } else {
                    playerLayer.frame = WallpaperGeometry.expandedFrame(parent: parent, crop: crop)
                    playerLayer.videoGravity = .resizeAspectFill
                }
            }
        }
    }

    /// Same CALayer gravity + contentsRect + speed path the desktop uses for image/GIF.
    private struct MatchedMediaLayerView: NSViewRepresentable {
        let url: URL
        let scaling: VideoScaling
        let crop: CGRect
        let speed: Double

        func makeNSView(context: Context) -> HostView {
            let view = HostView()
            view.wantsLayer = true
            view.layer = CALayer()
            view.layer?.backgroundColor = NSColor.black.cgColor
            view.layer?.masksToBounds = true
            view.renderer.install(into: view)
            context.coordinator.apply(url: url, scaling: scaling, crop: crop, speed: speed, to: view)
            return view
        }

        func updateNSView(_ nsView: HostView, context: Context) {
            context.coordinator.apply(url: url, scaling: scaling, crop: crop, speed: speed, to: nsView)
            nsView.renderer.relayout()
        }

        static func dismantleNSView(_ nsView: HostView, coordinator: Coordinator) {
            nsView.renderer.cleanup()
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class HostView: NSView {
            let renderer = AVVideoRenderer()
            override func layout() {
                super.layout()
                renderer.relayout()
            }
        }

        final class Coordinator {
            var loadedPath: String?

            func apply(url: URL, scaling: VideoScaling, crop: CGRect, speed: Double, to view: HostView) {
                if loadedPath != url.path {
                    loadedPath = url.path
                    view.renderer.load(url: url, autoPlay: true)
                }
                let mapped: AVVideoRenderer.VideoScaling
                switch scaling {
                case .fit: mapped = .fit
                case .fill: mapped = .fill
                case .stretch: mapped = .stretch
                }
                view.renderer.setScaling(mapped)
                view.renderer.setCropRect(crop)
                view.renderer.setPlaybackSpeed(speed)
                view.renderer.play()
            }
        }
    }

    private func setupLivePlaybackIfNeeded() {
        guard isLivePlayback,
              let assign = assignment,
              assign.mediaType == .video,
              player == nil else { return }

        guard let url = assign.resolvedURL() ?? (assign.filePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }) else {
            return
        }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true

        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.rate = Float(max(0.25, min(4, playbackSpeed)))

        self.player = queuePlayer
        self.playerLooper = looper
    }

    /// Paused AVPlayer for crop-mode frame scrubbing. Seeking is far more responsive than
    /// regenerating an AVAssetImageGenerator thumbnail on every slider tick.
    private func setupScrubPlayerIfNeeded() {
        guard isFrameScrubMode, player == nil else { return }
        guard let assign = assignment else { return }
        guard let url = assign.resolvedURL() ?? (assign.filePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }) else {
            return
        }

        let item = AVPlayerItem(url: url)
        let scrubPlayer = AVPlayer(playerItem: item)
        scrubPlayer.isMuted = true
        scrubPlayer.pause()

        self.player = scrubPlayer
        self.playerLooper = nil

        Task {
            let duration = (try? await item.asset.load(.duration))?.seconds ?? 0
            await MainActor.run {
                guard self.player === scrubPlayer else { return }
                self.scrubDurationSeconds = max(0, duration)
                self.seekScrubPlayer(to: self.previewTime)
            }
        }
    }

    private func seekScrubPlayer(to normalized: Double?) {
        guard let player, let normalized, scrubDurationSeconds > 0.05 else { return }
        let clamped = max(0.0, min(1.0, normalized))
        let seconds = scrubDurationSeconds * clamped
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.04, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func cleanupPlayer() {
        playerLooper?.disableLooping()
        player?.pause()
        player = nil
        playerLooper = nil
        scrubDurationSeconds = 0
    }

    private func loadThumbnailIfNeeded(force: Bool = false) {
        guard let assign = assignment else { return }
        if !force {
            guard thumbnail == nil, !isLoading else { return }
        }

        isLoading = true

        // Prefer resolved + security-scoped URL so AVAssetImageGenerator can open the file
        let url = assign.resolvedURL() ?? {
            if let path = assign.filePath {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            }
            return nil
        }()

        guard let url else {
            isLoading = false
            return
        }

        let mediaType = assign.mediaType
        let previewTimeCopy = previewTime

        let expectedPath = assign.filePath
        Task { [url, mediaType, previewTimeCopy] in
            let loadedImage = await ThumbnailService.shared.thumbnail(
                for: url,
                mediaType: mediaType,
                maxSize: CGSize(width: 640, height: 360),
                previewTime: previewTimeCopy
            )

            await MainActor.run {
                // Unstructured Task survives view identity changes — drop stale results if
                // the user switched to a different file while this decode was in flight.
                guard self.assignment?.filePath == expectedPath else { return }
                self.thumbnail = loadedImage
                self.isLoading = false
            }
        }
    }
}


private extension View {
    @ViewBuilder
    func aspectRatioIfNeeded(targetAspect: CGFloat, ignore: Bool) -> some View {
        if ignore {
            self
        } else {
            self.aspectRatio(targetAspect, contentMode: .fit)
        }
    }
}
