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
    private var currentSize: NSSize = DisplayScale.musicWidgetSize

    private override init() {
        super.init()
    }

    func show() {
        let isNew = panel == nil
        if isNew {
            panel = makePanel()
            currentSize = DisplayScale.musicWidgetSize
        }
        guard let panel else { return }
        // Don't collapse an already-open queue — only seed size for a fresh panel.
        if isNew {
            syncPanelSize(panel, size: currentSize)
        }
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

    func setContentSize(width: CGFloat, height: CGFloat) {
        let size = NSSize(width: width, height: height)
        guard abs(currentSize.width - size.width) > 0.5
                || abs(currentSize.height - size.height) > 0.5 else { return }
        currentSize = size
        guard let panel else { return }
        syncPanelSize(panel, size: size)
    }

    private func makePanel() -> NSPanel {
        let size = currentSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        // Dragging is handled by an explicit gesture so it can't steal from the scrubber.
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Lumina Music"
        self.panel = panel
        refreshHostingView()
        return panel
    }

    private func refreshHostingView() {
        guard let panel else { return }
        let size = currentSize
        let host = NSHostingView(rootView: NowPlayingWidgetView(
            onClose: { [weak self] in self?.hide() },
            onSizeChange: { [weak self] size in
                self?.setContentSize(width: size.width, height: size.height)
            }
        ))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    /// Resize with the top edge locked (macOS origin is bottom-left).
    private func syncPanelSize(_ panel: NSPanel, size: NSSize) {
        guard abs(panel.frame.width - size.width) > 0.5
                || abs(panel.frame.height - size.height) > 0.5 else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        panel.contentView?.setFrameSize(size)
        panel.setFrame(frame, display: true)
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

/// Fixed-size compact bar. Art tile and live waveform carry the visual weight;
/// transport, volume and queue fade in on hover so idle chrome stays minimal.
struct NowPlayingWidgetView: View {
    var onClose: () -> Void = {}
    var onSizeChange: (CGSize) -> Void = { _ in }

    @ObservedObject private var audio = AmbientAudioManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var isHovering: Bool = false
    @State private var showQueue: Bool = false
    /// Non-nil while the edge scrubber is being dragged — drives the elapsed readout.
    @State private var scrubPreview: Double? = nil

    private var accent: Color { theme.current.color }
    private var hasTrack: Bool { audio.trackURL != nil }

    private var contentWidth: CGFloat { DisplayScale.points(288) }
    private var contentHeight: CGFloat { DisplayScale.points(140) }
    private var sidePad: CGFloat { DisplayScale.points(12) }
    private var artSide: CGFloat { DisplayScale.points(56) }
    /// Waveform scrubber band — always visible, always the seek target.
    private var waveHeight: CGFloat { DisplayScale.points(30) }
    /// Reserved band for hover controls, so revealing them never resizes the card.
    private var controlsHeight: CGFloat { DisplayScale.points(24) }
    private var queueRowHeight: CGFloat { DisplayScale.points(24) }

    /// Header label + rows + the padding the list sits in.
    private var queueHeight: CGFloat {
        guard showQueue, !upcomingTracks.isEmpty else { return 0 }
        let gap = DisplayScale.points(2)
        let label = DisplayScale.points(12)
        let rows = CGFloat(upcomingTracks.count) * queueRowHeight
        let gaps = CGFloat(upcomingTracks.count) * gap // label→first + between rows
        return label + gaps + rows + DisplayScale.points(8)
    }

    private var cardHeight: CGFloat { contentHeight + queueHeight }

    private static let hoverAnimation = Animation.easeOut(duration: 0.16)

    private var upcomingTracks: [AmbientAudioManager.AudioTrack] {
        guard !audio.library.isEmpty else { return [] }
        guard let current = audio.trackURL,
              let idx = audio.library.firstIndex(where: { $0.url == current }) else {
            return Array(audio.library.prefix(3))
        }
        var result: [AmbientAudioManager.AudioTrack] = []
        for offset in 1..<audio.library.count {
            result.append(audio.library[(idx + offset) % audio.library.count])
            if result.count >= 3 { break }
        }
        return result
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: DisplayScale.points(14), style: .continuous)

        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, sidePad)
                .padding(.top, DisplayScale.points(12))

            Spacer(minLength: DisplayScale.points(6))

            waveformRow
                .frame(height: waveHeight)
                .padding(.horizontal, sidePad)

            if showQueue, !upcomingTracks.isEmpty {
                upNextList
                    .padding(.horizontal, sidePad)
                    .padding(.top, DisplayScale.points(6))
                    .transition(.opacity)
            }

            controlsRow
                .frame(height: controlsHeight)
                .padding(.horizontal, sidePad)
                .padding(.bottom, DisplayScale.points(10))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .frame(width: contentWidth, height: cardHeight, alignment: .top)
        .background(Color.luminaCard, in: cardShape)
        .overlay(cardShape.strokeBorder(Color.luminaBorder.opacity(0.9), lineWidth: 1))
        .clipShape(cardShape)
        .onHover { hovering in
            withAnimation(Self.hoverAnimation) {
                isHovering = hovering
                // Leaving the card closes the queue so the panel can't be left oversized.
                if !hovering { showQueue = false }
            }
        }
        .onAppear {
            onSizeChange(CGSize(width: contentWidth, height: cardHeight))
        }
        .onChange(of: cardHeight) { _, height in
            onSizeChange(CGSize(width: contentWidth, height: height))
        }
    }

    // MARK: Header — art, title, play

    private var headerRow: some View {
        HStack(spacing: DisplayScale.points(12)) {
            albumArt
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: DisplayScale.points(3)) {
                Text(hasTrack ? audio.trackTitle : "Nothing playing")
                    .font(.system(size: DisplayScale.points(14), weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitleLine)
                    .font(.system(size: DisplayScale.points(11)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)

            playButton
        }
        // The art + title block doubles as the drag handle for the whole panel.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .help("Drag to move")
        )
        .frame(height: artSide)
    }

    private var playButton: some View {
        Button {
            audio.toggle()
        } label: {
            ZStack {
                Circle().fill(accent.opacity(hasTrack ? 0.16 : 0.08))
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: DisplayScale.points(13), weight: .bold))
                    .foregroundStyle(hasTrack ? accent : Color.primary.opacity(0.3))
            }
            .frame(width: DisplayScale.points(34), height: DisplayScale.points(34))
            .contentShape(Circle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .disabled(!hasTrack)
        .help(audio.isPlaying ? "Pause" : "Play")
        .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
    }

    private var albumArt: some View {
        let shape = RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
        return ZStack {
            shape.fill(
                LinearGradient(
                    colors: [accent.opacity(0.9), accent.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            if let art = audio.trackArtwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: DisplayScale.points(20), weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: artSide, height: artSide)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
        .accessibilityLabel(audio.trackArtwork == nil ? "No artwork" : "Album artwork")
    }

    // MARK: Waveform — doubles as the timeline

    private var waveformRow: some View {
        HStack(spacing: DisplayScale.points(8)) {
            Text(formatTime(scrubPreview ?? audio.currentTime))
                .font(.system(size: DisplayScale.points(10), weight: .medium).monospacedDigit())
                .foregroundStyle(scrubPreview == nil ? Color.secondary : accent)

            WaveformScrubber(
                levels: audio.meterLevels,
                currentTime: audio.currentTime,
                duration: max(audio.duration, 0),
                accent: accent,
                isPlaying: audio.isPlaying,
                preview: $scrubPreview,
                onSeek: { audio.seekToTime($0) }
            )

            Text(formatTime(audio.duration))
                .font(.system(size: DisplayScale.points(10), weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: DisplayScale.points(2)) {
            quietButton(
                "shuffle",
                help: audio.shuffle ? "Shuffle on" : "Shuffle off",
                active: audio.shuffle,
                disabled: audio.library.count < 2
            ) {
                audio.setShuffle(!audio.shuffle)
            }

            quietButton("backward.end.fill", help: "Previous", disabled: audio.library.count < 2) {
                audio.previousTrack()
            }

            quietButton("forward.end.fill", help: "Next", disabled: audio.library.count < 2) {
                audio.nextTrack()
            }

            quietButton("repeat", help: audio.loops ? "Loop on" : "Loop off", active: audio.loops) {
                audio.setLoops(!audio.loops)
            }

            Image(systemName: audio.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: DisplayScale.points(9), weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, DisplayScale.points(2))

            Slider(
                value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }),
                in: 0...1
            )
            .controlSize(.mini)
            .tint(accent)
            .frame(width: DisplayScale.points(56))
            .help("Volume")

            quietButton(
                "list.bullet",
                help: showQueue ? "Hide Up Next" : "Show Up Next",
                active: showQueue,
                disabled: upcomingTracks.isEmpty
            ) {
                withAnimation(Self.hoverAnimation) { showQueue.toggle() }
            }

            quietButton("plus", help: "Add Track") {
                audio.chooseTrack()
            }

            quietButton("xmark", help: "Hide widget", action: onClose)
        }
    }

    /// Rendered inside the card — the panel grows by `queueHeight` while it's open.
    private var upNextList: some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(2)) {
            Text("Up Next")
                .font(.system(size: DisplayScale.points(9), weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)

            ForEach(Array(upcomingTracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    let wasPlaying = audio.isPlaying
                    audio.selectTrack(track)
                    if wasPlaying { audio.play() }
                    withAnimation(Self.hoverAnimation) { showQueue = false }
                } label: {
                    HStack(spacing: DisplayScale.points(6)) {
                        Text("\(index + 1)")
                            .font(.system(size: DisplayScale.points(9), weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: DisplayScale.points(10), alignment: .trailing)
                        Text(track.title)
                            .font(.system(size: DisplayScale.points(11), weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DisplayScale.points(6))
                    .frame(height: queueRowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: DisplayScale.points(6), style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(LuminaPressableButtonStyle())
                .help("Play \(track.title)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitleLine: String {
        if !hasTrack { return "Lumina Ambient" }
        if !audio.trackArtist.isEmpty { return audio.trackArtist }
        if !audio.trackAlbum.isEmpty { return audio.trackAlbum }
        return "Lumina Ambient"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func quietButton(
        _ symbol: String,
        help: String,
        active: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: DisplayScale.points(10), weight: .semibold))
                .foregroundStyle(active ? accent : Color.primary.opacity(0.5))
                .frame(width: DisplayScale.points(22), height: DisplayScale.points(24))
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.28 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Waveform scrubber

/// Live meter bars that double as the track timeline: bars left of the playhead
/// are filled, the rest are dimmed. Hovering reveals a draggable thumb.
private struct WaveformScrubber: View {
    let levels: [CGFloat]
    let currentTime: Double
    let duration: Double
    let accent: Color
    let isPlaying: Bool
    @Binding var preview: Double?
    var onSeek: (Double) -> Void

    @State private var isHovered = false

    private var barCount: Int { 32 }
    private var displayTime: Double { preview ?? currentTime }
    private var showThumb: Bool { isHovered || preview != nil }

    private var fraction: CGFloat {
        guard duration > 0, duration.isFinite, displayTime.isFinite else { return 0 }
        return CGFloat(min(1, max(0, displayTime / duration)))
    }

    private var displayLevels: [CGFloat] {
        guard !levels.isEmpty else { return Array(repeating: 0.12, count: barCount) }
        if levels.count == barCount { return levels }
        return (0..<barCount).map { i in
            let src = Int(Double(i) / Double(max(barCount - 1, 1)) * Double(levels.count - 1))
            return levels[min(levels.count - 1, max(0, src))]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = geo.size.height
            let playhead = width * fraction
            let thumb = DisplayScale.points(12)

            ZStack(alignment: .leading) {
                bars(height: height, playedWidth: playhead, totalWidth: width)

                if showThumb {
                    Circle()
                        .fill(Color.luminaCard)
                        .overlay(Circle().strokeBorder(accent, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                        .frame(width: thumb, height: thumb)
                        .offset(x: max(0, min(width - thumb, playhead - thumb / 2)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        preview = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        defer { preview = nil }
                        guard duration > 0 else { return }
                        onSeek(time(at: value.location.x, width: width))
                    }
            )
            .help(duration > 0 ? "Click or drag to scrub" : "No track loaded")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Track position")
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = max(1, duration * 0.05)
            switch direction {
            case .increment: onSeek(min(duration, currentTime + step))
            case .decrement: onSeek(max(0, currentTime - step))
            @unknown default: break
            }
        }
    }

    /// Bars are drawn once and masked twice so played/unplayed share exact geometry.
    private func bars(height: CGFloat, playedWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let shape = barStack(height: height)
        return ZStack(alignment: .leading) {
            shape
                .foregroundStyle(accent.opacity(0.22))

            shape
                .foregroundStyle(accent.opacity(isPlaying ? 0.95 : 0.6))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: playedWidth)
                }
        }
        .frame(width: totalWidth, height: height)
        .animation(.easeOut(duration: 0.07), value: displayLevels)
    }

    private func barStack(height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: DisplayScale.points(2)) {
            ForEach(Array(displayLevels.enumerated()), id: \.offset) { _, level in
                Capsule(style: .continuous)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(DisplayScale.points(2), level * height))
            }
        }
        .frame(height: height)
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        Double(min(1, max(0, x / max(width, 1)))) * duration
    }
}
