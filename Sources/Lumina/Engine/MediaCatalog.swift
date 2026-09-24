// Lumina/Engine/MediaCatalog — files on disk → MediaInventory facts.
import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import LuminaCore

@MainActor
final class MediaCatalog {
    private(set) var inventory = MediaInventory()
    var onChange: (() -> Void)?

    private let proxyRoot: URL
    private var inFlight: Set<PlanRequest> = []
    private var proxyBuilder: ProxyBuilder

    init(proxyRoot: URL = MediaCatalog.defaultProxyRoot()) {
        self.proxyRoot = proxyRoot
        self.proxyBuilder = ProxyBuilder(root: proxyRoot)
        try? FileManager.default.createDirectory(at: proxyRoot, withIntermediateDirectories: true)
    }

    func handle(_ requests: Set<PlanRequest>) {
        for request in requests where !inFlight.contains(request) {
            switch request {
            case .probe(let id):
                inFlight.insert(request)
                Task { @MainActor in
                    let facts = await MediaProber.probe(id, proxyRoot: self.proxyRoot)
                    self.inventory.facts[id] = facts
                    self.inFlight.remove(request)
                    self.onChange?()
                }
            case .buildProxy(let id, let spec):
                inFlight.insert(request)
                Task { @MainActor in
                    do {
                        let path = try await self.proxyBuilder.build(id, spec)
                        var facts = self.inventory.facts[id] ?? MediaFacts(availability: .available)
                        let variant = VariantFacts(spec: spec, path: path)
                        facts.variants.removeAll { $0.spec == spec }
                        facts.variants.append(variant)
                        self.inventory.facts[id] = facts
                        self.onChange?()
                    } catch {
                        LuminaLog.wallpaper.error("Proxy build failed: \(error.localizedDescription)")
                    }
                    self.inFlight.remove(request)
                }
            }
        }
    }

    func recordFailure(_ id: MediaIdentity, _ message: String) {
        inventory.facts[id] = MediaFacts(availability: .failed(message))
        onChange?()
    }

    /// Sets quality to `.efficient` for a display (health-banner "use a smaller video" hook).
    func requestEfficientQuality(for display: DisplayKey, prefs: PreferencesStore) {
        var playback = prefs.playback
        playback[display: display] = .efficient
        prefs.playback = playback
    }

    static func defaultProxyRoot() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Lumina/Proxies", isDirectory: true)
    }
}

/// Off-main probing: pixels, fps, duration, sibling variants, cached proxies.
enum MediaProber {
    static func probe(_ id: MediaIdentity, proxyRoot: URL) async -> MediaFacts {
        let path = id.path
        guard FileManager.default.fileExists(atPath: path) else {
            return MediaFacts(availability: .missing)
        }
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        var pixels: PixelSize?
        var fps: Double?
        var duration: Double?

        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first {
            if let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                pixels = PixelSize(width: Int(abs(rect.width)), height: Int(abs(rect.height)))
            }
            if let rate = try? await track.load(.nominalFrameRate), rate > 0 {
                fps = Double(rate)
            }
        }
        if let d = try? await asset.load(.duration), d.isNumeric, d.seconds.isFinite {
            duration = d.seconds
        }

        var variants = discoverSiblings(of: path)
        variants.append(contentsOf: discoverCachedProxies(for: id, in: proxyRoot))

        // Still/GIF: probe dimensions via ImageIO when no video track.
        if pixels == nil, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            pixels = PixelSize(width: w, height: h)
        }

        return MediaFacts(
            availability: .available,
            pixels: pixels,
            nominalFPS: fps,
            duration: duration,
            variants: variants
        )
    }

    /// Sibling convention: `<base>-low|<battery>|<lp>.<ext>`
    static func discoverSiblings(of path: String) -> [VariantFacts] {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffixes = ["low", "battery", "lp"]
        var result: [VariantFacts] = []
        for suffix in suffixes {
            let candidate = dir.appendingPathComponent("\(stem)-\(suffix).\(ext)")
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            // Treat siblings as efficient proxies (~1080p / 30 fps) until probed deeper.
            let spec = ProxySpec(maxHeight: 1080, fps: 30)
            result.append(VariantFacts(spec: spec, path: candidate.path))
        }
        return result
    }

    static func discoverCachedProxies(for id: MediaIdentity, in root: URL) -> [VariantFacts] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return [] }
        let hash = proxyHash(for: id)
        var result: [VariantFacts] = []
        for file in contents where file.lastPathComponent.hasPrefix(hash) {
            // Filename: <hash>-<h>p<fps>.mov
            let name = file.deletingPathExtension().lastPathComponent
            guard let dash = name.firstIndex(of: "-") else { continue }
            let rest = name[name.index(after: dash)...]
            if let match = rest.range(of: #"^(\d+)p(\d+)$"#, options: .regularExpression) {
                let token = String(rest[match])
                let parts = token.split(separator: "p")
                if parts.count == 2,
                   let h = Int(parts[0]),
                   let fps = Int(parts[1]) {
                    result.append(VariantFacts(spec: ProxySpec(maxHeight: h, fps: fps), path: file.path))
                }
            }
        }
        return result
    }

    static func proxyHash(for id: MediaIdentity) -> String {
        let digest = SHA256.hash(data: Data(id.path.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Wraps VideoCompressor. One job at a time; output encodes spec in the filename.
actor ProxyBuilder {
    private let root: URL
    private var busy = false

    init(root: URL) {
        self.root = root
    }

    func build(_ id: MediaIdentity, _ spec: ProxySpec) async throws -> String {
        guard !busy else { throw ProxyError.busy }
        busy = true
        defer { busy = false }

        let hash = MediaProber.proxyHash(for: id)
        let fpsPart = spec.fps.map(String.init) ?? "n"
        let name = "\(hash)-\(spec.maxHeight)p\(fpsPart).mov"
        let output = root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: output.path) {
            return output.path
        }

        let source = URL(fileURLWithPath: id.path)
        let preset = VideoCompressor.QualityPreset.closest(toHeight: spec.maxHeight)
        let compressed = try await VideoCompressor.shared.compress(sourceURL: source, preset: preset)
        // Copy/move into the Proxies cache with the encoded name.
        if compressed.path != output.path {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: compressed, to: output)
        }
        return output.path
    }

    enum ProxyError: Error { case busy }
}

extension VideoCompressor.QualityPreset {
    static func closest(toHeight height: Int) -> VideoCompressor.QualityPreset {
        switch height {
        case ...480: return .sd480
        case ...720: return .hd720
        case ...1080: return .fullHD
        default: return .uhd4k
        }
    }
}
