import AppKit
import Foundation
import UniformTypeIdentifiers

/// Controls which folders Lumina may use for wallpaper media.
/// Default: Pictures (Photos) and Movies only. Documents & Downloads are opt-in via Settings.
@MainActor
final class MediaAccessSettings: ObservableObject {
    static let shared = MediaAccessSettings()

    private let key = "Lumina.AllowDocumentsAndDownloads"

    @Published var allowDocumentsAndDownloads: Bool {
        didSet { UserDefaults.standard.set(allowDocumentsAndDownloads, forKey: key) }
    }

    private init() {
        allowDocumentsAndDownloads = UserDefaults.standard.bool(forKey: key)
    }
}

@MainActor
enum MediaAccessPolicy {
    // MARK: - Allowed locations

    static var photosAndVideoRoots: [URL] {
        let fm = FileManager.default
        var roots: [URL] = []
        for directory in [FileManager.SearchPathDirectory.picturesDirectory,
                          .moviesDirectory] {
            if let url = fm.urls(for: directory, in: .userDomainMask).first {
                roots.append(url.standardizedFileURL)
            }
        }
        return roots
    }

    static var optionalDocumentRoots: [URL] {
        guard MediaAccessSettings.shared.allowDocumentsAndDownloads else { return [] }
        let fm = FileManager.default
        var roots: [URL] = []
        for directory in [FileManager.SearchPathDirectory.downloadsDirectory,
                          .documentDirectory] {
            if let url = fm.urls(for: directory, in: .userDomainMask).first {
                roots.append(url.standardizedFileURL)
            }
        }
        return roots
    }

    static var allowedRoots: [URL] {
        photosAndVideoRoots + optionalDocumentRoots
    }

    static func isURLAllowed(_ url: URL) -> Bool {
        if isAppManagedURL(url) { return true }
        let path = url.standardizedFileURL.path
        return allowedRoots.contains { root in
            let rootPath = root.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    /// Lumina-generated files (compressed cache, etc.) — not subject to folder policy.
    static func isAppManagedURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return false }
        let luminaRoot = support.appendingPathComponent("Lumina", isDirectory: true).path
        return path == luminaRoot || path.hasPrefix(luminaRoot + "/")
    }

    // MARK: - Open panel

    static func defaultPickerDirectory() -> URL? {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
    }

    static func restrictionHint() -> String {
        if MediaAccessSettings.shared.allowDocumentsAndDownloads {
            return "You can choose files from Pictures, Movies, Documents, or Downloads."
        }
        return "Lumina can access Pictures and Movies only. Enable Documents & Downloads in Settings → Privacy if you need other folders."
    }

    /// Presents a wallpaper/media open panel scoped to the user's privacy preference.
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
        _ = FileAccess.registerUserSelectedFile(url)
        return true
    }

    // MARK: - Alerts

    private static func showAccessDeniedAlert(for url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Folder Not Allowed"
        if MediaAccessSettings.shared.allowDocumentsAndDownloads {
            alert.informativeText = """
            Lumina couldn't use “\(url.lastPathComponent)” from this location.

            Choose a file inside Pictures, Movies, Documents, or Downloads.
            """
        } else {
            alert.informativeText = """
            Lumina can only use wallpapers from your Pictures or Movies folders.

            “\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)” is outside those locations.

            Open Settings → Privacy and enable “Allow Documents & Downloads” to pick files from other folders.
            """
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
