import SwiftUI
import AppKit

// MARK: - Shared surface colors

extension NSColor {
    /// Window / column base. Pure black in dark mode, system window background in light.
    static let luminaBase = NSColor(name: "LuminaBase") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .black : .windowBackgroundColor
    }

    /// Card / panel surface. A faintly-lifted near-black in dark mode (so cards stay
    /// distinguishable against the black base via their border), light gray in light mode.
    static let luminaCard = NSColor(name: "LuminaCard") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor(white: 0.11, alpha: 1.0) : .controlBackgroundColor
    }

    /// Border / divider line. The system separator is nearly invisible on pure black, so in
    /// dark mode we use a translucent white that reads clearly against both base and cards.
    static let luminaBorder = NSColor(name: "LuminaBorder") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if isDark {
            return NSColor(white: 1.0, alpha: increased ? 0.35 : 0.18)
        }
        return increased ? NSColor(white: 0, alpha: 0.25) : .separatorColor
    }

    static let luminaFill = NSColor(name: "LuminaFill") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if isDark {
            return NSColor(white: 1.0, alpha: increased ? 0.12 : 0.08)
        }
        return NSColor(white: 0, alpha: increased ? 0.08 : 0.05)
    }

    static let luminaFillHover = NSColor(name: "LuminaFillHover") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor(white: 1.0, alpha: 0.12) : NSColor(white: 0, alpha: 0.08)
    }

    static let luminaFillPressed = NSColor(name: "LuminaFillPressed") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor(white: 1.0, alpha: 0.18) : NSColor(white: 0, alpha: 0.12)
    }
}

extension Color {
    static let luminaBase = Color(nsColor: .luminaBase)
    static let luminaCard = Color(nsColor: .luminaCard)
    static let luminaBorder = Color(nsColor: .luminaBorder)
    static let luminaFill = Color(nsColor: .luminaFill)
    static let luminaFillHover = Color(nsColor: .luminaFillHover)
    static let luminaFillPressed = Color(nsColor: .luminaFillPressed)
    static let luminaOverlay = Color.black.opacity(0.55)
    static let luminaScrim = Color.black.opacity(0.62)
}

/// A horizontal divider that stays clearly visible on Lumina's pure-black dark theme —
/// the system `Divider()` all but disappears against black.
struct LuminaDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.luminaBorder)
            .frame(height: 1)
    }
}

/// Vertical counterpart to `LuminaDivider` for inline separators in toolbars.
struct LuminaVerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.luminaBorder)
            .frame(width: 1)
    }
}

enum AccentTheme: String, CaseIterable, Identifiable {
    /// Neutral gray accent. Raw value stays `system` so existing installs keep their pick.
    case system, blue, purple, pink, red, orange, yellow, green, teal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:  return "Gray"
        case .blue:    return "Ocean"
        case .purple:  return "Aurora"
        case .pink:    return "Blossom"
        case .red:     return "Ember"
        case .orange:  return "Sunset"
        case .yellow:  return "Gold"
        case .green:   return "Forest"
        case .teal:    return "Teal"
        }
    }

    var color: Color {
        switch self {
        case .system:  return Color(white: 0.55)
        case .blue:    return Color(red: 0.18, green: 0.53, blue: 0.95)
        case .purple:  return Color(red: 0.60, green: 0.35, blue: 0.95)
        case .pink:    return Color(red: 0.95, green: 0.30, blue: 0.60)
        case .red:     return Color(red: 0.90, green: 0.22, blue: 0.22)
        case .orange:  return Color(red: 0.95, green: 0.55, blue: 0.18)
        case .yellow:  return Color(red: 0.95, green: 0.80, blue: 0.18)
        case .green:   return Color(red: 0.22, green: 0.78, blue: 0.38)
        case .teal:    return Color(red: 0.20, green: 0.70, blue: 0.72)
        }
    }

    /// Text/icon color drawn on top of an accent fill.
    var onAccent: Color {
        switch self {
        case .blue, .purple, .pink, .red:
            return .white
        case .system, .orange, .yellow, .green, .teal:
            return Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)
        }
    }

    /// Accent used as text (darker variants in light mode for contrast).
    func text(in scheme: ColorScheme) -> Color {
        guard scheme == .light else { return color }
        switch self {
        case .yellow: return Color(red: 0x9A / 255, green: 0x7A / 255, blue: 0)
        case .orange: return Color(red: 0xB3 / 255, green: 0x5F / 255, blue: 0x0E / 255)
        case .green:  return Color(red: 0x1E / 255, green: 0x8A / 255, blue: 0x3C / 255)
        case .teal:   return Color(red: 0x1C / 255, green: 0x7F / 255, blue: 0x83 / 255)
        case .system: return Color(red: 0x5E / 255, green: 0x5E / 255, blue: 0x5E / 255)
        case .blue, .purple, .pink, .red:
            return color
        }
    }

    init(_ accent: StudioLookPreferences.Accent) {
        self = AccentTheme(rawValue: accent.rawValue) ?? .blue
    }

    var studioAccent: StudioLookPreferences.Accent {
        StudioLookPreferences.Accent(rawValue: rawValue) ?? .blue
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var current: AccentTheme = .blue

    private weak var preferences: PreferencesStore?

    private init() {}

    func attach(preferences: PreferencesStore) {
        self.preferences = preferences
        current = AccentTheme(preferences.studio.accent)
        trackChanges()
    }

    func set(_ theme: AccentTheme) {
        current = theme
        guard let preferences else { return }
        var studio = preferences.studio
        studio.accent = theme.studioAccent
        preferences.studio = studio
    }

    private func trackChanges() {
        withObservationTracking {
            _ = preferences?.studio.accent
        } onChange: { [weak self] in
            Task { @MainActor in
                if let accent = self?.preferences?.studio.accent {
                    self?.current = AccentTheme(accent)
                }
                self?.trackChanges()
            }
        }
    }
}
