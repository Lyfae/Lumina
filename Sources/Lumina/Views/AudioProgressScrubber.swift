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
    @ObservedObject private var meter = AudioMeterModel.shared
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var displayTime: Double { preview ?? currentTime }
    private var showThumb: Bool { isHovered || preview != nil || isFocused }

    private var fraction: CGFloat {
        guard duration > 0, duration.isFinite, displayTime.isFinite else { return 0 }
        return CGFloat(min(1, max(0, displayTime / duration)))
    }

    private var accent: Color { theme.current.color }
    private var interactive: Bool { duration > 0 && duration.isFinite }

    var body: some View {
        Group {
            if style == .footer {
                footerBody
            } else {
                waveformBand(height: bandHeight)
            }
        }
        .opacity(interactive ? 1 : 0.35)
        .allowsHitTesting(interactive)
        .help(interactive ? "Drag to seek" : "No music")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(interactive
            ? "\(formatTime(displayTime)) of \(formatTime(duration))"
            : "Unavailable")
        .accessibilityAdjustableAction { direction in
            guard interactive else { return }
            switch direction {
            case .increment: seekBy(5)
            case .decrement: seekBy(-5)
            @unknown default: break
            }
        }
        .focusable(interactive)
        .focused($isFocused)
        .onKeyPress(.leftArrow) { seekBy(NSEvent.modifierFlags.contains(.shift) ? -30 : -5); return .handled }
        .onKeyPress(.rightArrow) { seekBy(NSEvent.modifierFlags.contains(.shift) ? 30 : 5); return .handled }
        .onKeyPress(.home) {
            guard interactive else { return .ignored }
            onSeek(0)
            return .handled
        }
    }

    private var bandHeight: CGFloat {
        LuminaMetrics.waveformFooterBand
    }

    private var footerBody: some View {
        HStack(spacing: LuminaSpace.sm) {
            Text(formatTime(displayTime))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(preview == nil ? .secondary : accent)
                .frame(width: LuminaMetrics.timeLabelWidth, alignment: .trailing)
                .accessibilityHidden(true)

            waveformBand(height: bandHeight)

            Text(formatTime(duration))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: LuminaMetrics.timeLabelWidth, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private func waveformBand(height: CGFloat) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let barPitch = LuminaMetrics.waveformBarWidth + LuminaMetrics.waveformBarGap
            let count = min(96, max(24, Int(floor(width / max(barPitch, 1)))))
            let playhead = width * fraction
            let thumb = LuminaMetrics.waveformThumb
            let levels = resolvedLevels(count: count)

            ZStack(alignment: .leading) {
                bars(levels: levels, height: height, playedWidth: playhead, totalWidth: width)

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
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard interactive else { return }
                        preview = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        defer { preview = nil }
                        guard interactive else { return }
                        onSeek(time(at: value.location.x, width: width))
                    }
            )
        }
        .frame(height: height)
    }

    private func bars(levels: [CGFloat], height: CGFloat, playedWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let shape = barStack(levels: levels, height: height)
        let playedOpacity: Double = isPlaying ? 1.0 : 0.6
        return ZStack(alignment: .leading) {
            shape
                .foregroundStyle(Color.primary.opacity(0.22))

            shape
                .foregroundStyle(accent.opacity(playedOpacity))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: playedWidth)
                }
        }
        .frame(width: totalWidth, height: height)
        .animation(LuminaMotion.meter, value: levels)
    }

    private func barStack(levels: [CGFloat], height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: LuminaMetrics.waveformBarGap) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule(style: .continuous)
                    .frame(width: LuminaMetrics.waveformBarWidth)
                    .frame(height: max(DisplayScale.points(2), level * height))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: height)
    }

    private func resolvedLevels(count: Int) -> [CGFloat] {
        switch source {
        case .live:
            return resample(meter.levels, count: count)
        case .staticSeed(let seed):
            return Self.staticLevels(count: count, seed: seed)
        }
    }

    private func resample(_ levels: [CGFloat], count: Int) -> [CGFloat] {
        guard !levels.isEmpty else { return Array(repeating: 0.12, count: count) }
        if levels.count == count { return levels }
        return (0..<count).map { i in
            let src = Int(Double(i) / Double(max(count - 1, 1)) * Double(levels.count - 1))
            return levels[min(levels.count - 1, max(0, src))]
        }
    }

    static func staticLevels(count: Int, seed: Int) -> [CGFloat] {
        let s = Double(seed % 1000) / 97
        return (0..<count).map { i in
            let di = Double(i)
            return CGFloat(0.25 + 0.55 * abs(sin(0.9 * di + s)) * (0.6 + 0.4 * abs(sin(0.37 * di + 1.3 * s))))
        }
    }

    private func seekBy(_ delta: Double) {
        guard interactive else { return }
        onSeek(min(duration, max(0, currentTime + delta)))
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        Double(min(1, max(0, x / max(width, 1)))) * duration
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
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
        // `accent` retained so existing call sites compile; waveform reads ThemeManager.
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
