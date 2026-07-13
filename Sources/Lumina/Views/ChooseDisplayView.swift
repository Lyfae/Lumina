import SwiftUI

struct ChooseDisplayView: View {
    @ObservedObject var store: WallpaperManagerStore
    @Binding var selectedMonitorID: String?

    var onChangeWallpaper: (String) -> Void
    var onRemoveWallpaper: (String) -> Void
    var onDone: () -> Void

    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DisplayScale.points(6)) {
                Text("Choose Display")
                    .font(uiScale.scaledFont(18, weight: .bold))
                Text("Select a display to configure its wallpaper and settings.")
                    .font(uiScale.scaledFont(12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, DisplayScale.points(20))
            .padding(.horizontal, DisplayScale.points(24))

            LuminaDivider()
                .padding(.top, DisplayScale.points(16))

            HStack(alignment: .top, spacing: DisplayScale.points(16)) {
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
                            selectedMonitorID = monitor.id
                            store.selectedMonitorID = monitor.id
                        }
                    }
                }
            }
            .padding(.horizontal, DisplayScale.points(24))
            .padding(.vertical, DisplayScale.points(20))

            LuminaDivider()

            HStack {
                Group {
                    if let selectedID = store.selectedMonitorID,
                       let monitor = store.monitors.first(where: { $0.id == selectedID }) {
                        let index = (store.monitors.firstIndex(where: { $0.id == selectedID }) ?? 0) + 1
                        Label("S\(index) — \(monitor.name)", systemImage: "display")
                            .font(uiScale.scaledFont(12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Click a display above to select it")
                            .font(uiScale.scaledFont(12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(uiScale.controlSize())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, DisplayScale.points(24))
            .padding(.vertical, DisplayScale.points(14))
        }
        .scaledMinFrame(width: 580, height: 320)
        .background(Color.luminaBase)
        .tint(theme.current.color)
    }
}

private struct MonitorDisplayCard: View {
    let monitor: MonitorInfo
    let index: Int
    let assignment: MonitorAssignment?
    let isSelected: Bool

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        VStack(spacing: DisplayScale.points(8)) {
            ZStack(alignment: .bottomLeading) {
                thumbnailContent
                    .frame(height: DisplayScale.points(160))
                    .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(8)))

                Text("S\(index)")
                    .font(uiScale.scaledFont(11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DisplayScale.points(7))
                    .padding(.vertical, DisplayScale.points(3))
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                    .padding(DisplayScale.points(8))
            }
            .overlay(
                RoundedRectangle(cornerRadius: DisplayScale.points(8))
                    .strokeBorder(
                        isSelected ? Color.yellow : Color.luminaBorder,
                        lineWidth: isSelected ? 3 : 1
                    )
            )
            .shadow(
                color: isSelected ? Color.yellow.opacity(0.55) : .clear,
                radius: isSelected ? 10 : 0
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DisplayScale.points(18), weight: .semibold))
                        .foregroundStyle(Color.yellow)
                        .background(Color.black.opacity(0.7), in: Circle())
                        .padding(DisplayScale.points(8))
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(spacing: 2) {
                Text(monitor.resolution)
                    .font(uiScale.scaledFont(11))
                    .foregroundStyle(.secondary)
                Text(monitor.name)
                    .font(uiScale.scaledFont(12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let assignment = assignment {
            WallpaperPreview(
                assignment: assignment,
                liveCropRect: nil,
                liveScaling: nil,
                targetAspect: monitor.aspectRatio
            )
        } else {
            RoundedRectangle(cornerRadius: DisplayScale.points(8))
                .fill(Color.luminaCard)
                .overlay(
                    VStack(spacing: DisplayScale.points(6)) {
                        Image(systemName: "photo")
                            .font(.system(size: DisplayScale.points(22)))
                            .foregroundStyle(.secondary)
                        Text("No wallpaper")
                            .font(uiScale.scaledFont(11))
                            .foregroundStyle(.secondary)
                    }
                )
        }
    }
}
