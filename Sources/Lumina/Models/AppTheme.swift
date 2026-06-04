import SwiftUI
import AppKit

// MARK: - Shared surface colors
// Lumina's dark theme uses pure black (matching the Welcome / What's New screens)
// rather than the system's gray `controlBackgroundColor`. These are appearance-adaptive
// so the Light/Dark/Match-System setting keeps working: black-based in dark mode,
// standard system surfaces in light mode.

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
        return isDark ? NSColor(white: 1.0, alpha: 0.18) : .separatorColor
    }
}

extension Color {
    static let luminaBase = Color(nsColor: .luminaBase)
    static let luminaCard = Color(nsColor: .luminaCard)
    static let luminaBorder = Color(nsColor: .luminaBorder)
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

enum AccentTheme: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, teal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:  return "System"
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
        case .system:  return .accentColor
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
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private let key = "Lumina.AccentTheme"

    @Published var current: AccentTheme = .system

    private init() {
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        current = AccentTheme(rawValue: saved) ?? .system
    }

    func set(_ theme: AccentTheme) {
        current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}
