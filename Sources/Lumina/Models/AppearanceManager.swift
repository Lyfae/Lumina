import SwiftUI
import AppKit

/// User-facing appearance preference for the Lumina UI windows.
///
/// This controls only Lumina's own windows (manager, setup, welcome) — it has no
/// effect on the wallpaper itself. `.system` follows the macOS appearance setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    init(_ appearance: StudioLookPreferences.Appearance) {
        self = AppAppearance(rawValue: appearance.rawValue) ?? .system
    }

    var studioAppearance: StudioLookPreferences.Appearance {
        StudioLookPreferences.Appearance(rawValue: rawValue) ?? .system
    }
}

@MainActor
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    @Published var current: AppAppearance = .system {
        didSet { AppChrome.apply(appearance: current.studioAppearance) }
    }

    private weak var preferences: PreferencesStore?

    private init() {}

    func attach(preferences: PreferencesStore) {
        self.preferences = preferences
        current = AppAppearance(preferences.studio.appearance)
        AppChrome.apply(appearance: preferences.studio.appearance)
        trackChanges()
    }

    func set(_ appearance: AppAppearance) {
        guard appearance != current else { return }
        current = appearance
        guard let preferences else { return }
        var studio = preferences.studio
        studio.appearance = appearance.studioAppearance
        preferences.studio = studio
    }

    /// Applies the current preference to the whole application.
    func apply() {
        AppChrome.apply(appearance: current.studioAppearance)
    }

    private func trackChanges() {
        withObservationTracking {
            _ = preferences?.studio.appearance
        } onChange: { [weak self] in
            Task { @MainActor in
                if let appearance = self?.preferences?.studio.appearance {
                    let mapped = AppAppearance(appearance)
                    if self?.current != mapped {
                        self?.current = mapped
                    }
                }
                self?.trackChanges()
            }
        }
    }
}
