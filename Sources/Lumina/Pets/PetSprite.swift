import AppKit
import LuminaCore
import SwiftUI

/// Draws one cached atlas frame for `pet` (or `PetCatalog.shared.currentPet`).
///
/// Atlas cells are heavily padded (~40–60% empty). `height` is the standing
/// character’s visible height. Hover, wave, and jump draw their own extra pixels
/// outside that box so raised fins, wings, and sparkles are not cropped away.
struct PetSprite: View {
    var state: PetState
    /// Visible character height in points (opaque content fills this exactly).
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

    /// Width / height of the opaque content box (falls back to cell aspect).
    private var contentAspect: CGFloat {
        Self.contentAspect(for: resolved)
    }

    var body: some View {
        let width = height * contentAspect
        Group {
            if shouldAnimate {
                // One frame only. A still copy underneath shows through while the
                // character leaves the ground, which reads as an afterimage.
                TimelineView(.periodic(from: .now, by: 1.0 / max(fps, 1))) { context in
                    frameContent(date: context.date)
                }
            } else if let first = frames.first {
                staticFrame(first, bob: 0)
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
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
        let layoutWidth = height * contentAspect
        let placed = Self.placedFrame(image, pet: resolved, state: state, height: height)
        // Layout slot stays the standing box so the playhead does not jump between poses.
        // Extra pixels (review fins, wave sparkles, jump) hang outside that slot.
        return Image(decorative: placed.image, scale: placed.scale)
            .interpolation(.high)
            .offset(x: placed.offsetX, y: placed.offsetY + bob)
            .frame(width: layoutWidth, height: height, alignment: .bottom)
    }

    // MARK: - Content bounds (cached per pet)

    /// Opaque-content aspect ratio (width / height). Stable across states.
    static func contentAspect(for pet: PetInfo?) -> CGFloat {
        guard let pet, let bounds = contentBounds(for: pet) else {
            return 192.0 / 208.0
        }
        return CGFloat(bounds.width) / CGFloat(max(bounds.height, 1))
    }

    private struct SpriteMetrics {
        /// Unpadded opaque union of the standing poses. Scale reference.
        var standing: CGRect
        /// Unpadded opaque union of each pose.
        var poses: [PetState: CGRect]
        var cellWidth: Int
        var cellHeight: Int
    }

    private struct PlacedFrame {
        var image: CGImage
        var scale: CGFloat
        var offsetX: CGFloat
        var offsetY: CGFloat
    }

    private static let cacheLock = NSLock()
    private static var metricsCache: [String: SpriteMetrics] = [:]
    /// Standing poses. Jump, wave, and hover raise pixels outside this box.
    private static let groundedStates: [PetState] = [.idle, .running, .runningLeft, .runningRight]

    /// Padded standing box. `height` maps to this box, so idle is not letterboxed
    /// by taller poses. Y matches `CGImage.cropping(to:)`.
    static func contentBounds(for pet: PetInfo) -> CGRect? {
        guard let metrics = metrics(for: pet) else { return nil }
        return padded(metrics.standing, cellWidth: metrics.cellWidth, cellHeight: metrics.cellHeight)
    }

    private static func metrics(for pet: PetInfo) -> SpriteMetrics? {
        cacheLock.lock()
        if let cached = metricsCache[pet.slug] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var poses: [PetState: CGRect] = [:]
        for state in PetState.allCases {
            var minX = Int.max
            var minY = Int.max
            var maxX = Int.min
            var maxY = Int.min
            var found = false
            for frame in pet.frames(for: state) {
                guard let box = opaqueBounds(of: frame) else { continue }
                found = true
                minX = min(minX, Int(box.minX.rounded(.down)))
                minY = min(minY, Int(box.minY.rounded(.down)))
                maxX = max(maxX, Int(box.maxX.rounded(.down)) - 1)
                maxY = max(maxY, Int(box.maxY.rounded(.down)) - 1)
            }
            guard found, maxX >= minX, maxY >= minY else { continue }
            poses[state] = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }

        let standingSource = groundedStates.compactMap { poses[$0] }
        let standing = union(of: standingSource.isEmpty ? Array(poses.values) : standingSource)
        guard let standing else { return nil }

        let cellW: Int
        let cellH: Int
        if let sample = pet.frames(for: .idle).first ?? pet.frames(for: .runningRight).first {
            cellW = sample.width
            cellH = sample.height
        } else {
            cellW = pet.cellWidth
            cellH = pet.cellHeight
        }

        let metrics = SpriteMetrics(standing: standing, poses: poses, cellWidth: cellW, cellHeight: cellH)
        cacheLock.lock()
        metricsCache[pet.slug] = metrics
        cacheLock.unlock()
        return metrics
    }

    /// Crop includes this pose’s extra pixels. Scale stays locked to the standing box
    /// so a hover pose does not shrink the pet, and the standing feet stay on the baseline.
    private static func placedFrame(_ image: CGImage, pet: PetInfo?, state: PetState, height: CGFloat) -> PlacedFrame {
        guard let pet, let metrics = metrics(for: pet) else {
            let scale = max(CGFloat(image.height) / max(height, 1), 0.01)
            return PlacedFrame(image: image, scale: scale, offsetX: 0, offsetY: 0)
        }
        let standing = padded(metrics.standing, cellWidth: metrics.cellWidth, cellHeight: metrics.cellHeight)
        let pose = metrics.poses[state] ?? metrics.standing
        let crop = padded(union(of: [metrics.standing, pose]) ?? metrics.standing, cellWidth: metrics.cellWidth, cellHeight: metrics.cellHeight)
        let clamped = CGRect(
            x: max(0, min(crop.origin.x, CGFloat(image.width - 1))),
            y: max(0, min(crop.origin.y, CGFloat(image.height - 1))),
            width: min(crop.width, CGFloat(image.width) - max(0, crop.origin.x)),
            height: min(crop.height, CGFloat(image.height) - max(0, crop.origin.y))
        )
        guard clamped.width >= 1, clamped.height >= 1, let cropped = image.cropping(to: clamped) else {
            let scale = max(standing.height / max(height, 1), 0.01)
            return PlacedFrame(image: image, scale: scale, offsetX: 0, offsetY: 0)
        }
        let scale = max(standing.height / max(height, 1), 0.01)
        // The image is centered in the standing slot, then shifted so that slot
        // stays put while pose pixels hang off the sides and above the head.
        let offsetX = (clamped.midX - standing.midX) / scale
        let offsetY = (standing.minY - clamped.minY) / scale
        return PlacedFrame(image: cropped, scale: scale, offsetX: offsetX, offsetY: offsetY)
    }

    private static func union(of rects: [CGRect]) -> CGRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result
    }

    /// 1px pad so anti-aliased edges aren’t clipped. Clamped to the cell.
    private static func padded(_ rect: CGRect, cellWidth: Int, cellHeight: Int) -> CGRect {
        let pad: CGFloat = 1
        let x = max(0, rect.minX - pad)
        let y = max(0, rect.minY - pad)
        let maxX = min(CGFloat(cellWidth), rect.maxX + pad)
        let maxY = min(CGFloat(cellHeight), rect.maxY + pad)
        return CGRect(x: x, y: y, width: max(1, maxX - x), height: max(1, maxY - y))
    }

    /// Opaque pixel bounds in CGImage coordinates (origin bottom-left).
    private static func opaqueBounds(of image: CGImage) -> CGRect? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(
                  data: nil,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Row 0 of this buffer matches CGImage y = 0, the same space cropping(to:) uses.
        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w {
                if ptr[row + x * 4 + 3] > 16 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}
