import AppKit
import SwiftUI

/// A separate, movable, resizable window that shows the user's physical monitor layout.
/// This can be toggled from the main Wallpaper Manager.
final class PhysicalSetupWindowController: NSWindowController {
    
    private let store: WallpaperManagerStore
    @Binding private var selectedMonitorID: String?
    /// The Lumina Studio window — used to keep the "manager active" power state on while
    /// focus merely moves between our own configuration windows.
    private weak var managerWindow: NSWindow?
    
    init(store: WallpaperManagerStore, selectedMonitorID: Binding<String?>, managerWindow: NSWindow? = nil) {
        self.store = store
        self._selectedMonitorID = selectedMonitorID
        self.managerWindow = managerWindow
        
        let defaultSize = DisplayScale.physicalSetupWindowSize
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Choose Display"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .utilityWindow]
        window.level = .floating
        window.center()
        window.setFrameAutosaveName("Lumina.PhysicalSetup")
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        
        // Host the new "Choose Display" style view (matching Wallpaper Engine)
        let chooseDisplayView = ChooseDisplayView(
            store: store,
            selectedMonitorID: $selectedMonitorID,
            onChangeWallpaper: { [weak self] monitorID in
                self?.selectWallpaperForMonitor(monitorID: monitorID)
            },
            onRemoveWallpaper: { [weak self] monitorID in
                self?.removeWallpaperForMonitor(monitorID: monitorID)
            },
            onDone: { [weak self] in
                self?.window?.close()
            }
        )
        .environment(store.appDelegate?.preferencesStore)
        .environment(store.appDelegate?.playbackEngine)

        let hostingView = NSHostingView(rootView: chooseDisplayView)
        window.contentView = hostingView
        
        // Tell PowerManager we're active so the wallpaper keeps playing smoothly while configuring
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
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func windowDidBecomeKey() {
        Task { @MainActor in
            store.appDelegate?.playbackEngine?.setStudioVisible(true)
        }
    }
    
    @objc private func windowDidResignKey() {
        Task { @MainActor in
            if self.managerWindow?.isKeyWindow != true {
                store.appDelegate?.playbackEngine?.setStudioVisible(false)
            }
        }
    }
    
    private func selectWallpaperForMonitor(monitorID: String) {
        // Open a file picker for this specific monitor
        guard let url = MediaAccessPolicy.runWallpaperPicker(
            title: "Choose wallpaper for this display",
            message: "Select a video, GIF, or image for this monitor."
        ).first else { return }

        // Assign via the store
        store.chooseVideoForMonitorID(monitorID: monitorID, url: url)
        
        // Update selection in both the shared binding and the store (single source for manager config)
        selectedMonitorID = monitorID
        store.selectedMonitorID = monitorID
    }
    
    private func removeWallpaperForMonitor(monitorID: String) {
        store.clearAssignmentForMonitorID(monitorID: monitorID)
        // Keep selection so user can immediately assign something else
    }
}
