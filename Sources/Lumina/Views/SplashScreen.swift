import SwiftUI
import AppKit

// Lumina
// SplashScreen — the release launch experience.
//
// A borderless, floating card that appears briefly when Lumina starts:
//   1. Deep aurora background (slow-drifting color glows — the app's wallpaper identity)
//   2. The cursive LS monogram draws itself in with a gradient ink + soft glow
//   3. The wordmark fades in as the stroke completes
//   4. The card holds for a beat, then fades and scales away on its own
//
// Design constraints:
//   • Never steals focus (NSPanel + .nonactivatingPanel — Lumina is a menu-bar app)
//   • Click anywhere to dismiss immediately
//   • Honors Reduce Motion (no drawing/drift animation, quick static card)
//   • Fully torn down after dismissal — no lingering window, timers, or layers

// MARK: - Splash View

struct SplashScreenView: View {
    /// Called when the splash has fully faded out and the window can be closed.
    var onFinished: () -> Void

    @State private var wordmarkVisible = false
    @State private var auroraPhase = false
    @State private var cardOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.96
    @State private var isDismissing = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // Shared palette — echoes the "living wallpaper" identity.
    private let inkGradient: [Color] = [
        Color(red: 0.62, green: 0.87, blue: 1.0),   // ice blue
        Color(red: 0.72, green: 0.62, blue: 1.0),   // violet
        Color(red: 1.0,  green: 0.78, blue: 0.55)   // warm amber tail
    ]

    var body: some View {
        ZStack {
            background

            VStack(spacing: 14) {
                CursiveLSView(
                    lineWidth: DisplayScale.points(3.0),
                    color: .white,
                    animate: !reduceMotion,
                    animationDuration: 2.2,
                    gradientColors: inkGradient,
                    glowRadius: DisplayScale.points(6),
                    onDrawingComplete: { revealWordmarkAndScheduleDismiss() }
                )
                .padding(.top, DisplayScale.points(6))

                Text("Lumina Studio")
                    .font(.system(size: DisplayScale.points(20), weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .tracking(0.5)
                    .opacity(wordmarkVisible ? 1 : 0)
                    .offset(y: wordmarkVisible ? 0 : 8)
            }
            .padding(.horizontal, DisplayScale.points(32))
            .padding(.vertical, DisplayScale.points(28))
        }
        .scaledFrame(width: 360, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DisplayScale.points(18), style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { dismiss() }
        .onAppear { enter() }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            // Base: near-black with a hint of indigo so it reads richer than flat black.
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.09),
                    Color(red: 0.02, green: 0.02, blue: 0.04)
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Aurora glows — soft orbs sized for the compact card.
            auroraOrb(Color(red: 0.25, green: 0.45, blue: 0.95), opacity: 0.38, diameter: 300)
                .offset(x: auroraPhase ? -90 : -50, y: auroraPhase ? -70 : -100)

            auroraOrb(Color(red: 0.55, green: 0.30, blue: 0.85), opacity: 0.34, diameter: 280)
                .offset(x: auroraPhase ? 100 : 70, y: auroraPhase ? 80 : 110)

            // Fine vignette to focus the monogram.
            RadialGradient(
                colors: [.clear, .black.opacity(0.45)],
                center: .center, startRadius: 60, endRadius: 220
            )
        }
    }

    /// A soft-edged glow orb: fully colored at the center, fading to clear at the rim.
    private func auroraOrb(_ color: Color, opacity: Double, diameter: CGFloat) -> some View {
        RadialGradient(
            colors: [color.opacity(opacity), color.opacity(opacity * 0.5), .clear],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2
        )
        .frame(width: diameter, height: diameter)
    }

    // MARK: Lifecycle

    private func enter() {
        if reduceMotion {
            cardOpacity = 1
            cardScale = 1
            wordmarkVisible = true
            // Static card: shorter hold, then out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { dismiss() }
            return
        }

        withAnimation(.easeOut(duration: 0.45)) {
            cardOpacity = 1
            cardScale = 1
        }
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
            auroraPhase = true
        }
    }

    private func revealWordmarkAndScheduleDismiss() {
        withAnimation(.easeOut(duration: 0.6)) {
            wordmarkVisible = true
        }
        // Hold long enough to read the wordmark, then leave.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(.easeIn(duration: 0.45)) {
            cardOpacity = 0
            cardScale = 0.97
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onFinished() }
    }
}

// MARK: - Splash Window

/// Hosts the splash in a borderless, transparent, non-activating floating panel
/// centered on the main screen. Owns its own lifetime: create, call `show()`,
/// and it closes + releases itself when the splash finishes.
@MainActor
final class SplashWindowController {

    private var panel: NSPanel?
    private var onFinished: (() -> Void)?
    /// Keeps the controller alive while the splash is on screen (released on finish).
    private static var active: SplashWindowController?

    /// Shows the splash once. Safe to call from applicationDidFinishLaunching.
    /// - Parameter onFinished: Invoked after the splash tears down (auto or click-dismiss).
    static func present(onFinished: (() -> Void)? = nil) {
        guard active == nil else { return }
        let controller = SplashWindowController()
        controller.onFinished = onFinished
        active = controller
        controller.show()
    }

    private func show() {
        let size = DisplayScale.splashWindowSize

        // .nonactivatingPanel: the splash must never steal key focus — Lumina is a
        // menu-bar accessory app and the user may be mid-typing elsewhere at login.
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let splash = SplashScreenView { [weak self] in
            self?.finish()
        }
        panel.contentView = NSHostingView(rootView: splash)

        // Center on the main screen (slightly above true center — optically balanced).
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2 + frame.height * 0.06
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func finish() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        let callback = onFinished
        onFinished = nil
        Self.active = nil
        callback?()
    }
}
