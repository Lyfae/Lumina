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

    /// Brings the widget on screen, creating it on first use and parking it in the
    /// top-right corner of the main display (only on first show).
    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.isMovableByWindowBackground = false
        syncPanelSize(panel, size: currentSize, anchorTop: true)
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

    /// Grows/shrinks the panel when Up Next expands — keeps the top edge anchored.
    func setContentSize(width: CGFloat, height: CGFloat) {
        let size = NSSize(width: width, height: height)
        currentSize = size
        guard let panel else { return }
        syncPanelSize(panel, size: size, anchorTop: true)
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
        panel.hasShadow = true
        panel.level = .floating
        // Scrubbing / volume must not drag the panel — move via WindowDragGesture in the view.
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Lumina Music"

        let host = NSHostingView(rootView: NowPlayingWidgetView(
            onClose: { [weak self] in self?.hide() },
            onSizeChange: { [weak self] size in
                self?.setContentSize(width: size.width, height: size.height)
            }
        ))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    private func syncPanelSize(_ panel: NSPanel, size: NSSize, anchorTop: Bool) {
        guard abs(panel.frame.width - size.width) > 0.5
                || abs(panel.frame.height - size.height) > 0.5 else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        if anchorTop {
            frame.origin.y = top - size.height
        }
        panel.setFrame(frame, display: true)
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

/// Compact desktop mini-player: art + metadata, scrubber, transport, horizontal volume,
/// and a collapsible Up Next queue.
struct NowPlayingWidgetView: View {
    var onClose: () -> Void = {}
    var onSizeChange: (CGSize) -> Void = { _ in }

    @StateObject private var audio = AmbientAudioManager.shared
    @StateObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrubTime: Double? = nil
    @State private var showQueue: Bool = false

    private var accent: Color { theme.current.color }
    private var hasTrack: Bool { audio.trackURL != nil }
    private var isDark: Bool { colorScheme == .dark }

    private var contentWidth: CGFloat { DisplayScale.points(340) }
    private var chromePadding: CGFloat { DisplayScale.points(16) } // outer padding × 2

    private var upcomingTracks: [AmbientAudioManager.AudioTrack] {
        guard !audio.library.isEmpty else { return [] }
        guard let current = audio.trackURL,
              let idx = audio.library.firstIndex(where: { $0.url == current }) else {
            return Array(audio.library.prefix(4))
        }
        var result: [AmbientAudioManager.AudioTrack] = []
        for offset in 1..<audio.library.count {
            result.append(audio.library[(idx + offset) % audio.library.count])
            if result.count >= 4 { break }
        }
        return result
    }

    private var panelHeight: CGFloat {
        var h = DisplayScale.points(162) // header + scrubber + transport + volume row
        if !upcomingTracks.isEmpty {
            h += DisplayScale.points(40) // divider + Up Next collapse bar
            if showQueue {
                h += CGFloat(upcomingTracks.count) * DisplayScale.points(36) + DisplayScale.points(8)
            }
        }
        return h + chromePadding
    }

    var body: some View {
        VStack(spacing: DisplayScale.points(8)) {
            headerRow
                .gesture(WindowDragGesture())
            scrubber
            transportCluster
            volumeAndAddRow

            if !upcomingTracks.isEmpty {
                upNextSection
            }
        }
        .padding(.horizontal, DisplayScale.points(14))
        .padding(.vertical, DisplayScale.points(12))
        .frame(width: contentWidth, alignment: .top)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isDark ? 0.45 : 0.18), radius: 18, y: 8)
        .padding(DisplayScale.points(8))
        .frame(width: contentWidth + chromePadding, height: panelHeight, alignment: .top)
        .gesture(WindowDragGesture())
        .onAppear { publishSize() }
        .onChange(of: showQueue) { _, _ in publishSize() }
        .onChange(of: upcomingTracks.count) { _, _ in publishSize() }
    }

    private func publishSize() {
        onSizeChange(CGSize(
            width: contentWidth + chromePadding,
            height: panelHeight
        ))
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous)
                .fill(isDark ? Color(white: 0.14) : Color(white: 0.97))
            RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(isDark ? 0.22 : 0.12), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
        }
    }

    private var primaryText: Color { isDark ? .white : Color(white: 0.12) }
    private var secondaryText: Color {
        isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: DisplayScale.points(12)) {
            albumArt

            VStack(alignment: .leading, spacing: DisplayScale.points(2)) {
                Text(hasTrack ? audio.trackTitle : "Nothing playing")
                    .font(.system(size: DisplayScale.points(13), weight: .semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitleLine)
                    .font(.system(size: DisplayScale.points(11), weight: .medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: DisplayScale.points(9), weight: .bold))
                    .foregroundStyle(secondaryText)
                    .frame(width: DisplayScale.points(22), height: DisplayScale.points(22))
                    .background(Circle().fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .help("Hide widget")
            .accessibilityLabel("Hide widget")
        }
    }

    private var albumArt: some View {
        let side = DisplayScale.points(44)
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
                    .font(.system(size: DisplayScale.points(16), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .symbolEffect(.variableColor.iterative, isActive: audio.isPlaying)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
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
        return VStack(spacing: DisplayScale.points(3)) {
            GeometryReader { geo in
                let fraction = audio.duration > 0 ? min(1, max(0, display / audio.duration)) : 0
                let trackH = DisplayScale.points(4)
                let thumb = DisplayScale.points(10)
                let x = geo.size.width * CGFloat(fraction)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.1))
                        .frame(height: trackH)
                    Capsule()
                        .fill(accent)
                        .frame(width: max(trackH, x), height: trackH)
                    Circle()
                        .fill(isDark ? Color.white : Color.luminaCard)
                        .overlay(
                            Circle().strokeBorder(accent.opacity(0.85), lineWidth: isDark ? 0 : 1.5)
                        )
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .scaleEffect(scrubTime == nil ? 1 : 1.15)
                        .offset(x: max(0, x - thumb / 2))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
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
                .help(scrubTime.map { "Release to seek to \(timeString($0))" }
                      ?? "Click or drag to scrub — time previews as you move")
            }
            .frame(height: DisplayScale.points(14))

            HStack {
                Text(timeString(display))
                Spacer()
                Text(timeString(audio.duration))
            }
            .font(.system(size: DisplayScale.points(10), weight: .medium).monospacedDigit())
            .foregroundStyle(scrubTime == nil ? secondaryText : accent)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Track position")
        .accessibilityValue(timeString(display))
        .accessibilityAdjustableAction { direction in
            guard audio.duration > 0 else { return }
            let step = max(1, audio.duration * 0.05)
            switch direction {
            case .increment: audio.seekToTime(min(audio.duration, audio.currentTime + step))
            case .decrement: audio.seekToTime(max(0, audio.currentTime - step))
            @unknown default: break
            }
        }
    }

    // MARK: Transport

    private var transportCluster: some View {
        HStack(spacing: DisplayScale.points(2)) {
            sideButton(
                "repeat",
                active: audio.loops,
                help: audio.loops ? "Looping on" : "Looping off"
            ) {
                audio.setLoops(!audio.loops)
            }

            sideButton("backward.end.fill", help: "Previous") {
                audio.previousTrack()
            }
            .disabled(audio.library.count < 2)
            .opacity(audio.library.count < 2 ? 0.35 : 1)

            sideButton("gobackward.10", help: "Skip back 10 seconds") {
                audio.seek(by: -10)
            }
            .disabled(!hasTrack)
            .opacity(hasTrack ? 1 : 0.35)

            Button { audio.toggle() } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: DisplayScale.points(13), weight: .bold))
                    .foregroundStyle(isDark ? Color(white: 0.12) : .white)
                    .offset(x: audio.isPlaying ? 0 : 1)
                    .frame(width: DisplayScale.points(34), height: DisplayScale.points(34))
                    .background(Circle().fill(isDark ? Color.white : Color(white: 0.16)))
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .disabled(!hasTrack)
            .opacity(hasTrack ? 1 : 0.4)
            .help(audio.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")

            sideButton("goforward.10", help: "Skip forward 10 seconds") {
                audio.seek(by: 10)
            }
            .disabled(!hasTrack)
            .opacity(hasTrack ? 1 : 0.35)

            sideButton("forward.end.fill", help: "Next") {
                audio.nextTrack()
            }
            .disabled(audio.library.count < 2)
            .opacity(audio.library.count < 2 ? 0.35 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Volume + add

    private var volumeAndAddRow: some View {
        HStack(spacing: DisplayScale.points(8)) {
            Image(systemName: audio.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: DisplayScale.points(11), weight: .semibold))
                .foregroundStyle(secondaryText)
                .frame(width: DisplayScale.points(16), alignment: .leading)

            LuminaSlider(
                value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }),
                range: 0...1,
                compact: true
            )
            .help("Ambient audio volume")
            .accessibilityLabel("Volume")

            sideButton("plus", help: "Add tracks") {
                audio.chooseTrack()
            }
        }
    }

    // MARK: Up Next

    private var upNextSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                .frame(height: 1)
                .padding(.bottom, DisplayScale.points(6))

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showQueue.toggle() }
            } label: {
                HStack(spacing: DisplayScale.points(6)) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: DisplayScale.points(10), weight: .semibold))
                    Text("Up Next")
                        .font(.system(size: DisplayScale.points(11), weight: .semibold))
                    Text("\(upcomingTracks.count)")
                        .font(.system(size: DisplayScale.points(10), weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .padding(.horizontal, DisplayScale.points(5))
                        .padding(.vertical, DisplayScale.points(1))
                        .background(
                            Capsule().fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        )
                    Spacer(minLength: 0)
                    Text(showQueue ? "Hide" : "Show")
                        .font(.system(size: DisplayScale.points(10), weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: DisplayScale.points(9), weight: .bold))
                        .rotationEffect(.degrees(showQueue ? 180 : 0))
                }
                .foregroundStyle(secondaryText)
                .padding(.horizontal, DisplayScale.points(8))
                .padding(.vertical, DisplayScale.points(7))
                .background(
                    RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .help(showQueue ? "Hide upcoming tracks" : "Show upcoming tracks")
            .accessibilityLabel(showQueue ? "Hide Up Next" : "Show Up Next")
            .accessibilityAddTraits(showQueue ? .isSelected : [])

            if showQueue {
                VStack(spacing: DisplayScale.points(2)) {
                    ForEach(Array(upcomingTracks.enumerated()), id: \.element.id) { index, track in
                        upNextRow(track: track, index: index + 1)
                    }
                }
                .padding(.top, DisplayScale.points(6))
            }
        }
    }

    private func upNextRow(track: AmbientAudioManager.AudioTrack, index: Int) -> some View {
        Button {
            let wasPlaying = audio.isPlaying
            audio.selectTrack(track)
            if wasPlaying { audio.play() }
        } label: {
            HStack(spacing: DisplayScale.points(8)) {
                Text("\(index)")
                    .font(.system(size: DisplayScale.points(10), weight: .semibold).monospacedDigit())
                    .foregroundStyle(secondaryText)
                    .frame(width: DisplayScale.points(14), alignment: .trailing)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: DisplayScale.points(11), weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                        .font(.system(size: DisplayScale.points(10)))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "play.fill")
                    .font(.system(size: DisplayScale.points(8), weight: .bold))
                    .foregroundStyle(secondaryText.opacity(0.7))
            }
            .padding(.horizontal, DisplayScale.points(6))
            .padding(.vertical, DisplayScale.points(5))
            .background(
                RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .help("Play \(track.title)")
        .accessibilityLabel("Play \(track.title)")
    }

    private func sideButton(
        _ symbol: String,
        active: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: DisplayScale.points(11), weight: .semibold))
                .foregroundStyle(active ? accent : (isDark ? Color.white.opacity(0.8) : Color.black.opacity(0.65)))
                .frame(width: DisplayScale.points(26), height: DisplayScale.points(26))
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
