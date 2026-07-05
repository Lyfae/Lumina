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
            store.appDelegate?.powerManager?.setManagerWindowsActive(true)
            store.appDelegate?.applyPolicyToRenderers(.normal)
        }
    }
    
    @objc private func windowDidResignKey() {
        Task { @MainActor in
            // Only deactivate if Lumina Studio isn't still focused — otherwise unfocusing
            // this floating panel would let Max Battery throttling kick in mid-configuration.
            if self.managerWindow?.isKeyWindow != true {
                store.appDelegate?.powerManager?.setManagerWindowsActive(false)
            }
        }
    }
    
    private func selectWallpaperForMonitor(monitorID: String) {
        // Open a file picker for this specific monitor
        let panel = NSOpenPanel()
        panel.title = "Choose wallpaper for this display"
        panel.allowedContentTypes = [.movie, .image, .gif]
        panel.canChooseFiles = true
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = FileAccess.registerUserSelectedFile(url)
        
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

/// The actual SwiftUI content for the floating physical setup window.
private struct PhysicalSetupWindowView: View {
    @ObservedObject var store: WallpaperManagerStore
    @Binding var selectedMonitorID: String?
    
    var onSelectWallpaper: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Physical Setup")
                    .font(.title2.bold())
                
                Spacer()
                
                Button("Refresh") {
                    store.refreshDisplays()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Divider()
            
            // The actual spatial layout
            let layout = store.getMonitorLayout()
            
            if layout.monitors.isEmpty {
                ContentUnavailableView("No Displays Detected", systemImage: "display")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MonitorLayoutView(
                    layout: layout,
                    selectedMonitorID: $selectedMonitorID,
                    assignments: Dictionary(uniqueKeysWithValues: store.monitors.compactMap { info in
                        if let assignment = store.assignment(for: info.id) {
                            return (info.id, assignment)
                        }
                        return nil
                    })
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
            
            Divider()
            
            // Bottom action bar - clear selection + assign flow
            HStack(spacing: 12) {
                Text("Select a monitor above, then assign a wallpaper. The selection will sync back to the main manager for live configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button("Done") {
                    // Close this floating tool window
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.bordered)
                
                Button("Assign Wallpaper") {
                    if let id = selectedMonitorID {
                        onSelectWallpaper(id)
                    } else if let first = store.monitors.first {
                        onSelectWallpaper(first.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.monitors.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .scaledMinFrame(width: 520, height: 380)
    }
}
