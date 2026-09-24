import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Locations

/// Standard macOS user folders Lumina may read wallpaper media from.
enum MediaAccessLocation: String, CaseIterable, Identifiable, Codable, Hashable {
    case pictures
    case movies
    case documents
    case downloads
    case desktop
    case music

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pictures: return "Pictures"
        case .movies: return "Movies"
        case .documents: return "Documents"
        case .downloads: return "Downloads"
        case .desktop: return "Desktop"
        case .music: return "Music"
        }
    }

    var subtitle: String {
        switch self {
        case .pictures: return "Photos and images"
        case .movies: return "Videos"
        case .documents: return "Files in Documents"
        case .downloads: return "Files you’ve downloaded"
        case .desktop: return "Files on your desktop"
        case .music: return "Songs for the music player"
        }
    }

    var icon: String {
        switch self {
        case .pictures: return "photo.on.rectangle"
        case .movies: return "film"
        case .documents: return "doc.text"
        case .downloads: return "arrow.down.circle"
        case .desktop: return "desktopcomputer"
        case .music: return "music.note"
        }
    }

    /// Recommended on first launch — keeps the default experience focused on media libraries.
    var isOnByDefault: Bool {
        switch self {
        case .pictures, .movies: return true
        default: return false
        }
    }

    var searchPathDirectory: FileManager.SearchPathDirectory? {
        // Kept for documentation / future sandbox entitlements mapping.
        switch self {
        case .pictures: return .picturesDirectory
        case .movies: return .moviesDirectory
        case .documents: return .documentDirectory
        case .downloads: return .downloadsDirectory
        case .desktop: return .desktopDirectory
        case .music: return .musicDirectory
        }
    }

    func resolvedRootURL() -> URL? {
        // Prefer home-relative paths for TCC-protected folders. Calling
        // `FileManager.urls(for: .documentDirectory / .desktopDirectory / …)`
        // can itself trigger macOS "Allow access to Documents?" prompts — even
        // when we only need the path for a preference checklist.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folderName: String
        switch self {
        case .pictures: folderName = "Pictures"
        case .movies: folderName = "Movies"
        case .documents: folderName = "Documents"
        case .downloads: folderName = "Downloads"
        case .desktop: folderName = "Desktop"
        case .music: folderName = "Music"
        }
        return home
            .appendingPathComponent(folderName, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }
}

// MARK: - User preferences

@MainActor
final class MediaAccessSettings: ObservableObject {
    static let shared = MediaAccessSettings()

    @Published private(set) var enabledLocations: Set<MediaAccessLocation> = []

    private weak var preferences: PreferencesStore?

    var hasConfiguredPrivacy: Bool {
        preferences?.mediaAccess.hasConfigured ?? false
    }

    private init() {}

    func attach(preferences: PreferencesStore) {
        self.preferences = preferences
        enabledLocations = Self.locations(from: preferences.mediaAccess)
        if enabledLocations.isEmpty && !preferences.mediaAccess.hasConfigured {
            enabledLocations = Set(MediaAccessLocation.allCases.filter(\.isOnByDefault))
        }
        trackChanges()
    }

    func isEnabled(_ location: MediaAccessLocation) -> Bool {
        enabledLocations.contains(location)
    }

    func setEnabled(_ location: MediaAccessLocation, _ enabled: Bool) {
        var next = enabledLocations
        if enabled {
            next.insert(location)
        } else {
            next.remove(location)
            FileAccess.removeFolderGrant(for: location)
        }
        apply(next, markConfigured: true)
    }

    func binding(for location: MediaAccessLocation) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(location) },
            set: { newValue in
                if newValue != self.isEnabled(location) {
                    self.setEnabled(location, newValue)
                }
            }
        )
    }

    /// Applies the onboarding / settings checklist in one shot.
    func applySelection(_ locations: Set<MediaAccessLocation>) {
        for location in MediaAccessLocation.allCases where !locations.contains(location) {
            FileAccess.removeFolderGrant(for: location)
        }
        apply(locations, markConfigured: true)
    }

    func resetToDefaults() {
        applySelection(Set(MediaAccessLocation.allCases.filter(\.isOnByDefault)))
    }

    private func apply(_ locations: Set<MediaAccessLocation>, markConfigured: Bool) {
        enabledLocations = locations
        guard let preferences else {
            objectWillChange.send()
            return
        }
        var access = preferences.mediaAccess
        access.enabledLocations = locations.map(\.rawValue)
        if markConfigured { access.hasConfigured = true }
        preferences.mediaAccess = access
        objectWillChange.send()
    }

    private static func locations(from prefs: MediaAccessPreferences) -> Set<MediaAccessLocation> {
        let parsed = Set(prefs.enabledLocations.compactMap(MediaAccessLocation.init(rawValue:)))
        return parsed
    }

    private func trackChanges() {
        withObservationTracking {
            _ = preferences?.mediaAccess
        } onChange: { [weak self] in
            Task { @MainActor in
                if let prefs = self?.preferences?.mediaAccess {
                    let locs = Self.locations(from: prefs)
                    if !locs.isEmpty || prefs.hasConfigured {
                        self?.enabledLocations = locs.isEmpty
                            ? Set(MediaAccessLocation.allCases.filter(\.isOnByDefault))
                            : locs
                    }
                }
                self?.objectWillChange.send()
                self?.trackChanges()
            }
        }
    }
}

// MARK: - Policy

@MainActor
enum MediaAccessPolicy {
    static var enabledLocations: Set<MediaAccessLocation> {
        MediaAccessSettings.shared.enabledLocations
    }

    static var allowedRoots: [URL] {
        enabledLocations.compactMap { $0.resolvedRootURL() }
    }

    static func isURLAllowed(_ url: URL) -> Bool {
        if isAppManagedURL(url) { return true }
        guard !allowedRoots.isEmpty else { return false }

        let path = normalizedPath(url)
        return allowedRoots.contains { root in
            let rootPath = normalizedPath(root)
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Lumina-generated files (compressed cache, etc.) — not subject to folder policy.
    static func isAppManagedURL(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return false }
        let luminaRoot = support.appendingPathComponent("Lumina", isDirectory: true).path
        return path == luminaRoot || path.hasPrefix(luminaRoot + "/")
    }

    // MARK: - Open panel

    static func defaultPickerDirectory() -> URL? {
        if let pictures = MediaAccessLocation.pictures.resolvedRootURL(),
           enabledLocations.contains(.pictures) {
            return pictures
        }
        return allowedRoots.first
    }

    static func restrictionHint() -> String {
        let names = enabledLocations.sorted { $0.label < $1.label }.map(\.label)
        guard !names.isEmpty else {
            return "Pick a folder in Settings → Privacy first."
        }
        if names.count == 1 {
            return "You can pick files from your \(names[0]) folder."
        }
        let joined = names.dropLast().joined(separator: ", ")
        return "You can pick files from \(joined), or \(names.last!)."
    }

    /// Presents a wallpaper/media open panel; access is enforced when files are accepted.
    @discardableResult
    static func runWallpaperPicker(
        title: String,
        message: String,
        allowedTypes: [UTType] = [.movie, .image, .gif],
        allowsMultipleSelection: Bool = false
    ) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = "\(message) \(restrictionHint())"
        panel.allowedContentTypes = allowedTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.directoryURL = defaultPickerDirectory()

        guard panel.runModal() == .OK else { return [] }

        let picked = allowsMultipleSelection ? panel.urls : (panel.url.map { [$0] } ?? [])
        var accepted: [URL] = []
        for url in picked {
            if accept(url) {
                accepted.append(url)
            }
        }
        return accepted
    }

    /// Validates location, registers security-scoped access, and shows an alert when denied.
    @discardableResult
    static func accept(_ url: URL) -> Bool {
        guard isURLAllowed(url) else {
            showAccessDeniedAlert(for: url)
            return false
        }
        // Per-file grant from the open panel — enough for playback + bookmarks.
        _ = FileAccess.registerUserSelectedFile(url)
        return true
    }

    // MARK: - Alerts

    private static func showAccessDeniedAlert(for url: URL) {
        let folder = url.deletingLastPathComponent().lastPathComponent
        let file = url.lastPathComponent
        let allowedList = enabledLocations.sorted { $0.label < $1.label }.map(\.label).joined(separator: ", ")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Folder Not Allowed"
        alert.informativeText = """
        “\(folder)/\(file)” is outside the folders you allowed Lumina to use.

        Currently allowed: \(allowedList.isEmpty ? "none" : allowedList).

        Open Settings → Privacy to add more locations, or move the file into an allowed folder.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
