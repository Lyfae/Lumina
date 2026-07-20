import SwiftUI

/// User-controlled interface density — combines with display auto-scaling in `DisplayScale`.
@MainActor
final class UIScaleManager: ObservableObject {
    static let shared = UIScaleManager()

    private let key = "Lumina.UIScalePreset"

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
            case .compact: return "Smaller icons and tighter spacing"
            case .standard: return "Balanced default layout"
            case .comfortable: return "Slightly larger type and controls"
            case .large: return "Maximum size for accessibility"
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
    }

    @Published private(set) var preset: Preset = .comfortable

    var multiplier: CGFloat { preset.multiplier }

    private init() {
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        preset = Preset(rawValue: saved) ?? .comfortable
    }

    func set(_ newPreset: Preset) {
        preset = newPreset
        UserDefaults.standard.set(newPreset.rawValue, forKey: key)
        NotificationCenter.default.post(name: .luminaUIScaleDidChange, object: nil)
    }

    // MARK: - Semantic icon sizes (design baseline × display × user scale)

    enum IconRole {
        case toolbar, filter, transport, card, hero
    }

    func iconSize(_ role: IconRole) -> CGFloat {
        let base: CGFloat
        switch role {
        case .toolbar: base = 18
        case .filter: base = 18
        case .transport: base = 18
        case .card: base = 16
        case .hero: base = 44
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
}

extension Notification.Name {
    static let luminaUIScaleDidChange = Notification.Name("Lumina.UIScaleDidChange")
}
