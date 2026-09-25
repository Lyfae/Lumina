import LuminaCore
import SwiftUI

/// Floating pet companion that wanders along the bottom of Studio's content area
/// (above the music bar). Only the sprite is hit-testable.
struct StudioPetCompanion: View {
    @ObservedObject private var catalog = PetCatalog.shared
    @ObservedObject private var audio = AmbientAudioManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var origin: CGPoint = .zero
    @State private var hasPlaced = false
    @State private var petState: PetState = .idle
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var waveUntil: Date? = nil
    @State private var pausedAt: Date? = nil
    @State private var wanderTask: Task<Void, Never>? = nil
    @State private var waveTask: Task<Void, Never>? = nil
    @State private var pauseTick = 0
    @State private var areaSize: CGSize = .zero

    private var petHeight: CGFloat { DisplayScale.points(64) }
    private var petWidth: CGFloat { petHeight * (192.0 / 208.0) }

    /// Keep clear of header/toolbar (~52) and music bar (~72) via insets from the overlay host.
    private var margin: CGFloat { DisplayScale.points(8) }

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
        if pausedLong { return .waiting }
        return petState
    }

    private var bobAmplitude: CGFloat {
        if reduceMotion || isDragging { return 0 }
        return audio.isPlaying ? 2.4 : 1.4
    }

    private var bobSpeed: Double {
        audio.isPlaying ? 3.2 : 2.0
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Color.clear
                    .allowsHitTesting(false)

                if isVisible, let pet = catalog.currentPet {
                    petBody(pet: pet)
                        .position(x: origin.x, y: origin.y)
                        .gesture(dragGesture(in: size))
                        .onTapGesture { pulseWave() }
                        .accessibilityLabel("Studio pet")
                        .accessibilityHint("Click to wave. Drag to move.")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(width: size.width, height: size.height)
            .onAppear {
                areaSize = size
                placeIfNeeded(in: size)
                syncPause(playing: audio.isPlaying)
                startWanderLoop(in: size)
            }
            .onChange(of: size) { _, newSize in
                areaSize = newSize
                origin = clamp(origin, in: newSize)
                if !hasPlaced { placeIfNeeded(in: newSize) }
            }
            .onChange(of: catalog.showInStudio) { _, show in
                if show {
                    placeIfNeeded(in: size)
                    startWanderLoop(in: size)
                } else {
                    wanderTask?.cancel()
                }
            }
            .onChange(of: audio.isPlaying) { _, playing in
                syncPause(playing: playing)
            }
            .onDisappear {
                wanderTask?.cancel()
                waveTask?.cancel()
            }
        }
        .allowsHitTesting(isVisible)
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
        .frame(width: petWidth, height: petHeight)
        .contentShape(Rectangle())
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = origin
                    wanderTask?.cancel()
                    petState = .jumping
                }
                let next = CGPoint(
                    x: dragStart.x + value.translation.width,
                    y: dragStart.y + value.translation.height
                )
                origin = clamp(next, in: size)
            }
            .onEnded { _ in
                isDragging = false
                petState = .idle
                startWanderLoop(in: size)
            }
    }

    private func placeIfNeeded(in size: CGSize) {
        guard size.width > petWidth, size.height > petHeight else { return }
        if !hasPlaced {
            // Start near the lower-left of the content strip.
            origin = clamp(
                CGPoint(
                    x: margin + petWidth * 0.5 + DisplayScale.points(24),
                    y: size.height - margin - petHeight * 0.35
                ),
                in: size
            )
            hasPlaced = true
        } else {
            origin = clamp(origin, in: size)
        }
    }

    private func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let halfW = petWidth * 0.5
        let halfH = petHeight * 0.5
        let minX = margin + halfW
        let maxX = max(minX, size.width - margin - halfW)
        let minY = margin + halfH
        let maxY = max(minY, size.height - margin - halfH * 0.4)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
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

    private func startWanderLoop(in size: CGSize) {
        wanderTask?.cancel()
        guard !reduceMotion, catalog.showInStudio else { return }
        wanderTask = Task { @MainActor in
            while !Task.isCancelled {
                let wait = Double.random(in: 8...15)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, !isDragging, catalog.showInStudio else { continue }
                if waveUntil != nil { continue }
                await wanderOnce(in: size)
            }
        }
    }

    private func wanderOnce(in size: CGSize) async {
        let target = clamp(
            CGPoint(
                x: CGFloat.random(in: (margin + petWidth * 0.5)...max(margin + petWidth, size.width - margin - petWidth * 0.5)),
                // Stay along the bottom edge of the content area.
                y: size.height - margin - petHeight * CGFloat.random(in: 0.25...0.55)
            ),
            in: size
        )
        let dx = target.x - origin.x
        petState = dx < -2 ? .runningLeft : (dx > 2 ? .runningRight : .idle)
        let distance = hypot(dx, target.y - origin.y)
        let duration = min(2.8, max(0.9, Double(distance) / 120.0))
        withAnimation(.easeInOut(duration: duration)) {
            origin = target
        }
        try? await Task.sleep(nanoseconds: UInt64((duration + 0.05) * 1_000_000_000))
        guard !Task.isCancelled, !isDragging else { return }
        petState = .idle
    }
}
