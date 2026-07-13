import SwiftUI

/// Checklist of macOS folders the user allows Lumina to read media from.
struct MediaAccessLocationChecklist: View {
    @ObservedObject var settings: MediaAccessSettings
    var showsHeader: Bool = true

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    private var selectionIsEmpty: Bool { settings.enabledLocations.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(12)) {
            if showsHeader {
                VStack(alignment: .leading, spacing: DisplayScale.points(4)) {
                    Text("Allowed folders")
                        .font(uiScale.scaledFont(13, weight: .semibold))
                    Text(headerCopy)
                        .font(uiScale.scaledFont(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(headerCopy)
                    .font(uiScale.scaledFont(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: DisplayScale.points(6)) {
                ForEach(MediaAccessLocation.allCases) { location in
                    locationRow(location)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if selectionIsEmpty {
                HStack(alignment: .top, spacing: DisplayScale.points(8)) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Select at least one folder so Lumina can find wallpapers.")
                        .font(uiScale.scaledFont(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DisplayScale.points(10))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(MediaAccessPolicy.restrictionHint())
                    .font(uiScale.scaledFont(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerCopy: String {
        "Choose which folders Lumina may use. Checking a box only sets your preference — macOS may still ask once the first time you open a file from Documents, Desktop, or Downloads."
    }

    private func locationRow(_ location: MediaAccessLocation) -> some View {
        let enabled = settings.isEnabled(location)

        return Button {
            settings.setEnabled(location, !enabled)
        } label: {
            HStack(alignment: .center, spacing: DisplayScale.points(12)) {
                checkmarkBox(enabled: enabled)

                Image(systemName: location.icon)
                    .font(.system(size: DisplayScale.points(14), weight: .semibold))
                    .foregroundStyle(enabled ? theme.current.color : .secondary)
                    .frame(width: DisplayScale.points(22), height: DisplayScale.points(22))

                VStack(alignment: .leading, spacing: 2) {
                    Text(location.label)
                        .font(uiScale.scaledFont(13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(location.subtitle)
                        .font(uiScale.scaledFont(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DisplayScale.points(12))
            .padding(.vertical, DisplayScale.points(10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                    .fill(enabled ? theme.current.color.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                    .strokeBorder(
                        enabled ? theme.current.color.opacity(0.28) : Color.luminaBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(location.label)
        .accessibilityValue(enabled ? "Allowed" : "Not allowed")
        .accessibilityAddTraits(.isButton)
    }

    private func checkmarkBox(enabled: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(enabled ? theme.current.color : Color.clear)
                .frame(width: 18, height: 18)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    enabled ? theme.current.color : Color.secondary.opacity(0.45),
                    lineWidth: 1.5
                )
                .frame(width: 18, height: 18)
            if enabled {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 18, height: 18)
    }
}
