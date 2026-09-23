import Foundation
import CoreGraphics

/// Isolated publisher for waveform bar heights so 24 Hz meter ticks don't
/// invalidate every `AmbientAudioManager` observer (Studio footer, etc.).
@MainActor
final class AudioMeterModel: ObservableObject {
    static let shared = AudioMeterModel()

    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.12, count: 28)

    private init() {}

    func replace(_ levels: [CGFloat]) {
        self.levels = levels
    }

    func mapLevels(_ transform: (CGFloat) -> CGFloat) {
        levels = levels.map(transform)
    }
}
