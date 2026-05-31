import AVFoundation
import AppKit
import Foundation

/// Transcodes a video to a smaller resolution/bitrate so it runs as a desktop wallpaper
/// without taxing the GPU or causing playback hiccups.
///
/// Uses AVAssetExportSession which routes through Apple's hardware encoder on Apple Silicon,
/// so compression is fast and battery-friendly.
@MainActor
final class VideoCompressor: ObservableObject {

    static let shared = VideoCompressor()

    @Published var isCompressing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var lastCompressedURL: URL? = nil

    private var exportSession: AVAssetExportSession?

    // MARK: - Quality Presets

    enum QualityPreset: String, CaseIterable, Identifiable {
        case uhd4k  = "4K"
        case fullHD = "1080p"
        case hd720  = "720p"
        case sd480  = "480p"

        var id: String { rawValue }
        var label: String { rawValue }

        var exportPreset: String {
            switch self {
            case .uhd4k:  return AVAssetExportPreset3840x2160
            case .fullHD: return AVAssetExportPreset1920x1080
            case .hd720:  return AVAssetExportPreset1280x720
            case .sd480:  return AVAssetExportPreset640x480
            }
        }

        var shortDescription: String {
            switch self {
            case .uhd4k:  return "Keeps full 4K quality. Best for dedicated 4K displays."
            case .fullHD: return "Up to 1920×1080. Recommended for most setups — great quality, lighter than 4K."
            case .hd720:  return "Up to 1280×720. Noticeably smaller file, still sharp on most screens."
            case .sd480:  return "Up to 640×480. Maximum performance & smallest file. Ideal for background use."
            }
        }

        /// Rough expected file-size ratio vs original (for the UI estimate label).
        var estimatedSizeRatio: Double {
            switch self {
            case .uhd4k:  return 0.85
            case .fullHD: return 0.45
            case .hd720:  return 0.20
            case .sd480:  return 0.07
            }
        }
    }

    // MARK: - Compression

    /// Compresses `sourceURL` to the given preset.
    /// Returns the URL of the newly created file inside the Lumina cache folder.
    func compress(sourceURL: URL, preset: QualityPreset) async throws -> URL {
        guard !isCompressing else { throw CompressionError.alreadyRunning }

        isCompressing = true
        progress = 0.0
        // Keep lastCompressedURL pointing to the previous result until the new one is ready
        statusMessage = "Preparing…"

        defer {
            isCompressing = false
            exportSession = nil
        }

        // Confirm the preset is compatible with this asset before starting
        let asset = AVURLAsset(url: sourceURL)
        let compatible = await AVAssetExportSession.compatibility(
            ofExportPreset: preset.exportPreset,
            with: asset, outputFileType: .mp4
        )
        guard compatible else {
            throw CompressionError.presetIncompatible(preset.label)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset.exportPreset) else {
            throw CompressionError.sessionCreationFailed
        }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        // Hash the full source path so same-named files from different folders never collide.
        let pathHash = String(format: "%06x", abs(sourceURL.path.hashValue) & 0xFFFFFF)
        let baseName = "\(stem)-\(preset.rawValue)-\(pathHash)"
        // Never delete an existing compressed file — they are permanent.
        // If this exact combination already exists, add a counter to create a new copy.
        var output = outputDirectory.appendingPathComponent("\(baseName).mp4")
        var counter = 1
        while FileManager.default.fileExists(atPath: output.path) {
            output = outputDirectory.appendingPathComponent("\(baseName)-\(counter).mp4")
            counter += 1
        }

        session.shouldOptimizeForNetworkUse = false
        exportSession = session

        statusMessage = "Compressing to \(preset.label)…"

        // Stream progress using the modern (non-deprecated, macOS 15+) states API.
        let progressTask = Task { @MainActor [weak self] in
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let p) = state {
                    self?.progress = p.fractionCompleted
                }
            }
        }

        do {
            try await session.export(to: output, as: .mp4)
        } catch {
            progressTask.cancel()
            // cancelExport() / task cancellation surface here.
            if error is CancellationError { throw CompressionError.cancelled }
            if (error as NSError).code == AVError.Code.operationCancelled.rawValue {
                throw CompressionError.cancelled
            }
            throw error
        }
        progressTask.cancel()

        progress = 1.0
        statusMessage = "Done"
        lastCompressedURL = output
        return output
    }

    func cancel() {
        exportSession?.cancelExport()
        isCompressing = false
        progress = 0
        statusMessage = "Cancelled"
    }

    // MARK: - Video Info

    struct VideoInfo {
        var fileSize: String  = "–"
        var resolution: String = "–"
        var duration: String  = "–"
        var fileSizeBytes: Int64 = 0
    }

    func loadInfo(for url: URL) async -> VideoInfo {
        var info = VideoInfo()

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let bytes = attrs[.size] as? Int64 {
            info.fileSizeBytes = bytes
            info.fileSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }

        let asset = AVURLAsset(url: url)
        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track  = tracks.first,
           let size   = try? await track.load(.naturalSize) {
            info.resolution = "\(Int(abs(size.width)))×\(Int(abs(size.height)))"
        }
        if let dur = try? await asset.load(.duration), dur.isNumeric {
            let s = Int(dur.seconds)
            info.duration = s >= 60
                ? String(format: "%d:%02d", s / 60, s % 60)
                : "\(s)s"
        }
        return info
    }

    // MARK: - Errors

    enum CompressionError: LocalizedError {
        case alreadyRunning
        case sessionCreationFailed
        case presetIncompatible(String)
        case exportFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:           return "A compression is already in progress."
            case .sessionCreationFailed:    return "Could not create an export session for this video."
            case .presetIncompatible(let p): return "This video cannot be exported at \(p)."
            case .exportFailed:             return "Compression failed — the video may be corrupted."
            case .cancelled:                return "Compression was cancelled."
            }
        }
    }

    // MARK: - Private

    private var outputDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Lumina/Compressed", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private init() {}
}
