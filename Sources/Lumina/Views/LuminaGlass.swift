import SwiftUI
import AppKit

/// Studio chrome materials — Glass uses `NSVisualEffectView` with `.behindWindow`
/// blending so toolbars read as translucent over the desktop / wallpaper.
@MainActor
enum LuminaGlass {
    /// True when Liquid Glass APIs exist and Reduce Transparency is off.
    static var isEnabled: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Prefer Glass material when the user chose it and accessibility allows.
    static var prefersGlassChrome: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            && LuminaLook.shared.material == .glass
    }

    private static var trackedWindows = NSHashTable<NSWindow>.weakObjects()
    private static var didObserveAccessibility = false

    /// Make Studio’s window admit behind-window materials when Glass is on.
    static func configureWindow(_ window: NSWindow) {
        trackedWindows.add(window)
        applyWindowChrome(to: window)
        startAccessibilityObserverIfNeeded()
    }

    /// Re-apply opaque vs clear window chrome after material / a11y changes.
    static func refreshConfiguredWindows() {
        for window in trackedWindows.allObjects {
            applyWindowChrome(to: window)
        }
    }

    private static func applyWindowChrome(to window: NSWindow) {
        if prefersGlassChrome {
            window.isOpaque = false
            window.backgroundColor = .clear
            if let hosting = window.contentView {
                hosting.wantsLayer = true
                hosting.layer?.backgroundColor = NSColor.clear.cgColor
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = .luminaBase
            if let hosting = window.contentView {
                hosting.wantsLayer = true
                hosting.layer?.backgroundColor = NSColor.luminaBase.cgColor
            }
        }
    }

    private static func startAccessibilityObserverIfNeeded() {
        guard !didObserveAccessibility else { return }
        didObserveAccessibility = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                refreshConfiguredWindows()
            }
        }
    }
}

// MARK: - Behind-window material

/// `NSVisualEffectView` that samples content behind the window (desktop / wallpaper).
struct LuminaBehindWindowMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .headerView

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

/// Toolbar / header / footer fill — Glass (behind-window) or Solid (`luminaCard`).
/// Always solid when Reduce Transparency is on.
struct LuminaToolbarMaterialFill: View {
    @ObservedObject private var look = LuminaLook.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let solid = reduceTransparency || look.material == .solid
        ZStack(alignment: .top) {
            if solid {
                Color.luminaCard
            } else {
                LuminaBehindWindowMaterial(material: .headerView)
            }
            // Top hairline highlight so Glass reads as chrome (call sites keep bottom dividers).
            Rectangle()
                .fill(highlightColor(solid: solid))
                .frame(height: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay {
            Rectangle()
                .strokeBorder(Color.luminaBorder.opacity(solid ? 0.55 : 0.85), lineWidth: 1)
        }
        .onChange(of: look.material) { _, _ in
            LuminaGlass.refreshConfiguredWindows()
        }
        .onChange(of: reduceTransparency) { _, _ in
            LuminaGlass.refreshConfiguredWindows()
        }
    }

    private func highlightColor(solid: Bool) -> Color {
        if solid { return Color.luminaBorder.opacity(0.25) }
        return colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.55)
    }
}

// MARK: - View helpers

extension View {
    /// Studio / sheet canvas — solid Lumina base for contrast over a clear window.
    func luminaWindowBackdrop() -> some View {
        self.background(Color.luminaBase)
    }

    /// Raised panel inside Studio (Settings fields, Adjust groups, search).
    /// Always a solid card — not toolbar chrome.
    /// `cornerRadius` is a design-baseline value (scaled here). Prefer passing `10`
    /// (panel) until call sites move to bare `luminaGlassPanel()` / token defaults.
    func luminaGlassPanel(cornerRadius: CGFloat = 10) -> some View {
        let radius = DisplayScale.points(cornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(Color.luminaCard, in: shape)
            .overlay(shape.strokeBorder(Color.luminaBorder, lineWidth: 1))
    }

    /// Header / footer / toolbar strip — glass or solid per `LuminaLook`,
    /// always solid under Reduce Transparency.
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
    func body(content: Content) -> some View {
        content.background { LuminaToolbarMaterialFill() }
    }
}
