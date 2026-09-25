import Foundation

/// Which Adjust inspector controls the engine honors for a wallpaper media kind.
/// Still → `StillImageSource`; GIF → `AnimatedImageSource`; video → `AVPlayer` path.
public struct AdjustCapability: Equatable, Sendable {
    public var playbackSpeed: Bool
    public var loopMode: Bool
    public var loopFade: Bool
    public var audioVolume: Bool
    /// Crop scrubber “Use as Still” / “Start Here” (video frame pick).
    public var videoFramePick: Bool
    /// Quality & Power decode-resolution preset.
    public var decodeQuality: Bool
    public var frameRate: Bool
    public var videoCompression: Bool

    public var playbackApplies: Bool {
        playbackSpeed || loopMode || loopFade || audioVolume
    }

    public var qualityMotionApplies: Bool {
        decodeQuality || frameRate
    }

    public static let none = AdjustCapability(
        playbackSpeed: false,
        loopMode: false,
        loopFade: false,
        audioVolume: false,
        videoFramePick: false,
        decodeQuality: false,
        frameRate: false,
        videoCompression: false
    )

    public static func `for`(_ mediaType: MediaType) -> AdjustCapability {
        switch mediaType {
        case .video:
            return AdjustCapability(
                playbackSpeed: true,
                loopMode: true,
                loopFade: true,
                audioVolume: true,
                videoFramePick: true,
                decodeQuality: true,
                frameRate: true,
                videoCompression: true
            )
        case .animatedImage:
            // GIF: speed + frame-cap decimation; no AV audio / loop modes / freeze / compress.
            return AdjustCapability(
                playbackSpeed: true,
                loopMode: false,
                loopFade: false,
                audioVolume: false,
                videoFramePick: false,
                decodeQuality: true,
                frameRate: true,
                videoCompression: false
            )
        case .image, .unknown:
            return .none
        }
    }

    /// Slideshow surfaces use still frames + transitions; video playback knobs do not apply.
    public static func forSlideshow() -> AdjustCapability {
        AdjustCapability(
            playbackSpeed: false,
            loopMode: false,
            loopFade: false,
            audioVolume: false,
            videoFramePick: false,
            decodeQuality: false,
            frameRate: true,
            videoCompression: false
        )
    }

    public static func unavailableLabel(mediaType: MediaType, isSlideshow: Bool) -> String {
        if isSlideshow { return "slideshows" }
        switch mediaType {
        case .video: return "videos"
        case .animatedImage: return "GIFs"
        case .image, .unknown: return "still images"
        }
    }

    public func playbackFootnote(mediaType: MediaType, isSlideshow: Bool) -> String? {
        guard !playbackApplies else { return nil }
        return "Not available for \(Self.unavailableLabel(mediaType: mediaType, isSlideshow: isSlideshow))"
    }

    public func qualityMotionFootnote(mediaType: MediaType, isSlideshow: Bool) -> String? {
        guard !qualityMotionApplies else { return nil }
        return "Not available for \(Self.unavailableLabel(mediaType: mediaType, isSlideshow: isSlideshow))"
    }
}
