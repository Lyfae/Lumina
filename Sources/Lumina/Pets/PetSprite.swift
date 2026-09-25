import AppKit
import LuminaCore
import SwiftUI

/// Draws one cached atlas frame for `pet` (or `PetCatalog.shared.currentPet`). Cheap: no per-frame decode.
struct PetSprite: View {
    var state: PetState
    var height: CGFloat
    var pet: PetInfo? = nil

    @ObservedObject private var catalog = PetCatalog.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    private var resolved: PetInfo? { pet ?? catalog.currentPet }

    private var frames: [CGImage] {
        resolved?.frames(for: state) ?? []
    }

    private var fps: Double {
        resolved?.fps(for: state) ?? 8
    }

    private var shouldAnimate: Bool {
        isVisible && !reduceMotion && frames.count > 1
    }

    private var shouldBob: Bool {
        !reduceMotion && (state == .runningRight || state == .runningLeft || state == .running)
    }

    var body: some View {
        Group {
            if shouldAnimate {
                // Always keep a static first frame underneath — TimelineView can
                // fail to paint in non-key / nonactivating panels (music widget).
                ZStack {
                    if let first = frames.first {
                        staticFrame(first, bob: 0)
                    }
                    TimelineView(.periodic(from: .now, by: 1.0 / max(fps, 1))) { context in
                        frameContent(date: context.date)
                    }
                }
            } else if let first = frames.first {
                staticFrame(first, bob: 0)
            } else {
                Color.clear
                    .frame(width: height * (192 / 208), height: height)
            }
        }
        .frame(height: height)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func frameContent(date: Date) -> some View {
        let count = max(frames.count, 1)
        let index = Int(date.timeIntervalSinceReferenceDate * fps) % count
        let image = frames[index]
        let bob: CGFloat = shouldBob
            ? CGFloat(sin(date.timeIntervalSinceReferenceDate * 9.0)) * 1.5
            : 0
        staticFrame(image, bob: bob)
    }

    private func staticFrame(_ image: CGImage, bob: CGFloat) -> some View {
        let scale = CGFloat(image.height) / max(height, 1)
        return Image(decorative: image, scale: max(scale, 0.01))
            .interpolation(.high)
            .offset(y: bob)
    }
}
