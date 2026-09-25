import SwiftUI

/// Unified waveform scrubber for Studio footer and the floating music widget.
struct LuminaWaveformScrubber: View {
    enum Style { case footer, widget }
    enum Source { case live, staticSeed(Int) }

    let currentTime: Double
    let duration: Double
    let isPlaying: Bool
    var style: Style = .footer
    var source: Source = .live
    @Binding var preview: Double?
    var onSeek: (Double) -> Void

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @State private var isHovered = false
    @State private var levels: [CGFloat] = []
    @FocusState private var isFocused: Bool

    private var safeDuration: Double {
        duration.isFinite ? max(0, duration) : 0
    }

    private var displayTime: Double {
        let t = preview ?? currentTime
        guard t.isFinite else { return 0 }
        return min(safeDuration, max(0, t))
    }

    private var showThumb: Bool { isHovered || preview != nil || isFocused }

    private var fraction: CGFloat {
        guard safeDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, displayTime / safeDuration)))
    }

    private var accent: Color { theme.current.color }
    private var interactive: Bool { safeDuration > 0 }

    private var liveTrackURL: URL? {
        AmbientAudioManager.shared.trackURL
    }

    private var waveformIdentity: String {
        switch source {
        case .live:
            return liveTrackURL?.absoluteString ?? ""
        case .staticSeed(let seed):
            return "seed:\(seed)"
        }
    }

    private var timeColumnWidth: CGFloat {
        safeDuration >= 3600 ? DisplayScale.points(56) : LuminaMetrics.timeLabelWidth
    }

    var body: some View {
        Group {
            if style == .footer {
                footerBody
            } else {
                waveformBand(fixedHeight: nil)
            }
        }
        .opacity(interactive ? 1 : 0.35)
        .allowsHitTesting(interactive)
        .help(interactive ? "Drag to seek" : "No music")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(interactive
            ? "\(formatTime(displayTime)) of \(formatTime(safeDuration))"
            : "Unavailable")
        .accessibilityAdjustableAction { direction in
            guard interactive else { return }
            let base = preview ?? currentTime
            let t = base.isFinite ? base : 0
            switch direction {
            case .increment: commitSeek(t + 5)
            case .decrement: commitSeek(t - 5)
            @unknown default: break
            }
        }
        .focusable(interactive)
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            seekBy(NSEvent.modifierFlags.contains(.shift) ? -30 : -5)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            seekBy(NSEvent.modifierFlags.contains(.shift) ? 30 : 5)
            return .handled
        }
        .onKeyPress(.home) {
            guard interactive else { return .ignored }
            commitSeek(0)
            return .handled
        }
        .task(id: waveformIdentity) {
            await refreshLevels()
        }
    }

    private var footerBody: some View {
        HStack(spacing: LuminaSpace.sm) {
            Text(formatTime(displayTime))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(preview == nil ? .secondary : accent)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .accessibilityHidden(true)

            waveformBand(fixedHeight: LuminaMetrics.waveformFooterBand)

            Text(formatTime(safeDuration))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private func waveformBand(fixedHeight: CGFloat?) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(fixedHeight ?? geo.size.height, 1)
            let barPitch = LuminaMetrics.waveformBarWidth + LuminaMetrics.waveformBarGap
            let count = min(96, max(24, Int(floor(width / max(barPitch, 1)))))
            let playhead = width * fraction
            let thumb = LuminaMetrics.waveformThumb
            let displayLevels = resolvedLevels(count: count)

            ZStack(alignment: .leading) {
                WaveformBars(
                    levels: displayLevels,
                    height: height,
                    width: width,
                    playedWidth: playhead,
                    accent: accent,
                    playedOpacity: isPlaying ? 1.0 : 0.6
                )

                if showThumb && interactive {
                    Circle()
                        .fill(Color.luminaCard)
                        .overlay(Circle().strokeBorder(accent, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                        .frame(width: thumb, height: thumb)
                        .offset(x: max(0, min(width - thumb, playhead - thumb / 2)))
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onHover { hovering in
                LuminaMotion.animate(LuminaMotion.hover) { isHovered = hovering }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard interactive else { return }
                        preview = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        guard interactive else {
                            preview = nil
                            return
                        }
                        let t = time(at: value.location.x, width: width)
                        preview = t
                        onSeek(t)
                        preview = nil
                    }
            )
        }
        .frame(height: fixedHeight)
    }

    private func resolvedLevels(count: Int) -> [CGFloat] {
        if !levels.isEmpty {
            return TrackWaveformCache.resample(levels, count: count)
        }
        switch source {
        case .live:
            let seed = liveTrackURL?.absoluteString.hashValue ?? 0
            return Self.staticLevels(count: count, seed: seed)
        case .staticSeed(let seed):
            return Self.staticLevels(count: count, seed: seed)
        }
    }

    private func refreshLevels() async {
        switch source {
        case .staticSeed(let seed):
            levels = Self.staticLevels(count: TrackWaveformCache.resolution, seed: seed)
        case .live:
            guard let url = liveTrackURL else {
                levels = []
                return
            }
            let key = url.absoluteString
            if let cached = await TrackWaveformCache.shared.cached(for: url) {
                levels = cached
            } else {
                levels = Self.staticLevels(count: 48, seed: key.hashValue)
            }
            let loaded = await TrackWaveformCache.shared.levels(for: url, count: TrackWaveformCache.resolution)
            guard !Task.isCancelled, AmbientAudioManager.shared.trackURL?.absoluteString == key else { return }
            levels = loaded
        }
    }

    static func staticLevels(count: Int, seed: Int) -> [CGFloat] {
        let s = Double(abs(seed) % 1000) / 97
        return (0..<count).map { i in
            let di = Double(i)
            return CGFloat(0.25 + 0.55 * abs(sin(0.9 * di + s)) * (0.6 + 0.4 * abs(sin(0.37 * di + 1.3 * s))))
        }
    }

    private func seekBy(_ delta: Double) {
        guard interactive else { return }
        let base = preview ?? currentTime
        let t = base.isFinite ? base : 0
        commitSeek(t + delta)
    }

    private func commitSeek(_ time: Double) {
        guard interactive else { return }
        let t = min(safeDuration, max(0, time))
        preview = t
        onSeek(t)
        preview = nil
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        Double(min(1, max(0, x / max(width, 1)))) * safeDuration
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// Bars laid out across the full width so playhead coloring matches seek geometry.
private struct WaveformBars: View {
    let levels: [CGFloat]
    let height: CGFloat
    let width: CGFloat
    let playedWidth: CGFloat
    let accent: Color
    let playedOpacity: Double

    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0, size.width > 0, size.height > 0 else { return }
            let barW = LuminaMetrics.waveformBarWidth
            let pitch = size.width / CGFloat(count)
            let minH = DisplayScale.points(2)

            for (i, level) in levels.enumerated() {
                let x = CGFloat(i) * pitch + max(0, (pitch - barW) / 2)
                let h = max(minH, CGFloat(level) * size.height)
                let y = (size.height - h) / 2
                let rect = CGRect(x: x, y: y, width: min(barW, pitch), height: h)
                let centerX = rect.midX
                let color = centerX <= playedWidth
                    ? accent.opacity(playedOpacity)
                    : Color.primary.opacity(0.22)
                context.fill(Path(roundedRect: rect, cornerRadius: min(barW, h) / 2), with: .color(color))
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

/// Temporary wrapper — Batch 2 switches the footer to `LuminaWaveformScrubber` and deletes this.
struct AudioProgressScrubber: View {
    let currentTime: Double
    let duration: Double
    let accent: Color
    var compact: Bool = false
    var onSeek: (Double) -> Void

    @State private var preview: Double? = nil

    var body: some View {
        let _ = accent
        return LuminaWaveformScrubber(
            currentTime: currentTime,
            duration: duration,
            isPlaying: true,
            style: compact ? .widget : .footer,
            source: .live,
            preview: $preview,
            onSeek: onSeek
        )
    }
}
