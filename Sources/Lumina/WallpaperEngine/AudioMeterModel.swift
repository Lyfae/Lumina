import Foundation
import CoreGraphics

/// Isolated publisher for waveform bar heights so 24 Hz meter ticks don't
/// invalidate every `AmbientAudioManager` observer (Studio footer, etc.).
@MainActor
final class AudioMeterModel: ObservableObject {
    static let shared = AudioMeterModel()

    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.12, count: 28)
    /// Beat hit against the recent loudness, 0 at the song's own average and 1 on a strike.
    /// Absolute dBFS would pin a quiet track to the floor, so the wave reads the ratio instead.
    @Published private(set) var level: CGFloat = 0.35

    private var fast: CGFloat = 0.4
    private var slow: CGFloat = 0.4

    private init() {}

    /// `raw` is a compressed 0...1 meter reading. While paused, the level eases to a resting shape.
    func push(raw: CGFloat, playing: Bool) {
        if !playing {
            fast += (0.45 - fast) * 0.25
            slow = fast
            let next: CGFloat = 0.55
            if abs(next - level) > 0.01 { level = next }
            return
        }
        let sample = min(1, max(0, raw))
        let follow: CGFloat = sample > fast ? 0.45 : 0.2
        fast += (sample - fast) * follow
        slow += (fast - slow) * 0.045
        let ratio = fast / max(slow, 0.03)
        // A wide window, so a typical swell lands in the middle instead of slamming to 0 or 1.
        let hit = min(1, max(0, (ratio - 0.88) / 0.75))
        if abs(hit - level) > 0.004 { level = hit }
    }

    func replace(_ levels: [CGFloat]) {
        self.levels = levels
    }

    func mapLevels(_ transform: (CGFloat) -> CGFloat) {
        levels = levels.map(transform)
    }
}
