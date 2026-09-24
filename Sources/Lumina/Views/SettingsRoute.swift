import Foundation
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance, size, power, music, shortcuts, privacy, general, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .size: return "Size & Spacing"
        case .power: return "Power"
        case .music: return "Music"
        case .shortcuts: return "Keyboard Shortcuts"
        case .privacy: return "Privacy"
        case .general: return "General"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .size: return "textformat.size"
        case .power: return "bolt.fill"
        case .music: return "music.note"
        case .shortcuts: return "keyboard"
        case .privacy: return "hand.raised.fill"
        case .general: return "gearshape.2.fill"
        case .about: return "info.circle.fill"
        }
    }
}

@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    @Published var pendingSection: SettingsSection?

    private init() {}

    func open(_ section: SettingsSection) {
        pendingSection = section
        NotificationCenter.default.post(name: .luminaOpenSettings, object: section)
    }
}

extension Notification.Name {
    static let luminaOpenSettings = Notification.Name("Lumina.OpenSettings")
    static let luminaRevealAdjustSection = Notification.Name("Lumina.RevealAdjustSection")
}
