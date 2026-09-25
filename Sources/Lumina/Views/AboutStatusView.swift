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
                VStack(alignment: .leading, spacing: LuminaSpace.xl) {
                    VStack(alignment: .leading, spacing: LuminaSpace.tight) {
                        Text("Lumina Studio")
                            .font(uiScale.font(.title).weight(.bold))
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(uiScale.font(.callout).weight(.medium))
                            .foregroundStyle(themeManager.current.color)
                        Text("Native live wallpaper engine for macOS — free, fast, and battery-friendly.")
                            .font(uiScale.font(.caption))
                            .foregroundStyle(.secondary)
                    }

                    statusCard

                    sectionHeader("Getting Started")
                    entryList(LuminaChangelog.welcomeEntries)

                    sectionHeader("Changelog")
                    ForEach(LuminaChangelog.releases) { release in
                        VStack(alignment: .leading, spacing: LuminaSpace.sm) {
                            Text("Version \(release.version)")
                                .font(uiScale.font(.callout).weight(.semibold))
                                .foregroundStyle(release.version == appVersion ? themeManager.current.color : .primary)
                            entryList(release.entries)
                        }
                    }
                }
                .padding(.horizontal, LuminaSpace.xxl)
                .padding(.vertical, LuminaSpace.lg)
            }
            .frame(maxHeight: .infinity)

            LuminaDivider()

            HStack(spacing: LuminaSpace.md) {
                Button("Print Debug") { onPrintDebug() }
                    .buttonStyle(LuminaSecondaryButtonStyle())
                    .controlSize(uiScale.controlSize())
                Button("Testing Guide") { onOpenTestingGuide() }
                    .buttonStyle(LuminaSecondaryButtonStyle())
                    .controlSize(uiScale.controlSize())
                Button("Releases") {
                    if let url = URL(string: "https://github.com/Lyfae/Lumina/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .controlSize(uiScale.controlSize())

                Spacer()

                Button("Close") { onClose() }
                    .buttonStyle(LuminaProminentButtonStyle())
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, LuminaSpace.xxl)
            .padding(.vertical, LuminaSpace.barPaddingV)
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
        VStack(alignment: .leading, spacing: LuminaSpace.md) {
            sectionHeader("Status")
            Text(statusSummary)
                .font(uiScale.font(.caption).monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LuminaSpace.md)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                )
        }
        .padding(LuminaSpace.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.luminaCard,
            in: RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                .strokeBorder(Color.luminaBorder, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(uiScale.font(.headline))
            .padding(.top, LuminaSpace.xs)
    }

    @ViewBuilder
    private func entryList(_ entries: [ChangelogEntry]) -> some View {
        VStack(alignment: .leading, spacing: LuminaSpace.lg) {
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: LuminaSpace.md) {
                    Image(systemName: entry.icon)
                        .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                        .foregroundStyle(themeManager.current.color)
                        .frame(width: DisplayScale.points(26), alignment: .center)
                    VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                        Text(entry.title)
                            .font(uiScale.font(.callout).weight(.semibold))
                        Text(entry.description)
                            .font(uiScale.font(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
