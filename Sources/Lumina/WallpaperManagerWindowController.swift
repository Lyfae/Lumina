import AppKit
import SwiftUI
import QuartzCore

/// Hosts the SwiftUI-based Wallpaper Manager view.
/// Also manages the separate floating Physical Setup window.
final class WallpaperManagerWindowController: NSWindowController {

    private let store = WallpaperManagerStore()
    private var physicalSetupWindow: PhysicalSetupWindowController?
    private weak var appDelegate: LuminaApp?

    /// Floating now-playing mini-player shown while the Studio window is minimized
    /// (when the user has enabled "Show music widget when minimized").
    private var musicWidget: NowPlayingWidgetController?

    /// Window frame snapshot taken when crop mode opens — restored on close even if growth was clamped.
    private var preCropWindowFrame: NSRect?

    /// Width snapshot taken when the Config column opens — restored on close without touching height.
    private var preConfigWindowWidth: CGFloat?
    private var preConfigWindowOriginX: CGFloat?

    // Shared selection between windows. Plain stored property — @State is only valid inside
    // SwiftUI Views; on an NSWindowController it silently does nothing reactive.
    private var selectedMonitorID: String? = nil

    init(appDelegate: LuminaApp) {
        self.appDelegate = appDelegate
        store.appDelegate = appDelegate

        let defaultSize = DisplayScale.managerWindowSize
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Lumina Studio"
        window.contentMinSize = DisplayScale.managerWindowMinSize
        window.center()
        window.setFrameAutosaveName("Lumina.WallpaperManager")

        super.init(window: window)
        
        // Host main SwiftUI view (now acts as a control hub)
        // [weak self]: the window retains the hosting view, which retains this binding —
        // a strong capture would create a retain cycle keeping the controller alive forever.
        let rootView = WallpaperManagerView(store: store, selectedMonitorID: Binding(
            get: { [weak self] in self?.selectedMonitorID },
            set: { [weak self] in self?.selectedMonitorID = $0 }
        ))
        
        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView
        
        // Listen for request to toggle the physical setup window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePhysicalSetupWindow),
            name: .togglePhysicalSetupWindow,
            object: nil
        )
        
        // Listen for crop editor opening so we can grow the window automatically
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCropEditorVisibilityChanged),
            name: .cropEditorVisibilityChanged,
            object: nil
        )

        // Listen for Config column — grow width so the preview keeps its size
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigColumnVisibilityChanged),
            name: .configColumnVisibilityChanged,
            object: nil
        )
        
        // Tell PowerManager when our windows are active so it doesn't pause the wallpaper
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )

        // Pop the floating now-playing widget when the window is minimized (if enabled),
        // and dismiss it again when the window is restored.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillMiniaturize),
            name: NSWindow.willMiniaturizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidDeminiaturize),
            name: NSWindow.didDeminiaturizeNotification,
            object: window
        )
    }

    // MARK: - Music widget on minimize

    @objc private func windowWillMiniaturize() {
        guard AmbientAudioManager.shared.showWidgetWhenMinimized else { return }
        if musicWidget == nil { musicWidget = NowPlayingWidgetController() }
        musicWidget?.show()
    }

    @objc private func windowDidDeminiaturize() {
        musicWidget?.hide()
    }

    @objc private func windowDidBecomeKey() {
        appDelegate?.powerManager?.setManagerWindowsActive(true)
        // Aggressively resume normal playback when user is in the manager
        appDelegate?.applyPolicyToRenderers(.normal)
    }
    
    @objc private func windowDidResignKey() {
        // Only turn off if the physical setup window is also not key
        if physicalSetupWindow?.window?.isKeyWindow != true {
            appDelegate?.powerManager?.setManagerWindowsActive(false)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // No need to notify power manager on deinit — app is shutting down.
    }
    
    @objc private func togglePhysicalSetupWindow() {
        if let existing = physicalSetupWindow {
            if existing.window?.isVisible == true {
                existing.window?.orderOut(nil)
            } else {
                existing.showWindow(nil)
            }
        } else {
            // Create new floating physical setup window
            let controller = PhysicalSetupWindowController(
                store: store,
                selectedMonitorID: Binding(
                    get: { [weak self] in self?.selectedMonitorID },
                    set: { [weak self] in self?.selectedMonitorID = $0 }
                ),
                managerWindow: self.window
            )
            self.physicalSetupWindow = controller
            controller.showWindow(nil)
        }
    }
    
    func refresh() {
        store.refreshDisplays()
    }
    
    /// Opens (or brings forward) the Choose Display window.
    /// Called automatically when the main manager is opened.
    func openChooseDisplayWindowIfNeeded() {
        if let existing = physicalSetupWindow {
            existing.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Create it if it doesn't exist yet
            togglePhysicalSetupWindow()
        }
    }
    
    @objc private func handleCropEditorVisibilityChanged(_ notification: Notification) {
        guard let isVisible = notification.userInfo?["visible"] as? Bool,
              let window = self.window else { return }

        if isVisible {
            if preCropWindowFrame == nil {
                preCropWindowFrame = window.frame
            }

            // Grow the window vertically to accommodate the crop editor (~180pt)
            let growth = DisplayScale.points(180)
            let currentFrame = window.frame
            let newHeight = currentFrame.height + growth

            // Don't grow beyond 85% of the main screen height
            let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) * 0.85
            let targetHeight = min(newHeight, maxHeight)

            if targetHeight > currentFrame.height {
                var newFrame = currentFrame
                newFrame.size.height = targetHeight
                // Keep the top of the window in the same place (grow downward)
                newFrame.origin.y = currentFrame.maxY - targetHeight
                window.setFrame(newFrame, display: true, animate: true)
            }
        } else if let saved = preCropWindowFrame {
            // Restore height only — Config may have widened the window independently.
            var frame = window.frame
            let top = frame.maxY
            frame.size.height = saved.height
            frame.origin.y = top - saved.height
            window.setFrame(frame, display: true, animate: true)
            preCropWindowFrame = nil
        }
    }

    @objc private func handleConfigColumnVisibilityChanged(_ notification: Notification) {
        guard let isVisible = notification.userInfo?["visible"] as? Bool,
              let window = self.window else { return }

        let growth = (notification.userInfo?["width"] as? CGFloat) ?? DisplayScale.points(340)
        let duration = (notification.userInfo?["duration"] as? TimeInterval) ?? 0.42
        let animateWindow = (notification.userInfo?["animateWindow"] as? Bool) ?? true

        if isVisible {
            if preConfigWindowWidth == nil {
                preConfigWindowWidth = window.frame.width
                preConfigWindowOriginX = window.frame.origin.x
            }

            let screen = (window.screen ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
            var frame = window.frame
            let targetWidth = min(frame.width + growth, screen.width * 0.95)
            let delta = targetWidth - frame.width
            guard delta > 1 else { return }

            frame.size.width = targetWidth
            // Prefer growing to the right so the preview stays put; clamp if needed.
            if frame.maxX > screen.maxX {
                frame.origin.x = max(screen.minX, screen.maxX - frame.width)
            }

            // Open path grows the window first (often instantly) so SwiftUI can slide
            // Config into already-available space without squeezing the header.
            if animateWindow {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
                    ctx.allowsImplicitAnimation = true
                    window.animator().setFrame(frame, display: true)
                }
            } else {
                window.setFrame(frame, display: true)
            }
        } else if let savedWidth = preConfigWindowWidth {
            var frame = window.frame
            frame.size.width = savedWidth
            if let savedX = preConfigWindowOriginX {
                frame.origin.x = savedX
            }
            // Keep current height (crop may have changed it).
            // Close path: called only after the Config column has fully collapsed.
            if animateWindow {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                    ctx.allowsImplicitAnimation = true
                    window.animator().setFrame(frame, display: true)
                }
            } else {
                window.setFrame(frame, display: true)
            }
            preConfigWindowWidth = nil
            preConfigWindowOriginX = nil
        }
    }
}

// Notification name for opening the physical setup window
extension Notification.Name {
    static let togglePhysicalSetupWindow = Notification.Name("Lumina.TogglePhysicalSetupWindow")
    
    /// Posted by MonitorDetailPanel when the user toggles the crop editor.
    /// Used by the window controller to automatically grow the window if needed.
    static let cropEditorVisibilityChanged = Notification.Name("Lumina.CropEditorVisibilityChanged")

    /// Posted when the wallpaper Config column opens/closes — window grows wider so preview size stays.
    static let configColumnVisibilityChanged = Notification.Name("Lumina.ConfigColumnVisibilityChanged")
}