import AppKit
import SwiftUI

/// Scales Lumina's fixed window and UI dimensions relative to the user's display.
/// Baseline: 15" MacBook logical resolution (1512×944 visible) — what the UI was tuned for.
@MainActor
enum DisplayScale {
    private static let designVisibleWidth: CGFloat = 1512
    private static let designVisibleHeight: CGFloat = 944

    /// Screen-relative scale (ignores user preference).
    static var displayFactor: CGFloat {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return 1 }
        let frame = screen.visibleFrame
        let w = frame.width / designVisibleWidth
        let h = frame.height / designVisibleHeight
        return min(max(min(w, h), 0.78), 1.28)
    }

    /// Display scale × user interface scale from Settings.
    static var factor: CGFloat {
        displayFactor * UIScaleManager.shared.multiplier
    }

    static func points(_ value: CGFloat) -> CGFloat { (value * factor).rounded() }

    static func size(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: points(width), height: points(height))
    }

    static func nsSize(width: CGFloat, height: CGFloat) -> NSSize {
        let s = size(width: width, height: height)
        return NSSize(width: s.width, height: s.height)
    }

    // MARK: - Windows

    static var managerWindowSize: NSSize { nsSize(width: 1240, height: 860) }
    static var managerWindowMinSize: NSSize { nsSize(width: 1080, height: 740) }
    static var physicalSetupWindowSize: NSSize { nsSize(width: 620, height: 420) }
    static var splashWindowSize: NSSize { nsSize(width: 360, height: 260) }
    /// Music widget is a fixed-size compact bar: art tile, waveform timeline, hover controls.
    static var musicWidgetSize: NSSize { nsSize(width: 288, height: 140) }

    // MARK: - Icons

    /// Template status-item size in points (macOS tints for the menu bar).
    static var menuBarIconSize: NSSize { nsSize(width: 22, height: 16) }

    static var menuBarIconLineWidth: CGFloat { points(1.5) }
}

extension View {
    /// Fixed frame scaled to the current display (design baseline × `DisplayScale.factor`).
    func scaledFrame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        frame(
            width: width.map { DisplayScale.points($0) },
            height: height.map { DisplayScale.points($0) },
            alignment: alignment
        )
    }

    func scaledMinFrame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        frame(
            minWidth: width.map { DisplayScale.points($0) },
            minHeight: height.map { DisplayScale.points($0) },
            alignment: alignment
        )
    }
}
