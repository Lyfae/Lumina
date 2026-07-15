import SwiftUI
import AVFoundation

/// Interactive crop editor — drag to reposition, corners to resize, dimmed area outside the crop.
/// Crop is stored as a normalized `CGRect` (0–1, top-left origin) locked to the monitor aspect.
struct CropRectangle: View {
    @Binding var cropRect: CGRect
    var onChange: (CGRect) -> Void = { _ in }

    var assignment: MonitorAssignment? = nil
    var previewTime: Double? = nil
    var targetAspect: CGFloat? = nil
    var sourceAspect: CGFloat? = nil

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
    private var handleArm: CGFloat { DisplayScale.points(18) }
    private var handleHit: CGFloat { DisplayScale.points(44) }

    private var effectiveSourceAspect: CGFloat { resolvedSourceAspect }

    private var normalizedLockAspect: CGFloat {
        guard let target = targetAspect, effectiveSourceAspect > 0 else {
            return targetAspect ?? 16.0 / 9.0
        }
        return target / effectiveSourceAspect
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .local)
            let mediaR = fittedMediaRect(in: frame)
            let cropR = denormalizedRect(in: mediaR)
            let isInteracting = isDragging || activeHandle != nil

            ZStack {
                previewChrome

                if let assignment {
                    WallpaperPreview(
                        assignment: assignment,
                        liveCropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                        liveScaling: .fit,
                        targetAspect: effectiveSourceAspect,
                        previewTime: previewTime,
                        ignoreAspectRatio: true,
                        showsChrome: false,
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
                        .frame(width: mediaR.width, height: mediaR.height)
                        .position(x: mediaR.midX, y: mediaR.midY)
                }

                // Dim everything outside the crop — standard photo-editor pattern.
                CropDimMask(mediaRect: mediaR, cropRect: cropR)
                    .allowsHitTesting(false)

                if isInteracting {
                    CropGridOverlay(rect: cropR)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Crop frame + drag surface
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.45), radius: 3)
                    .frame(width: cropR.width, height: cropR.height)
                    .position(x: cropR.midX, y: cropR.midY)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: cropR.width, height: cropR.height)
                    .position(x: cropR.midX, y: cropR.midY)
                    .gesture(dragGesture(in: mediaR))

                ForEach(CropHandle.allCases, id: \.self) { handle in
                    CropCornerHandle(alignment: handle.bracketAlignment, armLength: handleArm)
                        .position(handle.anchor(in: cropR, arm: handleArm))
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(width: handleHit, height: handleHit)
                        .contentShape(Rectangle())
                        .position(handle.position(in: cropR))
                        .gesture(resizeGesture(for: handle, in: mediaR))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .animation(.easeOut(duration: 0.12), value: activeHandle?.rawValue)
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
            if let newValue, newValue > 0 { resolvedSourceAspect = newValue }
        }
        .task(id: [targetAspect, resolvedSourceAspect]) {
            guard targetAspect != nil, normalizedLockAspect > 0 else { return }
            guard cropRect == CGRect(x: 0, y: 0, width: 1, height: 1) else { return }
            let newR = Self.centeredCrop(normalizedAspect: normalizedLockAspect, scale: 0.88)
            if newR != cropRect {
                cropRect = newR
                onChange(newR)
            }
        }
    }

    private var previewChrome: some View {
        RoundedRectangle(cornerRadius: previewCornerRadius)
            .fill(Color.black.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: previewCornerRadius)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
    }

    // MARK: - Public helpers

    /// Largest normalized width that fits in the source with the given aspect.
    static func maxCropWidth(normalizedAspect: CGFloat) -> CGFloat {
        guard normalizedAspect > 0 else { return 0.95 }
        var w: CGFloat = 0.95
        var h = w / normalizedAspect
        if h > 0.95 {
            h = 0.95
            w = h * normalizedAspect
        }
        return w
    }

    /// Centered crop rect; `scale` 1.0 = as large as possible, lower = zoomed in.
    static func centeredCrop(normalizedAspect: CGFloat, scale: CGFloat, minSize: CGFloat = 0.05) -> CGRect {
        guard normalizedAspect > 0 else {
            return CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        }
        let clampedScale = min(max(scale, 0.15), 1.0)
        var w = max(minSize, maxCropWidth(normalizedAspect: normalizedAspect) * clampedScale)
        var h = w / normalizedAspect
        if h > 0.98 {
            h = 0.98
            w = h * normalizedAspect
        }
        w = max(minSize, min(1, w))
        h = max(minSize, min(1, h))
        return CGRect(
            x: max(0, (1 - w) / 2),
            y: max(0, (1 - h) / 2),
            width: w,
            height: h
        )
    }

    static func resolveSourceAspect(for assignment: MonitorAssignment?) async -> CGFloat? {
        guard let assignment else { return nil }
        let url: URL? = assignment.resolvedURL()
            ?? assignment.filePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        guard let url else { return nil }

        let asset = AVURLAsset(url: url)
        if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
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
        let thumb = await ThumbnailService.shared.thumbnail(
            for: url, mediaType: sendableMediaType, maxSize: CGSize(width: 64, height: 64)
        )
        if let thumb, thumb.size.height > 0 {
            return thumb.size.width / thumb.size.height
        }
        return nil
    }

    // MARK: - Geometry

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
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    private func denormalizedRect(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + cropRect.minX * bounds.width,
            y: bounds.minY + cropRect.minY * bounds.height,
            width: cropRect.width * bounds.width,
            height: cropRect.height * bounds.height
        )
    }

    // MARK: - Gestures

    private func dragGesture(in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartRect = cropRect
                }
                var newRect = dragStartRect
                newRect.origin.x += value.translation.width / max(bounds.width, 1)
                newRect.origin.y += value.translation.height / max(bounds.height, 1)
                newRect = clampedToBounds(newRect)
                newRect = enforceTargetAspect(newRect)
                cropRect = newRect
                onChange(newRect)
            }
            .onEnded { _ in isDragging = false }
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

                let aspect = normalizedLockAspect
                if aspect > 0 {
                    let fixedX = (handle == .topRight || handle == .bottomRight) ? newRect.minX : newRect.maxX
                    let fixedY = (handle == .bottomLeft || handle == .bottomRight) ? newRect.minY : newRect.maxY
                    let moveX = (handle == .topLeft || handle == .bottomLeft) ? newRect.minX : newRect.maxX
                    let moveY = (handle == .topLeft || handle == .topRight) ? newRect.minY : newRect.maxY

                    var dw = abs(moveX - fixedX)
                    var dh = abs(moveY - fixedY)
                    if aspect >= 1.0 {
                        dh = dw / aspect
                    } else {
                        dw = dh * aspect
                    }
                    dw = max(minSize, dw)
                    dh = max(minSize, dh)

                    let newMinX = (handle == .topLeft || handle == .bottomLeft) ? fixedX - dw : fixedX
                    let newMaxX = (handle == .topLeft || handle == .bottomLeft) ? fixedX : fixedX + dw
                    let newMinY = (handle == .topLeft || handle == .topRight) ? fixedY - dh : fixedY
                    let newMaxY = (handle == .topLeft || handle == .topRight) ? fixedY : fixedY + dh
                    newRect = CGRect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
                }

                newRect = clampedToBounds(newRect)
                newRect = enforceTargetAspect(newRect)
                cropRect = newRect
                onChange(newRect)
            }
            .onEnded { _ in activeHandle = nil }
    }

    private func clampedToBounds(_ rect: CGRect) -> CGRect {
        var r = rect
        r.origin.x = max(0, r.origin.x)
        r.origin.y = max(0, r.origin.y)
        r.size.width = max(minSize, min(1 - r.origin.x, r.size.width))
        r.size.height = max(minSize, min(1 - r.origin.y, r.size.height))
        r.origin.x = max(0, min(1 - r.size.width, r.origin.x))
        r.origin.y = max(0, min(1 - r.size.height, r.origin.y))
        return r
    }

    private func enforceTargetAspect(_ rect: CGRect) -> CGRect {
        let aspect = normalizedLockAspect
        guard aspect > 0 else { return rect }
        var r = rect
        var w = max(minSize, r.width)
        var h = w / aspect
        if r.origin.y + h > 1.0 {
            h = max(minSize, 1.0 - r.origin.y)
            w = h * aspect
        }
        if r.origin.x + w > 1.0 {
            w = max(minSize, 1.0 - r.origin.x)
            h = w / aspect
        }
        r.size.width = w
        r.size.height = h
        r.origin.x = max(0, min(1 - r.size.width, r.origin.x))
        r.origin.y = max(0, min(1 - r.size.height, r.origin.y))
        return r
    }

    private enum CropHandle: String, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        func position(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }

        /// Positions the visible L-bracket so its corner sits on the crop vertex.
        func anchor(in rect: CGRect, arm: CGFloat) -> CGPoint {
            let p = position(in: rect)
            switch self {
            case .topLeft: return CGPoint(x: p.x + arm / 2, y: p.y + arm / 2)
            case .topRight: return CGPoint(x: p.x - arm / 2, y: p.y + arm / 2)
            case .bottomLeft: return CGPoint(x: p.x + arm / 2, y: p.y - arm / 2)
            case .bottomRight: return CGPoint(x: p.x - arm / 2, y: p.y - arm / 2)
            }
        }

        var bracketAlignment: Alignment {
            switch self {
            case .topLeft: return .topLeading
            case .topRight: return .topTrailing
            case .bottomLeft: return .bottomLeading
            case .bottomRight: return .bottomTrailing
            }
        }
    }
}

// MARK: - Overlay views

private struct CropDimMask: View {
    let mediaRect: CGRect
    let cropRect: CGRect

    var body: some View {
        Canvas { context, _ in
            var path = Path(mediaRect)
            path.addRect(cropRect)
            context.fill(path, with: .color(.black.opacity(0.62)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }
}

private struct CropGridOverlay: View {
    let rect: CGRect

    var body: some View {
        ZStack {
            ForEach(1..<3, id: \.self) { i in
                let t = CGFloat(i) / 3.0
                Path { p in
                    p.move(to: CGPoint(x: rect.minX + rect.width * t, y: rect.minY))
                    p.addLine(to: CGPoint(x: rect.minX + rect.width * t, y: rect.maxY))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                Path { p in
                    p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * t))
                    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * t))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            }
        }
    }
}

private struct CropCornerHandle: View {
    let alignment: Alignment
    let armLength: CGFloat

    private var thickness: CGFloat { max(2.5, armLength * 0.14) }

    var body: some View {
        ZStack(alignment: alignment) {
            Rectangle()
                .fill(Color.white)
                .frame(width: armLength, height: thickness)
            Rectangle()
                .fill(Color.white)
                .frame(width: thickness, height: armLength)
        }
        .frame(width: armLength, height: armLength, alignment: alignment)
        .shadow(color: .black.opacity(0.45), radius: 1)
    }
}
