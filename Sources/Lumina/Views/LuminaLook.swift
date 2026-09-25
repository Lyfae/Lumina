import Foundation
import Observation
import SwiftUI

/// Studio density and chrome material. Attached to preferences in Batch 3 (`main.swift`).
@MainActor
final class LuminaLook: ObservableObject {
    static let shared = LuminaLook()

    @Published private(set) var density: StudioLookPreferences.Density = .regular
    @Published private(set) var material: StudioLookPreferences.Material = .glass

    private weak var preferences: PreferencesStore?

    private init() {}

    func attach(preferences: PreferencesStore) {
        self.preferences = preferences
        density = preferences.studio.density
        material = preferences.studio.material
        trackChanges()
    }

    func set(density newValue: StudioLookPreferences.Density) {
        density = newValue
        guard let preferences else { return }
        var studio = preferences.studio
        studio.density = newValue
        preferences.studio = studio
    }

    func set(material newValue: StudioLookPreferences.Material) {
        material = newValue
        if let preferences {
            var studio = preferences.studio
            studio.material = newValue
            preferences.studio = studio
        }
        LuminaGlass.refreshConfiguredWindows()
    }

    private func trackChanges() {
        withObservationTracking {
            _ = preferences?.studio.density
            _ = preferences?.studio.material
        } onChange: { [weak self] in
            Task { @MainActor in
                if let studio = self?.preferences?.studio {
                    if self?.density != studio.density { self?.density = studio.density }
                    if self?.material != studio.material {
                        self?.material = studio.material
                        LuminaGlass.refreshConfiguredWindows()
                    }
                }
                self?.trackChanges()
            }
        }
    }
}
