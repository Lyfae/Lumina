import Foundation
import CoreGraphics

/// Shared layout math for desktop surfaces and Studio preview (WYSIWYG).
public enum WallpaperGeometry {
    public struct Layout: Equatable, Sendable {
        /// Top-left origin: where the full media draws so the crop+scaling result fills the display.
        public var mediaFrame: CGRect
        /// CALayer `contentsRect` (bottom-left origin, normalized).
        public var contentsRect: CGRect
        /// Expanded layer frame in parent coords (bottom-left origin) for AVPlayerLayer crop.
        public var expandedFrame: CGRect
    }

    /// CALayer contentsRect for a top-left-origin normalized crop.
    public static func contentsRect(crop: NormalizedRect) -> CGRect {
        let isFull = abs(crop.x) < 1e-9 && abs(crop.y) < 1e-9
            && abs(crop.width - 1) < 1e-9 && abs(crop.height - 1) < 1e-9
        if isFull { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: crop.x, y: 1 - (crop.y + crop.height), width: crop.width, height: crop.height)
    }

    public static func contentsRect(crop: CGRect) -> CGRect {
        let clamped = crop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let n = NormalizedRect(x: clamped.minX, y: clamped.minY, width: clamped.width, height: clamped.height)
                ?? (clamped.width > 0 && clamped.height > 0
                    ? NormalizedRect(unchecked: clamped.minX, clamped.minY, clamped.width, clamped.height)
                    : nil)
        else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return contentsRect(crop: n)
    }

    /// Expands a player layer beyond `parent` so a top-left crop fills the parent (Y-flipped).
    public static func expandedFrame(parent: CGRect, crop: NormalizedRect) -> CGRect {
        let isFull = abs(crop.x) < 1e-9 && abs(crop.y) < 1e-9
            && abs(crop.width - 1) < 1e-9 && abs(crop.height - 1) < 1e-9
        if isFull || crop.width < 1e-9 || crop.height < 1e-9 {
            return parent
        }
        let fullW = parent.width / crop.width
        let fullH = parent.height / crop.height
        let originX = parent.minX - crop.x * fullW
        let originY = parent.minY + (crop.y + crop.height) * fullH - fullH
        return CGRect(x: originX, y: originY, width: fullW, height: fullH)
    }

    public static func expandedFrame(parent: CGRect, crop: CGRect) -> CGRect {
        let clamped = crop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let n = NormalizedRect(x: clamped.minX, y: clamped.minY, width: max(clamped.width, 1e-6), height: max(clamped.height, 1e-6))
            ?? NormalizedRect(unchecked: 0, 0, 1, 1)
        return expandedFrame(parent: parent, crop: n)
    }

    /// Layout matching CALayer `contentsGravity` + `contentsRect` (image/GIF path) and
    /// AVPlayerLayer gravity with optional frame expansion (video crop path).
    public static func layout(
        mediaSize: CGSize,
        displaySize: CGSize,
        scaling: VideoScaling,
        crop: NormalizedRect = .full
    ) -> Layout {
        let mw = max(mediaSize.width, 1)
        let mh = max(mediaSize.height, 1)
        let dw = max(displaySize.width, 1)
        let dh = max(displaySize.height, 1)
        let parent = CGRect(x: 0, y: 0, width: dw, height: dh)

        let cropPx = CGRect(
            x: crop.x * mw,
            y: crop.y * mh,
            width: max(crop.width * mw, 1e-6),
            height: max(crop.height * mh, 1e-6)
        )

        let mediaFrame: CGRect
        switch scaling {
        case .stretch:
            let sx = dw / cropPx.width
            let sy = dh / cropPx.height
            let fullW = mw * sx
            let fullH = mh * sy
            mediaFrame = CGRect(
                x: -crop.x * fullW,
                y: -crop.y * fullH,
                width: fullW,
                height: fullH
            )
        case .fit, .fill:
            let sx = dw / cropPx.width
            let sy = dh / cropPx.height
            let scale = scaling == .fill ? max(sx, sy) : min(sx, sy)
            let fullW = mw * scale
            let fullH = mh * scale
            let croppedW = cropPx.width * scale
            let croppedH = cropPx.height * scale
            let padX = (dw - croppedW) / 2
            let padY = (dh - croppedH) / 2
            mediaFrame = CGRect(
                x: padX - crop.x * fullW,
                y: padY - crop.y * fullH,
                width: fullW,
                height: fullH
            )
        }

        return Layout(
            mediaFrame: mediaFrame,
            contentsRect: contentsRect(crop: crop),
            expandedFrame: expandedFrame(parent: parent, crop: crop)
        )
    }

    public static func layout(
        mediaSize: CGSize,
        displaySize: CGSize,
        scaling: VideoScaling,
        crop: CGRect
    ) -> Layout {
        let clamped = crop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let n = NormalizedRect(
            x: clamped.minX,
            y: clamped.minY,
            width: max(clamped.width, 1e-6),
            height: max(clamped.height, 1e-6)
        ) ?? .full
        return layout(mediaSize: mediaSize, displaySize: displaySize, scaling: scaling, crop: n)
    }
}
