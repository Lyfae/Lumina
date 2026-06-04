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

    /// The AppKit appearance to apply, or nil to follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()
    private let key = "Lumina.Appearance"

    @Published var current: AppAppearance = .system {
        didSet { apply() }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        current = AppAppearance(rawValue: saved) ?? .system
    }

    func set(_ appearance: AppAppearance) {
        guard appearance != current else { return }
        current = appearance
        UserDefaults.standard.set(appearance.rawValue, forKey: key)
    }

    /// Applies the current preference to the whole application. Setting
    /// `NSApp.appearance` to nil restores the system-driven appearance.
    func apply() {
        NSApp.appearance = current.nsAppearance
    }
}

/// Whole-interface zoom for the Studio window. Multiplies the logical layout size so all
/// text, icons, and controls scale together — useful on high-DPI displays where the default
/// UI feels small. Persisted across launches.
@MainActor
final class InterfaceScaleManager: ObservableObject {
    static let shared = InterfaceScaleManager()
    private let key = "Lumina.InterfaceScale"

    static let minScale: Double = 0.8
    static let maxScale: Double = 2.0

    @Published var scale: Double = 1.0 {
        didSet { UserDefaults.standard.set(scale, forKey: key) }
    }

    private init() {
        let saved = UserDefaults.standard.double(forKey: key)   // 0 when never set
        scale = saved >= Self.minScale ? min(saved, Self.maxScale) : 1.0
    }
}
