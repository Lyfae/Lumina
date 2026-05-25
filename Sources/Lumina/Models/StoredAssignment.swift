import Foundation

/// Lightweight struct for persisting monitor assignments.
struct StoredAssignment: Codable {
    let videoPath: String?          // Store path, resolve on load
    let scalingRaw: String
    let playbackSpeed: Double
    let isEnabled: Bool
    
    var scaling: VideoScaling {
        VideoScaling(rawValue: scalingRaw) ?? .fill
    }
}