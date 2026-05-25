import SwiftUI
import AppKit

/// Side panel that appears when a user selects a monitor in the layout.
/// Contains live preview + all per-monitor settings.
struct MonitorDetailPanel: View {
    let monitor: MonitorInfo
    @ObservedObject var store: WallpaperManagerStore
    
    var onClose: () -> Void
    
    // Local state for settings (synced with store)
    @State private var selectedScaling: VideoScaling = .fill
    @State private var keepOnStartup: Bool = false
    @State private var playbackSpeed: Double = 1.0
    
    // Note: We currently get assignment data via the monitor model or by asking the app delegate.
    // The previous computed property was removed because WallpaperManagerStore does not yet expose assignment(for:).
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header with close button
            HStack {
                VStack(alignment: .leading) {
                    Text(monitor.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(monitor.resolution)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Live Preview Area (Placeholder for now)
            VStack(alignment: .leading, spacing: 8) {
                Text("Live Preview")
                    .font(.headline)
                
                // This is where a real live preview of the wallpaper would go.
                // For now it shows a visual representation of what would be on screen.
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.9))
                        .frame(height: 220)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    
                    if let videoName = monitor.assignedVideoName {
                        VStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 42))
                            Text("Live Preview")
                                .font(.headline)
                            Text(videoName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.white)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "display")
                                .font(.system(size: 42))
                            Text("No wallpaper assigned")
                                .font(.headline)
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            
            Divider()
            
            // Settings
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings for this Display")
                    .font(.headline)
                
                // Scaling
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scaling Mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Picker("Scaling", selection: $selectedScaling) {
                        ForEach(VideoScaling.allCases, id: \.self) { scaling in
                            Text(scaling.displayName).tag(scaling)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Playback Speed
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Playback Speed")
                        Spacer()
                        Text(String(format: "%.2fx", playbackSpeed))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    
                    Slider(value: $playbackSpeed, in: 0.25...4.0, step: 0.25)
                }
                
                // Keep on Startup (wired to store)
                Toggle(isOn: $keepOnStartup) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep this wallpaper on startup")
                        Text("This monitor will automatically restore this video and its settings when Lumina launches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: keepOnStartup) { _, newValue in
                    store.setKeepOnStartup(for: monitor, enabled: newValue)
                }
                
                // Crop (Coming in next iteration)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Crop / Zoom")
                        Spacer()
                        Button("Edit Crop…") {
                            // Will open a draggable crop rectangle editor with live preview
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    
                    Text("Select which part of the media to show on this screen (drag-to-crop coming soon).")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Bottom Actions
            HStack {
                Button("Choose Different Media…") {
                    store.chooseVideo(for: monitor)
                }
                .buttonStyle(.borderedProminent)
                
                if monitor.assignedVideoName != nil {
                    Button("Clear Wallpaper", role: .destructive) {
                        store.clearAssignment(for: monitor)
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                Button("Done") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear {
            loadCurrentValues()
        }
        .onChange(of: monitor.id) { _, _ in
            loadCurrentValues()
        }
    }
    
    private func loadCurrentValues() {
        if let assignment = store.assignment(for: monitor.id) {
            selectedScaling = assignment.scaling
            keepOnStartup = assignment.keepOnStartup
            playbackSpeed = assignment.playbackSpeed
        } else {
            // Defaults for new assignments
            selectedScaling = .fill
            keepOnStartup = true
            playbackSpeed = 1.0
        }
    }
}

extension VideoScaling {
    var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill (Crop)"
        case .stretch: return "Stretch"
        }
    }
}