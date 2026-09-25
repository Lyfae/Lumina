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
    /// Stable identity for the current track (path / id). Changing it triggers a wave.
    var trackID: String? = nil
    var loadFailed: Bool = false
    @Binding var preview: Double?
    var onSeek: (Double) -> Void

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @ObservedObject private var pets = PetCatalog.shared
    @State private var isHovered = false
    @State private var dragDirection: Double = 0
    @State private var isWaving = false
    @State private var isJumping = false
    @State private var pausedAt: Date? = nil
    @State private var pauseTick = 0
    @State private var lastSampledTime: Double? = nil
    @State private var waveTask: Task<Void, Never>? = nil
    @State private var jumpTask: Task<Void, Never>? = nil
    @State private var pauseWatchTask: Task<Void, Never>? = nil
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let waveDuration: TimeInterval = 1.5
    private static let jumpDuration: TimeInterval = 0.85
    private static let pauseWaitSeconds: TimeInterval = 20
    private static let skipJumpThreshold: Double = 7.5

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
    private var hasTrack: Bool { trackID != nil || loadFailed || interactive }

    private var didFinish: Bool {
        guard hasTrack, !isPlaying, !isDragging, !loadFailed, safeDuration > 0 else { return false }
        return displayTime >= safeDuration - 0.12
    }

    private var pausedLong: Bool {
        let _ = pauseTick
        guard let pausedAt, !isPlaying, !isDragging else { return false }
        return Date().timeIntervalSince(pausedAt) >= Self.pauseWaitSeconds
    }

    private var petState: PetState {
        let mapped = PetState.forPlayback(
            isPlaying: isPlaying,
            isDragging: isDragging,
            dragDirection: dragDirection,
            didFinish: didFinish,
            loadFailed: loadFailed,
            hasTrack: hasTrack,
            isWaving: isWaving,
            isJumping: isJumping,
            isHovering: isHovered || isFocused,
            pausedLong: pausedLong
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
        .opacity(hasTrack ? 1 : 0.35)
        .allowsHitTesting(interactive)
        .help(loadFailed ? "Track failed to load" : (interactive ? "Drag to seek" : "No music"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(loadFailed
            ? "Load failed"
            : (interactive
                ? "\(formatTime(displayTime)) of \(formatTime(safeDuration))"
                : "Unavailable"))
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
        .onAppear {
            syncPauseWatch(playing: isPlaying)
            lastSampledTime = currentTime
        }
        .onDisappear {
            waveTask?.cancel()
            jumpTask?.cancel()
            pauseWatchTask?.cancel()
        }
        .onChange(of: trackID) { old, new in
            guard new != nil, new != old else { return }
            lastSampledTime = currentTime
            pulseWave()
        }
        .onChange(of: isPlaying) { _, playing in
            syncPauseWatch(playing: playing)
        }
        .onChange(of: preview) { _, newPreview in
            // After a scrub, realign the sample so the seek delta does not look like a skip.
            if newPreview == nil {
                lastSampledTime = currentTime
            }
        }
        .onChange(of: currentTime) { _, newTime in
            handleTimeJump(to: newTime)
        }
    }

    private var footerBody: some View {
        // Tall enough for a 48pt pet with the track clearly in the lower third.
        let bandH = DisplayScale.points(68)
        let trackLift = bandH / 5  // lower fifth ≈ lower-third band
        return HStack(alignment: .bottom, spacing: LuminaSpace.sm) {
            Text(formatTime(displayTime))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(preview == nil ? .secondary : accent)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .padding(.bottom, max(0, trackLift - DisplayScale.points(6)))
                .accessibilityHidden(true)

            journeyBand(bandHeight: bandH)

            Text(formatTime(safeDuration))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth, alignment: .leading)
                .padding(.bottom, max(0, trackLift - DisplayScale.points(6)))
                .accessibilityHidden(true)
        }
        .frame(height: bandH, alignment: .bottom)
    }

    private func journeyBand(bandHeight: CGFloat?) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(bandHeight ?? geo.size.height, 1)
            let petHeight: CGFloat = {
                let trackLift = height / 6
                let maxFit = max(DisplayScale.points(24), height - trackLift - DisplayScale.points(4))
                if style == .footer {
                    // 2× original (~24–28pt) → ~48pt Studio frame.
                    return min(DisplayScale.points(48), maxFit)
                }
                // Widget: 2× prior (~34) scaled to band, clamped so the full body fits.
                let desired = min(max(height * 0.82, DisplayScale.points(44)), DisplayScale.points(64))
                return min(desired, maxFit)
            }()
            let knobSize = DisplayScale.points(12)
            let aspect: CGFloat = 192.0 / 208.0
            let playheadW = petsEnabled ? petHeight * aspect : knobSize
            let trackH: CGFloat = isHovered || isDragging || isFocused
                ? DisplayScale.points(3)
                : DisplayScale.points(2)
            // Raise the track into the lower third so the pet sits fully inside the bar.
            let trackLift = style == .footer ? height / 5 : height / 6
            let inset = max(playheadW * 0.5, knobSize * 0.5)
            let travel = max(width - inset * 2, 1)
            let playheadX = inset + travel * fraction
            // Drag label sits just below the track (positive y from track baseline).
            let labelBelowTrack = DisplayScale.points(12)

            ZStack(alignment: .bottomLeading) {
                trackLayer(width: width, trackH: trackH, playheadX: playheadX)
                    .frame(width: width, height: trackH)
                    .offset(y: -trackLift)

                playheadContent(petHeight: petHeight, knobSize: knobSize)
                    .frame(width: playheadW, height: petsEnabled ? petHeight : knobSize, alignment: .bottom)
                    .offset(
                        x: playheadX - playheadW * 0.5,
                        y: -(trackLift + trackH * 0.45)
                    )
                    .allowsHitTesting(false)
                    .zIndex(1)

                if isDragging {
                    // Centered under the pet; just below the track; above the pet in z-order.
                    Text(formatTime(displayTime))
                        .font(uiScale.font(.micro).monospacedDigit().weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .fixedSize()
                        .frame(width: 0, alignment: .center)
                        .offset(x: playheadX, y: -(trackLift - labelBelowTrack))
                        .allowsHitTesting(false)
                        .zIndex(2)
                }
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
    private func trackLayer(width: CGFloat, trackH: CGFloat, playheadX: CGFloat) -> some View {
        let playedWidth = max(trackH, playheadX)
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.clear)
                .frame(width: width, height: trackH)
                .overlay {
                    // Unplayed: faint dotted hairline.
                    Canvas { context, size in
                        let spacing: CGFloat = 4.5
                        let r: CGFloat = 0.65
                        var x: CGFloat = r
                        let y = size.height * 0.5
                        while x < size.width {
                            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(Color.secondary.opacity(0.28))
                            )
                            x += spacing
                        }
                    }
                }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.25),
                                    accent.opacity(0.70)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: playedWidth, height: trackH)
                }
                .clipShape(Capsule())

            // Soft glow only near the playhead (outside the clip so it can bloom).
            Capsule()
                .fill(accent.opacity(0.45))
                .frame(width: max(DisplayScale.points(8), trackH * 3.5), height: trackH * 1.8)
                .blur(radius: 2.5)
                .opacity(0.75)
                .offset(x: playheadX - DisplayScale.points(6))
                .allowsHitTesting(false)
        }
        .frame(width: width, height: max(trackH * 1.8, trackH), alignment: .center)
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
            .shadow(color: accent.opacity(isFocused ? 0.55 : 0.3), radius: isFocused ? 5 : 0, y: 0)
            .frame(width: size, height: size)
    }

    // MARK: - Mood timers

    private func pulseWave() {
        guard !reduceMotion else { return }
        waveTask?.cancel()
        isWaving = true
        waveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.waveDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            isWaving = false
        }
    }

    private func pulseJump() {
        guard !reduceMotion else { return }
        jumpTask?.cancel()
        isJumping = true
        jumpTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.jumpDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            isJumping = false
        }
    }

    private func syncPauseWatch(playing: Bool) {
        pauseWatchTask?.cancel()
        if playing {
            pausedAt = nil
            return
        }
        if pausedAt == nil {
            pausedAt = Date()
        }
        pauseWatchTask = Task { @MainActor in
            let remaining: TimeInterval
            if let pausedAt {
                remaining = max(0, Self.pauseWaitSeconds - Date().timeIntervalSince(pausedAt))
            } else {
                remaining = Self.pauseWaitSeconds
            }
            try? await Task.sleep(nanoseconds: UInt64((remaining + 0.05) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            pauseTick &+= 1
        }
    }

    private func handleTimeJump(to newTime: Double) {
        defer { lastSampledTime = newTime }
        guard !isDragging, hasTrack, safeDuration > 0 else { return }
        guard let previous = lastSampledTime else { return }
        let delta = newTime - previous

        // Loop restart: near end → near start.
        if previous >= safeDuration - 1.5, newTime <= 1.5, abs(delta) > 1 {
            pulseJump()
            return
        }

        // Skip forward/back (±10 etc.) while not scrub-dragging.
        if abs(delta) >= Self.skipJumpThreshold {
            pulseJump()
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

struct AudioProgressScrubber: View {
    let currentTime: Double
    let duration: Double
    let accent: Color
    var compact: Bool = false
    var trackID: String? = nil
    var loadFailed: Bool = false
    var isPlaying: Bool = true
    var onSeek: (Double) -> Void

    @State private var preview: Double? = nil

    var body: some View {
        let _ = accent
        return LuminaWaveformScrubber(
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            style: compact ? .widget : .footer,
            source: .live,
            trackID: trackID,
            loadFailed: loadFailed,
            preview: $preview,
            onSeek: onSeek
        )
    }
}
