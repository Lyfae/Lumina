import SwiftUI

// MARK: - Design tokens

@MainActor
enum LuminaLayout {
    static var libraryColumnWidth: CGFloat { DisplayScale.points(440) }
    static var thumbnailWidth: CGFloat { DisplayScale.points(180) }
    static var thumbnailHeight: CGFloat { DisplayScale.points(101) }
    static var contentPadding: CGFloat { DisplayScale.points(20) }
    static var sectionSpacing: CGFloat { DisplayScale.points(16) }
}

// MARK: - Toolbar icon button (44pt min hit target)

struct LuminaToolbarButton: View {
    let title: String
    let icon: String
    var help: String? = nil
    var action: () -> Void

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: DisplayScale.points(4)) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.toolbar), weight: .semibold))
                Text(title)
                    .font(.system(size: DisplayScale.points(10), weight: .medium))
            }
            .foregroundStyle(.primary)
            .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

// MARK: - Filter chip (library tabs)

struct LuminaFilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let help: String
    var action: () -> Void

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: DisplayScale.points(8)) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.filter), weight: .semibold))
                Text(label)
                    .font(.system(size: DisplayScale.points(13), weight: .semibold))
            }
            .padding(.horizontal, DisplayScale.points(14))
            .padding(.vertical, DisplayScale.points(10))
            .foregroundStyle(isSelected ? theme.current.color : .secondary)
            .background(
                RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                    .fill(isSelected ? theme.current.color.opacity(0.14) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                    .strokeBorder(isSelected ? theme.current.color.opacity(0.45) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Section header

struct LuminaSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: DisplayScale.points(15), weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: DisplayScale.points(11)))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: DisplayScale.points(11), weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, DisplayScale.points(8))
                    .padding(.vertical, DisplayScale.points(4))
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
    }
}

// MARK: - Card surface

struct LuminaSurface<Content: View>: View {
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(Color.luminaCard, in: RoundedRectangle(cornerRadius: DisplayScale.points(cornerRadius), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DisplayScale.points(cornerRadius), style: .continuous)
                    .strokeBorder(Color.luminaBorder, lineWidth: 1)
            )
    }
}
