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
        ChangelogRelease(version: "0.4.3", entries: [
            ChangelogEntry(
                icon: "paintpalette",
                title: "Gray Accent Is Actually Gray",
                description: "The first accent swatch looked gray but applied the macOS system accent (usually blue). It now uses a real neutral gray, and the swatch matches what the UI tints."
            ),
        ]),
        ChangelogRelease(version: "0.4.2", entries: [
            ChangelogEntry(
                icon: "speedometer",
                title: "Simpler Adjust Column",
                description: "The video Performance section is hidden while it gets reworked. Its quality presets ignored the video's real resolution — offering 4K for a 1080p file — and the size estimates were rough guesses."
            ),
            ChangelogEntry(
                icon: "exclamationmark.triangle",
                title: "Clearer Performance Tips",
                description: "When a wallpaper is straining your Mac, Lumina now suggests a smaller or lower-resolution video, or Max Battery in Settings."
            ),
        ]),
        ChangelogRelease(version: "0.4.1", entries: [
            ChangelogEntry(
                icon: "crop",
                title: "Previews Show the Real Crop",
                description: "Previews now render exactly what lands on your desktop. The dimmed original image and the blue rectangle marking the crop area are gone — you just see the cropped picture."
            ),
            ChangelogEntry(
                icon: "paintbrush",
                title: "Cleaner Preview Chrome",
                description: "Removed the leftover blue outlines around the preview card and crop editor, and the Crop button now scales with the rest of the interface."
            ),
        ]),
        ChangelogRelease(version: "0.4.0", entries: [
            ChangelogEntry(
                icon: "waveform",
                title: "Waveform Music Widget",
                description: "Compact floating player with album art, title/artist, and a live waveform that doubles as the timeline. Hover for transport, volume, and Up Next; drag the playhead thumb to scrub."
            ),
            ChangelogEntry(
                icon: "menubar.arrow.up.rectangle",
                title: "Music Widget from the Menu Bar",
                description: "Open just the mini-player with Music Widget (⌘⇧M) — no need to bring Studio forward."
            ),
            ChangelogEntry(
                icon: "shuffle",
                title: "Shuffle & Shared Scrubbing",
                description: "Ambient shuffle remembers Previous while randomizing. Studio’s footer scrubber previews seek time while dragging and commits on release."
            ),
            ChangelogEntry(
                icon: "heart.text.square",
                title: "Playback Health Warnings",
                description: "Lumina watches for stalled buffers and thermal pressure, then warns in Studio and the menu bar tooltip when a wallpaper is too heavy — with tips to compress or use Max Battery."
            ),
            ChangelogEntry(
                icon: "rectangle.portrait.and.arrow.right",
                title: "Studio Polish",
                description: "Collapsed library rail opens again reliably, hit targets are larger, and surfaces stay solid branded cards instead of stacked glass for clearer readability."
            ),
        ]),
        ChangelogRelease(version: "0.3.0", entries: [
            ChangelogEntry(
                icon: "slider.horizontal.3",
                title: "Adjust Column & Clearer Actions",
                description: "Per-display Config is now Adjust. Clear removes the wallpaper; Reset Adjustments restores staged crop/effects. Keep on startup only pins for relaunch — it no longer blanks the desktop."
            ),
            ChangelogEntry(
                icon: "rectangle.split.3x1",
                title: "Studio Launch & Library",
                description: "Splash opens Studio every launch without stacking Choose Display. Library filters wrap (no stray scroll nub), empty states offer Clear Search / Show All, and Settings sections collapse into accordion fields."
            ),
            ChangelogEntry(
                icon: "music.note.list",
                title: "Ambient Music Widget",
                description: "Floating mini-player with artwork, metadata, Up Next queue, horizontal volume, and favorites. Footer scrubber previews time; Clear All asks before wiping the queue."
            ),
            ChangelogEntry(
                icon: "hand.tap",
                title: "Press Feedback & Polish",
                description: "Shared press styles across Studio controls, renamed About → Version & Status, and a tighter action bar (Apply / Clear / Reset Adjustments / Adjust)."
            ),
        ]),
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
