import SwiftUI

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

    @State private var isDragging = false
    @State private var dragStartRect: CGRect = .zero
    @State private var activeHandle: CropHandle? = nil

    private let minSize: CGFloat = 0.05
    private let handleSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .local)
            let rect = denormalizedRect(in: frame)

            ZStack {
                // Background: show the actual wallpaper content (full, uncropped)
                // so the user can visually choose the crop region.
                if let assignment = assignment {
                    WallpaperPreview(
                        assignment: assignment,
                        liveCropRect: CGRect(x: 0, y: 0, width: 1, height: 1), // Always show full for the editor
                        liveScaling: nil,
                        targetAspect: 16.0 / 9.0,
                        previewTime: previewTime
                    )
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    // Fallback when no media is assigned yet
                    Color.black.opacity(0.7)
                }

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
                    .gesture(dragGesture(in: frame))

                // Four corner resize handles
                ForEach(CropHandle.allCases, id: \.self) { handle in
                    handleView(for: handle, in: rect)
                        .gesture(resizeGesture(for: handle, in: frame))
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
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

                newRect = clampedToBounds(newRect)
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
