import SwiftUI
import AppKit

/// Rich, polished "What's New" / changelog viewer.
/// Matches the dark premium style of the onboarding experience.
/// Used both for automatic update notifications and when users explicitly click
/// "Welcome & What's New".
struct WhatsNewView: View {
    let version: String
    let entries: [ChangelogEntry]
    let onDismiss: () -> Void
    let onViewReleaseNotes: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Re-use the beautiful Grok Imagine header for brand consistency
            if let imageURL = Bundle.module.url(forResource: "OnboardingHeader", withExtension: "jpg", subdirectory: "Images"),
               let headerImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: headerImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 130)
                    .clipped()
            } else {
                ZStack {
                    Color.black
                    Image(systemName: "sparkles")
                        .font(.system(size: 42))
                        .foregroundStyle(.yellow)
                }
                .frame(height: 130)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                // Header text
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's New in Lumina")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    
                    Text("Version \(version)")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                }
                .padding(.top, 8)
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // Changelog entries
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(entries) { entry in
                            ChangeRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
                
                Spacer(minLength: 8)
                
                // Footer actions
                HStack(spacing: 12) {
                    Button {
                        onViewReleaseNotes()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("Full Release Notes")
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        onDismiss()
                    } label: {
                        Text("Got it, thanks!")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(width: 520, height: 560)
        .background(Color.black)
    }
}

/// A single changelog entry row, styled similarly to the onboarding FeatureRow.
private struct ChangeRow: View {
    let entry: ChangelogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.icon)
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 28, alignment: .center)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Text(entry.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Data Model

struct ChangelogEntry: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

// Convenience: current release highlights (expand this before shipping new versions)
extension WhatsNewView {
    static func entriesForCurrentVersion(_ version: String) -> [ChangelogEntry] {
        // You can key this by version in the future for historical notes.
        // For now we show the highlights for the active release.
        return [
            ChangelogEntry(
                icon: "music.note.list",
                title: "Redesigned Music Player",
                description: "A roomier now-playing bar with album art, bigger transport controls, a loop toggle, and skip — plus a floating mini-player that pops out when you minimize the Studio window."
            ),
            ChangelogEntry(
                icon: "macwindow.on.rectangle",
                title: "Adaptive, Resizable Window",
                description: "The Studio window now resizes freely to whatever size you like — crisp at every size, with no wasted empty space. Your size is remembered between launches."
            ),
            ChangelogEntry(
                icon: "slider.horizontal.3",
                title: "Preview First, Then Apply",
                description: "Stage brightness, opacity, color, crop and more on a live WYSIWYG preview, then commit it all to the desktop with one Apply — which now clearly shows when you're up to date."
            ),
            ChangelogEntry(
                icon: "arrow.triangle.2.circlepath",
                title: "Sync Displays",
                description: "Running the same video or GIF across multiple monitors but out of phase? One click restarts them together so they play in perfect lockstep."
            ),
            ChangelogEntry(
                icon: "gearshape.fill",
                title: "New Settings Panel",
                description: "Theme (dark / light / match system), accent color, launch at login, startup restore, sync, and battery & performance profiles — all in one tidy place."
            ),
            ChangelogEntry(
                icon: "bolt.fill",
                title: "Battery & Performance That Works",
                description: "Performance profiles, Low Power Mode pausing, thermal throttling, and pause-behind-fullscreen all take effect on the live wallpaper immediately."
            )
        ]
    }
}

// (Presentation is handled directly in LuminaApp for strong window controller ownership.)