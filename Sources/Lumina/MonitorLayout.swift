import AppKit

/// Provides information about the user's physical monitor arrangement.
/// Designed to power a visual layout in the Wallpaper Manager.
struct MonitorLayout {
    
    struct LayoutMonitor: Identifiable {
        let id: String
        let name: String
        let frame: CGRect          // Global coordinates
        let isPrimary: Bool
        let index: Int
    }
    
    let monitors: [LayoutMonitor]
    let boundingRect: CGRect       // The total bounding box of all monitors
    
    init() {
        let screens = NSScreen.screens
        
        var layoutMonitors: [LayoutMonitor] = []
        
        for (index, screen) in screens.enumerated() {
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            let isPrimary = screen == NSScreen.main
            
            let monitor = LayoutMonitor(
                id: MonitorInfo.identifier(for: screen, index: index),
                name: name,
                frame: screen.frame,
                isPrimary: isPrimary,
                index: index
            )
            layoutMonitors.append(monitor)
        }
        
        self.monitors = layoutMonitors
        
        // Calculate overall bounding rect for the visual layout
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for monitor in layoutMonitors {
            minX = min(minX, monitor.frame.minX)
            minY = min(minY, monitor.frame.minY)
            maxX = max(maxX, monitor.frame.maxX)
            maxY = max(maxY, monitor.frame.maxY)
        }
        
        self.boundingRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}