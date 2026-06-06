import SwiftUI
import AppKit

/// A floating, always-on-top "now playing" mini-player styled after the system media
/// widget. Shown while the Studio window is minimized (when the user has enabled
/// "Show music widget when minimized"). Controls Lumina's own ambient-audio library.
@MainActor
final class NowPlayingWidgetController: NSObject {
    private var panel: NSPanel?
    private static let size = NSSize(width: 440, height: 176)

    /// Brings the widget on screen, creating it on first use and parking it in the
    /// top-right corner of the main display.
    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        positionInTopRight(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: NowPlayingWidgetView(onClose: { [weak self] in
            self?.hide()
        }))
        host.frame = NSRect(origin: .zero, size: Self.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    private func positionInTopRight(_ panel: NSPanel) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24
        ))
    }
}

// MARK: - Widget View

struct NowPlayingWidgetView: View {
    var onClose: () -> Void = {}

    @StateObject private var audio = AmbientAudioManager.shared
    @StateObject private var theme = ThemeManager.shared

    private var accent: Color { theme.current.color }

    var body: some View {
        HStack(spacing: 16) {
            albumArt
            VStack(alignment: .leading, spacing: 8) {
                titleRow
                progressBar
                transportRow
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(white: 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(6)   // breathing room for the drop shadow
    }

    // MARK: Album art

    private var albumArt: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.95), accent.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 92, height: 92)
            .overlay(
                Image(systemName: audio.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: audio.isPlaying)
            )
            .shadow(color: accent.opacity(0.35), radius: 10, y: 4)
    }

    // MARK: Title + dismiss

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Ambient Audio")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Hide widget")
        }
    }

    private var displayTitle: String {
        audio.trackURL == nil ? "Nothing playing" : trackTitle
    }

    /// Filename without extension, lightly prettified for display.
    private var trackTitle: String {
        let stem = (audio.trackName as NSString).deletingPathExtension
        return stem.isEmpty ? audio.trackName : stem
    }

    // MARK: Progress

    private var progressBar: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let fraction = audio.duration > 0 ? audio.currentTime / audio.duration : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: max(0, geo.size.width * fraction))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        guard audio.duration > 0 else { return }
                        let f = (value.location.x / geo.size.width).clampedUnit
                        audio.seekToTime(f * audio.duration)
                    }
                )
            }
            .frame(height: 5)

            HStack {
                Text(timeString(audio.currentTime))
                Spacer()
                Text("-" + timeString(max(0, audio.duration - audio.currentTime)))
            }
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: Transport

    private var transportRow: some View {
        HStack(spacing: 0) {
            transportButton(
                "repeat",
                size: 15,
                active: audio.loops,
                help: audio.loops ? "Looping on" : "Looping off"
            ) { audio.setLoops(!audio.loops) }

            Spacer(minLength: 0)

            transportButton("backward.end.fill", size: 18, help: "Previous track") {
                audio.previousTrack()
            }
            .disabled(audio.library.count < 2)

            Spacer(minLength: 0)

            // Primary play/pause — the visual anchor of the widget.
            Button { audio.toggle() } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)
            .disabled(audio.trackURL == nil)
            .opacity(audio.trackURL == nil ? 0.4 : 1)
            .help(audio.isPlaying ? "Pause" : "Play")

            Spacer(minLength: 0)

            transportButton("forward.end.fill", size: 18, help: "Next track") {
                audio.nextTrack()
            }
            .disabled(audio.library.count < 2)

            Spacer(minLength: 0)

            transportButton(
                audio.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                size: 15,
                help: "Mute"
            ) {
                audio.setVolume(audio.volume < 0.01 ? 0.5 : 0)
            }
        }
        .padding(.top, 2)
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat,
        active: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? accent : Color.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private extension CGFloat {
    var clampedUnit: Double { Double(Swift.min(1, Swift.max(0, self))) }
}
