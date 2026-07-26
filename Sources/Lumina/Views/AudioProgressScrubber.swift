import SwiftUI

/// Shared timeline scrubber for Studio footer and the floating music widget.
/// Previews the target time while dragging; commits seek on release so it doesn’t
/// fight the playback timer.
struct AudioProgressScrubber: View {
    let currentTime: Double
    let duration: Double
    let accent: Color
    var compact: Bool = false
    var onSeek: (Double) -> Void

    @State private var scrubTime: Double? = nil

    private var displayTime: Double { scrubTime ?? currentTime }

    private var fraction: CGFloat {
        guard duration > 0, duration.isFinite else { return 0 }
        guard displayTime.isFinite else { return 0 }
        return CGFloat(min(1, max(0, displayTime / duration)))
    }

    private var trackH: CGFloat { DisplayScale.points(compact ? 3 : 6) }
    private var thumb: CGFloat { DisplayScale.points(compact ? 10 : 14) }
    private var rowHeight: CGFloat { DisplayScale.points(compact ? 20 : 28) }
    private var timeFontSize: CGFloat { DisplayScale.points(compact ? 10 : 11) }

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                inlineBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Track position")
        .accessibilityValue(formatTime(displayTime))
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

    /// Mini-player: track on top, times underneath — avoids crowding the thumb.
    private var compactBody: some View {
        VStack(spacing: DisplayScale.points(4)) {
            track(height: DisplayScale.points(18))

            HStack {
                Text(formatTime(displayTime))
                    .font(.system(size: timeFontSize, weight: .medium).monospacedDigit())
                    .foregroundStyle(scrubTime == nil ? .secondary : accent)
                Spacer(minLength: 0)
                Text(formatTime(duration))
                    .font(.system(size: timeFontSize, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
    }

    /// Studio footer: times flanking the track.
    private var inlineBody: some View {
        HStack(spacing: DisplayScale.points(8)) {
            Text(formatTime(displayTime))
                .font(.system(size: timeFontSize, weight: .medium).monospacedDigit())
                .foregroundStyle(scrubTime == nil ? .secondary : accent)
                .frame(width: DisplayScale.points(38), alignment: .trailing)
                .accessibilityHidden(true)

            track(height: rowHeight)

            Text(formatTime(duration))
                .font(.system(size: timeFontSize, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: DisplayScale.points(38), alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private func track(height: CGFloat) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let x = width * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackH)

                Capsule()
                    .fill(accent)
                    .frame(width: max(trackH, x), height: trackH)

                Circle()
                    .fill(Color.luminaCard)
                    .overlay(
                        Circle().strokeBorder(accent.opacity(0.9), lineWidth: compact ? 1.25 : 1.5)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 1.2, y: 0.5)
                    .frame(width: thumb, height: thumb)
                    .scaleEffect(scrubTime == nil ? 1 : 1.1)
                    .offset(x: max(0, min(width - thumb, x - thumb / 2)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        scrubTime = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        guard duration > 0 else {
                            scrubTime = nil
                            return
                        }
                        onSeek(time(at: value.location.x, width: width))
                        scrubTime = nil
                    }
            )
            .help(scrubTime.map { "Release to seek to \(formatTime($0))" }
                  ?? "Click or drag to scrub")
        }
        .frame(height: height)
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        let f = Double(min(1, max(0, x / max(width, 1))))
        return f * duration
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
