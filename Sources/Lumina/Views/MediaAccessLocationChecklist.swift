import SwiftUI

/// Checklist of macOS folders the user allows Lumina to read media from.
struct MediaAccessLocationChecklist: View {
    @ObservedObject var settings: MediaAccessSettings
    var showsHeader: Bool = true

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    private var selectionIsEmpty: Bool { settings.enabledLocations.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.md) {
            if showsHeader {
                VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                    Text("Allowed folders")
                        .font(LuminaFont.font(.bodyStrong))
                    Text(headerCopy)
                        .font(LuminaFont.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(headerCopy)
                    .font(LuminaFont.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: LuminaSpace.sm) {
                ForEach(MediaAccessLocation.allCases) { location in
                    locationRow(location)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if selectionIsEmpty {
                HStack(alignment: .top, spacing: LuminaSpace.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(LuminaStatusColor.paused)
                    Text("Pick at least one folder.")
                        .font(LuminaFont.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(LuminaSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LuminaStatusColor.paused.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                )
            } else {
                Text(MediaAccessPolicy.restrictionHint())
                    .font(LuminaFont.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerCopy: String {
        "Lumina only opens wallpapers from these folders. macOS may ask once for Documents, Desktop, or Downloads."
    }

    private func locationRow(_ location: MediaAccessLocation) -> some View {
        let enabled = settings.isEnabled(location)

        return Button {
            settings.setEnabled(location, !enabled)
        } label: {
            HStack(alignment: .center, spacing: LuminaSpace.md) {
                checkmarkBox(enabled: enabled)

                Image(systemName: location.icon)
                    .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                    .foregroundStyle(enabled ? theme.current.color : .secondary)
                    .frame(width: DisplayScale.points(24), height: DisplayScale.points(24))

                VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                    Text(location.label)
                        .font(LuminaFont.font(.bodyStrong))
                        .foregroundStyle(.primary)
                    Text(location.subtitle)
                        .font(LuminaFont.font(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, LuminaSpace.md)
            .padding(.vertical, LuminaSpace.sm)
            .frame(maxWidth: .infinity, minHeight: LuminaSpace.rowHeight + 8, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                    .fill(enabled ? theme.current.color.opacity(0.10) : Color.luminaFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                    .strokeBorder(
                        enabled ? theme.current.color.opacity(0.35) : Color.luminaBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .accessibilityLabel(location.label)
        .accessibilityValue(enabled ? "Allowed" : "Not allowed")
        .accessibilityAddTraits(.isButton)
    }

    private func checkmarkBox(enabled: Bool) -> some View {
        let size = DisplayScale.points(18)
        let radius = LuminaRadius.badge + 1
        let glyph = uiScale.iconSize(.inline) - 2

        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(enabled ? theme.current.color : Color.clear)
                .frame(width: size, height: size)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    enabled ? theme.current.color : Color.secondary.opacity(0.45),
                    lineWidth: 1.5
                )
                .frame(width: size, height: size)
            if enabled {
                Image(systemName: "checkmark")
                    .font(.system(size: glyph, weight: .bold))
                    .foregroundStyle(theme.current.onAccent)
            }
        }
        .frame(width: size, height: size)
    }
}
