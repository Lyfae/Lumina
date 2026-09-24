// AppChrome — applies prefs.studio.appearance → NSApp.appearance.
import AppKit
import LuminaCore

@MainActor
enum AppChrome {
    static func apply(appearance: StudioLookPreferences.Appearance) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func apply(studio: StudioLookPreferences) {
        apply(appearance: studio.appearance)
    }
}
