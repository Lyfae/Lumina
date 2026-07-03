import AppKit
import Foundation

enum UpdateChecker {
    private static let repo = "Lyfae/Lumina"
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    private static let releasesPageURL = URL(string: "https://github.com/Lyfae/Lumina/releases")!

    struct ReleaseInfo {
        let version: String
        let downloadURL: URL
        let releasePageURL: URL
    }

    enum Result {
        case upToDate
        case updateAvailable(ReleaseInfo)
        case error(String)
    }

    static func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }

    static func check(currentVersion: String) async -> Result {
        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Lumina-UpdateChecker", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error("Unexpected response from GitHub.")
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 404 {
                    return .error("No public release was found. If this is a private repository, open the Releases page in your browser while signed in to GitHub.")
                }
                return .error("GitHub returned status \(http.statusCode). Try again later.")
            }

            let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = normalizeVersion(decoded.tagName)
            guard !latest.isEmpty else {
                return .error("Could not parse the latest release version.")
            }

            if isVersion(latest, newerThan: normalizeVersion(currentVersion)) {
                guard let dmg = decoded.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
                      let downloadURL = URL(string: dmg.browserDownloadURL),
                      let pageURL = URL(string: decoded.htmlURL) else {
                    return .error("A newer version (\(latest)) exists but no DMG download was found on the release page.")
                }
                return .updateAvailable(ReleaseInfo(version: latest, downloadURL: downloadURL, releasePageURL: pageURL))
            }
            return .upToDate
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func normalizeVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        compareVersions(a, b) == .orderedDescending
    }

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(pa.count, pb.count)
        for i in 0..<count {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
