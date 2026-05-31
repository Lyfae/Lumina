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
                icon: "display.2",
                title: "New Choose Display Window",
                description: "A beautiful floating window with unmistakable yellow/gold selection highlighting. Click any monitor to instantly configure it."
            ),
            ChangelogEntry(
                icon: "rectangle.on.rectangle",
                title: "Recent Wallpapers Canvas",
                description: "A horizontal strip of your previously used wallpapers with real thumbnails. Click any one to instantly apply it to the selected display."
            ),
            ChangelogEntry(
                icon: "person.crop.circle",
                title: "Welcome & What's New for Everyone",
                description: "The welcome screen and changelog are now easily accessible from the menu bar and inside the Wallpaper Manager — no more digging in Debug menus."
            ),
            ChangelogEntry(
                icon: "wand.and.stars",
                title: "Cleaner Manager Experience",
                description: "Removed the old workflow instructions. Display information moved down. Configuration only appears when you have actually selected a screen."
            ),
            ChangelogEntry(
                icon: "bolt.fill",
                title: "Better Power & Playback Reliability",
                description: "Videos no longer freeze while the manager or Choose Display window is open. Smoother low-power mode handling and thermal awareness."
            ),
            ChangelogEntry(
                icon: "paintbrush.fill",
                title: "Polished Selection & Visual Feedback",
                description: "Much stronger visual indication when choosing monitors, matching the experience you loved in Wallpaper Engine."
            )
        ]
    }
}

// (Presentation is handled directly in LuminaApp for strong window controller ownership.)