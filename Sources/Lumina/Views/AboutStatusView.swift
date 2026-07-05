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

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    private let inkGradient: [Color] = [
        Color(red: 0.62, green: 0.87, blue: 1.0),
        Color(red: 0.72, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.78, blue: 0.55)
    ]

    var body: some View {
        VStack(spacing: 0) {
            brandHeader

            ScrollView {
                VStack(alignment: .leading, spacing: DisplayScale.points(20)) {
                    VStack(alignment: .leading, spacing: DisplayScale.points(6)) {
                        Text("Lumina Studio")
                            .font(.system(size: DisplayScale.points(22), weight: .bold))
                        Text("Version \(appVersion) (build \(buildNumber))")
                            .font(.system(size: DisplayScale.points(14), weight: .medium))
                            .foregroundStyle(themeManager.current.color)
                        Text("Native live wallpaper engine for macOS — free, fast, and battery-friendly.")
                            .font(.system(size: DisplayScale.points(12)))
                            .foregroundStyle(.secondary)
                    }

                    statusCard

                    sectionHeader("Getting Started")
                    entryList(LuminaChangelog.welcomeEntries)

                    sectionHeader("Changelog")
                    ForEach(LuminaChangelog.releases) { release in
                        VStack(alignment: .leading, spacing: DisplayScale.points(8)) {
                            Text("Version \(release.version)")
                                .font(.system(size: DisplayScale.points(14), weight: .semibold))
                                .foregroundStyle(release.version == appVersion ? themeManager.current.color : .primary)
                            entryList(release.entries)
                        }
                    }
                }
                .padding(.horizontal, DisplayScale.points(24))
                .padding(.vertical, DisplayScale.points(18))
            }
            .frame(maxHeight: .infinity)

            LuminaDivider()

            HStack(spacing: DisplayScale.points(10)) {
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
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, DisplayScale.points(24))
            .padding(.vertical, DisplayScale.points(14))
            .background(.bar)
        }
        .scaledFrame(width: 540, height: 620)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
    }

    // MARK: - Header

    private var brandHeader: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.16),
                    Color(red: 0.10, green: 0.07, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            CursiveLSView(
                lineWidth: DisplayScale.points(2.6),
                color: .white,
                animate: false,
                gradientColors: inkGradient,
                glowRadius: DisplayScale.points(5)
            )
            .scaledFrame(width: 120, height: 68)
        }
        .frame(height: DisplayScale.points(120))
        .clipped()
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(10)) {
            sectionHeader("Status")
            Text(statusSummary)
                .font(.system(size: DisplayScale.points(11), design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DisplayScale.points(12))
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous))
        }
        .padding(DisplayScale.points(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.luminaCard, in: RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                .strokeBorder(Color.luminaBorder, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: DisplayScale.points(15), weight: .bold))
            .padding(.top, DisplayScale.points(4))
    }

    @ViewBuilder
    private func entryList(_ entries: [ChangelogEntry]) -> some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(14)) {
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: DisplayScale.points(12)) {
                    Image(systemName: entry.icon)
                        .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                        .foregroundStyle(themeManager.current.color)
                        .frame(width: DisplayScale.points(26), alignment: .center)
                    VStack(alignment: .leading, spacing: DisplayScale.points(3)) {
                        Text(entry.title)
                            .font(.system(size: DisplayScale.points(13), weight: .semibold))
                        Text(entry.description)
                            .font(.system(size: DisplayScale.points(12)))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
