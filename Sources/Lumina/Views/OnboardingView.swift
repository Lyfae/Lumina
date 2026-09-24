import SwiftUI

/// First-run welcome shown once when the user opens Lumina Studio.
struct OnboardingView: View {
    var onContinue: () -> Void

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var mediaAccess = MediaAccessSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var canContinue: Bool { !mediaAccess.enabledLocations.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LuminaBrand.auroraBackground(animated: false)
                CursiveLSView(
                    lineWidth: DisplayScale.points(2.6),
                    color: .white,
                    animate: false,
                    gradientColors: LuminaBrand.ink,
                    glowRadius: DisplayScale.points(5)
                )
                .scaledFrame(width: 120, height: 68)
            }
            .frame(height: DisplayScale.points(140))
            .clipped()

            VStack(alignment: .leading, spacing: DisplayScale.points(18)) {
                VStack(alignment: .leading, spacing: LuminaSpace.tight) {
                    Text("Welcome to Lumina")
                        .font(LuminaFont.font(.largeTitle))
                    Text("Live wallpapers for every display, easy on your battery.")
                        .font(LuminaFont.font(.body))
                        .foregroundStyle(themeManager.current.text(in: colorScheme))
                }
                .padding(.top, LuminaSpace.xs)

                LuminaDivider()

                ScrollView {
                    VStack(alignment: .leading, spacing: LuminaSpace.md) {
                        FeatureRow(
                            icon: "battery.100.bolt",
                            title: "Easy on battery",
                            description: "Pauses on battery, in Low Power Mode, or when your Mac gets hot. You choose the rules."
                        )
                        FeatureRow(
                            icon: "slider.horizontal.3",
                            title: "Preview first",
                            description: "Crop and tune a wallpaper in Adjust. Your desktop changes when you click Apply."
                        )
                        FeatureRow(
                            icon: "display.2",
                            title: "One wallpaper per display",
                            description: "Give each display its own video, image, or slideshow."
                        )

                        LuminaDivider()

                        MediaAccessLocationChecklist(settings: mediaAccess)
                            .padding(LuminaSpace.cardPadding)
                            .luminaGlassPanel(cornerRadius: 12)
                    }
                    .padding(.vertical, LuminaSpace.xs)
                }
                .frame(maxHeight: DisplayScale.points(340))

                Spacer(minLength: LuminaSpace.sm)

                HStack(alignment: .center, spacing: LuminaSpace.md) {
                    if !canContinue {
                        Text("Pick at least one folder.")
                            .font(LuminaFont.font(.caption))
                            .foregroundStyle(LuminaStatusColor.paused)
                    }
                    Spacer(minLength: 0)
                    Button("Get Started") {
                        if canContinue {
                            onContinue()
                        }
                    }
                    .buttonStyle(LuminaProminentButtonStyle())
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
                }
            }
            .padding(.horizontal, LuminaSpace.xxl)
            .padding(.vertical, LuminaSpace.xxl)
        }
        .scaledFrame(width: 520, height: 640)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: LuminaSpace.md) {
            Image(systemName: icon)
                .font(.system(size: uiScale.iconSize(.card) + 3, weight: .semibold))
                .foregroundStyle(themeManager.current.color)
                .frame(width: DisplayScale.points(24), alignment: .center)

            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                Text(title)
                    .font(LuminaFont.font(.bodyStrong))
                Text(description)
                    .font(LuminaFont.font(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
