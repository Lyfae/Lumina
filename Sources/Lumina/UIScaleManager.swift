import SwiftUI

/// User-controlled interface density — combines with display auto-scaling in `DisplayScale`.
@MainActor
final class UIScaleManager: ObservableObject {
    static let shared = UIScaleManager()

    enum Preset: String, CaseIterable, Identifiable {
        case compact
        case standard
        case comfortable
        case large

        var id: String { rawValue }

        var label: String {
            switch self {
            case .compact: return "Compact"
            case .standard: return "Standard"
            case .comfortable: return "Comfortable"
            case .large: return "Large"
            }
        }

        var subtitle: String {
            switch self {
            case .compact: return "Fits the most on screen."
            case .standard: return "A little smaller than default."
            case .comfortable: return "The default size."
            case .large: return "Biggest text and buttons."
            }
        }

        var multiplier: CGFloat {
            switch self {
            case .compact: return 0.92
            case .standard: return 1.0
            case .comfortable: return 1.06
            case .large: return 1.22
            }
        }

        var sampleIconSize: CGFloat {
            switch self {
            case .compact: return 15
            case .standard: return 17
            case .comfortable: return 18
            case .large: return 22
            }
        }

        init(_ scale: StudioLookPreferences.Scale) {
            self = Preset(rawValue: scale.rawValue) ?? .comfortable
        }

        var studioScale: StudioLookPreferences.Scale {
            StudioLookPreferences.Scale(rawValue: rawValue) ?? .comfortable
        }
    }

    @Published private(set) var preset: Preset = .comfortable

    var multiplier: CGFloat { preset.multiplier }

    private weak var preferences: PreferencesStore?

    private init() {}

    func attach(preferences: PreferencesStore) {
        self.preferences = preferences
        preset = Preset(preferences.studio.scale)
        trackChanges()
    }

    func set(_ newPreset: Preset) {
        preset = newPreset
        if let preferences {
            var studio = preferences.studio
            studio.scale = newPreset.studioScale
            preferences.studio = studio
        }
        NotificationCenter.default.post(name: .luminaUIScaleDidChange, object: nil)
    }

    // MARK: - Semantic icon sizes (design baseline × display × user scale)

    enum IconRole {
        case toolbar, filter, transport, card, hero, inline
    }

    func iconSize(_ role: IconRole) -> CGFloat {
        let base: CGFloat
        switch role {
        case .toolbar: base = 17
        case .filter: base = 13
        case .transport: base = 15
        case .card: base = 15
        case .hero: base = 40
        case .inline: base = 12
        }
        return DisplayScale.points(base)
    }

    func touchTarget() -> CGFloat { DisplayScale.points(preset == .large ? 44 : 36) }

    /// macOS control size for sliders, toggles, and pickers.
    func controlSize() -> ControlSize {
        switch preset {
        case .compact, .standard, .comfortable: return .regular
        case .large: return .large
        }
    }

    func scaledFont(_ base: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: DisplayScale.points(base), weight: weight)
    }

    func font(_ style: LuminaTextStyle) -> Font {
        switch style {
        case .micro: return scaledFont(10, weight: .medium)
        case .caption: return scaledFont(11, weight: .regular)
        case .callout: return scaledFont(12, weight: .regular)
        case .body: return scaledFont(13, weight: .regular)
        case .bodyStrong: return scaledFont(13, weight: .semibold)
        case .headline: return scaledFont(15, weight: .semibold)
        case .title: return scaledFont(17, weight: .bold)
        case .largeTitle: return scaledFont(22, weight: .bold)
        }
    }

    private func trackChanges() {
        withObservationTracking {
            _ = preferences?.studio.scale
        } onChange: { [weak self] in
            Task { @MainActor in
                if let scale = self?.preferences?.studio.scale {
                    let mapped = Preset(scale)
                    if self?.preset != mapped {
                        self?.preset = mapped
                        NotificationCenter.default.post(name: .luminaUIScaleDidChange, object: nil)
                    }
                }
                self?.trackChanges()
            }
        }
    }
}

extension Notification.Name {
    static let luminaUIScaleDidChange = Notification.Name("Lumina.UIScaleDidChange")
}
