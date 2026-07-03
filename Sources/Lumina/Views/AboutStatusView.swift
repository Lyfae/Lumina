import SwiftUI
import AppKit

/// Combined About, live status, welcome copy, and full version changelog.
struct AboutStatusView: View {
    let appVersion: String
    let buildNumber: String
    let statusSummary: String
    var onPrintDebug: () -> Void
    var onOpenTestingGuide: () -> Void
    var onClose: () -> Void

    @State private var headerImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            if let headerImage {
                Image(nsImage: headerImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 110)
                    .clipped()
            } else {
                ZStack {
                    Color.black
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundStyle(.yellow)
                }
                .frame(height: 110)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lumina Studio")
                            .font(.title.bold())
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                        Text("Native live wallpaper engine for macOS — free, fast, and battery-friendly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    sectionHeader("Status")
                    Text(statusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    sectionHeader("Getting Started")
                    entryList(LuminaChangelog.welcomeEntries)

                    sectionHeader("Changelog")
                    ForEach(LuminaChangelog.releases) { release in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Version \(release.version)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(release.version == appVersion ? .yellow : .primary)
                            entryList(release.entries)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider().background(Color.white.opacity(0.15))

            HStack(spacing: 10) {
                Button("Print Debug") { onPrintDebug() }
                    .buttonStyle(.bordered)
                Button("Testing Guide") { onOpenTestingGuide() }
                    .buttonStyle(.bordered)
                Button("Releases") {
                    if let url = URL(string: "https://github.com/Lyfae/Lumina/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 540, height: 620)
        .background(Color.black)
        .onAppear {
            guard headerImage == nil else { return }
            let candidates = [
                Bundle.module.url(forResource: "OnboardingHeader", withExtension: "jpg"),
                Bundle.module.url(forResource: "OnboardingHeader", withExtension: "jpg", subdirectory: "Images"),
            ]
            for url in candidates {
                if let url, let image = NSImage(contentsOf: url) {
                    headerImage = image
                    break
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func entryList(_ entries: [ChangelogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.icon)
                        .font(.body)
                        .foregroundStyle(.yellow)
                        .frame(width: 22, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline.weight(.semibold))
                        Text(entry.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
