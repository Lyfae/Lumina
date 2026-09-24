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
    @State private var cardOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.96
    @State private var isDismissing = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ZStack {
            LuminaBrand.auroraBackground(animated: !reduceMotion)

            VStack(spacing: LuminaSpace.md) {
                CursiveLSView(
                    lineWidth: DisplayScale.points(3.0),
                    color: .white,
                    animate: !reduceMotion,
                    animationDuration: 1.8,
                    gradientColors: LuminaBrand.ink,
                    glowRadius: DisplayScale.points(6),
                    onDrawingComplete: { revealWordmarkAndScheduleDismiss() }
                )
                .padding(.top, LuminaSpace.tight)

                Text("Lumina Studio")
                    .font(.system(size: DisplayScale.points(20), weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .tracking(0.5)
                    .opacity(wordmarkVisible ? 1 : 0)
                    .offset(y: wordmarkVisible ? 0 : 8)
            }
            .padding(.horizontal, LuminaSpace.xxxl)
            .padding(.vertical, LuminaMetrics.heroPadding)
        }
        .scaledFrame(width: 360, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.floating, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.floating, style: .continuous)
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
        .contentShape(RoundedRectangle(cornerRadius: LuminaRadius.floating, style: .continuous))
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lumina is starting")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction(named: "Dismiss") { dismiss() }
        .onAppear { enter() }
    }

    // MARK: Lifecycle

    private func enter() {
        if reduceMotion {
            cardOpacity = 1
            cardScale = 1
            wordmarkVisible = true
            // Static card: shorter hold, then out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            return
        }

        withAnimation(.easeOut(duration: LuminaMotion.splashIn)) {
            cardOpacity = 1
            cardScale = 1
        }
    }

    private func revealWordmarkAndScheduleDismiss() {
        withAnimation(.easeOut(duration: 0.6)) {
            wordmarkVisible = true
        }
        // Hold long enough to read the wordmark, then leave.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(.easeIn(duration: LuminaMotion.splashOut)) {
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
