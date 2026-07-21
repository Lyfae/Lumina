import SwiftUI
import AppKit

/// Floating always-on-top mini-player for Lumina ambient audio.
/// Open from the Studio footer, or automatically when Studio is minimized
/// (if "Show music widget when minimized" is on).
@MainActor
final class NowPlayingWidgetController: NSObject, ObservableObject {
    static let shared = NowPlayingWidgetController()

    @Published private(set) var isVisible: Bool = false

    private var panel: NSPanel?
    private var panelSize: NSSize { DisplayScale.musicWidgetSize }

    private override init() {
        super.init()
    }

    /// Brings the widget on screen, creating it on first use and parking it in the
    /// top-right corner of the main display (only on first show).
    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.isMovableByWindowBackground = false
        syncPanelSize(panel)
        if !panel.isVisible {
            positionInTopRight(panel)
        }
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    private func makePanel() -> NSPanel {
        let size = panelSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // Scrubbing the timeline must not drag the panel — move via WindowDragGesture in the view.
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Lumina Music"

        let host = NSHostingView(rootView: NowPlayingWidgetView(onClose: { [weak self] in
            self?.hide()
        }))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    private func syncPanelSize(_ panel: NSPanel) {
        let size = panelSize
        guard abs(panel.frame.width - size.width) > 0.5
                || abs(panel.frame.height - size.height) > 0.5 else { return }
        var frame = panel.frame
        frame.size = size
        panel.setFrame(frame, display: false)
        panel.contentView?.setFrameSize(size)
    }

    private func positionInTopRight(_ panel: NSPanel) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - DisplayScale.points(20),
            y: visible.maxY - size.height - DisplayScale.points(20)
        ))
    }
}

// MARK: - Widget View

/// Compact desktop mini-player: art + metadata, scrubber, then a centered transport cluster.
struct NowPlayingWidgetView: View {
    var onClose: () -> Void = {}

    @StateObject private var audio = AmbientAudioManager.shared
    @StateObject private var theme = ThemeManager.shared
    @State private var scrubTime: Double? = nil

    private var accent: Color { theme.current.color }
    private var hasTrack: Bool { audio.trackURL != nil }

    var body: some View {
        VStack(spacing: DisplayScale.points(10)) {
            headerRow
                .gesture(WindowDragGesture())

            scrubber

            transportCluster
                .gesture(WindowDragGesture())
        }
        .padding(.horizontal, DisplayScale.points(14))
        .padding(.vertical, DisplayScale.points(12))
        .frame(width: DisplayScale.points(340), height: DisplayScale.points(148), alignment: .center)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(DisplayScale.points(8))
        // Empty chrome (padding / gaps) can still drag the widget.
        .gesture(WindowDragGesture())
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous)
                .fill(Color(white: 0.12))
            // Soft accent wash from the art corner — keeps the card from feeling flat.
            RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
        }
    }

    // MARK: Header — art + titles + close

    private var headerRow: some View {
        HStack(alignment: .center, spacing: DisplayScale.points(12)) {
            albumArt

            VStack(alignment: .leading, spacing: DisplayScale.points(2)) {
                Text(hasTrack ? audio.trackTitle : "Nothing playing")
                    .font(.system(size: DisplayScale.points(13), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitleLine)
                    .font(.system(size: DisplayScale.points(11), weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: DisplayScale.points(9), weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: DisplayScale.points(22), height: DisplayScale.points(22))
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .help("Hide widget")
            .accessibilityLabel("Hide widget")
        }
    }

    private var albumArt: some View {
        let side = DisplayScale.points(48)
        return ZStack {
            RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.95), accent.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let art = audio.trackArtwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: audio.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: DisplayScale.points(18), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .symbolEffect(.variableColor.iterative, isActive: audio.isPlaying)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    private var subtitleLine: String {
        if !hasTrack { return "Lumina Ambient" }
        if !audio.trackArtist.isEmpty, !audio.trackAlbum.isEmpty {
            return "\(audio.trackArtist) · \(audio.trackAlbum)"
        }
        if !audio.trackArtist.isEmpty { return audio.trackArtist }
        if !audio.trackAlbum.isEmpty { return audio.trackAlbum }
        return "Lumina Ambient"
    }

    // MARK: Scrubber

    private var scrubber: some View {
        let display = scrubTime ?? audio.currentTime
        return VStack(spacing: DisplayScale.points(4)) {
            GeometryReader { geo in
                let fraction = audio.duration > 0 ? min(1, max(0, display / audio.duration)) : 0
                let trackH = DisplayScale.points(4)
                let thumb = DisplayScale.points(10)
                let x = geo.size.width * CGFloat(fraction)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: trackH)
                    Capsule()
                        .fill(accent)
                        .frame(width: max(trackH, x), height: trackH)
                    Circle()
                        .fill(.white)
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .scaleEffect(scrubTime == nil ? 1 : 1.15)
                        .offset(x: max(0, x - thumb / 2))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                // highPriority so timeline scrub wins over the card's WindowDragGesture.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard audio.duration > 0 else { return }
                            let f = Double(min(1, max(0, value.location.x / max(geo.size.width, 1))))
                            scrubTime = f * audio.duration
                        }
                        .onEnded { value in
                            guard audio.duration > 0 else { scrubTime = nil; return }
                            let f = Double(min(1, max(0, value.location.x / max(geo.size.width, 1))))
                            audio.seekToTime(f * audio.duration)
                            scrubTime = nil
                        }
                )
            }
            .frame(height: DisplayScale.points(16))

            HStack {
                Text(timeString(display))
                Spacer()
                Text(timeString(audio.duration))
            }
            .font(.system(size: DisplayScale.points(10), weight: .medium).monospacedDigit())
            .foregroundStyle(scrubTime == nil ? Color.white.opacity(0.4) : accent)
        }
    }

    // MARK: Transport — one centered cluster

    private var transportCluster: some View {
        HStack(spacing: 0) {
            sideButton(
                "repeat",
                active: audio.loops,
                help: audio.loops ? "Looping on" : "Looping off"
            ) {
                audio.setLoops(!audio.loops)
            }

            Spacer(minLength: 0)

            HStack(spacing: DisplayScale.points(6)) {
                sideButton("backward.end.fill", help: "Previous") {
                    audio.previousTrack()
                }
                .disabled(audio.library.count < 2)
                .opacity(audio.library.count < 2 ? 0.35 : 1)

                Button { audio.toggle() } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: DisplayScale.points(14), weight: .bold))
                        .foregroundStyle(Color(white: 0.12))
                        .offset(x: audio.isPlaying ? 0 : 1) // optically center the play triangle
                        .frame(width: DisplayScale.points(36), height: DisplayScale.points(36))
                        .background(Circle().fill(.white))
                }
                .buttonStyle(LuminaPressableButtonStyle())
                .disabled(!hasTrack)
                .opacity(hasTrack ? 1 : 0.4)
                .help(audio.isPlaying ? "Pause" : "Play")
                .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")

                sideButton("forward.end.fill", help: "Next") {
                    audio.nextTrack()
                }
                .disabled(audio.library.count < 2)
                .opacity(audio.library.count < 2 ? 0.35 : 1)
            }

            Spacer(minLength: 0)

            sideButton("plus", help: "Add tracks") {
                audio.chooseTrack()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sideButton(
        _ symbol: String,
        active: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: DisplayScale.points(12), weight: .semibold))
                .foregroundStyle(active ? accent : Color.white.opacity(0.8))
                .frame(width: DisplayScale.points(28), height: DisplayScale.points(28))
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
