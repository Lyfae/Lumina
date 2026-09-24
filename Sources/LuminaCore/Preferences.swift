// LuminaCore/Preferences — every user preference, as plain Codable value sections.
//
// Invariants:
// - Each section is a self-contained Codable, Equatable, Sendable struct with defaults that
//   reproduce today's behavior when nothing is stored.
// - Per-display customization is an override map + an effective-value subscript. Reading the
//   subscript never mutates; writing through it creates/updates the override.
// - No derived state is stored (e.g. the performance profile is computed from the rules).
import Foundation

// MARK: - Document

public struct PreferencesDocument: Codable, Equatable, Sendable {
    public var power = PowerPreferences()
    public var playback = PlaybackPreferences()
    public var wallpapers = WallpaperPreferences()
    public var widget = MusicWidgetPreferences()
    public var studio = StudioLookPreferences()
    public var shortcuts = ShortcutPreferences()
    public var startup = StartupPreferences()
    public var audio = AmbientAudioPreferences()
    public var mediaAccess = MediaAccessPreferences()
    public var milestones = Milestones()
    public init() {}
}

/// Persistence and reset granularity. One case per stored property of `PreferencesDocument`.
public enum PreferenceSection: String, CaseIterable, Sendable {
    case power, playback, wallpapers, widget, studio, shortcuts, startup, audio, mediaAccess, milestones
}

/// The subset of preferences the planner reads. The engine tracks exactly these sections, so
/// changing the accent color never triggers a replan.
public struct PlanningPreferences: Equatable, Sendable {
    public var power: PowerPreferences
    public var playback: PlaybackPreferences
    public var wallpapers: WallpaperPreferences
    public var startup: StartupPreferences
    public init(
        power: PowerPreferences,
        playback: PlaybackPreferences,
        wallpapers: WallpaperPreferences,
        startup: StartupPreferences
    ) {
        self.power = power
        self.playback = playback
        self.wallpapers = wallpapers
        self.startup = startup
    }
}

// MARK: - Power

public enum ThermalLevel: Int, Codable, Comparable, Sendable, CaseIterable {
    case nominal, fair, serious, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

/// A user-selectable frame-rate ceiling. `.native` = no cap. The planner quantizes the chosen
/// cap to a divisor of the media's frame rate, so `.fps(24)` on 60 fps media yields 20.
public enum FrameRateCap: Hashable, Codable, Sendable, Comparable {
    case native
    case fps(Int) // invariant: 1...240, enforced by `init?(fps:)`

    public init?(fps: Int) {
        guard (1...240).contains(fps) else { return nil }
        self = .fps(fps)
    }

    public static let choices: [FrameRateCap] = [.native, .fps(60), .fps(30), .fps(24), .fps(15), .fps(8)]

    public var label: String {
        switch self {
        case .native: return "Native"
        case .fps(let n): return "\(n) fps"
        }
    }

    /// `.native` sorts highest so `min(caps)` yields the tightest cap.
    public static func < (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.native, .native): return false
        case (.native, _): return false
        case (_, .native): return true
        case (.fps(let x), .fps(let y)): return x < y
        }
    }
}

public struct BatteryRule: Hashable, Codable, Sendable {
    /// Pause playback on battery power when charge is below `pauseBelowPercent`.
    public var pauseBelowEnabled = false
    public var pauseBelowPercent: Double = 20 // 5...80
    /// Extra cap applied whenever running on battery (independent of percentage).
    public var capOnBattery: FrameRateCap = .native
    /// Pause entirely whenever on battery.
    public var pauseOnBattery = false
    public init() {}
}

public struct ThermalRule: Hashable, Codable, Sendable {
    /// Pause at or above this level. nil = never pause for heat.
    /// Migrated: `Lumina.Power.PauseOnHighThermal` true → .serious, false → nil.
    public var pauseAt: ThermalLevel? = .serious
    /// Cap at or above this level (below `pauseAt`). Migrated from the hardcoded fair → 8/15 fps.
    public var capAt: ThermalLevel? = .fair
    public var cap: FrameRateCap = .fps(15)
    public init() {}
}

/// The full set of power rules for one display (or the defaults for all displays).
public struct PowerRuleSet: Hashable, Codable, Sendable {
    /// Migrated from `Lumina.Power.RespectFullscreenApps`. Uses per-window occlusion.
    public var pauseWhenCovered = true
    /// Migrated from `Lumina.Power.PauseOnLowPowerMode`.
    public var pauseInLowPowerMode = true
    public var thermal = ThermalRule()
    public var battery = BatteryRule()
    /// Always-on ceiling (the "real frame-rate cap"). Max Battery migrates to `.fps(30)`.
    public var frameCap: FrameRateCap = .native
    /// While Studio is visible, lift frame caps (never lifts pauses). Replaces
    /// `luminaManagerWindowsAreActive` forcing `.normal` (PowerManager.swift:243-247).
    public var fullQualityWhileStudioOpen = true
    public init() {}
}

public struct PowerPreferences: Equatable, Sendable {
    public var defaults = PowerRuleSet()
    public private(set) var overrides: [DisplayKey: PowerRuleSet] = [:]
    /// When true, `.renderCap` uses AVPlayerItemVideoOutput + display-link FramePump.
    /// Off by default — measure with powermetrics before exposing in UI / shipping as default.
    public var experimentalRenderCap = false

    public init() {}

    /// Effective rules for a display; writing creates an override seeded from the effective value.
    public subscript(display key: DisplayKey) -> PowerRuleSet {
        get { overrides[key] ?? defaults }
        set { overrides[key] = newValue }
    }
    public func hasOverride(for key: DisplayKey) -> Bool { overrides[key] != nil }
    public mutating func clearOverride(for key: DisplayKey) { overrides[key] = nil }

    /// Derived, never stored: which preset (if any) `defaults` equals.
    public var profile: PowerProfile? { PowerProfile.allCases.first { $0.rules == defaults } }
    public var profileLabel: String { profile?.label ?? "Custom" }
    public mutating func apply(_ profile: PowerProfile) { defaults = profile.rules }
}

extension PowerPreferences: Codable {
    enum CodingKeys: String, CodingKey { case defaults, overrides, experimentalRenderCap }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaults = try c.decodeIfPresent(PowerRuleSet.self, forKey: .defaults) ?? PowerRuleSet()
        overrides = try c.decodeIfPresent([DisplayKey: PowerRuleSet].self, forKey: .overrides) ?? [:]
        experimentalRenderCap = try c.decodeIfPresent(Bool.self, forKey: .experimentalRenderCap) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(defaults, forKey: .defaults)
        try c.encode(overrides, forKey: .overrides)
        try c.encode(experimentalRenderCap, forKey: .experimentalRenderCap)
    }
}

/// Presets are templates that fill `PowerRuleSet`, not a live mode. Rule values reproduce
/// today's `PowerManager.updatePolicy` behavior exactly for each profile.
public enum PowerProfile: String, CaseIterable, Codable, Sendable, Identifiable {
    case maximumBattery, balanced, highQuality

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .maximumBattery: return "Max Battery"
        case .balanced: return "Balanced"
        case .highQuality: return "High Quality"
        }
    }

    /// maximumBattery: frameCap .fps(30), thermal cap .fps(8) at .fair
    /// balanced:       frameCap .native,  thermal cap .fps(15) at .fair
    /// highQuality:    frameCap .native,  thermal capAt nil
    public var rules: PowerRuleSet {
        var rules = PowerRuleSet()
        switch self {
        case .maximumBattery:
            rules.frameCap = .fps(30)
            rules.thermal.capAt = .fair
            rules.thermal.cap = .fps(8)
            rules.thermal.pauseAt = .serious
        case .balanced:
            rules.frameCap = .native
            rules.thermal.capAt = .fair
            rules.thermal.cap = .fps(15)
            rules.thermal.pauseAt = .serious
        case .highQuality:
            rules.frameCap = .native
            rules.thermal.capAt = nil
            rules.thermal.cap = .fps(15)
            rules.thermal.pauseAt = .serious
        }
        return rules
    }
}

// MARK: - Playback quality

/// Resolves to (decode height cap, frame cap) in `Planner.qualityLimits(_:)`.
public enum QualityPreset: String, Codable, CaseIterable, Sendable {
    /// Decode no more pixels than the display (after crop) needs; native fps.
    case automatic
    /// Always the original file; no cap.
    case original
    /// ≤ 2160p, native fps.
    case uhd2160
    /// ≤ 1440p, native fps.
    case balanced
    /// ≤ 1080p, native fps.
    case fhd1080
    /// ≤ 1080p, ≤ 30 fps. Kept for migrated data; UI maps it to 1080p.
    case efficient
}

public enum ProxyPolicy: String, Codable, CaseIterable, Sendable {
    case never, whenPluggedIn, always
}

public struct PlaybackPreferences: Codable, Equatable, Sendable {
    public var defaultQuality: QualityPreset = .automatic
    public private(set) var qualityOverrides: [DisplayKey: QualityPreset] = [:]
    /// Global hard ceiling on decode height (nil = none), applied after presets.
    public var maxDecodeHeight: Int? = nil
    public var proxyPolicy: ProxyPolicy = .whenPluggedIn
    public var proxyDiskBudgetMB: Int = 4096

    public init() {}

    public subscript(display key: DisplayKey) -> QualityPreset {
        get { qualityOverrides[key] ?? defaultQuality }
        set { qualityOverrides[key] = newValue }
    }
    public mutating func clearOverride(for key: DisplayKey) { qualityOverrides[key] = nil }
}

// MARK: - Wallpapers (content assignment; replaces AssignmentStore's in-memory model)

public enum VideoScaling: String, Codable, CaseIterable, Sendable { case fit, fill, stretch }
public enum LoopMode: String, Codable, CaseIterable, Sendable { case loop, once, bounce }
public enum FadeEasing: String, Codable, CaseIterable, Sendable { case linear, easeIn, easeInOut, easeOut }
public enum SlideshowTransition: String, Codable, CaseIterable, Sendable { case fade, cut }

/// Layer-level appearance. Anything here can differ between displays sharing one decode.
public struct WallpaperLook: Hashable, Codable, Sendable {
    public var scaling: VideoScaling = .fill
    public var crop: NormalizedRect = .full
    public var brightness: Double = 0 // -0.5...0.5
    public var opacity: Double = 1 // 0...1
    public var saturation: Double = 1 // 0...2
    public var hue: Double = 0 // -180...180
    public var grayscale = false
    public var loopFade = LoopFade()
    public var crossfadeDuration: Double = 0.35
    public var crossfadeEasing: FadeEasing = .easeInOut
    public struct LoopFade: Hashable, Codable, Sendable {
        public var enabled = false
        public var duration: Double = 1.5
        public var easing: FadeEasing = .easeInOut
        public init() {}
    }
    public init() {}
}

/// Player-level timing. Differences here force separate decoders (they are part of SourceKey).
public struct PlaybackTiming: Hashable, Codable, Sendable {
    public var speed: Double = 1.0 // user speed; the ONLY source of AVPlayer.rate
    public var loopMode: LoopMode = .loop
    /// Normalized 0...1 start/freeze position.
    public var startFrame: Double? = nil
    public var freezeAtStartFrame = false
    public init() {}
}

public struct AudioSetting: Hashable, Codable, Sendable {
    public var muted = true
    public var volume: Double = 0
    public init() {}
    public init(muted: Bool, volume: Double) {
        self.muted = muted
        self.volume = volume
    }
}

public struct SlideshowSpec: Hashable, Codable, Sendable {
    public var items: [MediaReference] // images only; validated at boundary
    public var interval: Double = 10
    public var transition: SlideshowTransition = .fade
    public var kenBurns = true
    public init(
        items: [MediaReference],
        interval: Double = 10,
        transition: SlideshowTransition = .fade,
        kenBurns: Bool = true
    ) {
        self.items = items
        self.interval = interval
        self.transition = transition
        self.kenBurns = kenBurns
    }
}

/// One mode per display, by construction (replaces the "clear slideshowItems" convention).
public enum WallpaperContent: Hashable, Codable, Sendable {
    case none
    case media(MediaReference)
    case slideshow(SlideshowSpec)
}

public struct DisplayWallpaper: Hashable, Codable, Sendable {
    public var content: WallpaperContent = .none
    public var look = WallpaperLook()
    public var timing = PlaybackTiming()
    public var audio = AudioSetting()
    /// "Restore at launch" (wire key: keepOnStartup).
    public var pinned = false
    /// Temporarily disabled without losing settings (wire key: isEnabled).
    public var enabled = true
    public init() {}
}

public struct LibraryItem: Hashable, Codable, Sendable, Identifiable {
    public var id: String // today's "library-import-…" key, kept verbatim
    public var media: MediaReference
    public var favorite = false // folds in Lumina.FavoriteWallpapers
    public init(id: String, media: MediaReference, favorite: Bool = false) {
        self.id = id
        self.media = media
        self.favorite = favorite
    }
}

public struct WallpaperPreferences: Codable, Equatable, Sendable {
    /// Session + pinned assignments. Only `pinned` entries persist (today's semantics), so at
    /// launch this contains exactly the pinned set — launch restore needs no special code.
    public private(set) var byDisplay: [DisplayKey: DisplayWallpaper] = [:]
    /// Separate from assignments (today they share one dict, distinguished by id prefix).
    public var library: [LibraryItem] = []

    public init() {}

    public subscript(display key: DisplayKey) -> DisplayWallpaper {
        get { byDisplay[key] ?? DisplayWallpaper() }
        set { byDisplay[key] = newValue }
    }

    /// Sets content, preserving look/timing/pinned (fixes the un-pin bug noted at main.swift:1053-1057).
    public mutating func assign(_ content: WallpaperContent, to key: DisplayKey) {
        var wallpaper = self[display: key]
        wallpaper.content = content
        byDisplay[key] = wallpaper
    }

    public mutating func clear(_ key: DisplayKey) {
        var wallpaper = self[display: key]
        wallpaper.content = .none
        byDisplay[key] = wallpaper
    }

    /// Rename a legacy resolution-dependent key; no-op if `new` already has an entry.
    public mutating func adoptLegacyKey(_ legacy: DisplayKey, as new: DisplayKey) {
        guard legacy != new, byDisplay[new] == nil, let value = byDisplay.removeValue(forKey: legacy) else { return }
        byDisplay[new] = value
    }

    /// Bulk replace used by legacy migration (private(set) blocks external writes).
    public mutating func replaceAll(
        assignments: [DisplayKey: DisplayWallpaper],
        library: [LibraryItem]
    ) {
        byDisplay = assignments
        self.library = library
    }
}

// MARK: - Music widget

public struct MusicWidgetPreferences: Codable, Equatable, Sendable {
    public enum Size: String, Codable, CaseIterable, Sendable { case compact, regular, expanded }
    public enum Corner: String, Codable, CaseIterable, Sendable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }
    public struct Placement: Hashable, Codable, Sendable {
        public var corner: Corner = .topTrailing // today: positionInTopRight
        public var display: DisplayKey? = nil // nil = main display
        public var inset: Double = 16 // points from the corner
        /// Set when the user drags the panel; overrides corner until "Snap to corner".
        public var customOrigin: CodablePoint? = nil
        public init() {}
    }
    public struct AutoShow: Hashable, Codable, Sendable {
        public var whenStudioMinimized = true // Lumina.AmbientAudio.ShowWidgetWhenMinimized
        public var whenPlaybackStarts = false
        public var hideWhenDesktopCovered = true
        public init() {}
    }
    public var size: Size = .regular
    public var placement = Placement()
    public var showsWaveform = true
    public var showsUpNext = true
    public var autoShow = AutoShow()
    public init() {}
}

public struct CodablePoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

// MARK: - Studio look

public struct StudioLookPreferences: Codable, Equatable, Sendable {
    public enum Accent: String, Codable, CaseIterable, Sendable {
        case system, blue, purple, pink, red, orange, yellow, green, teal
    }
    public enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
    public enum Scale: String, Codable, CaseIterable, Sendable {
        case compact, standard, comfortable, large
    }
    public enum Density: String, Codable, CaseIterable, Sendable { case tight, regular, airy }
    public enum Material: String, Codable, CaseIterable, Sendable { case glass, solid }
    public enum Side: String, Codable, CaseIterable, Sendable { case leading, trailing }
    public enum ThumbnailSize: String, Codable, CaseIterable, Sendable { case small, medium, large }
    public struct Layout: Hashable, Codable, Sendable {
        public var librarySide: Side = .leading
        public var thumbnailSize: ThumbnailSize = .medium
        public var showsAudioFooter = true
        public var showsHealthBanner = true
        public var adjustColumnExpanded = true
        public init() {}
    }
    public var accent: Accent = .blue // Lumina.AccentTheme
    public var appearance: Appearance = .system // Lumina.Appearance
    /// Matches today's UIScaleManager default (`.comfortable`), not the sketch's `.standard`.
    public var scale: Scale = .comfortable // Lumina.UIScalePreset
    public var density: Density = .regular
    public var material: Material = .glass
    public var layout = Layout()
    public init() {}
}

// MARK: - Shortcuts

public enum ShortcutAction: String, Codable, CaseIterable, Sendable {
    case togglePause, openStudio, toggleMusicWidget, restartInSync, nextSlide, quit
}

public struct KeyCombo: Hashable, Codable, Sendable {
    public var keyCode: UInt16 // Carbon virtual key code
    public var modifiers: Modifiers
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }
    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct ShortcutBinding: Hashable, Codable, Sendable {
    public enum Scope: String, Codable, Sendable { case menu, global }
    public var combo: KeyCombo?
    public var scope: Scope
    public init(combo: KeyCombo?, scope: Scope) {
        self.combo = combo
        self.scope = scope
    }
}

public struct ShortcutPreferences: Codable, Equatable, Sendable {
    /// Defaults: openStudio ⌘M (menu), toggleMusicWidget ⇧⌘M (menu), quit ⌘Q (menu),
    /// togglePause ⌥⌘P (global), others unbound.
    public private(set) var bindings: [ShortcutAction: ShortcutBinding] = ShortcutPreferences.defaultBindings

    public init() {}

    private static let defaultBindings: [ShortcutAction: ShortcutBinding] = [
        .openStudio: ShortcutBinding(
            combo: KeyCombo(keyCode: 46, modifiers: .command), // M
            scope: .menu
        ),
        .toggleMusicWidget: ShortcutBinding(
            combo: KeyCombo(keyCode: 46, modifiers: [.command, .shift]), // ⇧⌘M
            scope: .menu
        ),
        .quit: ShortcutBinding(
            combo: KeyCombo(keyCode: 12, modifiers: .command), // Q
            scope: .menu
        ),
        .togglePause: ShortcutBinding(
            combo: KeyCombo(keyCode: 35, modifiers: [.command, .option]), // ⌥⌘P
            scope: .global
        ),
    ]

    private static let reservedCombos: Set<KeyCombo> = [
        KeyCombo(keyCode: 12, modifiers: .command), // ⌘Q
        KeyCombo(keyCode: 48, modifiers: .command), // ⌘Tab (approximate; reserved list)
    ]

    /// Falls back to the default binding when the user hasn't customized `action`.
    public subscript(action: ShortcutAction) -> ShortcutBinding {
        get { bindings[action] ?? Self.defaultBindings[action] ?? ShortcutBinding(combo: nil, scope: .menu) }
        set { bindings[action] = newValue }
    }

    public enum Conflict: Equatable, Sendable {
        case usedBy(ShortcutAction)
        case reservedBySystem
    }

    /// Pure: refuses duplicates and a small reserved list (⌘Q is fixed to quit, ⌘Tab, …).
    public mutating func bind(
        _ combo: KeyCombo?,
        to action: ShortcutAction,
        scope: ShortcutBinding.Scope
    ) -> Conflict? {
        if let combo {
            if action != .quit, Self.reservedCombos.contains(combo) {
                return .reservedBySystem
            }
            for other in ShortcutAction.allCases where other != action {
                if let existing = self[other].combo, existing == combo {
                    return .usedBy(other)
                }
            }
        }
        bindings[action] = ShortcutBinding(combo: combo, scope: scope)
        return nil
    }
}

// MARK: - Misc sections

public struct StartupPreferences: Codable, Equatable, Sendable {
    /// Master switch (from Lumina.PersistAssignments). When false, pins are kept but not restored.
    public var restoreAtLaunch = true
    public var autoCheckUpdates = true // Lumina.AutoCheckUpdates
    public init() {}
}

public struct AmbientAudioPreferences: Codable, Equatable, Sendable {
    public var trackPath: String? = nil // Lumina.AmbientAudio.TrackPath
    public var volume: Double = 0.5 // .Volume
    public var loops = true // .Loops
    public var shuffle = false // .Shuffle
    public var favoriteTrackPaths: [String] = [] // .Favorites
    /// When false, ambient audio pauses while the screen is locked. Default true matches today.
    public var keepsPlayingWhenLocked = true
    public init() {}
}

public struct MediaAccessPreferences: Codable, Equatable, Sendable {
    public var enabledLocations: [String] = [] // Lumina.EnabledMediaLocations
    public var hasConfigured = false // Lumina.HasConfiguredMediaAccess (+ legacy AllowDocumentsAndDownloads)
    public init() {}
}

public struct Milestones: Codable, Equatable, Sendable {
    public var hasShownOnboarding = false // Lumina.HasShownOnboarding
    public var lastShownChangelogVersion: String? = nil
    public var hasDiscoveredAdjust = false // Lumina.HasDiscoveredAdjust
    // Lumina.HasAutoOpenedStudio was write-only: dropped.
    public init() {}
}
