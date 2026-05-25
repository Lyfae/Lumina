import SwiftUI
import AppKit

/// Visual representation of the user's physical monitor arrangement.
/// This gives users a clear sense of which physical screen they're configuring.
struct MonitorLayoutView: View {
    let layout: MonitorLayout
    @Binding var selectedMonitorID: String?
    
    private let padding: CGFloat = 24
    private let maxCanvasSize: CGFloat = 380
    
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
                    
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.accentColor : Color.blue.opacity(0.5), lineWidth: isSelected ? 3 : 1.5)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .overlay(
                            VStack(spacing: 4) {
                                Text(monitor.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Text(monitor.isPrimary ? "Primary" : "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(6)
                        )
                        .onTapGesture {
                            selectedMonitorID = monitor.id
                        }
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                        .animation(.easeInOut(duration: 0.15), value: selectedMonitorID)
                }
            }
            .frame(width: canvasSize, height: canvasSize)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.06))
            )
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(height: 220)
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