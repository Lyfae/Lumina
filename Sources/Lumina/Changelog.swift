import Foundation

struct ChangelogEntry: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

struct ChangelogRelease: Identifiable {
    let version: String
    let entries: [ChangelogEntry]
    var id: String { version }
}

/// In-app changelog and welcome copy — single source for About & Status.
enum LuminaChangelog {
    static let welcomeEntries: [ChangelogEntry] = [
        ChangelogEntry(
            icon: "battery.100.bolt",
            title: "Designed for Battery Life",
            description: "Hardware-accelerated playback with smart power management. Lumina pauses or throttles on battery, in Low Power Mode, or under thermal pressure."
        ),
        ChangelogEntry(
            icon: "slider.horizontal.3",
            title: "You Stay in Control",
            description: "Adjust performance profiles, per-display crop, speed, scaling, and effects. Preview changes live, then Apply to Wallpaper when ready."
        ),
        ChangelogEntry(
            icon: "info.circle",
            title: "Getting Started",
            description: "Menu bar icon → Lumina Studio (⌘M). Add media to your library, pick a display, tune settings in the preview, then Apply. Slideshows, crop, and sync are all supported."
        ),
    ]

    static let releases: [ChangelogRelease] = [
        ChangelogRelease(version: "0.2.0", entries: [
            ChangelogEntry(
                icon: "sparkles",
                title: "Release Splash & Branding",
                description: "Launch splash with animated cursive LS monogram, refreshed app icon, and menu bar icon drawn from the same artwork."
            ),
            ChangelogEntry(
                icon: "shield.checkered",
                title: "Stability Audit",
                description: "Fixes for player observer leaks, fullscreen detector teardown, scoped bookmark leaks, crash guards, and sticky manual pause."
            ),
            ChangelogEntry(
                icon: "gauge.with.dots.needle.67percent",
                title: "Performance Polish",
                description: "Reduced UI re-renders, cached menu bar icon, streaming update downloads, and smarter slideshow resume timing."
            ),
            ChangelogEntry(
                icon: "crop",
                title: "Crop Editor Fix",
                description: "Re-opening the crop editor preserves your last crop position instead of resetting to the default frame."
            ),
        ]),
        ChangelogRelease(version: "0.1.0", entries: [
            ChangelogEntry(
                icon: "music.note.list",
                title: "Redesigned Music Player",
                description: "Roomier now-playing bar with album art, transport controls, loop toggle, skip, and a floating mini-player when the Studio window is minimized."
            ),
            ChangelogEntry(
                icon: "macwindow.on.rectangle",
                title: "Adaptive, Resizable Window",
                description: "The Studio window resizes freely — crisp at every size, with your preferred size remembered between launches."
            ),
            ChangelogEntry(
                icon: "slider.horizontal.3",
                title: "Preview First, Then Apply",
                description: "Stage brightness, opacity, color, and crop on a live preview, then commit with one Apply."
            ),
            ChangelogEntry(
                icon: "arrow.triangle.2.circlepath",
                title: "Sync Displays",
                description: "Restart matching videos across monitors in lockstep with one click."
            ),
            ChangelogEntry(
                icon: "gearshape.fill",
                title: "Settings Panel",
                description: "Theme, accent color, launch at login, startup restore, sync, and battery & performance profiles."
            ),
            ChangelogEntry(
                icon: "bolt.fill",
                title: "Battery & Performance",
                description: "Performance profiles, Low Power Mode pausing, thermal throttling, and pause-behind-fullscreen on the live wallpaper."
            ),
        ]),
    ]

    static func entries(for version: String) -> [ChangelogEntry] {
        releases.first { $0.version == version }?.entries ?? releases.first?.entries ?? []
    }

    static func formattedText(includeWelcome: Bool = true) -> String {
        var lines: [String] = []
        if includeWelcome {
            lines.append("GETTING STARTED")
            for entry in welcomeEntries {
                lines.append("• \(entry.title) — \(entry.description)")
            }
            lines.append("")
        }
        lines.append("CHANGELOG")
        for release in releases {
            lines.append("")
            lines.append("Version \(release.version)")
            for entry in release.entries {
                lines.append("• \(entry.title) — \(entry.description)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
