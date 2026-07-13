import SwiftUI
import AppKit
import Foundation

/// Visual representation of the user's physical monitor arrangement.
/// This gives users a clear sense of which physical screen they're configuring.
struct MonitorLayoutView: View {
    let layout: MonitorLayout
    @Binding var selectedMonitorID: String?
    /// Optional dictionary of current assignments so we can show real thumbnails inside the layout.
    var assignments: [String: MonitorAssignment] = [:]
    
    private let padding: CGFloat = 32   // More breathing room so nothing clips
    private let maxCanvasSize: CGFloat = 420
    
    var body: some View {
        GeometryReader { geometry in
            let canvasSize = min(maxCanvasSize, min(geometry.size.width - padding * 2, geometry.size.height - padding * 2))
            let scale = min(
                canvasSize / max(layout.boundingRect.width, 1),
                canvasSize / max(layout.boundingRect.height, 1)
            )
            
            ZStack {
                ForEach(layout.monitors) { monitor in
                    let rect = normalizedRect(for: monitor, scale: scale)
                    let isSelected = selectedMonitorID == monitor.id
                    
                    MonitorCard(
                        monitor: monitor,
                        assignment: assignments[monitor.id],
                        isSelected: isSelected,
                        size: CGSize(width: rect.width, height: rect.height)
                    )
                    .position(x: rect.midX, y: rect.midY)
                    .onTapGesture {
                        selectedMonitorID = monitor.id
                    }
                    .animation(.easeInOut(duration: 0.12), value: selectedMonitorID)
                }
            }
            .frame(width: canvasSize, height: canvasSize)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(minHeight: 240)
    }
    
    private func normalizedRect(for monitor: MonitorLayout.LayoutMonitor, scale: CGFloat) -> CGRect {
        let bounds = layout.boundingRect
        let offsetX = (monitor.frame.minX - bounds.minX) * scale
        let offsetY = (monitor.frame.minY - bounds.minY) * scale
        
        return CGRect(
            x: padding + offsetX,
            y: padding + offsetY,
            width: monitor.frame.width * scale,
            height: monitor.frame.height * scale
        )
    }
}

/// Content shown inside each monitor rectangle (thumbnail + label when assigned).
private struct MonitorLayoutContent: View {
    let monitor: MonitorLayout.LayoutMonitor
    let assignment: MonitorAssignment?

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            if let thumb = thumbnail, let assign = assignment {
                // Properly contained thumbnail with crop visualization
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        // Micro crop rect (subtle and contained)
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white, lineWidth: 1.5)
                            .frame(
                                width: max(8, 44 * assign.cropRect.width),
                                height: max(6, 28 * assign.cropRect.height)
                            )
                            .position(
                                x: 22 + (44 * (assign.cropRect.minX + assign.cropRect.width/2) - 22),
                                y: 14 + (28 * (assign.cropRect.minY + assign.cropRect.height/2) - 14)
                            )
                    )
                    .cornerRadius(4)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            } else {
                // Fallback
                VStack(spacing: 4) {
                    Text(monitor.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if monitor.isPrimary {
                        Text("Primary")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Clean, readable filename label at the bottom (better contrast)
            if let name = assignment?.displayName {
                Text(name)
                    .font(.system(size: DisplayScale.points(11), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, DisplayScale.points(7))
                    .padding(.vertical, DisplayScale.points(3))
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0.5)
            }
        }
        .padding(6)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let assign = assignment,
              thumbnail == nil else { return }

        // Prefer resolved security-scoped URL
        let url = assign.resolvedURL() ?? {
            if let path = assign.filePath {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            }
            return nil
        }()

        guard let url else { return }

        let mediaType = assign.mediaType
        // nonisolated(unsafe) copy allows safely sending this Sendable value type across
        // actor isolation boundaries (from main-actor-isolated func to ThumbnailService actor).
        // Safe because MediaType is an immutable enum with no shared state.
        nonisolated(unsafe) let sendableMediaType = mediaType

        if let image = await ThumbnailService.shared.smallThumbnail(for: url, mediaType: sendableMediaType) {
            await MainActor.run {
                self.thumbnail = image
            }
        }
    }
}

/// Extracted card to help the SwiftUI compiler and keep monitors nicely contained.
private struct MonitorCard: View {
    let monitor: MonitorLayout.LayoutMonitor
    let assignment: MonitorAssignment?
    let isSelected: Bool
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
            .frame(width: size.width, height: size.height)
            .overlay(
                MonitorLayoutContent(monitor: monitor, assignment: assignment)
            )
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
    }
}