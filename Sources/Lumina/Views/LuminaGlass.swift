import SwiftUI
import AppKit

/// Restrained surface helpers for Lumina.
///
/// Studio and floating chrome stay on solid branded surfaces (readable, intentional).
/// System `.bar` materials can still pick up native Tahoe styling where used.
@MainActor
enum LuminaGlass {
    /// True when the OS supports Liquid Glass and the user hasn’t reduced transparency.
    static var isEnabled: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Kept for call-site compatibility — Studio windows stay opaque so content
    /// doesn’t fight the wallpaper behind the glass.
    static func configureWindow(_ window: NSWindow) {
        // Intentionally no-op: clear/transparent Studio chrome looked muddy.
        _ = window
    }
}

// MARK: - View helpers

extension View {
    /// Studio / sheet canvas — always solid Lumina base for contrast.
    func luminaWindowBackdrop() -> some View {
        self.background(Color.luminaBase)
    }

    /// Raised panel inside Studio (Settings fields, Adjust groups, search).
    /// `cornerRadius` is a design-baseline value (scaled here). Prefer passing `10`
    /// (panel) until call sites move to bare `luminaGlassPanel()` / token defaults.
    func luminaGlassPanel(cornerRadius: CGFloat = 10) -> some View {
        let radius = DisplayScale.points(cornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(Color.luminaCard, in: shape)
            .overlay(shape.strokeBorder(Color.luminaBorder, lineWidth: 1))
    }

    /// Header / footer strip — glass or solid per `LuminaLook`, always solid under Reduce Transparency.
    func luminaGlassChrome() -> some View {
        modifier(LuminaGlassChromeModifier())
    }

    /// Floating overlay card — solid surface (no Liquid Glass). Default radius = widget (14).
    func luminaFloatingGlass(cornerRadius: CGFloat = 14) -> some View {
        let radius = DisplayScale.points(cornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(Color.luminaCard, in: shape)
            .overlay(shape.strokeBorder(Color.luminaBorder, lineWidth: 1))
    }
}

@MainActor
private struct LuminaGlassChromeModifier: ViewModifier {
    @ObservedObject private var look = LuminaLook.shared

    func body(content: Content) -> some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let solid = reduce || look.material == .solid
        if solid {
            content.background(Color.luminaCard)
        } else {
            content.background(.bar)
        }
    }
}
