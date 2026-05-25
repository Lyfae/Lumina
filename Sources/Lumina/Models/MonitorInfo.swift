import Foundation
import AppKit

/// Represents a connected display/monitor in the UI.
public struct MonitorInfo: Identifiable, Equatable {
    public let id: String              // Stable-ish identifier
    public let name: String
    public let resolution: String
    public let isPrimary: Bool
    
    // Current assignment (for UI state)
    public var assignedVideoName: String?
    
    public init(id: String, name: String, resolution: String, isPrimary: Bool, assignedVideoName: String? = nil) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.isPrimary = isPrimary
        self.assignedVideoName = assignedVideoName
    }
}

/// Helper to generate a reasonably stable monitor identifier.
extension MonitorInfo {
    static func identifier(for screen: NSScreen, index: Int) -> String {
        let name = screen.localizedName.isEmpty ? "Display-\(index)" : screen.localizedName
        let res = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
        return "\(name)-\(res)"
    }
}