// Lumina/Rendering/SurfaceLayer — pure geometry + look application helpers.
import AppKit
import QuartzCore
import LuminaCore

enum SurfaceLayer {
    /// Expands a player layer's frame beyond `parent` so the normalized top-left-origin `crop`
    /// region exactly fills the parent. CALayer uses bottom-left origin → Y flip.
    static func expandedVideoFrame(parent: CGRect, crop: CGRect) -> CGRect {
        AVVideoRenderer.expandedVideoFrame(parent: parent, crop: crop)
    }

    static func imageContentsRect(crop: CGRect) -> CGRect {
        AVVideoRenderer.imageContentsRect(crop: crop)
    }

    static func apply(look: SurfaceLook, to layer: CALayer, brightnessOverlay: CALayer?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = Float(look.opacity)
        if let overlay = brightnessOverlay {
            let b = look.brightness
            overlay.backgroundColor = b >= 0
                ? NSColor.white.withAlphaComponent(CGFloat(b)).cgColor
                : NSColor.black.withAlphaComponent(CGFloat(-b)).cgColor
            overlay.isHidden = abs(b) < 0.001
        }
        CATransaction.commit()
    }
}
