import SwiftUI
import AppKit

struct ChooseDisplayView: View {
    @ObservedObject var store: WallpaperManagerStore
    @Binding var selectedMonitorID: String?

    var onChangeWallpaper: (String) -> Void
    var onRemoveWallpaper: (String) -> Void
    var onDone: () -> Void

    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var theme = ThemeManager.shared
    @Environment(PlaybackEngine.self) private var engine: PlaybackEngine?

    var body: some View {
        VStack(spacing: 0) {
            LuminaSheetHeader(
                icon: "display.2",
                title: "Choose Display",
                subtitle: "Pick the display you want to set up."
            )

            HStack(alignment: .top, spacing: LuminaSpace.lg) {
                ForEach(Array(store.monitors.enumerated()), id: \.element.id) { offset, monitor in
                    let index = offset + 1
                    let isSelected = store.selectedMonitorID == monitor.id

                    Button {
                        LuminaMotion.animate(LuminaMotion.state) {
                            selectedMonitorID = monitor.id
                            store.selectedMonitorID = monitor.id
                        }
                    } label: {
                        MonitorDisplayCard(
                            monitor: monitor,
                            index: index,
                            assignment: store.assignment(for: monitor.id),
                            isSelected: isSelected,
                            displayState: displayState(for: monitor)
                        )
                    }
                    .buttonStyle(LuminaPressableButtonStyle())
                }
            }
            .padding(.horizontal, LuminaSpace.xxl)
            .padding(.vertical, LuminaSpace.xl)
            .onMoveCommand { direction in
                moveSelection(direction)
            }

            LuminaDivider()

            HStack {
                Group {
                    if let selectedID = store.selectedMonitorID,
                       let monitor = store.monitors.first(where: { $0.id == selectedID }),
                       let index = store.monitors.firstIndex(where: { $0.id == selectedID }) {
                        Label("Display \(index + 1) · \(monitor.name)", systemImage: "display")
                            .font(uiScale.font(.callout))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Click a display to select it.")
                            .font(uiScale.font(.callout))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    onDone()
                }
                .buttonStyle(LuminaProminentButtonStyle())
                .controlSize(uiScale.controlSize())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, LuminaSpace.xxl)
            .padding(.vertical, LuminaSpace.barPaddingV)
        }
        .scaledMinFrame(width: 580, height: 320)
        .background(Color.luminaBase)
        .tint(theme.current.color)
    }

    private func displayState(for monitor: MonitorInfo) -> LuminaDisplayState {
        guard let engine else { return .empty }
        return LuminaDisplayState.from(plan: engine.plan, key: DisplayKey(monitor.id))
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !store.monitors.isEmpty else { return }
        let ids = store.monitors.map(\.id)
        let current = store.selectedMonitorID ?? selectedMonitorID
        let index = current.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next: Int
        switch direction {
        case .left, .up:
            next = max(0, index - 1)
        case .right, .down:
            next = min(ids.count - 1, index + 1)
        @unknown default:
            return
        }
        let id = ids[next]
        selectedMonitorID = id
        store.selectedMonitorID = id
    }
}

private struct MonitorDisplayCard: View {
    let monitor: MonitorInfo
    let index: Int
    let assignment: MonitorAssignment?
    let isSelected: Bool
    let displayState: LuminaDisplayState

    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var theme = ThemeManager.shared
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.sm) {
            ZStack(alignment: .bottomLeading) {
                thumbnailContent
                    .frame(height: LuminaMetrics.displayCardThumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous))

                LuminaOverlayChip(text: "\(index)")
                    .padding(LuminaSpace.sm)
            }
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? theme.current.color
                            : (isHovered ? Color.luminaFillPressed : Color.luminaBorder),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DisplayScale.points(18), weight: .semibold))
                        .foregroundStyle(theme.current.color)
                        .background(Circle().fill(Color.luminaCard).padding(2))
                        .padding(LuminaSpace.sm)
                }
            }

            VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                Text(monitor.name)
                    .font(isSelected ? uiScale.font(.bodyStrong) : uiScale.font(.body))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Text(monitor.resolution)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                if assignment != nil, displayState != .empty {
                    LuminaStatusPill(style: .status(displayState))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let assignment {
            WallpaperPreview(
                assignment: assignment,
                liveCropRect: nil,
                liveScaling: nil,
                targetAspect: monitor.aspectRatio
            )
        } else {
            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                .fill(Color.luminaCard)
                .overlay {
                    LuminaEmptyState(icon: "photo", title: "No wallpaper", compact: true)
                }
        }
    }
}
