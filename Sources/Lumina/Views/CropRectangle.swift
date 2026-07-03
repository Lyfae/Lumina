import SwiftUI
import AVFoundation

/// High-quality draggable + resizable crop rectangle for the Lumina Wallpaper Manager.
/// Designed to feel premium and precise, like professional video editing tools.
/// - Supports dragging the whole rect
/// - Supports resizing from four corners
/// - Live clamping to [0,1] bounds with minimum size
/// - Reports normalized CGRect back to parent
struct CropRectangle: View {
    @Binding var cropRect: CGRect   // Normalized 0-1, top-left origin
    var onChange: (CGRect) -> Void = { _ in }

    // Optional: the actual media to show as background so user can see what they're cropping
    var assignment: MonitorAssignment? = nil
    var previewTime: Double? = nil

    /// If provided, the crop rectangle will be constrained to this aspect ratio (e.g. the monitor's aspect).
    /// This ensures the selected region matches what the target display will show.
    var targetAspect: CGFloat? = nil

    /// Pre-resolved source aspect from the parent — avoids a 16:9 placeholder layout that
    /// jumps when the async probe finishes (the main cause of the preview shifting on enter).
    var sourceAspect: CGFloat? = nil

    // Match WallpaperPreview WYSIWYG effects so entering crop mode doesn't change brightness/color.
    var brightness: Double = 0
    var previewOpacity: Double = 1
    var saturation: Double = 1
    var hueDegrees: Double = 0
    var grayscale: Bool = false

    @State private var isDragging = false
    @State private var dragStartRect: CGRect = .zero
    @State private var activeHandle: CropHandle? = nil
    @State private var resolvedSourceAspect: CGFloat = 16.0 / 9.0

    private let previewCornerRadius: CGFloat = 10

    private let minSize: CGFloat = 0.05
    private let handleSize: CGFloat = 14

    private var effectiveSourceAspect: CGFloat {
        resolvedSourceAspect
    }

    /// The aspect to lock the *normalized* cropRect to.
    /// To make the on-screen box have the monitor's aspect (targetAspect), while the background shows the full source,
    /// the normalized rect must have aspect = targetAspect / sourceAspect.
    private var normalizedLockAspect: CGFloat {
        guard let target = targetAspect, effectiveSourceAspect > 0 else {
            return targetAspect ?? 16.0 / 9.0
        }
        return target / effectiveSourceAspect
    }

    /// Fits the source media into the available bounds while preserving the source's aspect ratio.

    private func fittedMediaRect(in bounds: CGRect) -> CGRect {
        let aspect = effectiveSourceAspect
        if aspect <= 0 { return bounds }
        let availableAspect = bounds.width / max(bounds.height, 1.0)
        let w: CGFloat
        let h: CGFloat
        if aspect >= availableAspect {
            w = bounds.width
            h = w / aspect
        } else {
            h = bounds.height
            w = h * aspect
        }
        let x = bounds.midX - w / 2
        let y = bounds.midY - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .local)
            let mediaR = fittedMediaRect(in: frame)
            let rect = denormalizedRect(in: mediaR)

            ZStack {
                // Same chrome as WallpaperPreview so the swap into crop mode doesn't resize the frame.
                RoundedRectangle(cornerRadius: previewCornerRadius)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: previewCornerRadius)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    )

                // Background: show the actual wallpaper content (full, uncropped)
                // so the user can visually choose the crop region.
                // Use mediaR so vertical sources show full undistorted (not squeezed to screen aspect).
                if let assignment = assignment {
                    WallpaperPreview(
                        assignment: assignment,
                        liveCropRect: CGRect(x: 0, y: 0, width: 1, height: 1), // Always show full for the editor
                        liveScaling: .fit,
                        targetAspect: effectiveSourceAspect,
                        previewTime: previewTime,
                        ignoreAspectRatio: true,
                        brightness: brightness,
                        previewOpacity: previewOpacity,
                        saturation: saturation,
                        hueDegrees: hueDegrees,
                        grayscale: grayscale
                    )
                    .frame(width: mediaR.width, height: mediaR.height)
                    .position(x: mediaR.midX, y: mediaR.midY)
                    .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius - 2))
                } else {
                    Color.black.opacity(0.7)
                }

                // Subtle border to clearly show the bounds of the *full original frame*
                RoundedRectangle(cornerRadius: previewCornerRadius - 2)
                    .stroke(Color.primary.opacity(0.28), lineWidth: 1)
                    .frame(width: mediaR.width, height: mediaR.height)
                    .position(x: mediaR.midX, y: mediaR.midY)

                // The crop rectangle overlay (semi-transparent with border)
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white, lineWidth: 1.5)
                            .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(dragGesture(in: mediaR))

                // Four corner resize handles
                ForEach(CropHandle.allCases, id: \.self) { handle in
                    handleView(for: handle, in: rect)
                        .gesture(resizeGesture(for: handle, in: mediaR))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
        .task(id: assignment?.filePath) {
            if let sourceAspect, sourceAspect > 0 {
                resolvedSourceAspect = sourceAspect
            }
            let computed = await Self.resolveSourceAspect(for: assignment) ?? sourceAspect ?? 16.0 / 9.0
            if abs(computed - resolvedSourceAspect) > 0.001 {
                resolvedSourceAspect = computed
            }
        }
        .onChange(of: sourceAspect) { _, newValue in
            if let newValue, newValue > 0 {
                resolvedSourceAspect = newValue
            }
        }
        .task(id: [targetAspect, resolvedSourceAspect]) {
            guard targetAspect != nil, normalizedLockAspect > 0 else { return }

            // Only auto-initialize when no crop has been chosen yet (full-frame sentinel).
            // Re-entering the editor with a saved crop must preserve position/size — do not
            // reset just because resolvedSourceAspect finishes loading asynchronously.
            guard cropRect == CGRect(x: 0, y: 0, width: 1, height: 1) else { return }

            let targetNormAspect = normalizedLockAspect

            // Start with a reasonably sized horizontal crop box on the full original.
            let scale: CGFloat = 0.75
            var w: CGFloat = min(0.9, scale)
            var h: CGFloat = w / targetNormAspect

            // If the computed height is too tall for the source, shrink width
            if h > 0.9 {
                h = 0.6
                w = h * targetNormAspect
            }

            let x = (1 - w) / 2
            let y = (1 - h) / 2   // centered vertically on the tall frame

            let newR = CGRect(x: max(0, x), y: max(0, y), width: min(1, w), height: min(1, h))
            if newR != cropRect {
                cropRect = newR
                onChange(newR)
            }
        }
    }

    private func denormalizedRect(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + cropRect.minX * bounds.width,
            y: bounds.minY + cropRect.minY * bounds.height,
            width: cropRect.width * bounds.width,
            height: cropRect.height * bounds.height
        )
    }

    private func normalizedRect(from pixelRect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: (pixelRect.minX - bounds.minX) / max(bounds.width, 1),
            y: (pixelRect.minY - bounds.minY) / max(bounds.height, 1),
            width: pixelRect.width / max(bounds.width, 1),
            height: pixelRect.height / max(bounds.height, 1)
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func resolveSourceAspect(for assignment: MonitorAssignment?) async -> CGFloat? {
        guard let assignment else { return nil }
        let url: URL? = assignment.resolvedURL() ?? (assignment.filePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
        guard let url else { return nil }

        let asset = AVURLAsset(url: url)
        if let tracks = try? await asset.loadTracks(withMediaType: AVMediaType.video), let track = tracks.first {
            if let naturalSize = try? await track.load(.naturalSize), naturalSize.width > 0, naturalSize.height > 0 {
                let transform = (try? await track.load(.preferredTransform)) ?? .identity
                let displayRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
                let w = abs(displayRect.width)
                let h = abs(displayRect.height)
                if w > 0, h > 0 { return w / h }
            }
        }
        let mediaType = assignment.mediaType
        nonisolated(unsafe) let sendableMediaType = mediaType
        let thumb = await ThumbnailService.shared.thumbnail(for: url, mediaType: sendableMediaType, maxSize: CGSize(width: 64, height: 64))
        if let thumb, thumb.size.height > 0 {
            return thumb.size.width / thumb.size.height
        }
        return nil
    }

    // MARK: - Gestures

    private func dragGesture(in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartRect = cropRect
                }

                let deltaX = value.translation.width / max(bounds.width, 1)
                let deltaY = value.translation.height / max(bounds.height, 1)

                var newRect = dragStartRect
                newRect.origin.x += deltaX
                newRect.origin.y += deltaY

                newRect = clampedToBounds(newRect)
                newRect = enforceTargetAspect(newRect)
                cropRect = newRect
                onChange(newRect)
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private func resizeGesture(for handle: CropHandle, in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeHandle == nil {
                    activeHandle = handle
                    dragStartRect = cropRect
                }

                let deltaX = value.translation.width / max(bounds.width, 1)
                let deltaY = value.translation.height / max(bounds.height, 1)

                var newRect = dragStartRect

                // Apply free deltas first (tentative)
                switch handle {
                case .topLeft:
                    newRect.origin.x += deltaX
                    newRect.origin.y += deltaY
                    newRect.size.width -= deltaX
                    newRect.size.height -= deltaY
                case .topRight:
                    newRect.origin.y += deltaY
                    newRect.size.width += deltaX
                    newRect.size.height -= deltaY
                case .bottomLeft:
                    newRect.origin.x += deltaX
                    newRect.size.width -= deltaX
                    newRect.size.height += deltaY
                case .bottomRight:
                    newRect.size.width += deltaX
                    newRect.size.height += deltaY
                }

                // Strictly enforce target aspect (horizontal for typical monitors) by anchoring the opposite corner.
                // This ensures the rect is always wider than tall when targetAspect > 1 (16:9 etc.).
                let aspect = normalizedLockAspect; if aspect > 0 {
                    // Fixed corner (opposite to the handle being dragged)
                    let fixedX = (handle == .topRight || handle == .bottomRight) ? newRect.minX : newRect.maxX
                    let fixedY = (handle == .bottomLeft || handle == .bottomRight) ? newRect.minY : newRect.maxY

                    // Current tentative moving corner
                    let moveX = (handle == .topLeft || handle == .bottomLeft) ? newRect.minX : newRect.maxX
                    let moveY = (handle == .topLeft || handle == .topRight) ? newRect.minY : newRect.maxY

                    var dw = abs(moveX - fixedX)
                    var dh = abs(moveY - fixedY)

                    // Force aspect: for wide aspect (horizontal box), compute the matching dimension
                    if aspect >= 1.0 {
                        // Prefer driving from width to keep it horizontal (L longer)
                        dh = dw / aspect
                    } else {
                        dw = dh * aspect
                    }

                    dw = max(minSize, dw)
                    dh = max(minSize, dh)

                    // Rebuild the rect from the fixed corner with the aspect-correct size
                    let newMinX = (handle == .topLeft || handle == .bottomLeft) ? fixedX - dw : fixedX
                    let newMaxX = (handle == .topLeft || handle == .bottomLeft) ? fixedX : fixedX + dw
                    let newMinY = (handle == .topLeft || handle == .topRight) ? fixedY - dh : fixedY
                    let newMaxY = (handle == .topLeft || handle == .topRight) ? fixedY : fixedY + dh

                    newRect = CGRect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
                }

                newRect = clampedToBounds(newRect)
                // Extra safety: force the aspect one more time using the simple enforcer
                newRect = enforceTargetAspect(newRect)
                cropRect = newRect
                onChange(newRect)
            }
            .onEnded { _ in
                activeHandle = nil
            }
    }

    /// Clamps a normalized rect so it stays fully within [0,1]×[0,1]
    /// and respects the minimum size on both axes.
    private func clampedToBounds(_ rect: CGRect) -> CGRect {
        var r = rect

        // Clamp origin to valid range first
        r.origin.x = max(0, r.origin.x)
        r.origin.y = max(0, r.origin.y)

        // Clamp size so the rect doesn't overflow 1.0 on either axis
        r.size.width  = max(minSize, min(1 - r.origin.x, r.size.width))
        r.size.height = max(minSize, min(1 - r.origin.y, r.size.height))

        // Re-clamp origin in case a corner handle moved it negative
        // (e.g. topLeft dragged past the right/bottom edge)
        r.origin.x = max(0, min(1 - r.size.width,  r.origin.x))
        r.origin.y = max(0, min(1 - r.size.height, r.origin.y))

        return r
    }

    /// If a targetAspect (monitor aspect) is set, adjust the rect so its width/height matches exactly.
    /// For typical monitors (aspect > 1) this forces a horizontal rectangle (wider than tall)
    /// so you can select a 16:9 (or monitor aspect) horizontal band from the vertical source.
    private func enforceTargetAspect(_ rect: CGRect) -> CGRect {
        let aspect = normalizedLockAspect; guard aspect > 0 else { return rect }
        var r = rect

        // Always compute height from width for wide aspect to keep it horizontal (L longer)
        var w = max(minSize, r.width)
        var h = w / aspect

        // If it doesn't fit vertically, shrink the width instead
        if r.origin.y + h > 1.0 {
            h = max(minSize, 1.0 - r.origin.y)
            w = h * aspect
        }
        if r.origin.y < 0 {
            h = max(minSize, r.height)
            w = h * aspect
        }

        // Also respect horizontal bounds
        if r.origin.x + w > 1.0 {
            w = max(minSize, 1.0 - r.origin.x)
            h = w / aspect
        }

        r.size.width = w
        r.size.height = h

        // Re-clamp origin to keep it inside
        r.origin.x = max(0, min(1 - r.size.width, r.origin.x))
        r.origin.y = max(0, min(1 - r.size.height, r.origin.y))

        return r
    }

    private func handleView(for handle: CropHandle, in rect: CGRect) -> some View {
        let position: CGPoint = {
            switch handle {
            case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }()

        return Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            .position(position)
            .shadow(radius: 1)
    }

    private enum CropHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

// Preview disabled for SPM `swift test` compatibility (requires Xcode Previews macro plugin).
// Works fine when opened in Xcode.
// #Preview { ... }
