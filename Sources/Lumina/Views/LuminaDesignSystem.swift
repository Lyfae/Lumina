import SwiftUI

// MARK: - Design tokens

@MainActor
enum LuminaLayout {
    static var libraryColumnWidth: CGFloat { DisplayScale.points(440) }
    /// Collapsed library rail — just wide enough for the expand control.
    static var libraryRailWidth: CGFloat { DisplayScale.points(48) }
    static var thumbnailWidth: CGFloat { DisplayScale.points(180) }
    static var thumbnailHeight: CGFloat { DisplayScale.points(101) }
    static var contentPadding: CGFloat { DisplayScale.points(20) }
    static var sectionSpacing: CGFloat { DisplayScale.points(16) }
}

// MARK: - Brand mark (splash / menu bar LS monogram)

/// Compact app icon tile — aurora LS monogram; background adapts to light/dark mode.
struct LuminaBrandMark: View {
    var side: CGFloat = 36

    @Environment(\.colorScheme) private var colorScheme

    private let inkGradient: [Color] = [
        Color(red: 0.62, green: 0.87, blue: 1.0),
        Color(red: 0.72, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.78, blue: 0.55)
    ]

    var body: some View {
        let markSize = CGSize(width: side * 0.72, height: side * 0.44)
        ZStack {
            tileBackground
            LuminaMenuIcon.fittedLSPath(in: markSize)
                .stroke(
                    LinearGradient(colors: inkGradient, startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(
                        lineWidth: max(1.1, side * 0.055),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: inkGradient[0].opacity(colorScheme == .light ? 0.25 : 0.45), radius: side * 0.07)
                .frame(width: markSize.width, height: markSize.height)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .strokeBorder(tileBorder, lineWidth: 1)
        )
        .accessibilityLabel("Lumina Studio")
    }

    @ViewBuilder
    private var tileBackground: some View {
        if colorScheme == .light {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 1.0),
                    Color(red: 0.90, green: 0.92, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.14, blue: 0.24),
                    Color(red: 0.10, green: 0.09, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var tileBorder: Color {
        colorScheme == .light
            ? Color.primary.opacity(0.08)
            : Color.white.opacity(0.12)
    }
}

// MARK: - Scaled slider (larger thumb + accent tint; light-mode track chrome)

struct LuminaSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    /// Use in compact toolbars (e.g. audio footer) — tighter padding.
    var compact: Bool = false

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        Group {
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
        .controlSize(uiScale.controlSize())
        .tint(theme.current.color)
        .frame(minHeight: DisplayScale.points(compact ? 18 : 24))
    }
}

/// Label + value row used above sliders for consistent hierarchy.
struct LuminaSliderLabel: View {
    let title: String
    var value: String? = nil

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        HStack {
            Text(title)
                .font(uiScale.scaledFont(13, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value)
                    .font(uiScale.scaledFont(12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Press feedback

/// Shared press motion so custom buttons feel tactile (scale + brief dim).
enum LuminaButtonPress {
    static let scale: CGFloat = 0.96
    static let animation = Animation.easeOut(duration: 0.1)
}

/// For buttons that already draw their own chrome (toolbar, chips, icon buttons).
struct LuminaPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? LuminaButtonPress.scale : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(LuminaButtonPress.animation, value: configuration.isPressed)
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.primary)
            // Hit area at least touchTarget, but never clip the title (e.g. "Settings").
            .padding(.horizontal, DisplayScale.points(4))
            .frame(minWidth: uiScale.touchTarget(), minHeight: uiScale.touchTarget())
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaToolbarButtonStyle())
        .fixedSize()
        .layoutPriority(1)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// Toolbar: pressed state gets a clear inset plate + scale so it reads as a real click.
private struct LuminaToolbarButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed
                                               ? (colorScheme == .light ? 0.12 : 0.18)
                                               : 0))
            )
            .scaleEffect(configuration.isPressed ? LuminaButtonPress.scale : 1)
            .animation(LuminaButtonPress.animation, value: configuration.isPressed)
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
            HStack(spacing: DisplayScale.points(6)) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.filter), weight: .semibold))
                Text(label)
                    .font(.system(size: DisplayScale.points(12), weight: .semibold))
            }
            .padding(.horizontal, DisplayScale.points(10))
            .padding(.vertical, DisplayScale.points(7))
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
        .buttonStyle(LuminaPressableButtonStyle())
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Left-to-right chip/flow layout that wraps to the next line instead of scrolling.
struct LuminaWrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        var y = bounds.minY
        var index = 0
        for row in rows {
            var x = bounds.minX
            for _ in 0..<row.count {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
                index += 1
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var count: Int
        var width: CGFloat
        var height: CGFloat
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row(count: 0, width: 0, height: 0)

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = current.count == 0
                ? size.width
                : current.width + spacing + size.width

            if current.count > 0, nextWidth > maxWidth {
                rows.append(current)
                current = Row(count: 1, width: size.width, height: size.height)
            } else {
                current.count += 1
                current.width = nextWidth
                current.height = max(current.height, size.height)
            }
        }
        if current.count > 0 { rows.append(current) }
        return rows
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

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: DisplayScale.points(10)) {
            Image(systemName: icon)
                .font(uiScale.scaledFont(12, weight: .semibold))
                .foregroundStyle(style.iconColor)
                .frame(width: DisplayScale.points(16), alignment: .center)
                .padding(.top, 1)

            Text(message)
                .font(uiScale.scaledFont(12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(uiScale.scaledFont(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: uiScale.touchTarget() * 0.6, height: uiScale.touchTarget() * 0.6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
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

// MARK: - Secondary button (readable on light backgrounds — not washed-out green text)

/// Matched chrome for secondary (and optional filled primary) actions so paired
/// buttons like Done / Reset share the same height and padding.
struct LuminaSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var theme = ThemeManager.shared

    var destructive: Bool = false
    /// Filled accent style — same metrics as secondary so pairs align.
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: DisplayScale.points(13), weight: .semibold))
            .padding(.horizontal, DisplayScale.points(14))
            .padding(.vertical, DisplayScale.points(7))
            .frame(minHeight: DisplayScale.points(28))
            .foregroundStyle(foreground.opacity(pressed && !prominent ? 0.85 : 1))
            .background(
                RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                    .fill(fill(pressed: pressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                    .strokeBorder(border(pressed: pressed), lineWidth: prominent ? 0 : 1)
            )
            .overlay {
                if pressed {
                    RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                        .fill(Color.black.opacity(prominent ? 0.18 : (colorScheme == .light ? 0.06 : 0.12)))
                }
            }
            .scaleEffect(pressed ? LuminaButtonPress.scale : 1)
            .animation(LuminaButtonPress.animation, value: pressed)
    }

    private var foreground: Color {
        if prominent { return .white }
        if destructive { return .red }
        return .primary
    }

    private func fill(pressed: Bool) -> Color {
        if prominent { return theme.current.color }
        if colorScheme == .light {
            return Color.primary.opacity(pressed ? 0.14 : 0.06)
        }
        return Color.primary.opacity(pressed ? 0.22 : 0.12)
    }

    private func border(pressed: Bool) -> Color {
        if prominent { return .clear }
        if destructive {
            return Color.red.opacity(colorScheme == .light ? (pressed ? 0.5 : 0.35) : (pressed ? 0.6 : 0.45))
        }
        return Color.primary.opacity(colorScheme == .light ? (pressed ? 0.28 : 0.16) : (pressed ? 0.34 : 0.22))
    }
}

/// Primary filled action (Apply, etc.) with the same press language as secondary buttons.
struct LuminaProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var theme = ThemeManager.shared

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: DisplayScale.points(13), weight: .semibold))
            .padding(.horizontal, DisplayScale.points(14))
            .padding(.vertical, DisplayScale.points(7))
            .frame(minHeight: DisplayScale.points(28))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.7))
            .background(
                RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                    .fill(theme.current.color.opacity(isEnabled ? 1 : 0.45))
            )
            .overlay {
                if pressed && isEnabled {
                    RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                        .fill(Color.black.opacity(0.2))
                }
            }
            .scaleEffect(pressed && isEnabled ? LuminaButtonPress.scale : 1)
            .animation(LuminaButtonPress.animation, value: pressed)
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
