import AppKit
import SwiftUI

/// Menu bar status-item icon — cursive LS monogram drawn from the same path as the splash.
@MainActor
enum LuminaMenuIcon {
    /// Renders a template image sized for `NSStatusItem` (macOS tints it for light/dark menu bars).
    static func make(size: NSSize = NSSize(width: 22, height: 16), lineWidth: CGFloat = 1.5) -> NSImage {
        let renderer = ImageRenderer(content: Glyph(size: size, lineWidth: lineWidth))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else {
            return NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Lumina")
                ?? NSImage(size: size)
        }
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }

    static func fittedLSPath(in target: CGSize) -> Path {
        let bounds = CGRect(x: 65, y: 44, width: 277, height: 245)
        let scale = min(target.width / bounds.width, target.height / bounds.height)
        let scaled = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let dx = (target.width - scaled.width) / 2 - bounds.minX * scale
        let dy = (target.height - scaled.height) / 2 - bounds.minY * scale
        return CursiveLSView.lsPath.applying(
            CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: dx, y: dy))
        )
    }

    private struct Glyph: View {
        let size: NSSize
        let lineWidth: CGFloat

        var body: some View {
            LuminaMenuIcon.fittedLSPath(in: CGSize(width: size.width, height: size.height))
                .stroke(
                    Color.black,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size.width, height: size.height)
        }
    }
}
