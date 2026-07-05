import SwiftUI

/// First-run welcome shown once when the user opens Lumina Studio.
struct OnboardingView: View {
    var onContinue: () -> Void

    @StateObject private var themeManager = ThemeManager.shared

    private let inkGradient: [Color] = [
        Color(red: 0.62, green: 0.87, blue: 1.0),
        Color(red: 0.72, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.78, blue: 0.55)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Brand header — same cursive LS as splash/menu bar (no missing bundle image).
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
                    lineWidth: 2.6,
                    color: .white,
                    animate: false,
                    gradientColors: inkGradient,
                    glowRadius: 5
                )
                .scaledFrame(width: 120, height: 68)
            }
            .frame(height: DisplayScale.points(130))
            .clipped()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Lumina Studio")
                        .font(.title2.bold())
                    Text("Native live wallpapers for macOS — free, battery-aware, and per-display.")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.current.color)
                }
                .padding(.top, 8)

                LuminaDivider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(
                            icon: "battery.100.bolt",
                            title: "Designed for Battery Life",
                            description: "Hardware-accelerated playback with smart pausing on battery, Low Power Mode, and thermal pressure."
                        )
                        FeatureRow(
                            icon: "slider.horizontal.3",
                            title: "You Stay in Control",
                            description: "Preview crop, speed, scaling, and effects live — then Apply to Wallpaper when you're ready."
                        )
                        FeatureRow(
                            icon: "display.2",
                            title: "Every Display, Independently",
                            description: "Set different wallpapers per monitor, sync playback, or run slideshows with Ken Burns."
                        )
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: DisplayScale.points(260))

                Spacer(minLength: 8)

                HStack {
                    Spacer()
                    Button("Get Started") {
                        onContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .scaledFrame(width: 520, height: 560)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
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
