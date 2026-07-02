import SwiftUI

/// Animated cursive "LS" logo using the original path from the zip animation.
/// Progressive stroke drawing (the old splash style the user wants), with optional
/// gradient ink and glow for the release splash.
struct CursiveLSView: View {
    var lineWidth: CGFloat = 3.0
    var color: Color = .white
    var animate: Bool = true
    var animationDuration: Double = 2.4
    /// When set, the stroke is drawn with this gradient instead of the flat `color`.
    var gradientColors: [Color]? = nil
    /// Soft glow radius behind the stroke (0 = none).
    var glowRadius: CGFloat = 0
    /// Called once, after the progressive drawing finishes.
    var onDrawingComplete: (() -> Void)? = nil

    @State private var trimEnd: CGFloat = 0
    @State private var hasAnimated = false

    private let lsPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 65, y: 108))
        path.addCurve(to: CGPoint(x: 137, y: 80), control1: CGPoint(x: 92, y: 100), control2: CGPoint(x: 118, y: 88))
        path.addCurve(to: CGPoint(x: 148, y: 44), control1: CGPoint(x: 139, y: 70), control2: CGPoint(x: 141, y: 52))
        path.addCurve(to: CGPoint(x: 168, y: 52), control1: CGPoint(x: 155, y: 36), control2: CGPoint(x: 168, y: 39))
        path.addCurve(to: CGPoint(x: 145, y: 79), control1: CGPoint(x: 168, y: 65), control2: CGPoint(x: 157, y: 75))
        path.addCurve(to: CGPoint(x: 142, y: 135), control1: CGPoint(x: 143, y: 87), control2: CGPoint(x: 142, y: 110))
        path.addCurve(to: CGPoint(x: 142, y: 184), control1: CGPoint(x: 142, y: 158), control2: CGPoint(x: 142, y: 172))
        path.addCurve(to: CGPoint(x: 118, y: 212), control1: CGPoint(x: 142, y: 196), control2: CGPoint(x: 132, y: 207))
        path.addCurve(to: CGPoint(x: 108, y: 247), control1: CGPoint(x: 104, y: 218), control2: CGPoint(x: 97, y: 235))
        path.addCurve(to: CGPoint(x: 146, y: 244), control1: CGPoint(x: 119, y: 257), control2: CGPoint(x: 136, y: 254))
        path.addCurve(to: CGPoint(x: 148, y: 208), control1: CGPoint(x: 156, y: 234), control2: CGPoint(x: 156, y: 216))
        path.addCurve(to: CGPoint(x: 302, y: 94), control1: CGPoint(x: 168, y: 188), control2: CGPoint(x: 272, y: 118))
        path.addCurve(to: CGPoint(x: 342, y: 90), control1: CGPoint(x: 315, y: 78), control2: CGPoint(x: 338, y: 74))
        path.addCurve(to: CGPoint(x: 314, y: 130), control1: CGPoint(x: 346, y: 108), control2: CGPoint(x: 332, y: 126))
        path.addCurve(to: CGPoint(x: 258, y: 145), control1: CGPoint(x: 294, y: 134), control2: CGPoint(x: 272, y: 132))
        path.addCurve(to: CGPoint(x: 252, y: 185), control1: CGPoint(x: 243, y: 158), control2: CGPoint(x: 241, y: 173))
        path.addCurve(to: CGPoint(x: 302, y: 222), control1: CGPoint(x: 264, y: 198), control2: CGPoint(x: 288, y: 204))
        path.addCurve(to: CGPoint(x: 298, y: 282), control1: CGPoint(x: 318, y: 242), control2: CGPoint(x: 315, y: 268))
        path.addCurve(to: CGPoint(x: 233, y: 289), control1: CGPoint(x: 280, y: 296), control2: CGPoint(x: 253, y: 299))
        path.addCurve(to: CGPoint(x: 215, y: 241), control1: CGPoint(x: 213, y: 279), control2: CGPoint(x: 207, y: 258))
        path.addCurve(to: CGPoint(x: 256, y: 225), control1: CGPoint(x: 223, y: 225), control2: CGPoint(x: 242, y: 219))
        return path
    }()

    var body: some View {
        // Natural bounds from the original zip path
        let naturalBounds = CGRect(x: 65, y: 44, width: 277, height: 245)
        let targetSize = CGSize(width: 160, height: 92)

        let scale = min(
            targetSize.width / naturalBounds.width,
            targetSize.height / naturalBounds.height
        )

        let scaledSize = CGSize(width: naturalBounds.width * scale, height: naturalBounds.height * scale)
        let offsetX = (targetSize.width - scaledSize.width) / 2 - naturalBounds.minX * scale
        let offsetY = (targetSize.height - scaledSize.height) / 2 - naturalBounds.minY * scale

        strokedPath
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: offsetX, y: offsetY)
            .frame(width: targetSize.width, height: targetSize.height)
            .onAppear {
                // Only animate the first appearance — re-appearing (window re-shown,
                // parent re-rendered) should not replay the full drawing.
                guard !hasAnimated else {
                    trimEnd = 1.0
                    return
                }
                hasAnimated = true
                if animate {
                    trimEnd = 0
                    withAnimation(.easeInOut(duration: animationDuration)) {
                        trimEnd = 1.0
                    }
                    if let onDrawingComplete {
                        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                            onDrawingComplete()
                        }
                    }
                } else {
                    trimEnd = 1.0
                    onDrawingComplete?()
                }
            }
    }

    @ViewBuilder
    private var strokedPath: some View {
        let trimmed = lsPath.trim(from: 0, to: trimEnd)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        if let gradientColors {
            trimmed
                .stroke(
                    LinearGradient(colors: gradientColors,
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: style
                )
                .shadow(color: (gradientColors.first ?? color).opacity(glowRadius > 0 ? 0.8 : 0),
                        radius: glowRadius)
        } else {
            trimmed
                .stroke(color, style: style)
                .shadow(color: color.opacity(glowRadius > 0 ? 0.8 : 0), radius: glowRadius)
        }
    }
}

/// Splash using the old zip-based animated cursive LS (progressive drawing).
/// Transparent background + "Lumina Studio" text. Kept for inline/legacy use;
/// the release launch experience is `SplashScreenView` (see SplashScreen.swift).
struct CursiveLSLoadingSplash: View {
    var body: some View {
        VStack(spacing: 6) {
            CursiveLSView(
                lineWidth: 3.0,
                color: .white,
                animate: true,
                animationDuration: 2.4
            )

            Text("Lumina Studio")
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.95))
                .tracking(0.3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
