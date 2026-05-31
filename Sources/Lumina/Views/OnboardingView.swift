import SwiftUI

/// First-run / onboarding experience that educates users about power impact.
/// Includes a "Never show again" option so it doesn't annoy users on every launch.
struct OnboardingView: View {
    var onContinue: (Bool) -> Void   // Bool = should never show again

    @State private var neverShowAgain: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header image (same Grok Imagine asset used in What's New for brand consistency)
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
                // Title + subtitle (matching What's New visual treatment)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Lumina")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("A native, ultra-low-power live wallpaper engine for macOS.")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                }
                .padding(.top, 8)

                Divider()
                    .background(Color.white.opacity(0.15))

                // Education content in a ScrollView for consistency with What's New
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(
                            icon: "battery.100.bolt",
                            title: "Designed for Battery Life",
                            description: "Lumina uses hardware-accelerated playback and smart power management. It automatically pauses or throttles when you're on battery, in Low Power Mode, or under thermal pressure."
                        )

                        FeatureRow(
                            icon: "slider.horizontal.3",
                            title: "You Stay in Control",
                            description: "Use the Performance Profile menu in the menu bar to instantly switch between Maximum Battery Saving, Balanced, or High Quality modes."
                        )

                        FeatureRow(
                            icon: "info.circle",
                            title: "What to Expect",
                            description: "Beautiful video wallpapers with almost no impact on AC power. Automatic power saving on battery. Full per-monitor control with live crop, speed, and scaling. Completely free and open source."
                        )
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 260)

                Spacer(minLength: 8)

                // Footer actions (styled to match the What's New sheet)
                HStack(spacing: 12) {
                    Toggle("Don't show this again", isOn: $neverShowAgain)
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Done") {
                        onContinue(neverShowAgain)
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

/// Small reusable component for clean, modular feature rows.
private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
