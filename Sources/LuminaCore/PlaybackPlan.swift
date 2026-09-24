// LuminaCore/Plan/PlaybackPlan — the complete desired state of every surface and decoder.
import Foundation
import CoreGraphics

public struct PlaybackPlan: Equatable, Sendable {
    public var surfaces: [SurfaceID: SurfacePlan] = [:]
    public var sources: [SourceKey: SourcePlan] = [:]
    public var requests: Set<PlanRequest> = []
    public static let empty = PlaybackPlan()
    public init() {}

    /// Returns invariant violations (empty when valid).
    public func validate() -> [String] {
        var violations: [String] = []
        var referenced: Set<SourceKey> = []
        for (id, surface) in surfaces {
            if case let .source(key, _) = surface.content {
                referenced.insert(key)
                if sources[key] == nil {
                    violations.append("surface \(id) references missing source")
                }
            }
        }
        for (key, source) in sources {
            if source.consumers.isEmpty {
                violations.append("source \(key) has zero consumers")
            }
            let expected = surfaces
                .compactMap { sid, s -> SurfaceID? in
                    if case .source(key, _) = s.content { return sid }
                    return nil
                }
                .sorted { Self.surfaceSort($0, $1) }
            if source.consumers != expected {
                violations.append("source \(key) consumers mismatch")
            }
            let anyPlaying = expected.contains { sid in
                if case .playing = surfaces[sid]?.run { return true }
                return false
            }
            if source.running != anyPlaying {
                violations.append("source \(key) running flag mismatch")
            }
            if !referenced.contains(key) {
                violations.append("orphan source \(key)")
            }
        }
        return violations
    }

    static func surfaceSort(_ a: SurfaceID, _ b: SurfaceID) -> Bool {
        switch (a, b) {
        case let (.desktop(x), .desktop(y)): return x.rawValue < y.rawValue
        case (.desktop, .preview): return true
        case (.preview, .desktop): return false
        case let (.preview(x), .preview(y)): return x.raw.uuidString < y.raw.uuidString
        }
    }
}

public struct SurfacePlan: Equatable, Sendable {
    public var id: SurfaceID
    public var geometry: SurfaceGeometry
    public var content: SurfaceContent
    public var run: SurfaceRun
    public init(id: SurfaceID, geometry: SurfaceGeometry, content: SurfaceContent, run: SurfaceRun) {
        self.id = id
        self.geometry = geometry
        self.content = content
        self.run = run
    }
}

public struct SurfaceGeometry: Hashable, Sendable {
    public var frame: CGRect?
    public var pixels: PixelSize
    public init(frame: CGRect?, pixels: PixelSize) {
        self.frame = frame
        self.pixels = pixels
    }
}

public enum SurfaceContent: Equatable, Sendable {
    case empty
    case failed(String)
    case source(SourceKey, SurfaceLook)
}

public struct SurfaceLook: Hashable, Sendable {
    public var scaling: VideoScaling
    public var crop: NormalizedRect
    public var brightness: Double
    public var opacity: Double
    public var saturation: Double
    public var hue: Double
    public var grayscale: Bool
    public var loopFade: WallpaperLook.LoopFade
    public var crossfade: Double
    public var crossfadeEasing: FadeEasing
    public init(
        scaling: VideoScaling = .fill,
        crop: NormalizedRect = .full,
        brightness: Double = 0,
        opacity: Double = 1,
        saturation: Double = 1,
        hue: Double = 0,
        grayscale: Bool = false,
        loopFade: WallpaperLook.LoopFade = WallpaperLook.LoopFade(),
        crossfade: Double = 0.35,
        crossfadeEasing: FadeEasing = .easeInOut
    ) {
        self.scaling = scaling
        self.crop = crop
        self.brightness = brightness
        self.opacity = opacity
        self.saturation = saturation
        self.hue = hue
        self.grayscale = grayscale
        self.loopFade = loopFade
        self.crossfade = crossfade
        self.crossfadeEasing = crossfadeEasing
    }
}

public enum SurfaceRun: Hashable, Sendable {
    case playing
    case paused(PauseReasons)
    case idle
}

public struct PauseReasons: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let manual = PauseReasons(rawValue: 1 << 0)
    public static let displayInactive = PauseReasons(rawValue: 1 << 1)
    public static let lowPowerMode = PauseReasons(rawValue: 1 << 2)
    public static let batteryLow = PauseReasons(rawValue: 1 << 3)
    public static let onBattery = PauseReasons(rawValue: 1 << 4)
    public static let thermal = PauseReasons(rawValue: 1 << 5)
    public static let covered = PauseReasons(rawValue: 1 << 6)
    public static let disabled = PauseReasons(rawValue: 1 << 7)

    public var headline: PauseReasons? {
        guard rawValue != 0 else { return nil }
        var bit: UInt16 = 1
        while bit != 0 {
            if rawValue & bit != 0 { return PauseReasons(rawValue: bit) }
            bit <<= 1
        }
        return nil
    }

    public var label: String {
        switch headline {
        case .manual?: return "Paused: Manual"
        case .displayInactive?: return "Paused: Display inactive"
        case .lowPowerMode?: return "Paused: Low Power Mode"
        case .batteryLow?: return "Paused: Battery low"
        case .onBattery?: return "Paused: On battery"
        case .thermal?: return "Paused: Thermal"
        case .covered?: return "Paused: Covered"
        case .disabled?: return "Paused: Disabled"
        default: return "Paused"
        }
    }
}

/// What forces a separate decoder. Deliberately excludes quality, look, and audio.
public enum SourceKey: Hashable, Sendable {
    case video(MediaIdentity, VideoTiming)
    case still(MediaIdentity)
    case animated(MediaIdentity, speed: Double)
    case slideshow(SlideshowSpec)

    /// Same media identity; only playing speed/loop (or animated speed) differs.
    public func isRetimable(to other: SourceKey) -> Bool {
        switch (self, other) {
        case let (.video(a, .playing(sa, la)), .video(b, .playing(sb, lb))):
            return a == b && (sa != sb || la != lb)
        case let (.animated(a, sa), .animated(b, sb)):
            return a == b && sa != sb
        default:
            return false
        }
    }

    public var identity: MediaIdentity? {
        switch self {
        case .video(let id, _), .still(let id), .animated(let id, _): return id
        case .slideshow: return nil
        }
    }
}

public enum VideoTiming: Hashable, Sendable {
    case playing(speed: Double, loop: LoopMode)
    case frozen(at: Double)
    case scrub(PreviewID)
}

public struct SourcePlan: Equatable, Sendable {
    public var key: SourceKey
    public var variant: Variant
    public var budget: FrameBudget
    public var decodeTarget: PixelSize?
    public var audio: AudioSetting
    public var startFrame: Double?
    public var running: Bool
    public var consumers: [SurfaceID]

    public init(
        key: SourceKey,
        variant: Variant,
        budget: FrameBudget,
        decodeTarget: PixelSize?,
        audio: AudioSetting,
        startFrame: Double?,
        running: Bool,
        consumers: [SurfaceID]
    ) {
        self.key = key
        self.variant = variant
        self.budget = budget
        self.decodeTarget = decodeTarget
        self.audio = audio
        self.startFrame = startFrame
        self.running = running
        self.consumers = consumers
    }

    /// Spec equality ignoring runtime fields that retune doesn't care about.
    public func retuneEquals(_ other: SourcePlan) -> Bool {
        key == other.key
            && variant == other.variant
            && budget == other.budget
            && decodeTarget == other.decodeTarget
            && audio == other.audio
            && startFrame == other.startFrame
    }
}

public enum Variant: Hashable, Sendable {
    case original(path: String)
    case proxy(ProxySpec, path: String)
    public var path: String {
        switch self {
        case .original(let path): return path
        case .proxy(_, let path): return path
        }
    }
}

public struct FrameBudget: Hashable, Sendable {
    public var maxFPS: Int?
    public var enforcement: Enforcement
    public enum Enforcement: Hashable, Sendable {
        case native, variant, renderCap
    }
    public static let native = FrameBudget(maxFPS: nil, enforcement: .native)
    public init(maxFPS: Int?, enforcement: Enforcement) {
        self.maxFPS = maxFPS
        self.enforcement = enforcement
    }
}

public enum PlanRequest: Hashable, Sendable {
    case probe(MediaIdentity)
    case buildProxy(MediaIdentity, ProxySpec)
}
