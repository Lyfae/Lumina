import AppKit
import SwiftUI

/// Hosts the SwiftUI-based Wallpaper Manager view.
final class WallpaperManagerWindowController: NSWindowController {
    
    private let store = WallpaperManagerStore()
    
    init(appDelegate: LuminaApp) {
        store.appDelegate = appDelegate
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Lumina – Wallpaper Manager"
        window.center()
        window.setFrameAutosaveName("Lumina.WallpaperManager")
        
        super.init(window: window)
        
        // Host SwiftUI view
        let hostingView = NSHostingView(rootView: WallpaperManagerView(store: store))
        window.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func refresh() {
        store.refreshDisplays()
    }
}