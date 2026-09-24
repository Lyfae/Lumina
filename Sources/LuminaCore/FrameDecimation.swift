/// Pure GIF frame-decimation helper (self-tested; used by AnimatedImageSource later).
public enum FrameDecimation {
    /// Merges consecutive frames so the effective rate stays ≤ maxFPS.
    public static func decimate(delays: [Double], maxFPS: Int?) -> [(index: Int, delay: Double)] {
        guard let maxFPS, maxFPS > 0, !delays.isEmpty else {
            return delays.enumerated().map { ($0.offset, $0.element) }
        }
        let minDelay = 1.0 / Double(maxFPS)
        var result: [(index: Int, delay: Double)] = []
        var i = 0
        while i < delays.count {
            var acc = delays[i]
            var last = i
            while acc < minDelay - 1e-12, last + 1 < delays.count {
                last += 1
                acc += delays[last]
            }
            result.append((i, max(acc, minDelay)))
            i = last + 1
        }
        return result
    }
}
