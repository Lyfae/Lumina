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

/// Controls the Studio window's size by picking a native resolution preset. Resizing the
/// real window (rather than geometrically zooming the content) keeps the UI perfectly crisp
/// at every size. Presets run from a comfortable minimum up to the largest the current
/// display can show. Persisted across launches.
@MainActor
final class WindowSizeManager: ObservableObject {
    static let shared = WindowSizeManager()
    private let key = "Lumina.WindowSize"

    /// Width:height the presets keep, tuned for the two-column layout.
    static let aspect: CGFloat = 1100.0 / 860.0
    static let minWidth: CGFloat = 1000

    @Published var size: CGSize {
        didSet {
            UserDefaults.standard.set("\(Int(size.width))x\(Int(size.height))", forKey: key)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: key) {
            let parts = saved.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                size = CGSize(width: parts[0], height: parts[1])
                return
            }
        }
        size = CGSize(width: 1100, height: 860)
    }

    /// Native window-size presets that fit the given screen, smallest → largest.
    func presets(for screen: NSScreen?) -> [CGSize] {
        let vf = (screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1680, height: 1050)
        let aspect = Self.aspect
        let marginW = vf.width - 24
        let marginH = vf.height - 24

        var result: [CGSize] = []
        var w = Self.minWidth
        while w <= marginW {
            let h = (w / aspect).rounded()
            if h <= marginH { result.append(CGSize(width: w, height: h)) }
            w += 200
        }

        // Always offer a "largest that fits this display" option.
        let maxW = min(marginW, marginH * aspect).rounded()
        let maxSize = CGSize(width: maxW, height: (maxW / aspect).rounded())
        if let last = result.last {
            if abs(last.width - maxSize.width) > 40 { result.append(maxSize) }
        } else {
            result.append(maxSize)
        }
        return result
    }
}
