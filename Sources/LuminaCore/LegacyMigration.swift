// LuminaCore/Preferences/LegacyMigration — pure translation from today's UserDefaults keys.
//
// Invariants:
// - Pure: input is a read-only snapshot of the legacy keys; output is a document. No I/O here.
// - Idempotent: migrate(legacy) run twice yields the same document. The store only runs it when
//   no v2 blob exists for a section, and NEVER deletes legacy keys (cleanup is a later release).
// - Lossless: every key in grounding.md maps to a field, or is listed in `intentionallyDropped`
//   with a reason. A self-test asserts the mapping table covers every known key.
// - Wire compatibility: `Lumina.MonitorAssignments.v1` and `Lumina.LibraryItems.v1` keep their
//   exact JSON shape forever (older builds can still read them after a downgrade).
import Foundation
import CoreGraphics

/// Read-only view of legacy defaults. The app passes a dictionary built from
/// `UserDefaults.dictionaryRepresentation()` filtered to `LegacyKey.allCases`.
public struct LegacyDefaults: Sendable {
    public enum Value: Sendable, Equatable {
        case bool(Bool), double(Double), string(String), data(Data), strings([String])
    }
    public let values: [LegacyKey: Value]
    public init(values: [LegacyKey: Value]) { self.values = values }

    public func bool(for key: LegacyKey) -> Bool? {
        if case .bool(let v) = values[key] { return v }
        return nil
    }
    public func double(for key: LegacyKey) -> Double? {
        if case .double(let v) = values[key] { return v }
        return nil
    }
    public func string(for key: LegacyKey) -> String? {
        if case .string(let v) = values[key] { return v }
        return nil
    }
    public func data(for key: LegacyKey) -> Data? {
        if case .data(let v) = values[key] { return v }
        return nil
    }
    public func strings(for key: LegacyKey) -> [String]? {
        if case .strings(let v) = values[key] { return v }
        return nil
    }
}

public enum LegacyKey: String, CaseIterable, Sendable {
    case monitorAssignments = "Lumina.MonitorAssignments.v1"
    case libraryItems = "Lumina.LibraryItems.v1"
    case persistAssignments = "Lumina.PersistAssignments"
    case lastVideoBookmark = "lastVideoBookmarkData"
    case lastVideoPath = "lastVideoPathFallback"
    case accentTheme = "Lumina.AccentTheme"
    case appearance = "Lumina.Appearance"
    case uiScale = "Lumina.UIScalePreset"
    case favoriteWallpapers = "Lumina.FavoriteWallpapers"
    case pauseLowPower = "Lumina.Power.PauseOnLowPowerMode"
    case pauseThermal = "Lumina.Power.PauseOnHighThermal"
    case respectFullscreen = "Lumina.Power.RespectFullscreenApps"
    case performanceProfile = "Lumina.Power.PerformanceProfile"
    case syncPlayback = "Lumina.SyncPlaybackAcrossDisplays"
    case autoCheckUpdates = "Lumina.AutoCheckUpdates"
    case hasShownOnboarding = "Lumina.HasShownOnboarding"
    case lastChangelog = "Lumina.LastShownChangelogVersion"
    case hasAutoOpenedStudio = "Lumina.HasAutoOpenedStudio"
    case hasDiscoveredAdjust = "Lumina.HasDiscoveredAdjust"
    case enabledMediaLocations = "Lumina.EnabledMediaLocations"
    case hasConfiguredMediaAccess = "Lumina.HasConfiguredMediaAccess"
    case allowDocumentsAndDownloads = "Lumina.AllowDocumentsAndDownloads"
    case audioTrackPath = "Lumina.AmbientAudio.TrackPath"
    case audioVolume = "Lumina.AmbientAudio.Volume"
    case audioLoops = "Lumina.AmbientAudio.Loops"
    case audioShuffle = "Lumina.AmbientAudio.Shuffle"
    case audioShowWidgetWhenMinimized = "Lumina.AmbientAudio.ShowWidgetWhenMinimized"
    case audioFavorites = "Lumina.AmbientAudio.Favorites"
    // Not migrated into the document; still owned by their managers under the same keys:
    //   Lumina.FolderBookmarks (FileAccess), Lumina.AmbientAudio.Library / .Durations (AmbientAudioManager)
}

public enum LegacyMigration {
    /// Keys whose data is deliberately not carried forward, with the reason.
    public static let intentionallyDropped: [LegacyKey: String] = [
        .lastVideoBookmark: "Cleared every launch since the per-monitor system (main.swift:79-80).",
        .lastVideoPath: "Same as above.",
        .hasAutoOpenedStudio: "Write-only flag; nothing reads it.",
        .syncPlayback: "Identical media shares one decoder and is inherently in sync.",
    ]

    public struct Report: Equatable, Sendable {
        public var migratedKeys: Set<LegacyKey>
        public var skippedAssignments: [String: String] // monitor id → reason (e.g. undecodable)
        public init(migratedKeys: Set<LegacyKey> = [], skippedAssignments: [String: String] = [:]) {
            self.migratedKeys = migratedKeys
            self.skippedAssignments = skippedAssignments
        }
    }

    /// Builds a document from legacy values; unspecified fields keep defaults.
    public static func migrate(_ legacy: LegacyDefaults) -> (PreferencesDocument, Report) {
        var doc = PreferencesDocument()
        var report = Report()

        // Power: apply profile first (frame caps), then overlay the three bools.
        if let raw = legacy.string(for: .performanceProfile),
           let profile = PowerProfile(rawValue: raw) {
            doc.power.apply(profile)
            report.migratedKeys.insert(.performanceProfile)
        }
        if let v = legacy.bool(for: .pauseLowPower) {
            doc.power.defaults.pauseInLowPowerMode = v
            report.migratedKeys.insert(.pauseLowPower)
        }
        if let v = legacy.bool(for: .pauseThermal) {
            doc.power.defaults.thermal.pauseAt = v ? .serious : nil
            report.migratedKeys.insert(.pauseThermal)
        }
        if let v = legacy.bool(for: .respectFullscreen) {
            doc.power.defaults.pauseWhenCovered = v
            report.migratedKeys.insert(.respectFullscreen)
        }

        if let v = legacy.bool(for: .persistAssignments) {
            doc.startup.restoreAtLaunch = v
            report.migratedKeys.insert(.persistAssignments)
        }
        if let v = legacy.bool(for: .autoCheckUpdates) {
            doc.startup.autoCheckUpdates = v
            report.migratedKeys.insert(.autoCheckUpdates)
        }

        // Studio look
        if let raw = legacy.string(for: .accentTheme),
           let accent = StudioLookPreferences.Accent(rawValue: raw) {
            doc.studio.accent = accent
            report.migratedKeys.insert(.accentTheme)
        }
        if let raw = legacy.string(for: .appearance),
           let appearance = StudioLookPreferences.Appearance(rawValue: raw) {
            doc.studio.appearance = appearance
            report.migratedKeys.insert(.appearance)
        }
        if let raw = legacy.string(for: .uiScale),
           let scale = StudioLookPreferences.Scale(rawValue: raw) {
            doc.studio.scale = scale
            report.migratedKeys.insert(.uiScale)
        }

        // Audio + widget
        if let path = legacy.string(for: .audioTrackPath) {
            doc.audio.trackPath = path
            report.migratedKeys.insert(.audioTrackPath)
        }
        if let volume = legacy.double(for: .audioVolume) {
            doc.audio.volume = volume == 0 ? 0.5 : volume
            report.migratedKeys.insert(.audioVolume)
        }
        if let v = legacy.bool(for: .audioLoops) {
            doc.audio.loops = v
            report.migratedKeys.insert(.audioLoops)
        }
        if let v = legacy.bool(for: .audioShuffle) {
            doc.audio.shuffle = v
            report.migratedKeys.insert(.audioShuffle)
        }
        if let favs = legacy.strings(for: .audioFavorites) {
            doc.audio.favoriteTrackPaths = favs
            report.migratedKeys.insert(.audioFavorites)
        }
        if let v = legacy.bool(for: .audioShowWidgetWhenMinimized) {
            doc.widget.autoShow.whenStudioMinimized = v
            report.migratedKeys.insert(.audioShowWidgetWhenMinimized)
        }

        // Media access
        if let locs = legacy.strings(for: .enabledMediaLocations) {
            doc.mediaAccess.enabledLocations = locs
            report.migratedKeys.insert(.enabledMediaLocations)
        }
        let configured = legacy.bool(for: .hasConfiguredMediaAccess) ?? false
        let allowDocs = legacy.bool(for: .allowDocumentsAndDownloads) ?? false
        if configured || allowDocs {
            doc.mediaAccess.hasConfigured = true
            if configured { report.migratedKeys.insert(.hasConfiguredMediaAccess) }
            if allowDocs {
                report.migratedKeys.insert(.allowDocumentsAndDownloads)
                if doc.mediaAccess.enabledLocations.isEmpty {
                    doc.mediaAccess.enabledLocations = [
                        "pictures", "movies", "documents", "downloads"
                    ]
                }
            }
        }

        // Milestones
        if let v = legacy.bool(for: .hasShownOnboarding) {
            doc.milestones.hasShownOnboarding = v
            report.migratedKeys.insert(.hasShownOnboarding)
        }
        if let v = legacy.string(for: .lastChangelog) {
            doc.milestones.lastShownChangelogVersion = v
            report.migratedKeys.insert(.lastChangelog)
        }
        if let v = legacy.bool(for: .hasDiscoveredAdjust) {
            doc.milestones.hasDiscoveredAdjust = v
            report.migratedKeys.insert(.hasDiscoveredAdjust)
        }

        // Wallpapers + library
        var assignments: [DisplayKey: DisplayWallpaper] = [:]
        if let data = legacy.data(for: .monitorAssignments) {
            report.migratedKeys.insert(.monitorAssignments)
            do {
                let decoded = try JSONDecoder().decode([String: MonitorAssignmentWire].self, from: data)
                for (id, wire) in decoded {
                    assignments[DisplayKey(id)] = wallpaper(from: wire)
                }
            } catch {
                report.skippedAssignments["*"] = "decode failed: \(error.localizedDescription)"
            }
        }

        var library: [LibraryItem] = []
        if let data = legacy.data(for: .libraryItems) {
            report.migratedKeys.insert(.libraryItems)
            if let decoded = try? JSONDecoder().decode([String: MonitorAssignmentWire].self, from: data) {
                for (id, wire) in decoded {
                    let wallpaper = wallpaper(from: wire)
                    if case .media(let ref) = wallpaper.content {
                        library.append(LibraryItem(id: id, media: ref))
                    } else if let path = wire.filePath {
                        let kind = mediaKind(from: wire.mediaType)
                        let ref = MediaReference(
                            identity: MediaIdentity(normalizing: path),
                            displayPath: path,
                            bookmark: wire.bookmarkData,
                            kind: kind ?? .image
                        )
                        library.append(LibraryItem(id: id, media: ref))
                    }
                }
            }
        }

        let favorites = Set(legacy.strings(for: .favoriteWallpapers) ?? [])
        if !favorites.isEmpty {
            report.migratedKeys.insert(.favoriteWallpapers)
            for i in library.indices {
                if favorites.contains(library[i].media.displayPath)
                    || favorites.contains(library[i].media.identity.path) {
                    library[i].favorite = true
                }
            }
        }

        doc.wallpapers.replaceAll(assignments: assignments, library: library)

        // Record dropped keys that were present so coverage tests can see them as handled.
        for key in intentionallyDropped.keys {
            if legacy.values[key] != nil {
                report.migratedKeys.insert(key)
            }
        }

        return (doc, report)
    }

    /// Maps the flat v1 record to the domain type. Slideshow wins when items exist (matches
    /// today's restore precedence, main.swift:404-415). Unknown media types → `.none`.
    public static func wallpaper(from wire: MonitorAssignmentWire) -> DisplayWallpaper {
        var wallpaper = DisplayWallpaper()
        wallpaper.pinned = wire.keepOnStartup
        wallpaper.enabled = wire.isEnabled
        wallpaper.look.scaling = wire.scaling
        wallpaper.look.crop = NormalizedRect(
            x: wire.cropRect.origin.x,
            y: wire.cropRect.origin.y,
            width: wire.cropRect.size.width,
            height: wire.cropRect.size.height
        ) ?? .full
        wallpaper.look.brightness = wire.brightness
        wallpaper.look.opacity = wire.opacity
        wallpaper.look.saturation = wire.saturation
        wallpaper.look.hue = wire.hue
        wallpaper.look.grayscale = wire.grayscale
        wallpaper.look.loopFade.enabled = wire.loopFadeEnabled
        wallpaper.look.loopFade.duration = wire.loopFadeDuration
        wallpaper.look.loopFade.easing = wire.loopFadeEasing
        wallpaper.look.crossfadeDuration = wire.crossfadeDuration
        wallpaper.look.crossfadeEasing = wire.crossfadeEasing

        wallpaper.timing.speed = wire.playbackSpeed
        wallpaper.timing.loopMode = wire.loopMode
        wallpaper.timing.startFrame = wire.videoFrameTime
        wallpaper.timing.freezeAtStartFrame = wire.useStaticVideoFrame

        wallpaper.audio.muted = wire.isMuted
        wallpaper.audio.volume = wire.audioVolume

        if !wire.slideshowItems.isEmpty {
            let items: [MediaReference] = wire.slideshowItems.map { path in
                MediaReference(
                    identity: MediaIdentity(normalizing: path),
                    displayPath: path,
                    bookmark: nil,
                    kind: .image
                )
            }
            wallpaper.content = .slideshow(SlideshowSpec(
                items: items,
                interval: wire.slideshowInterval,
                transition: wire.slideshowTransition,
                kenBurns: wire.slideshowKenBurnsEnabled
            ))
        } else if let path = wire.filePath, let kind = mediaKind(from: wire.mediaType) {
            wallpaper.content = .media(MediaReference(
                identity: MediaIdentity(normalizing: path),
                displayPath: path,
                bookmark: wire.bookmarkData,
                kind: kind
            ))
        } else {
            wallpaper.content = .none
        }
        return wallpaper
    }

    /// Inverse, used by the store when persisting pinned wallpapers under the v1 key.
    public static func wire(from wallpaper: DisplayWallpaper, key: DisplayKey) -> MonitorAssignmentWire {
        var wire = MonitorAssignmentWire(monitorIdentifier: key.rawValue)
        wire.keepOnStartup = wallpaper.pinned
        wire.isEnabled = wallpaper.enabled
        wire.scaling = wallpaper.look.scaling
        wire.cropRect = CGRect(
            x: wallpaper.look.crop.x,
            y: wallpaper.look.crop.y,
            width: wallpaper.look.crop.width,
            height: wallpaper.look.crop.height
        )
        wire.brightness = wallpaper.look.brightness
        wire.opacity = wallpaper.look.opacity
        wire.saturation = wallpaper.look.saturation
        wire.hue = wallpaper.look.hue
        wire.grayscale = wallpaper.look.grayscale
        wire.loopFadeEnabled = wallpaper.look.loopFade.enabled
        wire.loopFadeDuration = wallpaper.look.loopFade.duration
        wire.loopFadeEasing = wallpaper.look.loopFade.easing
        wire.crossfadeDuration = wallpaper.look.crossfadeDuration
        wire.crossfadeEasing = wallpaper.look.crossfadeEasing
        wire.playbackSpeed = wallpaper.timing.speed
        wire.loopMode = wallpaper.timing.loopMode
        wire.videoFrameTime = wallpaper.timing.startFrame
        wire.useStaticVideoFrame = wallpaper.timing.freezeAtStartFrame
        wire.isMuted = wallpaper.audio.muted
        wire.audioVolume = wallpaper.audio.volume

        switch wallpaper.content {
        case .none:
            break
        case .media(let ref):
            wire.filePath = ref.displayPath
            wire.bookmarkData = ref.bookmark
            wire.mediaType = mediaType(from: ref.kind)
        case .slideshow(let spec):
            wire.slideshowItems = spec.items.map(\.displayPath)
            wire.slideshowInterval = spec.interval
            wire.slideshowTransition = spec.transition
            wire.slideshowKenBurnsEnabled = spec.kenBurns
            if let first = spec.items.first {
                wire.filePath = first.displayPath
                wire.bookmarkData = first.bookmark
                wire.mediaType = .image
            }
        }
        return wire
    }

    private static func mediaKind(from type: MediaType) -> MediaKind? {
        switch type {
        case .unknown: return nil
        case .image: return .image
        case .animatedImage: return .animatedImage
        case .video: return .video
        }
    }

    private static func mediaType(from kind: MediaKind) -> MediaType {
        switch kind {
        case .image: return .image
        case .animatedImage: return .animatedImage
        case .video: return .video
        }
    }
}

/// Wire media type — mirrors today's `MediaType` including `.unknown` for v1 compatibility.
public enum MediaType: String, Codable, CaseIterable, Sendable {
    case unknown
    case image
    case animatedImage
    case video
}

/// Exact field-for-field copy of today's `MonitorAssignment` Codable shape
/// (MonitorAssignment.swift), including resilient decoding.
public struct MonitorAssignmentWire: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var monitorIdentifier: String
    public var filePath: String?
    public var bookmarkData: Data?
    public var mediaType: MediaType = .unknown
    public var scaling: VideoScaling = .fill
    public var brightness: Double = 0.0
    public var opacity: Double = 1.0
    public var saturation: Double = 1.0
    public var hue: Double = 0.0
    public var audioVolume: Double = 0.0
    public var grayscale: Bool = false
    public var loopMode: LoopMode = .loop
    public var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    public var videoFrameTime: Double? = nil
    public var useStaticVideoFrame: Bool = false
    public var playbackSpeed: Double = 1.0
    public var isMuted: Bool = true
    public var loopFadeEnabled: Bool = false
    public var loopFadeDuration: Double = 1.5
    public var loopFadeEasing: FadeEasing = .easeInOut
    public var crossfadeDuration: Double = 0.35
    public var crossfadeEasing: FadeEasing = .easeInOut
    public var slideshowItems: [String] = []
    public var slideshowInterval: Double = 10.0
    public var slideshowTransition: SlideshowTransition = .fade
    public var slideshowKenBurnsEnabled: Bool = true
    public var keepOnStartup: Bool = false
    public var isEnabled: Bool = true
    public var lastSuccessfulLoad: Date?
    public var lastError: String?

    public init(monitorIdentifier: String) {
        self.monitorIdentifier = monitorIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, monitorIdentifier, filePath, bookmarkData, mediaType,
             scaling, brightness, opacity, saturation, hue, audioVolume, grayscale,
             loopMode, cropRect, videoFrameTime, useStaticVideoFrame, playbackSpeed, isMuted,
             keepOnStartup, isEnabled, lastSuccessfulLoad, lastError,
             loopFadeEnabled, loopFadeDuration, loopFadeEasing,
             crossfadeDuration, crossfadeEasing,
             slideshowItems, slideshowInterval, slideshowTransition,
             slideshowKenBurnsEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitorIdentifier = try container.decode(String.self, forKey: .monitorIdentifier)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        mediaType = try container.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .unknown
        scaling = try container.decodeIfPresent(VideoScaling.self, forKey: .scaling) ?? .fill
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1.0
        hue = try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0.0
        audioVolume = try container.decodeIfPresent(Double.self, forKey: .audioVolume) ?? 0.0
        grayscale = try container.decodeIfPresent(Bool.self, forKey: .grayscale) ?? false
        loopMode = try container.decodeIfPresent(LoopMode.self, forKey: .loopMode) ?? .loop
        cropRect = try container.decodeIfPresent(CGRect.self, forKey: .cropRect) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        videoFrameTime = try container.decodeIfPresent(Double.self, forKey: .videoFrameTime)
        useStaticVideoFrame = try container.decodeIfPresent(Bool.self, forKey: .useStaticVideoFrame) ?? false
        playbackSpeed = try container.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? 1.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? true
        keepOnStartup = try container.decodeIfPresent(Bool.self, forKey: .keepOnStartup) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastSuccessfulLoad = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulLoad)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        loopFadeEnabled = try container.decodeIfPresent(Bool.self, forKey: .loopFadeEnabled) ?? false
        loopFadeDuration = try container.decodeIfPresent(Double.self, forKey: .loopFadeDuration) ?? 1.5
        loopFadeEasing = try container.decodeIfPresent(FadeEasing.self, forKey: .loopFadeEasing) ?? .easeInOut
        crossfadeDuration = try container.decodeIfPresent(Double.self, forKey: .crossfadeDuration) ?? 0.35
        crossfadeEasing = try container.decodeIfPresent(FadeEasing.self, forKey: .crossfadeEasing) ?? .easeInOut
        slideshowItems = try container.decodeIfPresent([String].self, forKey: .slideshowItems) ?? []
        slideshowInterval = try container.decodeIfPresent(Double.self, forKey: .slideshowInterval) ?? 10.0
        slideshowTransition = try container.decodeIfPresent(SlideshowTransition.self, forKey: .slideshowTransition) ?? .fade
        slideshowKenBurnsEnabled = try container.decodeIfPresent(Bool.self, forKey: .slideshowKenBurnsEnabled) ?? true
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}
