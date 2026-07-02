import Foundation
import AppKit
import CoreGraphics

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
    
    /// Approximate aspect ratio (width / height) parsed from the resolution string.
    /// Falls back to 16:9. Used for preview containers and crop locking.
    public var aspectRatio: CGFloat {
        let components = resolution.split(separator: "x")
        guard components.count == 2,
              let w = Double(components[0]),
              let h = Double(components[1]),
              h > 0 else {
            return 16.0 / 9.0
        }
        return CGFloat(w / h)
    }
}

/// Helper to generate a reasonably stable monitor identifier.
extension MonitorInfo {
    static func identifier(for screen: NSScreen, index: Int) -> String {
        let name = screen.localizedName.isEmpty ? "Display-\(index)" : screen.localizedName
        // Key on the display's persistent UUID when available. Resolution is deliberately
        // NOT part of the identifier: it changes with scaling/resolution switches, which
        // orphaned saved assignments (pinned wallpapers came back black).
        if let uuid = persistentUUID(for: screen) {
            let suffix = String(uuid.prefix(8))
            return "\(name)-\(suffix)"
        }
        let res = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
        return "\(name)-\(res)"
    }

    /// The identifier format used by older builds (resolution baked in). Used only to
    /// migrate previously saved assignments to the resolution-independent key.
    static func legacyIdentifier(for screen: NSScreen, index: Int) -> String {
        let name = screen.localizedName.isEmpty ? "Display-\(index)" : screen.localizedName
        let res = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
        if let uuid = persistentUUID(for: screen) {
            let suffix = String(uuid.prefix(8))
            return "\(name)-\(res)-\(suffix)"
        }
        return "\(name)-\(res)"
    }

    /// The live Core Graphics display ID for a screen. Valid only for the current
    /// session/configuration — use it to reconcile windows/renderers across display changes,
    /// not for persistence.
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// A UUID that is stable across reboots and reconnects for the same physical display.
    /// Returns nil if the system can't provide one (e.g. some virtual displays).
    static func persistentUUID(for screen: NSScreen) -> String? {
        let displayID = displayID(for: screen)
        guard displayID != 0,
              let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuidRef) as String
    }
}