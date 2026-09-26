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
    /// Finger-to-playhead offset while dragging the pet, so a click on its body does not seek.
    @State private var grabOffset: CGFloat? = nil
    /// After a scrub or window drag, ignore hover-enter until the pointer leaves.
    /// Otherwise macOS can leave `isHovered` stuck (or re-fire it as the panel slides
    /// under the cursor) and the pet stays in the review pose instead of running.
    @State private var suppressHoverUntilExit = false
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
            // Pointer hover only. Keyboard focus stays on after a widget drag and
            // was leaving the pet in the review pose until play/pause stole focus.
            isHovering: isHovered,
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

    private var petsEnabled: Bool { pets.isEnabled }

    var body: some View {
        let _ = source
        scrubberContent
            .frame(minWidth: 0, maxWidth: style == .footer ? .infinity : nil, alignment: .center)
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
                clearPointerInteraction(commitPreview: false)
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
                if newPreview == nil {
                    lastSampledTime = currentTime
                    // Parent may clear preview when the panel moves; drop leftover drag chrome.
                    dragDirection = 0
                    grabOffset = nil
                }
            }
            .onChange(of: currentTime) { _, newTime in
                handleTimeJump(to: newTime)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { note in
                guard (note.object as? NSWindow)?.title == "Music Widget" else { return }
                // Window drag cancels scrub gestures. applyHover ignores enters while
                // the mouse button is down so the band cannot re-arm review mid-drag.
                clearPointerInteraction(commitPreview: false)
            }
    }

    @ViewBuilder
    private var scrubberContent: some View {
        if style == .footer {
            footerTrack
        } else {
            journeyBand(bandHeight: nil)
        }
    }

    /// Widget waveform plus the time under the playhead. The Studio dock uses a shorter track.
    static var footerBandHeight: CGFloat { DisplayScale.points(48) }
    /// The widget stage is shorter than a full window, so the pet reads smaller there.
    static var widgetPetHeight: CGFloat { DisplayScale.points(32) }

    private var timeColumnWidth: CGFloat {
        safeDuration >= 3600 ? DisplayScale.points(56) : LuminaMetrics.timeLabelWidth
    }

    /// Compact Studio track: elapsed time, a centered waveform, and the duration.
    private var footerTrack: some View {
        HStack(spacing: LuminaSpace.sm) {
            Text(formatTime(displayTime))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(isDragging ? accent : .secondary)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .accessibilityHidden(true)

            GeometryReader { geo in
                footerWave(
                    width: max(geo.size.width, 1),
                    height: LuminaMetrics.waveformFooterBand
                )
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: LuminaMetrics.waveformFooterBand)

            Text(formatTime(safeDuration))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func footerWave(width: CGFloat, height: CGFloat) -> some View {
        let playheadX = width * fraction
        let bar = max(2, DisplayScale.points(2.5))
        let gap = max(1, DisplayScale.points(1.5))
        let count = max(24, Int(width / (bar + gap)))
        let peaks = Self.wavePeaks(count: count, seed: Self.stableHash(trackID ?? "lumina"))
        return BeatWaveform(
            width: width,
            height: height,
            played: playheadX,
            peaks: peaks,
            accent: accent,
            playing: isPlaying
        )
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onHover { hovering in
            applyHover(hovering)
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard interactive else { return }
                    let dx = value.translation.width
                    dragDirection = abs(dx) < 0.5 ? 0 : (dx < 0 ? -1 : 1)
                    preview = time(at: value.location.x, width: width, inset: 0)
                }
                .onEnded { value in
                    finishScrub(at: value.location.x, width: width, inset: 0)
                }
        )
    }

    private func journeyBand(bandHeight: CGFloat?) -> some View {
        GeometryReader { geo in
            journeyBandContent(
                width: max(geo.size.width, 1),
                height: max(bandHeight ?? geo.size.height, 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func journeyBandContent(width: CGFloat, height: CGFloat) -> some View {
        let timeBlock = DisplayScale.points(16)
        let waveH = max(DisplayScale.points(16), height - timeBlock - DisplayScale.points(4))
        let playheadX = width * fraction
        let labelInset = DisplayScale.points(16)
        let labelX = min(max(playheadX, labelInset), max(labelInset, width - labelInset))
        let bar = max(2, DisplayScale.points(2.5))
        let gap = max(1, DisplayScale.points(1.5))
        let count = max(16, Int(width / (bar + gap)))
        let peaks = Self.wavePeaks(count: count, seed: Self.stableHash(trackID ?? "lumina"))

        return ZStack(alignment: .bottomLeading) {
            BeatWaveform(
                width: width,
                height: waveH,
                played: playheadX,
                peaks: peaks,
                accent: accent,
                playing: isPlaying,
                growsUp: true
            )
            .frame(width: width, height: waveH)
            .offset(y: -timeBlock)
            .allowsHitTesting(false)

            Text(formatTime(displayTime))
                .font(uiScale.font(.micro).monospacedDigit().weight(.semibold))
                .foregroundStyle(isDragging ? accent : Color.secondary)
                .fixedSize()
                .frame(width: 0, alignment: .center)
                .offset(x: labelX, y: -DisplayScale.points(1))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: width, height: height, alignment: .bottom)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard interactive else { return }
                    let dx = value.translation.width
                    dragDirection = abs(dx) < 0.5 ? 0 : (dx < 0 ? -1 : 1)
                    preview = time(at: value.location.x, width: width, inset: 0)
                }
                .onEnded { value in
                    finishScrub(at: value.location.x, width: width, inset: 0)
                }
        )
        .onDisappear {
            clearPointerInteraction(commitPreview: false)
        }
    }

    private func applyHover(_ hovering: Bool) {
        if !hovering {
            suppressHoverUntilExit = false
            LuminaMotion.animate(LuminaMotion.hover) { isHovered = false }
            return
        }
        // Window drag (and active mouse scrub) keep a button down; ignoring enter
        // stops the journey band from arming review as the panel slides under the cursor.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        guard !suppressHoverUntilExit else { return }
        LuminaMotion.animate(LuminaMotion.hover) { isHovered = true }
    }

    /// Drop scrub / hover chrome so a playing track returns to `.running`.
    /// `suppressHoverUntilExit` blocks a still-overlapping pointer from immediately
    /// re-arming the review pose after mouse-up; a real leave/re-enter can hover again.
    private func clearPointerInteraction(commitPreview: Bool) {
        dragDirection = 0
        grabOffset = nil
        if isHovered || preview != nil {
            suppressHoverUntilExit = true
        }
        isHovered = false
        if !commitPreview, preview != nil {
            preview = nil
        }
    }

    private func finishScrub(at x: CGFloat, width: CGFloat, inset: CGFloat) {
        // Always clear drag + hover first so a zero-move click cannot leave `.review`.
        let seekTime: Double? = {
            guard interactive else { return nil }
            return time(at: x, width: width, inset: inset)
        }()
        clearPointerInteraction(commitPreview: seekTime != nil)
        // Scrub end must return to running even if the pointer is still over the band.
        suppressHoverUntilExit = true
        isHovered = false
        guard let t = seekTime else {
            preview = nil
            return
        }
        preview = t
        onSeek(t)
        preview = nil
        dragDirection = 0
        grabOffset = nil
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

    private func time(at x: CGFloat, width: CGFloat, inset: CGFloat) -> Double {
        let travel = max(width - inset * 2, 1)
        let fraction = min(1, max(0, (x - inset) / travel))
        return Double(fraction) * safeDuration
    }

    /// FNV-1a. Stable across launches so a track keeps the same waveform.
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    private static var peakCache: [String: [CGFloat]] = [:]

    private static func wavePeaks(count: Int, seed: UInt64) -> [CGFloat] {
        let key = "\(seed)-\(count)"
        if let cached = peakCache[key] { return cached }
        func noise(_ i: Int) -> CGFloat {
            var x = seed &+ UInt64(i) &* 0x9E3779B97F4A7C15
            x ^= x >> 30
            x &*= 0xBF58476D1CE4E5B9
            x ^= x >> 27
            return CGFloat(x % 1000) / 999
        }
        // Song character: hill spacing and punch come from the seed, so each
        // track gets its own contour instead of a lookalike ripple.
        let character = noise(0)
        let hill = 2 + Int(character * 7)
        let punch = 0.55 + noise(1) * 0.85
        var values = (0..<count).map { i -> CGFloat in
            let roll = (sin(CGFloat(i) / CGFloat(hill) + character * 6.2) + 1) * 0.5
            let mid = noise(i / 2 + 3)
            let fine = noise(i + 11)
            let mixed = roll * 0.55 + mid * 0.30 + fine * 0.15
            return pow(max(mixed, 0.001), punch)
        }
        guard count > 2 else { return values }
        var next = values
        for i in 1..<(count - 1) {
            next[i] = (values[i - 1] + values[i] * 2 + values[i + 1]) / 4
        }
        values = next.map { 0.22 + 0.78 * $0 }
        if peakCache.count > 24 { peakCache.removeAll(keepingCapacity: true) }
        peakCache[key] = values
        return values
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        // Truncate elapsed seconds (media convention). Rounding made 0.5s read as 0:01.
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

private enum FlowMotion {
    static func gain(index: Int, peak: CGFloat, time: TimeInterval, beat: CGFloat, playing: Bool) -> CGFloat {
        let n = CGFloat(index)
        let t = CGFloat(time)
        let travel = sin(t * 9.0 + n * 0.46)
        let swell = sin(t * 3.4 - n * 0.17)
        let flow = min(1, max(0, 0.5 + 0.5 * (travel * 0.76 + swell * 0.24)))
        let shape = 0.62 + 0.38 * min(1, max(0, peak))
        let crest = pow(flow, 1.15)
        if !playing {
            return min(1, max(0, shape * (0.35 + 0.55 * crest)))
        }
        let amp = 0.45 + 0.55 * min(1, max(0, beat))
        let body = 0.35 + 0.65 * crest
        return min(1, max(0, shape * amp * body))
    }
}

private struct BeatWaveform: View {
    @ObservedObject private var meter = AudioMeterModel.shared

    var width: CGFloat
    var height: CGFloat
    var played: CGFloat
    var peaks: [CGFloat]
    var accent: Color
    var playing: Bool
    var growsUp: Bool = false

    private static let samples = 72
    private static let echoScale: CGFloat = 1.15
    private static let echoPhase: TimeInterval = 0.28
    private static let echoIndexShift = 5
    private static let strokeWidth: CGFloat = 1.25
    private static let playheadDot: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let beat = meter.level
            let time = timeline.date.timeIntervalSinceReferenceDate
            let playedX = min(max(0, played), width)
            Canvas { context, size in
                let mid = size.height * 0.5
                let heights = Self.sampleHeights(
                    peaks: peaks,
                    time: time,
                    beat: beat,
                    playing: playing,
                    bandHeight: size.height,
                    indexShift: 0,
                    scale: 1
                )
                let echoHeights = Self.sampleHeights(
                    peaks: peaks,
                    time: time - Self.echoPhase,
                    beat: beat,
                    playing: playing,
                    bandHeight: size.height,
                    indexShift: Self.echoIndexShift,
                    scale: Self.echoScale
                )
                let fillPath = Self.ribbonPath(heights: heights, size: size, mid: mid, growsUp: growsUp)
                let echoPath = Self.ribbonPath(heights: echoHeights, size: size, mid: mid, growsUp: growsUp)
                let crestPath = Self.crestPath(heights: heights, size: size, mid: mid, growsUp: growsUp)

                Self.paintRegion(
                    context: &context,
                    rect: CGRect(x: 0, y: 0, width: playedX, height: size.height),
                    fillPath: fillPath,
                    echoPath: echoPath,
                    crestPath: crestPath,
                    size: size,
                    growsUp: growsUp,
                    fillStrong: accent.opacity(0.92),
                    fillFade: accent.opacity(0.18),
                    echoColor: accent.opacity(0.12),
                    strokeColor: accent.opacity(1.0)
                )
                Self.paintRegion(
                    context: &context,
                    rect: CGRect(x: playedX, y: 0, width: max(0, size.width - playedX), height: size.height),
                    fillPath: fillPath,
                    echoPath: echoPath,
                    crestPath: crestPath,
                    size: size,
                    growsUp: growsUp,
                    fillStrong: Color.primary.opacity(0.22),
                    fillFade: Color.primary.opacity(0.08),
                    echoColor: Color.primary.opacity(0.10),
                    strokeColor: Color.primary.opacity(0.35)
                )

                if playedX > 0.5 {
                    let crestY = Self.crestY(at: playedX, heights: heights, size: size, mid: mid, growsUp: growsUp)
                    Self.drawPlayhead(
                        context: &context,
                        x: playedX,
                        y: crestY,
                        accent: accent,
                        playing: playing,
                        time: time
                    )
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private static func sampleHeights(
        peaks: [CGFloat],
        time: TimeInterval,
        beat: CGFloat,
        playing: Bool,
        bandHeight: CGFloat,
        indexShift: Int,
        scale: CGFloat
    ) -> [CGFloat] {
        var heights = [CGFloat](repeating: 0, count: samples + 1)
        for i in 0...samples {
            let peak = peakAt(i, peaks: peaks)
            let gain = FlowMotion.gain(
                index: i + indexShift,
                peak: peak,
                time: time,
                beat: beat,
                playing: playing
            )
            heights[i] = max(2, min(bandHeight, gain * bandHeight * scale))
        }
        return heights
    }

    private static func peakAt(_ i: Int, peaks: [CGFloat]) -> CGFloat {
        guard peaks.count > 1 else { return peaks.first ?? 0.5 }
        let t = CGFloat(i) / CGFloat(samples) * CGFloat(peaks.count - 1)
        let lo = min(peaks.count - 1, Int(t))
        let hi = min(peaks.count - 1, lo + 1)
        let u = t - CGFloat(lo)
        return peaks[lo] * (1 - u) + peaks[hi] * u
    }

    private static func crestPoints(heights: [CGFloat], size: CGSize, mid: CGFloat, growsUp: Bool, upper: Bool) -> [CGPoint] {
        (0...samples).map { i in
            let x = size.width * CGFloat(i) / CGFloat(samples)
            let h = heights[i]
            if growsUp {
                return CGPoint(x: x, y: size.height - h)
            }
            let y = upper ? mid - h * 0.5 : mid + h * 0.5
            return CGPoint(x: x, y: y)
        }
    }

    /// Midpoint quadratic smoothing keeps the ribbon continuous without cubic control-point math each frame.
    private static func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        let firstMid = CGPoint(
            x: (points[0].x + points[1].x) * 0.5,
            y: (points[0].y + points[1].y) * 0.5
        )
        path.addLine(to: firstMid)
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(
                x: (points[i].x + points[i + 1].x) * 0.5,
                y: (points[i].y + points[i + 1].y) * 0.5
            )
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private static func ribbonPath(heights: [CGFloat], size: CGSize, mid: CGFloat, growsUp: Bool) -> Path {
        if growsUp {
            var path = smoothPath(through: crestPoints(heights: heights, size: size, mid: mid, growsUp: true, upper: true))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
            return path
        }
        let top = crestPoints(heights: heights, size: size, mid: mid, growsUp: false, upper: true)
        let bottom = Array(crestPoints(heights: heights, size: size, mid: mid, growsUp: false, upper: false).reversed())
        var path = smoothPath(through: top)
        appendSmooth(to: &path, points: bottom)
        path.closeSubpath()
        return path
    }

    private static func crestPath(heights: [CGFloat], size: CGSize, mid: CGFloat, growsUp: Bool) -> Path {
        if growsUp {
            return smoothPath(through: crestPoints(heights: heights, size: size, mid: mid, growsUp: true, upper: true))
        }
        var path = smoothPath(through: crestPoints(heights: heights, size: size, mid: mid, growsUp: false, upper: true))
        path.addPath(smoothPath(through: crestPoints(heights: heights, size: size, mid: mid, growsUp: false, upper: false)))
        return path
    }

    private static func appendSmooth(to path: inout Path, points: [CGPoint]) {
        guard let first = points.first else { return }
        path.addLine(to: first)
        guard points.count > 1 else { return }
        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }
        let firstMid = CGPoint(
            x: (points[0].x + points[1].x) * 0.5,
            y: (points[0].y + points[1].y) * 0.5
        )
        path.addLine(to: firstMid)
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(
                x: (points[i].x + points[i + 1].x) * 0.5,
                y: (points[i].y + points[i + 1].y) * 0.5
            )
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
    }

    private static func crestY(at x: CGFloat, heights: [CGFloat], size: CGSize, mid: CGFloat, growsUp: Bool) -> CGFloat {
        let t = min(1, max(0, x / max(size.width, 1))) * CGFloat(samples)
        let lo = min(samples, Int(t))
        let hi = min(samples, lo + 1)
        let u = t - CGFloat(lo)
        let h = heights[lo] * (1 - u) + heights[hi] * u
        if growsUp { return size.height - h }
        return mid - h * 0.5
    }

    private static func paintRegion(
        context: inout GraphicsContext,
        rect: CGRect,
        fillPath: Path,
        echoPath: Path,
        crestPath: Path,
        size: CGSize,
        growsUp: Bool,
        fillStrong: Color,
        fillFade: Color,
        echoColor: Color,
        strokeColor: Color
    ) {
        guard rect.width > 0.5 else { return }
        let gradient: Gradient
        let start: CGPoint
        let end: CGPoint
        if growsUp {
            gradient = Gradient(colors: [fillStrong, fillFade])
            start = CGPoint(x: rect.midX, y: 0)
            end = CGPoint(x: rect.midX, y: size.height)
        } else {
            gradient = Gradient(stops: [
                .init(color: fillStrong, location: 0),
                .init(color: fillFade, location: 0.5),
                .init(color: fillStrong, location: 1),
            ])
            start = CGPoint(x: rect.midX, y: 0)
            end = CGPoint(x: rect.midX, y: size.height)
        }
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            layer.fill(echoPath, with: .color(echoColor))
            layer.fill(
                fillPath,
                with: .linearGradient(gradient, startPoint: start, endPoint: end)
            )
            layer.stroke(
                crestPath,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private static func drawPlayhead(
        context: inout GraphicsContext,
        x: CGFloat,
        y: CGFloat,
        accent: Color,
        playing: Bool,
        time: TimeInterval
    ) {
        let pulse: CGFloat = playing
            ? (0.55 + 0.45 * (0.5 + 0.5 * sin(CGFloat(time) * 5.0)))
            : 0.55
        let halo = playheadDot * 2.4
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            let haloRect = CGRect(
                x: x - halo * 0.5,
                y: y - halo * 0.5,
                width: halo,
                height: halo
            )
            layer.fill(Path(ellipseIn: haloRect), with: .color(accent.opacity(0.35 * pulse)))
        }
        let dotRect = CGRect(
            x: x - playheadDot * 0.5,
            y: y - playheadDot * 0.5,
            width: playheadDot,
            height: playheadDot
        )
        context.fill(Path(ellipseIn: dotRect), with: .color(accent.opacity(0.95)))
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
