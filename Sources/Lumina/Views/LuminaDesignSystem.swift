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

// MARK: - Brand mark (splash / menu bar LS monogram)

/// Compact app icon tile — aurora background + gradient cursive LS (same artwork as splash & menu bar).
struct LuminaBrandMark: View {
    var side: CGFloat = 36

    private let inkGradient: [Color] = [
        Color(red: 0.62, green: 0.87, blue: 1.0),
        Color(red: 0.72, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.78, blue: 0.55)
    ]

    var body: some View {
        let markSize = CGSize(width: side * 0.72, height: side * 0.44)
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.16),
                    Color(red: 0.10, green: 0.07, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LuminaMenuIcon.fittedLSPath(in: markSize)
                .stroke(
                    LinearGradient(colors: inkGradient, startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(
                        lineWidth: max(1.1, side * 0.055),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: inkGradient[0].opacity(0.45), radius: side * 0.07)
                .frame(width: markSize.width, height: markSize.height)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
        .accessibilityLabel("Lumina Studio")
    }
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

// MARK: - Hint bubble (inline guidance)

struct LuminaHintBubble: View {
    enum Style {
        case info, success, tip

        var iconColor: Color {
            switch self {
            case .info: return Color.accentColor
            case .success: return .green
            case .tip: return .yellow
            }
        }

        var borderColor: Color {
            switch self {
            case .info: return Color.accentColor.opacity(0.35)
            case .success: return Color.green.opacity(0.4)
            case .tip: return Color.yellow.opacity(0.45)
            }
        }
    }

    let icon: String
    let message: String
    var style: Style = .info
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DisplayScale.points(10)) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.iconColor)
                .frame(width: DisplayScale.points(16), alignment: .center)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(DisplayScale.points(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.luminaCard.opacity(0.95), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style.borderColor, lineWidth: 1)
        )
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
