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
    static var musicWidgetSize: NSSize { musicWidgetSize(for: .regular) }

    /// Design points for one widget size. `baseHeight` is the real stack so the panel
    /// cannot open shorter than the art, the pet band, and the controls.
    struct MusicWidgetLayout {
        var width: CGFloat
        var baseHeight: CGFloat
        var sidePad: CGFloat
        var art: CGFloat
        var waveBand: CGFloat
        var controlsBand: CGFloat
        var play: CGFloat
        var volume: CGFloat
    }

    static func musicWidgetLayout(for size: MusicWidgetPreferences.Size) -> MusicWidgetLayout {
        let width: CGFloat
        let art: CGFloat
        let controls: CGFloat
        let side: CGFloat
        let play: CGFloat
        let volume: CGFloat
        switch size {
        case .compact:
            width = 248; art = 40; controls = 24; side = 10; play = 28; volume = 44
        case .regular:
            width = 288; art = 56; controls = 24; side = 12; play = 34; volume = 56
        case .expanded:
            width = 336; art = 72; controls = 28; side = 14; play = 40; volume = 72
        }
        let artPt = points(art)
        let controlsPt = points(controls)
        let wave = LuminaWaveformScrubber.footerBandHeight
        let height = LuminaSpace.md * 2 + artPt + LuminaSpace.xs + wave + controlsPt
        return MusicWidgetLayout(
            width: points(width),
            baseHeight: height,
            sidePad: points(side),
            art: artPt,
            waveBand: wave,
            controlsBand: controlsPt,
            play: points(play),
            volume: points(volume)
        )
    }

    static func musicWidgetSize(for size: MusicWidgetPreferences.Size) -> NSSize {
        let layout = musicWidgetLayout(for: size)
        return NSSize(width: layout.width, height: layout.baseHeight)
    }

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
