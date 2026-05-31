import SwiftUI

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
