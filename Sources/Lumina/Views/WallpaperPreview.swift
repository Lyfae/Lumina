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

    @State private var thumbnail: NSImage?
    @State private var isLoading = false
    @State private var player: AVPlayer? = nil
    @State private var playerLooper: AVPlayerLooper? = nil

    private var effectiveCrop: CGRect {
        liveCropRect ?? assignment?.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private var effectiveScaling: VideoScaling {
        liveScaling ?? assignment?.scaling ?? .fill
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    )

                if let assign = assignment {
                    if isLivePlayback && assign.mediaType == .video {
                        liveVideoView(assignment: assign, size: geometry.size)
                    } else if let thumb = thumbnail {
                        thumbnailView(thumb, assignment: assign, size: geometry.size)
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                            Text("Generating preview…")
                                .font(.caption)
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 36))
                        Text("No wallpaper assigned")
                            .font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .aspectRatio(targetAspect, contentMode: .fit)
        .onAppear {
            setupLivePlaybackIfNeeded()
            loadThumbnailIfNeeded()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: assignment?.filePath) { _, _ in
            cleanupPlayer()
            thumbnail = nil
            setupLivePlaybackIfNeeded()
            loadThumbnailIfNeeded()
        }
        .onChange(of: effectiveCrop) { _, _ in
            // Crop changes are visual only — no need to reload
        }
    }

    @ViewBuilder
    private func thumbnailView(_ image: NSImage, assignment: MonitorAssignment, size: CGSize) -> some View {
        let mediaType = assignment.mediaType
        let scaling = effectiveScaling

        GeometryReader { geo in
            let containerSize = geo.size

            Group {
                if scaling == .stretch {
                    // Stretch: fill the frame with distortion (no aspectRatio constraint)
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: containerSize.width, height: containerSize.height)
                } else if scaling == .fill {
                    // Fill: fill entire frame, crop any overflow (matches AVLayerVideoGravity.resizeAspectFill)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: containerSize.width, height: containerSize.height)
                        .clipped()
                } else {
                    // Fit: show full image with letterbox/pillarbox (matches AVLayerVideoGravity.resizeAspect)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: containerSize.width, height: containerSize.height)
                }
            }
            .overlay(cropOverlay(size: containerSize))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                let icon = mediaType == .video ? "play.rectangle.fill" :
                           mediaType == .animatedImage ? "photo.stack.fill" : "photo.fill"
                Image(systemName: icon)
                    .font(.caption2)
                Text(assignment.displayName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
            .foregroundStyle(.white)
        }
    }

    // MARK: - Live Video Playback

    @ViewBuilder
    private func liveVideoView(assignment: MonitorAssignment, size: CGSize) -> some View {
        if let player = player {
            PlayerLayerView(player: player)
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(cropOverlay(size: size))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Color.black.opacity(0.7)
                .overlay(ProgressView().tint(.white))
        }
    }

    /// Draws a semi-transparent dim outside the crop region and a clean accent-color border
    /// around it. Uses Canvas with even-odd fill so the crop area is a true hole in the overlay.
    @ViewBuilder
    private func cropOverlay(size: CGSize) -> some View {
        let crop = effectiveCrop
        let isFullCrop = abs(crop.minX) < 0.001 && abs(crop.minY) < 0.001
                      && abs(crop.width - 1) < 0.001 && abs(crop.height - 1) < 0.001

        if !isFullCrop {
            Canvas { context, canvasSize in
                let cx = crop.minX * canvasSize.width
                let cy = crop.minY * canvasSize.height
                let cw = crop.width  * canvasSize.width
                let ch = crop.height * canvasSize.height
                let cropRect = CGRect(x: cx, y: cy, width: cw, height: ch)

                // Dim everything outside the crop using even-odd rule (hole = no fill inside crop)
                var dimPath = Path()
                dimPath.addRect(CGRect(origin: .zero, size: canvasSize))
                dimPath.addRoundedRect(in: cropRect, cornerSize: CGSize(width: 3, height: 3))
                context.fill(dimPath, with: .color(.black.opacity(0.45)),
                             style: FillStyle(eoFill: true))

                // Bright border on the crop region
                context.stroke(
                    Path(roundedRect: cropRect, cornerSize: CGSize(width: 3, height: 3)),
                    with: .color(Color.accentColor.opacity(0.95)),
                    style: StrokeStyle(lineWidth: 2.5)
                )
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    /// Lightweight NSViewRepresentable that hosts an AVPlayerLayer.
    /// This avoids pulling in AVPlayerView (the cause of the "VideoPlayerView" demangle crash in .accessory apps).
    private struct PlayerLayerView: NSViewRepresentable {
        let player: AVPlayer

        func makeNSView(context: Context) -> PlayerHostingView {
            let view = PlayerHostingView()
            view.playerLayer.player = player
            view.wantsLayer = true
            return view
        }

        func updateNSView(_ nsView: PlayerHostingView, context: Context) {
            nsView.playerLayer.player = player
        }

        final class PlayerHostingView: NSView {
            let playerLayer = AVPlayerLayer()

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                wantsLayer = true
                layer = CALayer()
                layer?.addSublayer(playerLayer)
            }

            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func layout() {
                super.layout()
                playerLayer.frame = bounds
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
        queuePlayer.isMuted = true   // Previews in manager should be silent

        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.play()

        self.player = queuePlayer
        self.playerLooper = looper
    }

    private func cleanupPlayer() {
        player?.pause()
        player = nil
        playerLooper = nil
    }

    private func loadThumbnailIfNeeded() {
        guard let assign = assignment,
              thumbnail == nil,
              !isLoading else { return }

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

        // Use Task (not detached) so the closure is main-actor-isolated: avoids the
        // #SendingClosureRisksDataRace entirely. Inside the task we use nonisolated(unsafe)
        // copy of the captured mediaType before the cross-actor call. This is safe for the
        // immutable enum and breaks the isolation-region tracking for the send.
        Task { [url, mediaType, previewTimeCopy] in
            nonisolated(unsafe) let sendableMediaType = mediaType
            let loadedImage = await ThumbnailService.shared.thumbnail(
                for: url,
                mediaType: sendableMediaType,
                maxSize: CGSize(width: 640, height: 360),
                previewTime: previewTimeCopy
            )

            await MainActor.run {
                self.thumbnail = loadedImage
                self.isLoading = false
            }
        }
    }
}
