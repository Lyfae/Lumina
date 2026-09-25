import AVFoundation
import CoreGraphics
import Foundation

/// Peak-envelope waveforms keyed by track URL. Extraction runs off the main actor.
actor TrackWaveformCache {
    static let shared = TrackWaveformCache()
    static let resolution = 128

    private var store: [String: [CGFloat]] = [:]

    func cached(for url: URL) -> [CGFloat]? {
        store[url.absoluteString]
    }

    func levels(for url: URL, count: Int) async -> [CGFloat] {
        let key = url.absoluteString
        if let hit = store[key] {
            return Self.resample(hit, count: count)
        }
        let extracted = await Task.detached(priority: .userInitiated) {
            await Self.extract(url: url, bins: Self.resolution)
        }.value
        store[key] = extracted
        return Self.resample(extracted, count: count)
    }

    nonisolated static func resample(_ levels: [CGFloat], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0.12, count: count) }
        if levels.count == count { return levels }
        let last = Double(levels.count - 1)
        let denom = Double(max(count - 1, 1))
        return (0..<count).map { i in
            let src = Int((Double(i) / denom * last).rounded())
            return levels[min(levels.count - 1, max(0, src))]
        }
    }

    nonisolated private static func extract(url: URL, bins: Int) async -> [CGFloat] {
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard let track = tracks.first else {
            return fallback(bins: bins, seed: url.absoluteString.hashValue)
        }

        guard let reader = try? AVAssetReader(asset: asset) else {
            return fallback(bins: bins, seed: url.absoluteString.hashValue)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            return fallback(bins: bins, seed: url.absoluteString.hashValue)
        }
        reader.add(output)
        guard reader.startReading() else {
            return fallback(bins: bins, seed: url.absoluteString.hashValue)
        }

        let channels = await channelCount(for: track)
        var windowPeaks: [Float] = []
        windowPeaks.reserveCapacity(bins * 32)
        var windowMax: Float = 0
        var framesInWindow = 0
        let windowSize = 512

        while reader.status == .reading {
            if Task.isCancelled {
                reader.cancelReading()
                break
            }
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length >= MemoryLayout<Int16>.size else { continue }

            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: nil,
                dataPointerOut: &dataPointer
            )
            guard let dataPointer else { continue }

            let sampleCount = length / MemoryLayout<Int16>.size
            dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
                var i = 0
                while i + channels <= sampleCount {
                    var peak: Float = 0
                    for c in 0..<channels {
                        peak = max(peak, abs(Float(ptr[i + c]) / Float(Int16.max)))
                    }
                    windowMax = max(windowMax, peak)
                    framesInWindow += 1
                    if framesInWindow >= windowSize {
                        windowPeaks.append(windowMax)
                        windowMax = 0
                        framesInWindow = 0
                    }
                    i += channels
                }
            }
        }

        if framesInWindow > 0 {
            windowPeaks.append(windowMax)
        }

        guard !windowPeaks.isEmpty else {
            return fallback(bins: bins, seed: url.absoluteString.hashValue)
        }

        var peaks = [Float](repeating: 0, count: bins)
        let last = Double(windowPeaks.count - 1)
        let denom = Double(max(bins - 1, 1))
        for b in 0..<bins {
            let start = Int((Double(b) / Double(bins) * Double(windowPeaks.count)).rounded(.down))
            let end = Int((Double(b + 1) / Double(bins) * Double(windowPeaks.count)).rounded(.down))
            let lo = min(windowPeaks.count - 1, max(0, start))
            let hi = min(windowPeaks.count, max(lo + 1, end))
            var local: Float = 0
            for i in lo..<hi {
                local = max(local, windowPeaks[i])
            }
            if hi <= lo {
                let src = Int((Double(b) / denom * last).rounded())
                local = windowPeaks[min(windowPeaks.count - 1, max(0, src))]
            }
            peaks[b] = local
        }

        var maxPeak: Float = 0
        for p in peaks { maxPeak = max(maxPeak, p) }
        if maxPeak < 0.0008 {
            return fallback(bins: bins, seed: url.absoluteString.hashValue)
        }

        let inv = 1 / maxPeak
        return peaks.map { CGFloat(min(1, max(0.08, CGFloat($0 * inv)))) }
    }

    nonisolated private static func channelCount(for track: AVAssetTrack) async -> Int {
        let descriptions = (try? await track.load(.formatDescriptions)) ?? []
        guard let format = descriptions.first else { return 2 }
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return 2 }
        return max(1, Int(asbd.pointee.mChannelsPerFrame))
    }

    nonisolated private static func fallback(bins: Int, seed: Int) -> [CGFloat] {
        let s = Double(abs(seed) % 1000) / 97
        return (0..<bins).map { i in
            let di = Double(i)
            return CGFloat(0.22 + 0.5 * abs(sin(0.9 * di + s)) * (0.55 + 0.45 * abs(sin(0.37 * di + 1.3 * s))))
        }
    }
}
