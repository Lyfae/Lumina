import SwiftUI
import AppKit

// MARK: - Text styles

enum LuminaTextStyle {
    case micro, caption, callout, body, bodyStrong, headline, title, largeTitle
}

// MARK: - Spacing (4-pt grid)

@MainActor
enum LuminaSpace {
    static var hair: CGFloat { DisplayScale.points(2) }
    static var xs: CGFloat { DisplayScale.points(4) }
    static var tight: CGFloat { DisplayScale.points(6) }
    static var sm: CGFloat { DisplayScale.points(8) }
    static var md: CGFloat { DisplayScale.points(12) }
    static var lg: CGFloat { DisplayScale.points(16) }
    static var xl: CGFloat { DisplayScale.points(20) }
    static var xxl: CGFloat { DisplayScale.points(24) }
    static var xxxl: CGFloat { DisplayScale.points(32) }

    static var cardPadding: CGFloat {
        switch LuminaLook.shared.density {
        case .tight: return DisplayScale.points(10)
        case .regular: return DisplayScale.points(12)
        case .airy: return DisplayScale.points(16)
        }
    }

    static var cardGap: CGFloat {
        switch LuminaLook.shared.density {
        case .tight: return DisplayScale.points(8)
        case .regular: return DisplayScale.points(12)
        case .airy: return DisplayScale.points(16)
        }
    }

    static var gridGap: CGFloat {
        switch LuminaLook.shared.density {
        case .tight: return DisplayScale.points(12)
        case .regular: return DisplayScale.points(16)
        case .airy: return DisplayScale.points(20)
        }
    }

    static var rowHeight: CGFloat {
        switch LuminaLook.shared.density {
        case .tight: return DisplayScale.points(32)
        case .regular: return DisplayScale.points(36)
        case .airy: return DisplayScale.points(40)
        }
    }

    static var barPaddingV: CGFloat {
        switch LuminaLook.shared.density {
        case .tight: return DisplayScale.points(8)
        case .regular: return DisplayScale.points(10)
        case .airy: return DisplayScale.points(14)
        }
    }

    /// Chip padding horizontal / vertical (10×6).
    static var chipPaddingH: CGFloat { DisplayScale.points(10) }
    static var chipPaddingV: CGFloat { DisplayScale.points(6) }
    /// Overlay chip padding (10×5).
    static var overlayChipPaddingH: CGFloat { DisplayScale.points(10) }
    static var overlayChipPaddingV: CGFloat { DisplayScale.points(5) }
    /// Status pill padding (8×3).
    static var statusPillPaddingH: CGFloat { DisplayScale.points(8) }
    static var statusPillPaddingV: CGFloat { DisplayScale.points(3) }
}

// MARK: - Radii (continuous, scaled)

@MainActor
enum LuminaRadius {
    static var badge: CGFloat { DisplayScale.points(4) }
    static var small: CGFloat { DisplayScale.points(6) }
    static var control: CGFloat { DisplayScale.points(8) }
    static var panel: CGFloat { DisplayScale.points(10) }
    static var card: CGFloat { DisplayScale.points(12) }
    static var widget: CGFloat { DisplayScale.points(14) }
    static var floating: CGFloat { DisplayScale.points(18) }
}

// MARK: - Type scale entry (via UIScaleManager)

@MainActor
enum LuminaFont {
    static func font(_ style: LuminaTextStyle) -> Font {
        UIScaleManager.shared.font(style)
    }
}

// MARK: - Status colors

enum LuminaStatusColor {
    static let playing = Color(nsColor: .systemGreen)
    static let paused = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)
    static let off = Color(nsColor: .systemGray)
    static let star = Color(nsColor: .systemYellow)
}

// MARK: - Motion

@MainActor
enum LuminaMotion {
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var pressScale: CGFloat { reduceMotion ? 1 : 0.96 }

    static var press: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.10)
    }

    static var hover: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    static var state: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.15)
    }

    static var reveal: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.20)
    }

    static var panel: Animation? {
        reduceMotion ? nil : .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.35)
    }

    static var adjustOpen: Animation? {
        reduceMotion ? nil : .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.42)
    }

    static var adjustClose: Animation? {
        reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.55)
    }

    /// Window resize duration paired with `adjustClose` (not an Animation token).
    static var adjustCloseWindow: TimeInterval { reduceMotion ? 0 : 0.40 }

    static var meter: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.07)
    }

    static var splashIn: Double { 0.45 }
    static var splashOut: Double { 0.45 }

    static func animate(_ animation: Animation?, _ body: () -> Void) {
        if let animation {
            withAnimation(animation, body)
        } else {
            body()
        }
    }
}

// MARK: - Shadow

@MainActor
enum LuminaShadow {
    static var floating: (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(0.35), DisplayScale.points(12), DisplayScale.points(8))
    }
}

// MARK: - Named component metrics

@MainActor
enum LuminaMetrics {
    static var sliderHeightCompact: CGFloat { DisplayScale.points(18) }
    static var sliderHeight: CGFloat { DisplayScale.points(24) }
    static var iconColumn: CGFloat { DisplayScale.points(16) }
    static var brandMark: CGFloat { DisplayScale.points(36) }
    static var emptyStateTextWidth: CGFloat { DisplayScale.points(280) }
    static var emptyStateMinHeight: CGFloat { DisplayScale.points(240) }
    static var footerTitleMin: CGFloat { DisplayScale.points(120) }
    static var footerTitleIdeal: CGFloat { DisplayScale.points(170) }
    static var footerTitleMax: CGFloat { DisplayScale.points(220) }
    static var footerPlay: CGFloat { DisplayScale.points(28) }
    static var footerVolumeWidth: CGFloat { DisplayScale.points(88) }
    static var queueRow: CGFloat { DisplayScale.points(48) }
    static var queuePanelMax: CGFloat { DisplayScale.points(240) }
    static var thumbLabelHeight: CGFloat { DisplayScale.points(20) }
    static var adjustColumnWidth: CGFloat { DisplayScale.points(340) }
    static var libraryStripHeight: CGFloat { DisplayScale.points(72) }
    static var displayCardThumbHeight: CGFloat { DisplayScale.points(160) }
    static var upNextLabel: CGFloat { DisplayScale.points(12) }
    static var heroPadding: CGFloat { DisplayScale.points(28) }
    static var updateIcon: CGFloat { DisplayScale.points(48) }
    static var cropGridOpacity: Double { 0.35 }
    static var waveformBarWidth: CGFloat { DisplayScale.points(2) }
    static var waveformBarGap: CGFloat { DisplayScale.points(2) }
    static var waveformFooterBand: CGFloat { DisplayScale.points(40) }
    static var waveformThumb: CGFloat { DisplayScale.points(12) }
    static var timeLabelWidth: CGFloat { DisplayScale.points(38) }
    static var cornerPickerScreen: CGSize {
        CGSize(width: DisplayScale.points(56), height: DisplayScale.points(38))
    }
    static var cornerPickerHit: CGSize {
        CGSize(width: DisplayScale.points(16), height: DisplayScale.points(10))
    }
}

// MARK: - Brand

@MainActor
enum LuminaBrand {
    static let ink: [Color] = [
        Color(red: 0.62, green: 0.87, blue: 1.0),
        Color(red: 0.72, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.78, blue: 0.55),
    ]

    static var auroraBlue: Color { Color(red: 0.25, green: 0.45, blue: 0.95) }
    static var auroraViolet: Color { Color(red: 0.55, green: 0.30, blue: 0.85) }

    static var night: [Color] {
        [Color(red: 0.04, green: 0.04, blue: 0.09), Color(red: 0.02, green: 0.02, blue: 0.04)]
    }

    static var heroDark: [Color] {
        [Color(red: 0.10, green: 0.09, blue: 0.16), Color(red: 0.06, green: 0.07, blue: 0.12)]
    }

    static var heroLight: [Color] {
        [Color(red: 0.96, green: 0.97, blue: 1.0), Color(red: 0.90, green: 0.92, blue: 0.99)]
    }

    static var tileDark: [Color] {
        [Color(red: 0.16, green: 0.14, blue: 0.24), Color(red: 0.10, green: 0.09, blue: 0.16)]
    }

    static var previewBackdrop: Color { Color.black.opacity(0.85) }

    static func auroraBackground(animated: Bool) -> some View {
        LuminaAuroraBackground(animated: animated)
    }
}

@MainActor
private struct LuminaAuroraBackground: View {
    var animated: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(
                    colors: LuminaBrand.night,
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(LuminaBrand.auroraBlue.opacity(0.55))
                    .frame(width: DisplayScale.points(300), height: DisplayScale.points(300))
                    .blur(radius: DisplayScale.points(60))
                    .offset(
                        x: -w * 0.25 + (animated ? phase * 12 : 0),
                        y: -h * 0.2 + (animated ? phase * 8 : 0)
                    )

                Circle()
                    .fill(LuminaBrand.auroraViolet.opacity(0.5))
                    .frame(width: DisplayScale.points(280), height: DisplayScale.points(280))
                    .blur(radius: DisplayScale.points(55))
                    .offset(
                        x: w * 0.28 - (animated ? phase * 10 : 0),
                        y: h * 0.15 - (animated ? phase * 6 : 0)
                    )

                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    center: .center,
                    startRadius: DisplayScale.points(60),
                    endRadius: DisplayScale.points(220)
                )
            }
            .frame(width: w, height: h)
        }
        .onAppear {
            guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}
