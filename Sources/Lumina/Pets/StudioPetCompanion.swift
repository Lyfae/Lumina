import LuminaCore
import SwiftUI

/// Free-floating Studio companion. Top-level window overlay — zero layout space.
/// Empty areas pass clicks through; only the sprite is hit-testable.
struct StudioPetCompanion: View {
    private static let posXKey = "music.pet.studio.pos.x"
    private static let posYKey = "music.pet.studio.pos.y"

    @ObservedObject private var catalog = PetCatalog.shared
    @ObservedObject private var audio = AmbientAudioManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(Self.posXKey) private var storedX: Double = -1
    @AppStorage(Self.posYKey) private var storedY: Double = -1

    @State private var origin: CGPoint = .zero
    @State private var hasPlaced = false
    @State private var windowSize: CGSize = .zero
    @State private var petState: PetState = .idle
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var waveUntil: Date? = nil
    @State private var pausedAt: Date? = nil
    @State private var wanderTask: Task<Void, Never>? = nil
    @State private var waveTask: Task<Void, Never>? = nil
    @State private var pauseTick = 0
    /// Sitting in the music widget. Wander stays off until the pet is moved out.
    @State private var anchoredInMusic = false

    private var petHeight: CGFloat { DisplayScale.points(46) * CGFloat(catalog.studioScale) }
    private var petWidth: CGFloat { petHeight * PetSprite.contentAspect(for: catalog.currentPet) }
    private var margin: CGFloat { DisplayScale.points(12) }

    private var isVisible: Bool {
        catalog.showInStudio && catalog.currentPet != nil
    }

    private var pausedLong: Bool {
        let _ = pauseTick
        guard let pausedAt, !audio.isPlaying, !isDragging else { return false }
        return Date().timeIntervalSince(pausedAt) >= 20
    }

    private var resolvedState: PetState {
        if reduceMotion { return .idle }
        if isDragging { return .jumping }
        if let waveUntil, Date() < waveUntil { return .waving }
        // Waiting is the long-pause idle face — don't clobber wander / wave / jump.
        if pausedLong, petState == .idle { return .waiting }
        return petState
    }

    private var bobAmplitude: CGFloat {
        if reduceMotion || isDragging { return 0 }
        return audio.isPlaying ? 2.2 : 1.2
    }

    private var bobSpeed: Double {
        audio.isPlaying ? 3.2 : 2.0
    }

    var body: some View {
        // Full-canvas ZStack: size probe is non-hit-testable; only the pet view receives clicks.
        // Clear regions return nil from hit-testing, so Studio chrome underneath stays clickable.
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Color.clear
                    .onAppear { handleSize(geo.size) }
                    .onChange(of: geo.size) { _, newSize in handleSize(newSize) }
            }
            .allowsHitTesting(false)

            if isVisible, let pet = catalog.currentPet, windowSize.width > 1, windowSize.height > 1 {
                petBody(pet: pet)
                    .offset(
                        x: origin.x - petWidth * 0.5,
                        y: origin.y - petHeight * 0.5
                    )
                    .gesture(dragGesture(in: windowSize))
                    .onTapGesture { pulseWave() }
                    .accessibilityLabel("Studio pet")
                    .accessibilityHint("Click to wave. Drag it anywhere.")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: catalog.studioScale) { _, _ in
            origin = clamp(origin, in: windowSize)
        }
        .onChange(of: catalog.showInStudio) { _, show in
            if show {
                placeIfNeeded(in: windowSize)
                startWanderLoop(in: windowSize)
            } else {
                stopMotionTasks()
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                wanderTask?.cancel()
                wanderTask = nil
                petState = .idle
            } else {
                startWanderLoop(in: windowSize)
            }
        }
        .onChange(of: audio.isPlaying) { _, playing in
            syncPause(playing: playing)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { note in
            guard (note.object as? NSWindow)?.title == "Music Widget" else { return }
            reevaluateMusicAnchor()
        }
        .onDisappear {
            stopMotionTasks()
        }
    }

    @ViewBuilder
    private func petBody(pet: PetInfo) -> some View {
        Group {
            if reduceMotion {
                PetSprite(state: resolvedState, height: petHeight, pet: pet)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let bob = CGFloat(sin(t * bobSpeed)) * bobAmplitude
                    PetSprite(state: resolvedState, height: petHeight, pet: pet)
                        .offset(y: bob)
                }
            }
        }
        .frame(width: petWidth, height: petHeight, alignment: .bottom)
        .contentShape(Rectangle())
    }

    private func handleSize(_ size: CGSize) {
        windowSize = size
        placeIfNeeded(in: size)
        syncPause(playing: audio.isPlaying)
        startWanderLoop(in: size)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = origin
                    wanderTask?.cancel()
                    petState = .jumping
                }
                origin = clamp(
                    CGPoint(
                        x: dragStart.x + value.translation.width,
                        y: dragStart.y + value.translation.height
                    ),
                    in: size
                )
            }
            .onEnded { _ in
                isDragging = false
                persistPosition()
                if isInMusicArea(origin, size: size) {
                    anchoredInMusic = true
                    petState = .idle
                    startWanderLoop(in: size)
                } else {
                    let leavingMusic = anchoredInMusic
                    anchoredInMusic = false
                    petState = .idle
                    startWanderLoop(in: size, resumeImmediately: leavingMusic)
                }
            }
    }

    private func placeIfNeeded(in size: CGSize) {
        guard size.width > petWidth + margin * 2, size.height > petHeight + margin * 2 else { return }
        if !hasPlaced {
            if storedX > 0, storedY > 0 {
                origin = clamp(CGPoint(x: storedX, y: storedY), in: size)
            } else {
                origin = clamp(
                    CGPoint(
                        x: margin + petWidth * 0.5 + DisplayScale.points(24),
                        y: size.height - margin - petHeight * 0.5 - DisplayScale.points(100)
                    ),
                    in: size
                )
            }
            hasPlaced = true
            persistPosition()
        } else {
            origin = clamp(origin, in: size)
        }
        if isInMusicArea(origin, size: size) {
            anchoredInMusic = true
            petState = .idle
        }
    }

    /// The dock owns the bottom of the window. The companion stays on the canvas.
    private var footerClearance: CGFloat {
        LuminaSpace.barPaddingV * 2
            + DisplayScale.points(40)
            + DisplayScale.points(8)
    }

    private func verticalRange(in size: CGSize) -> (min: CGFloat, max: CGFloat) {
        let halfH = petHeight * 0.5
        let minY = margin + halfH
        let maxY = max(minY, size.height - footerClearance - halfH)
        return (minY, maxY)
    }

    private func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let halfW = petWidth * 0.5
        let minX = margin + halfW
        let maxX = max(minX, size.width - margin - halfW)
        let yRange = verticalRange(in: size)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, yRange.min), yRange.max)
        )
    }

    private func persistPosition() {
        storedX = Double(origin.x)
        storedY = Double(origin.y)
    }

    private func pulseWave() {
        guard !reduceMotion else { return }
        waveTask?.cancel()
        waveUntil = Date().addingTimeInterval(1.5)
        petState = .waving
        waveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            waveUntil = nil
            if !isDragging { petState = .idle }
        }
    }

    private func syncPause(playing: Bool) {
        if playing {
            pausedAt = nil
        } else if pausedAt == nil {
            pausedAt = Date()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_050_000_000)
                pauseTick &+= 1
            }
        }
    }

    private func stopMotionTasks() {
        wanderTask?.cancel()
        wanderTask = nil
        waveTask?.cancel()
        waveTask = nil
        waveUntil = nil
        if !isDragging { petState = .idle }
    }

    private func startWanderLoop(in size: CGSize, resumeImmediately: Bool = false) {
        wanderTask?.cancel()
        // A cancelled mid-travel task returns before resetting pose; drop emotes so
        // the pet never rests in review / wave / jump from a killed crossing.
        if !isDragging, waveUntil == nil {
            petState = .idle
        }
        guard !reduceMotion, catalog.showInStudio, size.width > 1, size.height > 1 else {
            wanderTask = nil
            return
        }
        wanderTask = Task { @MainActor in
            var runNow = resumeImmediately
            while !Task.isCancelled {
                if anchoredInMusic {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled, !isDragging else { continue }
                    if !isInMusicArea(origin, size: size) {
                        anchoredInMusic = false
                        runNow = true
                    }
                    continue
                }
                if !runNow {
                    let wait = Double.random(in: 8...15)
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
                runNow = false
                guard !Task.isCancelled, !isDragging, catalog.showInStudio, !reduceMotion else { continue }
                if waveUntil != nil || anchoredInMusic { continue }
                await wanderOnce(in: size)
            }
        }
    }

    private func wanderOnce(in size: CGSize) async {
        if isInMusicArea(origin, size: size) {
            anchoredInMusic = true
            petState = .idle
            return
        }
        let minX = margin + petWidth * 0.5
        let maxX = max(minX, size.width - margin - petWidth * 0.5)
        let yRange = verticalRange(in: size)
        let minY = yRange.min
        let maxY = yRange.max
        guard maxX > minX, maxY > minY else { return }
        let rawTarget = clamp(
            CGPoint(
                x: CGFloat.random(in: minX...maxX),
                y: CGFloat.random(in: minY...maxY)
            ),
            in: size
        )
        let music = musicWidgetRect(in: size)
        let target: CGPoint
        let willAnchor: Bool
        if let music, let entry = musicEntry(from: origin, to: rawTarget, music: music) {
            target = clamp(entry, in: size)
            willAnchor = true
        } else {
            target = rawTarget
            willAnchor = false
        }
        let distance = hypot(target.x - origin.x, target.y - origin.y)
        guard distance > 2, let pet = catalog.currentPet else {
            petState = .idle
            return
        }
        petState = travelPose(for: pet, from: origin, to: target)
        let duration = min(2.8, max(0.9, Double(distance) / 140.0))
        withAnimation(.easeInOut(duration: duration)) {
            origin = target
        }
        try? await Task.sleep(nanoseconds: UInt64((duration + 0.05) * 1_000_000_000))
        guard !Task.isCancelled, !isDragging else { return }
        if willAnchor || isInMusicArea(origin, size: size) {
            anchoredInMusic = true
        }
        petState = .idle
        persistPosition()
    }

    /// Locomotion only, facing the travel direction. Never review / wave / jump / wait / fail.
    private func travelPose(for pet: PetInfo, from: CGPoint, to: CGPoint) -> PetState {
        let goingLeft = (to.x - from.x) < 0
        let preferred: [PetState] = goingLeft
            ? [.runningLeft, .running]
            : [.runningRight, .running]
        if let pose = preferred.first(where: { pet.hasState($0) }) {
            return pose
        }
        let loco: [PetState] = [.runningLeft, .runningRight, .running]
        return loco.first(where: { pet.hasState($0) }) ?? .idle
    }

    private func reevaluateMusicAnchor() {
        guard !isDragging, windowSize.width > 1 else { return }
        let inside = isInMusicArea(origin, size: windowSize)
        if inside {
            anchoredInMusic = true
            if waveUntil == nil { petState = .idle }
            if wanderTask == nil {
                startWanderLoop(in: windowSize)
            }
        } else if anchoredInMusic {
            anchoredInMusic = false
            startWanderLoop(in: windowSize, resumeImmediately: true)
        }
    }

    private func isInMusicArea(_ center: CGPoint, size: CGSize) -> Bool {
        guard let music = musicWidgetRect(in: size) else { return false }
        return petFrame(center).intersects(music)
    }

    private func petFrame(_ center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - petWidth * 0.5,
            y: center.y - petHeight * 0.5,
            width: petWidth,
            height: petHeight
        )
    }

    /// Music widget frame in this overlay's top-left coordinates, if it overlaps Studio.
    private func musicWidgetRect(in size: CGSize) -> CGRect? {
        guard size.width > 1, size.height > 1,
              let widget = NSApp.windows.first(where: { $0.title == "Music Widget" && $0.isVisible }),
              let studio = NSApp.windows.first(where: { $0.title == "Lumina Studio" })
        else { return nil }
        let content = studio.contentRect(forFrameRect: studio.frame)
        let overlap = content.intersection(widget.frame)
        guard !overlap.isNull, overlap.width > 1, overlap.height > 1 else { return nil }
        return CGRect(
            x: overlap.minX - content.minX,
            y: content.maxY - overlap.maxY,
            width: overlap.width,
            height: overlap.height
        )
    }

    /// Where a straight run first enters the widget, nudged just inside so the pet can sit there.
    private func musicEntry(from start: CGPoint, to end: CGPoint, music: CGRect) -> CGPoint? {
        if music.contains(start) { return start }
        if music.contains(end) { return end }
        let dx = end.x - start.x
        let dy = end.y - start.y
        var bestT: CGFloat = 2
        func consider(_ t: CGFloat) {
            guard t > 0.02, t < 0.98, t < bestT else { return }
            let p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            let onEdge = abs(p.x - music.minX) < 1.5 || abs(p.x - music.maxX) < 1.5
                || abs(p.y - music.minY) < 1.5 || abs(p.y - music.maxY) < 1.5
            guard onEdge, music.insetBy(dx: -1, dy: -1).contains(p) else { return }
            bestT = t
        }
        if abs(dx) > 0.001 {
            consider((music.minX - start.x) / dx)
            consider((music.maxX - start.x) / dx)
        }
        if abs(dy) > 0.001 {
            consider((music.minY - start.y) / dy)
            consider((music.maxY - start.y) / dy)
        }
        guard bestT <= 1 else { return nil }
        let len = max(hypot(dx, dy), 1)
        let inside = CGPoint(
            x: start.x + dx * bestT + (dx / len) * 10,
            y: start.y + dy * bestT + (dy / len) * 10
        )
        return music.contains(inside) ? inside : CGPoint(x: start.x + dx * bestT, y: start.y + dy * bestT)
    }
}
