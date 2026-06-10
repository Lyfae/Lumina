import AppKit
import SwiftUI

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

    @State private var selectedMonitorID: String? = nil   // Shared selection between windows

    init(appDelegate: LuminaApp) {
        self.appDelegate = appDelegate
        store.appDelegate = appDelegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Lumina Studio"
        // Adaptive: the user can freely resize the window; we only enforce a sensible floor
        // so the two-column layout never collapses. The chosen size persists across launches.
        window.contentMinSize = NSSize(width: 960, height: 720)
        window.center()
        window.setFrameAutosaveName("Lumina.WallpaperManager")

        super.init(window: window)
        
        // Host main SwiftUI view (now acts as a control hub)
        let rootView = WallpaperManagerView(store: store, selectedMonitorID: Binding(
            get: { self.selectedMonitorID },
            set: { self.selectedMonitorID = $0 }
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
                    get: { self.selectedMonitorID },
                    set: { self.selectedMonitorID = $0 }
                )
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
            let growth: CGFloat = 180
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
            window.setFrame(saved, display: true, animate: true)
            preCropWindowFrame = nil
        }
    }
}

// Notification name for opening the physical setup window
extension Notification.Name {
    static let togglePhysicalSetupWindow = Notification.Name("Lumina.TogglePhysicalSetupWindow")
    
    /// Posted by MonitorDetailPanel when the user toggles the crop editor.
    /// Used by the window controller to automatically grow the window if needed.
    static let cropEditorVisibilityChanged = Notification.Name("Lumina.CropEditorVisibilityChanged")
}