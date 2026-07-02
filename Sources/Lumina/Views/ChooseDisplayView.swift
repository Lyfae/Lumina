import SwiftUI

struct ChooseDisplayView: View {
    @ObservedObject var store: WallpaperManagerStore
    @Binding var selectedMonitorID: String?

    var onChangeWallpaper: (String) -> Void
    var onRemoveWallpaper: (String) -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 5) {
                Text("Choose Display")
                    .font(.title2.bold())
                Text("Select a display below to configure its wallpaper and settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            Divider()
                .padding(.top, 16)

            // Monitor cards
            // isSelected is derived from store.selectedMonitorID (@Published) so that
            // changes trigger a re-render even when the backing @Binding is a plain
            // stored property on an NSWindowController (which has no SwiftUI reactivity).
            HStack(alignment: .top, spacing: 16) {
                ForEach(store.monitors) { monitor in
                    let index = (store.monitors.firstIndex(where: { $0.id == monitor.id }) ?? 0) + 1
                    let isSelected = store.selectedMonitorID == monitor.id

                    MonitorDisplayCard(
                        monitor: monitor,
                        index: index,
                        assignment: store.assignment(for: monitor.id),
                        isSelected: isSelected
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedMonitorID = monitor.id        // keep external binding in sync
                            store.selectedMonitorID = monitor.id  // reactive source of truth
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            // Footer
            HStack {
                // Status
                Group {
                    if let selectedID = store.selectedMonitorID,
                       let monitor = store.monitors.first(where: { $0.id == selectedID }) {
                        let index = (store.monitors.firstIndex(where: { $0.id == selectedID }) ?? 0) + 1
                        Label("S\(index) — \(monitor.name)", systemImage: "display")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Click a display above to select it")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button("Done") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 580, minHeight: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct MonitorDisplayCard: View {
    let monitor: MonitorInfo
    let index: Int
    let assignment: MonitorAssignment?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail with bounding box overlay
            ZStack(alignment: .bottomLeading) {
                thumbnailContent
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Monitor label badge (bottom-left)
                Text("S\(index)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            }
            // Selection bounding box
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.yellow : Color(NSColor.separatorColor),
                        lineWidth: isSelected ? 3 : 1
                    )
            )
            // Glow when selected
            .shadow(
                color: isSelected ? Color.yellow.opacity(0.55) : .clear,
                radius: isSelected ? 10 : 0
            )
            // Small checkmark badge in top-right corner
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.yellow)
                        .background(Color.black.opacity(0.7), in: Circle())
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Resolution + name
            VStack(spacing: 2) {
                Text(monitor.resolution)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(monitor.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let assignment = assignment {
            WallpaperPreview(
                assignment: assignment,
                liveCropRect: nil,
                liveScaling: nil,
                targetAspect: monitor.aspectRatio   // ultrawide/portrait displays previewed correctly
            )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No wallpaper")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                )
        }
    }
}
