import LuminaCore
import SwiftUI

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
    @ObservedObject private var pets = PetCatalog.shared
    @State private var isHovered = false
    @State private var dragDirection: Double = 0
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var safeDuration: Double {
        duration.isFinite ? max(0, duration) : 0
    }

    private var displayTime: Double {
        let t = preview ?? currentTime
        guard t.isFinite else { return 0 }
        return min(safeDuration, max(0, t))
    }

    private var fraction: CGFloat {
        guard safeDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, displayTime / safeDuration)))
    }

    private var accent: Color { theme.current.color }
    private var interactive: Bool { safeDuration > 0 }
    private var isDragging: Bool { preview != nil }
    private var hasTrack: Bool { interactive }

    private var didFinish: Bool {
        guard hasTrack, !isPlaying, !isDragging else { return false }
        return displayTime >= safeDuration - 0.12
    }

    private var petState: PetState {
        let mapped = PetState.forPlayback(
            isPlaying: isPlaying,
            isDragging: isDragging,
            dragDirection: dragDirection,
            didFinish: didFinish,
            loadFailed: false,
            hasTrack: hasTrack
        )
        if reduceMotion {
            switch mapped {
            case .runningRight, .runningLeft, .running, .jumping, .waving:
                return .idle
            default:
                return mapped
            }
        }
        return mapped
    }

    private var timeColumnWidth: CGFloat {
        safeDuration >= 3600 ? DisplayScale.points(56) : LuminaMetrics.timeLabelWidth
    }

    private var petsEnabled: Bool { pets.isEnabled }

    var body: some View {
        let _ = source
        Group {
            if style == .footer {
                footerBody
            } else {
                journeyBand(bandHeight: nil)
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
        .focusEffectDisabled()
        .environment(\.luminaButtonFocusRing, false)
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
    }

    private var footerBody: some View {
        HStack(spacing: LuminaSpace.sm) {
            Text(formatTime(displayTime))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(preview == nil ? .secondary : accent)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .accessibilityHidden(true)

            journeyBand(bandHeight: DisplayScale.points(28))

            Text(formatTime(safeDuration))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private func journeyBand(bandHeight: CGFloat?) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(bandHeight ?? geo.size.height, 1)
            let petHeight: CGFloat = {
                if style == .footer {
                    return min(DisplayScale.points(28), max(DisplayScale.points(22), height - DisplayScale.points(2)))
                }
                return min(max(height * 0.9, DisplayScale.points(22)), DisplayScale.points(34))
            }()
            let knobSize = DisplayScale.points(12)
            let aspect: CGFloat = 192.0 / 208.0
            let playheadW = petsEnabled ? petHeight * aspect : knobSize
            let trackH: CGFloat = isHovered || isDragging || isFocused
                ? DisplayScale.points(6)
                : DisplayScale.points(4)
            let inset = max(playheadW * 0.5, knobSize * 0.5)
            let travel = max(width - inset * 2, 1)
            let playheadX = inset + travel * fraction

            ZStack(alignment: .bottomLeading) {
                Capsule()
                    .fill(Color.clear)
                    .frame(width: width, height: trackH)
                    .overlay {
                        Canvas { context, size in
                            let spacing: CGFloat = 5
                            let r: CGFloat = 0.9
                            var x: CGFloat = r
                            let y = size.height * 0.5
                            while x < size.width {
                                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                                context.fill(
                                    Path(ellipseIn: rect),
                                    with: .color(Color.secondary.opacity(0.35))
                                )
                                x += spacing
                            }
                        }
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(accent)
                            .frame(width: max(trackH, playheadX), height: trackH)
                            .shadow(color: accent.opacity(0.45), radius: 4, y: 0)
                    }
                    .clipShape(Capsule())
                    .frame(width: width, height: trackH)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if isDragging {
                    Text(formatTime(displayTime))
                        .font(uiScale.font(.micro).monospacedDigit().weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .fixedSize()
                        .offset(x: playheadX - 24, y: trackH + DisplayScale.points(16))
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                playheadContent(petHeight: petHeight, knobSize: knobSize)
                    .frame(width: playheadW, height: petsEnabled ? petHeight : knobSize, alignment: .bottom)
                    .offset(x: playheadX - playheadW * 0.5, y: -trackH * 0.35)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height, alignment: .bottom)
            .contentShape(Rectangle())
            .onHover { hovering in
                LuminaMotion.animate(LuminaMotion.hover) { isHovered = hovering }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard interactive else { return }
                        let dx = value.translation.width
                        if abs(dx) < 0.5 {
                            dragDirection = 0
                        } else {
                            dragDirection = dx < 0 ? -1 : 1
                        }
                        preview = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        dragDirection = 0
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
        .frame(height: bandHeight)
    }

    @ViewBuilder
    private func playheadContent(petHeight: CGFloat, knobSize: CGFloat) -> some View {
        if petsEnabled, let pet = pets.currentPet {
            let hasFrames = !pet.frames(for: petState).isEmpty || !pet.frames(for: .idle).isEmpty
            if hasFrames {
                PetSprite(state: petState, height: petHeight, pet: pet)
                    .shadow(color: isFocused ? accent.opacity(0.5) : .clear, radius: isFocused ? 5 : 0)
            } else if let thumb = pet.thumbnailImage() {
                Image(nsImage: thumb)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: petHeight)
            } else {
                knobView(size: knobSize)
            }
        } else {
            knobView(size: knobSize)
        }
    }

    private func knobView(size: CGFloat) -> some View {
        Circle()
            .fill(accent)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
            .shadow(color: accent.opacity(isFocused ? 0.55 : 0.3), radius: isFocused ? 5 : 2, y: 0)
            .frame(width: size, height: size)
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
