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
            case .comfortable: return "Larger icons — easier to scan"
            case .large: return "Maximum size for accessibility"
            }
        }

        var multiplier: CGFloat {
            switch self {
            case .compact: return 0.92
            case .standard: return 1.0
            case .comfortable: return 1.14
            case .large: return 1.28
            }
        }

        var sampleIconSize: CGFloat {
            switch self {
            case .compact: return 16
            case .standard: return 18
            case .comfortable: return 22
            case .large: return 26
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
        case .toolbar: base = 20
        case .filter: base = 22
        case .transport: base = 24
        case .card: base = 18
        case .hero: base = 52
        }
        return DisplayScale.points(base)
    }

    func touchTarget() -> CGFloat { DisplayScale.points(44) }
}

extension Notification.Name {
    static let luminaUIScaleDidChange = Notification.Name("Lumina.UIScaleDidChange")
}
