import SwiftUI

/// First-run welcome shown once when the user opens Lumina Studio.
struct OnboardingView: View {
    var onContinue: () -> Void

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var mediaAccess = MediaAccessSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                heroBackground
                LuminaBrandMark(side: DisplayScale.points(72))
            }
            .frame(height: DisplayScale.points(120))
            .clipped()

            VStack(alignment: .leading, spacing: DisplayScale.points(18)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Lumina Studio")
                        .font(.title2.bold())
                    Text("Native live wallpapers for macOS — free, battery-aware, and per-display.")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.current.color)
                }
                .padding(.top, 4)

                LuminaDivider()

                ScrollView {
                    VStack(alignment: .leading, spacing: DisplayScale.points(14)) {
                        FeatureRow(
                            icon: "battery.100.bolt",
                            title: "Designed for Battery Life",
                            description: "Hardware-accelerated playback with smart pausing on battery, Low Power Mode, and thermal pressure."
                        )
                        FeatureRow(
                            icon: "slider.horizontal.3",
                            title: "You Stay in Control",
                            description: "Open Adjust for crop, speed, scaling, and effects — then Apply to Wallpaper when you're ready."
                        )
                        FeatureRow(
                            icon: "display.2",
                            title: "Every Display, Independently",
                            description: "Set different wallpapers per monitor, sync playback, or run slideshows with Ken Burns."
                        )

                        LuminaDivider()

                        MediaAccessLocationChecklist(settings: mediaAccess)
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: DisplayScale.points(340))

                Spacer(minLength: 8)

                HStack {
                    Spacer()
                    Button("Get Started") {
                        if !mediaAccess.enabledLocations.isEmpty {
                            onContinue()
                        }
                    }
                    .buttonStyle(LuminaProminentButtonStyle())
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(mediaAccess.enabledLocations.isEmpty)
                    .help(mediaAccess.enabledLocations.isEmpty
                          ? "Select at least one allowed folder"
                          : "Continue to Lumina Studio")
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .scaledFrame(width: 520, height: 640)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
    }

    @ViewBuilder
    private var heroBackground: some View {
        if colorScheme == .light {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 1.0),
                    Color(red: 0.90, green: 0.92, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.09, blue: 0.16),
                    Color(red: 0.06, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(themeManager.current.color)
                .scaledFrame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
