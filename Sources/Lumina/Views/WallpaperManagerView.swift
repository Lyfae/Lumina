import SwiftUI
import AppKit

/// The main view for Lumina's Wallpaper Manager.
/// Designed with clarity, visual hierarchy, and forgiveness in mind.
/// Suitable for both casual and power users.
struct WallpaperManagerView: View {
    @ObservedObject var store: WallpaperManagerStore
    
    // Selection state for side panel
    @State private var selectedMonitorID: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallpaper Manager")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Assign and customize wallpapers for each of your displays")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                Button("Refresh Displays") {
                    store.refreshDisplays()
                    selectedMonitorID = nil
                }
                .buttonStyle(.bordered)
            }
            
            // Persistence Toggle (as a clear config option)
            HStack {
                Toggle("Remember these assignments when Lumina starts", isOn: $store.persistAssignments)
                    .onChange(of: store.persistAssignments) { _, newValue in
                        store.savePersistencePreference(newValue)
                    }
                Spacer()
            }
            .padding(.vertical, 4)
            
            Divider()
            
            // Main Content: Spatial Layout + Side Panel
            HStack(spacing: 0) {
                
                // Left: Visual Physical Monitor Layout
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Physical Setup")
                        .font(.headline)
                    
                    let layout = store.getMonitorLayout()
                    
                    if layout.monitors.isEmpty {
                        ContentUnavailableView("No Displays Detected", systemImage: "display")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        MonitorLayoutView(layout: layout, selectedMonitorID: $selectedMonitorID)
                            .frame(maxWidth: .infinity)
                    }
                    
                    Text("Click a monitor to configure it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 420)
                .padding(.trailing, 16)
                
                Divider()
                
                // Right: Side Panel (Detail View)
                VStack {
                    if let selectedID = selectedMonitorID,
                       let monitor = store.monitors.first(where: { $0.id == selectedID }) {
                        
                        MonitorDetailPanel(
                            monitor: monitor,
                            store: store,
                            onClose: { selectedMonitorID = nil }
                        )
                    } else {
                        // Empty state for side panel
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "display")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Select a monitor")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Click on one of your displays on the left to assign a wallpaper and customize its settings.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 280)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 16)
            }
            
            Spacer(minLength: 12)
            
            // Footer
            HStack {
                Text("Lumina • Early Access")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}

// MARK: - Bento Style Monitor Card

struct MonitorBentoCard: View {
    let monitor: MonitorInfo
    let onChooseVideo: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(monitor.resolution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if monitor.isPrimary {
                    Text("Primary")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
            
            // Preview / Status Area
            Group {
                if let videoName = monitor.assignedVideoName {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(.secondary)
                        Text(videoName)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("No wallpaper assigned")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            
            // Actions
            HStack(spacing: 8) {
                Button("Choose Video") {
                    onChooseVideo()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                if monitor.assignedVideoName != nil {
                    Button("Clear", role: .destructive) {
                        onClear()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Spacer()
                
                // Future settings menu
                Menu {
                    Button("Scaling: Fill (Crop)") {}
                    Button("Scaling: Fit") {}
                    Button("Scaling: Stretch") {}
                    Divider()
                    Button("Crop...") {}
                    Button("Playback Speed...") {}
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}