// Lumina/Preferences — the single observable, typed preference store.
import Foundation
import Observation
import LuminaCore

@MainActor
@Observable
public final class PreferencesStore {
    public var power: PowerPreferences { didSet { dirty(.power) } }
    public var playback: PlaybackPreferences { didSet { dirty(.playback) } }
    public var wallpapers: WallpaperPreferences { didSet { dirty(.wallpapers) } }
    public var widget: MusicWidgetPreferences { didSet { dirty(.widget) } }
    public var studio: StudioLookPreferences { didSet { dirty(.studio) } }
    public var shortcuts: ShortcutPreferences { didSet { dirty(.shortcuts) } }
    public var startup: StartupPreferences { didSet { dirty(.startup) } }
    public var audio: AmbientAudioPreferences { didSet { dirty(.audio) } }
    public var mediaAccess: MediaAccessPreferences { didSet { dirty(.mediaAccess) } }
    public var milestones: Milestones { didSet { dirty(.milestones) } }

    @ObservationIgnored private let backend: PreferencesBackend
    @ObservationIgnored private var pending: Set<PreferenceSection> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var isLoading = false

    public init(backend: PreferencesBackend) {
        self.backend = backend
        let legacy = backend.readLegacy()
        let (migrated, _) = LegacyMigration.migrate(legacy)

        isLoading = true
        defer { isLoading = false }

        var doc = PreferencesDocument()
        for section in PreferenceSection.allCases {
            if !backend.readSection(section, into: &doc) {
                switch section {
                case .power: doc.power = migrated.power
                case .playback: doc.playback = migrated.playback
                case .wallpapers: doc.wallpapers = migrated.wallpapers
                case .widget: doc.widget = migrated.widget
                case .studio: doc.studio = migrated.studio
                case .shortcuts: doc.shortcuts = migrated.shortcuts
                case .startup: doc.startup = migrated.startup
                case .audio: doc.audio = migrated.audio
                case .mediaAccess: doc.mediaAccess = migrated.mediaAccess
                case .milestones: doc.milestones = migrated.milestones
                }
            }
        }

        power = doc.power
        playback = doc.playback
        wallpapers = doc.wallpapers
        widget = doc.widget
        studio = doc.studio
        shortcuts = doc.shortcuts
        startup = doc.startup
        audio = doc.audio
        mediaAccess = doc.mediaAccess
        milestones = doc.milestones
    }

    /// Exactly the sections the planner reads.
    public var planning: PlanningPreferences {
        PlanningPreferences(power: power, playback: playback, wallpapers: wallpapers, startup: startup)
    }

    public func reset(_ section: PreferenceSection) {
        let defaults = PreferencesDocument()
        switch section {
        case .power: power = defaults.power
        case .playback: playback = defaults.playback
        case .wallpapers: wallpapers = defaults.wallpapers
        case .widget: widget = defaults.widget
        case .studio: studio = defaults.studio
        case .shortcuts: shortcuts = defaults.shortcuts
        case .startup: startup = defaults.startup
        case .audio: audio = defaults.audio
        case .mediaAccess: mediaAccess = defaults.mediaAccess
        case .milestones: milestones = defaults.milestones
        }
    }

    public func flush() {
        flushTask?.cancel()
        flushTask = nil
        let sections = pending
        pending.removeAll()
        write(sections)
    }

    private func dirty(_ section: PreferenceSection) {
        guard !isLoading else { return }
        pending.insert(section)
        flushTask?.cancel()
        flushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let sections = pending
            pending.removeAll()
            write(sections)
        }
    }

    private func write(_ sections: Set<PreferenceSection>) {
        var doc = PreferencesDocument()
        doc.power = power
        doc.playback = playback
        doc.wallpapers = wallpapers
        doc.widget = widget
        doc.studio = studio
        doc.shortcuts = shortcuts
        doc.startup = startup
        doc.audio = audio
        doc.mediaAccess = mediaAccess
        doc.milestones = milestones
        for section in sections {
            backend.writeSection(section, from: doc)
        }
    }

    /// Snapshot used by self-tests / debugging.
    public func documentSnapshot() -> PreferencesDocument {
        var doc = PreferencesDocument()
        doc.power = power
        doc.playback = playback
        doc.wallpapers = wallpapers
        doc.widget = widget
        doc.studio = studio
        doc.shortcuts = shortcuts
        doc.startup = startup
        doc.audio = audio
        doc.mediaAccess = mediaAccess
        doc.milestones = milestones
        return doc
    }
}

/// Storage boundary. Wire formats never leave this protocol's implementations.
public protocol PreferencesBackend: Sendable {
    func readLegacy() -> LegacyDefaults
    /// JSON blob under "Lumina.Preferences.v2.<section>", except `.wallpapers`, which reads the
    /// v1 assignment and library keys (their format is frozen for downgrade safety).
    func readSection(_ section: PreferenceSection, into doc: inout PreferencesDocument) -> Bool
    func writeSection(_ section: PreferenceSection, from doc: PreferencesDocument)
}

public struct UserDefaultsBackend: PreferencesBackend, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func v2Key(_ section: PreferenceSection) -> String {
        "Lumina.Preferences.v2.\(section.rawValue)"
    }

    public func readLegacy() -> LegacyDefaults {
        var values: [LegacyKey: LegacyDefaults.Value] = [:]
        for key in LegacyKey.allCases {
            let raw = key.rawValue
            if let b = defaults.object(forKey: raw) as? Bool {
                values[key] = .bool(b)
            } else if let n = defaults.object(forKey: raw) as? NSNumber,
                      CFGetTypeID(n) == CFBooleanGetTypeID() {
                values[key] = .bool(n.boolValue)
            } else if let d = defaults.object(forKey: raw) as? Double {
                values[key] = .double(d)
            } else if let n = defaults.object(forKey: raw) as? NSNumber {
                // Distinguish bool-looking numbers already handled; treat as double when useful.
                if key == .audioVolume || key == .audioLoops || key == .audioShuffle
                    || key == .audioShowWidgetWhenMinimized {
                    if key == .audioVolume {
                        values[key] = .double(n.doubleValue)
                    } else {
                        values[key] = .bool(n.boolValue)
                    }
                } else if [
                    LegacyKey.pauseLowPower, .pauseThermal, .respectFullscreen,
                    .persistAssignments, .autoCheckUpdates, .hasShownOnboarding,
                    .hasAutoOpenedStudio, .hasDiscoveredAdjust, .hasConfiguredMediaAccess,
                    .allowDocumentsAndDownloads, .syncPlayback, .audioLoops, .audioShuffle,
                    .audioShowWidgetWhenMinimized
                ].contains(key) {
                    values[key] = .bool(n.boolValue)
                } else {
                    values[key] = .double(n.doubleValue)
                }
            } else if let s = defaults.string(forKey: raw) {
                values[key] = .string(s)
            } else if let data = defaults.data(forKey: raw) {
                values[key] = .data(data)
            } else if let arr = defaults.stringArray(forKey: raw) {
                values[key] = .strings(arr)
            }
        }
        return LegacyDefaults(values: values)
    }

    public func readSection(_ section: PreferenceSection, into doc: inout PreferencesDocument) -> Bool {
        if section == .wallpapers {
            return readWallpapersV1(into: &doc)
        }
        guard let data = defaults.data(forKey: Self.v2Key(section)) else { return false }
        do {
            switch section {
            case .power:
                doc.power = try JSONDecoder().decode(PowerPreferences.self, from: data)
            case .playback:
                doc.playback = try JSONDecoder().decode(PlaybackPreferences.self, from: data)
            case .wallpapers:
                return false
            case .widget:
                doc.widget = try JSONDecoder().decode(MusicWidgetPreferences.self, from: data)
            case .studio:
                doc.studio = try JSONDecoder().decode(StudioLookPreferences.self, from: data)
            case .shortcuts:
                doc.shortcuts = try JSONDecoder().decode(ShortcutPreferences.self, from: data)
            case .startup:
                doc.startup = try JSONDecoder().decode(StartupPreferences.self, from: data)
            case .audio:
                doc.audio = try JSONDecoder().decode(AmbientAudioPreferences.self, from: data)
            case .mediaAccess:
                doc.mediaAccess = try JSONDecoder().decode(MediaAccessPreferences.self, from: data)
            case .milestones:
                doc.milestones = try JSONDecoder().decode(Milestones.self, from: data)
            }
            return true
        } catch {
            return false
        }
    }

    public func writeSection(_ section: PreferenceSection, from doc: PreferencesDocument) {
        if section == .wallpapers {
            writeWallpapersV1(from: doc)
            return
        }
        let encoder = JSONEncoder()
        let data: Data?
        switch section {
        case .power: data = try? encoder.encode(doc.power)
        case .playback: data = try? encoder.encode(doc.playback)
        case .wallpapers: data = nil
        case .widget: data = try? encoder.encode(doc.widget)
        case .studio: data = try? encoder.encode(doc.studio)
        case .shortcuts: data = try? encoder.encode(doc.shortcuts)
        case .startup: data = try? encoder.encode(doc.startup)
        case .audio: data = try? encoder.encode(doc.audio)
        case .mediaAccess: data = try? encoder.encode(doc.mediaAccess)
        case .milestones: data = try? encoder.encode(doc.milestones)
        }
        if let data {
            defaults.set(data, forKey: Self.v2Key(section))
        }
    }

    /// Dual-write: pinned assignments + full library under the frozen v1 keys so older builds can read them.
    private func readWallpapersV1(into doc: inout PreferencesDocument) -> Bool {
        var assignments: [DisplayKey: DisplayWallpaper] = [:]
        var library: [LibraryItem] = []
        var found = false

        if let data = defaults.data(forKey: LegacyKey.monitorAssignments.rawValue),
           let decoded = try? JSONDecoder().decode([String: MonitorAssignmentWire].self, from: data) {
            found = true
            for (id, wire) in decoded where wire.keepOnStartup && !id.hasPrefix("library-import-") {
                assignments[DisplayKey(id)] = LegacyMigration.wallpaper(from: wire)
            }
        }
        if let data = defaults.data(forKey: LegacyKey.libraryItems.rawValue),
           let decoded = try? JSONDecoder().decode([String: MonitorAssignmentWire].self, from: data) {
            found = true
            for (id, wire) in decoded {
                let wallpaper = LegacyMigration.wallpaper(from: wire)
                if case .media(let ref) = wallpaper.content {
                    library.append(LibraryItem(id: id, media: ref))
                } else if let path = wire.filePath {
                    let kind: MediaKind
                    switch wire.mediaType {
                    case .image: kind = .image
                    case .animatedImage: kind = .animatedImage
                    case .video: kind = .video
                    case .unknown: kind = .image
                    }
                    library.append(LibraryItem(
                        id: id,
                        media: MediaReference(
                            identity: MediaIdentity(normalizing: path),
                            displayPath: path,
                            bookmark: wire.bookmarkData,
                            kind: kind
                        )
                    ))
                }
            }
        }
        guard found else { return false }
        doc.wallpapers.replaceAll(assignments: assignments, library: library)
        return true
    }

    private func writeWallpapersV1(from doc: PreferencesDocument) {
        var pinned: [String: MonitorAssignmentWire] = [:]
        for (key, wallpaper) in doc.wallpapers.byDisplay where wallpaper.pinned {
            pinned[key.rawValue] = LegacyMigration.wire(from: wallpaper, key: key)
        }
        if let data = try? JSONEncoder().encode(pinned) {
            defaults.set(data, forKey: LegacyKey.monitorAssignments.rawValue)
        }
        var library: [String: MonitorAssignmentWire] = [:]
        for item in doc.wallpapers.library {
            var wire = LegacyMigration.wire(
                from: {
                    var wp = DisplayWallpaper()
                    wp.content = .media(item.media)
                    return wp
                }(),
                key: DisplayKey(item.id)
            )
            wire.monitorIdentifier = item.id
            library[item.id] = wire
        }
        if let data = try? JSONEncoder().encode(library) {
            defaults.set(data, forKey: LegacyKey.libraryItems.rawValue)
        }
    }
}

/// For self-tests: seeded with a legacy dictionary, records writes.
public final class InMemoryBackend: PreferencesBackend, @unchecked Sendable {
    private var legacy: LegacyDefaults
    private var sections: [PreferenceSection: Data] = [:]
    public private(set) var writeLog: [PreferenceSection] = []

    public init(legacy: LegacyDefaults = LegacyDefaults(values: [:])) {
        self.legacy = legacy
    }

    public func readLegacy() -> LegacyDefaults { legacy }

    /// Dual-write mirror of v1 assignment/library blobs for self-tests.
    public private(set) var v1Assignments: Data?
    public private(set) var v1Library: Data?

    public func readSection(_ section: PreferenceSection, into doc: inout PreferencesDocument) -> Bool {
        if section == .wallpapers {
            guard v1Assignments != nil || v1Library != nil else { return false }
            var assignments: [DisplayKey: DisplayWallpaper] = [:]
            var library: [LibraryItem] = []
            if let data = v1Assignments,
               let decoded = try? JSONDecoder().decode([String: MonitorAssignmentWire].self, from: data) {
                for (id, wire) in decoded {
                    assignments[DisplayKey(id)] = LegacyMigration.wallpaper(from: wire)
                }
            }
            if let data = v1Library,
               let decoded = try? JSONDecoder().decode([String: MonitorAssignmentWire].self, from: data) {
                for (id, wire) in decoded {
                    let wp = LegacyMigration.wallpaper(from: wire)
                    if case .media(let ref) = wp.content {
                        library.append(LibraryItem(id: id, media: ref))
                    }
                }
            }
            doc.wallpapers.replaceAll(assignments: assignments, library: library)
            return true
        }
        guard let data = sections[section] else { return false }
        do {
            switch section {
            case .power: doc.power = try JSONDecoder().decode(PowerPreferences.self, from: data)
            case .playback: doc.playback = try JSONDecoder().decode(PlaybackPreferences.self, from: data)
            case .wallpapers: return false
            case .widget: doc.widget = try JSONDecoder().decode(MusicWidgetPreferences.self, from: data)
            case .studio: doc.studio = try JSONDecoder().decode(StudioLookPreferences.self, from: data)
            case .shortcuts: doc.shortcuts = try JSONDecoder().decode(ShortcutPreferences.self, from: data)
            case .startup: doc.startup = try JSONDecoder().decode(StartupPreferences.self, from: data)
            case .audio: doc.audio = try JSONDecoder().decode(AmbientAudioPreferences.self, from: data)
            case .mediaAccess: doc.mediaAccess = try JSONDecoder().decode(MediaAccessPreferences.self, from: data)
            case .milestones: doc.milestones = try JSONDecoder().decode(Milestones.self, from: data)
            }
            return true
        } catch {
            return false
        }
    }

    public func writeSection(_ section: PreferenceSection, from doc: PreferencesDocument) {
        writeLog.append(section)
        let encoder = JSONEncoder()
        switch section {
        case .power: sections[section] = try? encoder.encode(doc.power)
        case .playback: sections[section] = try? encoder.encode(doc.playback)
        case .wallpapers:
            var pinned: [String: MonitorAssignmentWire] = [:]
            for (key, wallpaper) in doc.wallpapers.byDisplay where wallpaper.pinned {
                pinned[key.rawValue] = LegacyMigration.wire(from: wallpaper, key: key)
            }
            v1Assignments = try? encoder.encode(pinned)
            var library: [String: MonitorAssignmentWire] = [:]
            for item in doc.wallpapers.library {
                var wire = LegacyMigration.wire(from: {
                    var wp = DisplayWallpaper()
                    wp.content = .media(item.media)
                    return wp
                }(), key: DisplayKey(item.id))
                wire.monitorIdentifier = item.id
                library[item.id] = wire
            }
            v1Library = try? encoder.encode(library)
        case .widget: sections[section] = try? encoder.encode(doc.widget)
        case .studio: sections[section] = try? encoder.encode(doc.studio)
        case .shortcuts: sections[section] = try? encoder.encode(doc.shortcuts)
        case .startup: sections[section] = try? encoder.encode(doc.startup)
        case .audio: sections[section] = try? encoder.encode(doc.audio)
        case .mediaAccess: sections[section] = try? encoder.encode(doc.mediaAccess)
        case .milestones: sections[section] = try? encoder.encode(doc.milestones)
        }
    }
}
