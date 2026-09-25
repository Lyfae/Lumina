import SwiftUI
import AppKit

// MARK: - Design tokens (layout shims)

@MainActor
enum LuminaLayout {
    static var libraryColumnWidth: CGFloat { DisplayScale.points(440) }
    /// Collapsed library rail — wide enough for the expand control at every UI scale.
    static var libraryRailWidth: CGFloat {
        max(DisplayScale.points(52), UIScaleManager.shared.touchTarget() + DisplayScale.points(12))
    }
    static var thumbnailWidth: CGFloat { DisplayScale.points(180) }
    static var thumbnailHeight: CGFloat { DisplayScale.points(101) }
    static var contentPadding: CGFloat { LuminaSpace.xl }
    static var sectionSpacing: CGFloat { LuminaSpace.gridGap }
}

// MARK: - Brand mark (splash / menu bar LS monogram)

/// Compact app icon tile — aurora LS monogram; background adapts to light/dark mode.
struct LuminaBrandMark: View {
    var side: CGFloat = 36

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let markSize = CGSize(width: side * 0.72, height: side * 0.44)
        ZStack {
            tileBackground
            LuminaMenuIcon.fittedLSPath(in: markSize)
                .stroke(
                    LinearGradient(colors: LuminaBrand.ink, startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(
                        lineWidth: max(1.1, side * 0.055),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: LuminaBrand.ink[0].opacity(colorScheme == .light ? 0.25 : 0.45), radius: side * 0.07)
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
                colors: LuminaBrand.heroLight,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: LuminaBrand.tileDark,
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

// MARK: - Scaled slider

struct LuminaSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    /// Use in compact toolbars (e.g. audio footer) — tighter padding.
    var compact: Bool = false
    var label: String = ""

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
        .frame(minHeight: compact ? LuminaMetrics.sliderHeightCompact : LuminaMetrics.sliderHeight)
        .accessibilityLabel(label.isEmpty ? "Slider" : label)
        .accessibilityValue(valueText)
    }

    private var valueText: String {
        if range.upperBound <= 1.01 {
            return "\(Int((value * 100).rounded()))%"
        }
        return String(format: "%.0f", value)
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
                .font(uiScale.font(.bodyStrong))
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value)
                    .font(uiScale.font(.callout).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Press feedback

/// Shared press motion so custom buttons feel tactile (scale + brief dim).
@MainActor
enum LuminaButtonPress {
    static var scale: CGFloat { LuminaMotion.pressScale }
    static var animation: Animation { LuminaMotion.press ?? .easeOut(duration: 0.10) }
}

private struct LuminaHoverPlateKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var luminaHoverPlate: Bool {
        get { self[LuminaHoverPlateKey.self] }
        set { self[LuminaHoverPlateKey.self] = newValue }
    }
}

extension View {
    /// Opt the pressable label into a hover fill plate.
    func luminaHoverPlate(_ enabled: Bool = true) -> some View {
        environment(\.luminaHoverPlate, enabled)
    }
}

/// For buttons that already draw their own chrome (toolbar, chips, icon buttons).
struct LuminaPressableButtonStyle: ButtonStyle {
    @Environment(\.luminaHoverPlate) private var wantsHoverPlate
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        LuminaPressableBody(
            configuration: configuration,
            wantsHoverPlate: wantsHoverPlate,
            isEnabled: isEnabled
        )
    }
}

private struct LuminaPressableBody: View {
    let configuration: ButtonStyleConfiguration
    let wantsHoverPlate: Bool
    let isEnabled: Bool
    @State private var isHovered = false
    @Environment(\.isFocused) private var isFocused
    @StateObject private var theme = ThemeManager.shared

    var body: some View {
        configuration.label
            .background {
                if wantsHoverPlate && isHovered && isEnabled {
                    RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                        .fill(Color.luminaFillHover)
                }
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: LuminaRadius.control + 3, style: .continuous)
                        .strokeBorder(theme.current.color.opacity(0.9), lineWidth: 2)
                        .padding(-3)
                }
            }
            .scaleEffect(configuration.isPressed && isEnabled ? LuminaButtonPress.scale : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.7 : 1)
            .animation(LuminaButtonPress.animation, value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .focusEffectDisabled()
    }
}

// MARK: - Toolbar icon button

struct LuminaToolbarButton: View {
    let title: String
    let icon: String
    var help: String? = nil
    var action: () -> Void

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: LuminaSpace.xs) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.toolbar), weight: .semibold))
                Text(title)
                    .font(uiScale.font(.micro))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, LuminaSpace.xs)
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

private struct LuminaToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        LuminaToolbarButtonBody(configuration: configuration, isEnabled: isEnabled)
    }
}

private struct LuminaToolbarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isEnabled: Bool
    @State private var isHovered = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.luminaButtonFocusRing) private var showsFocusRing
    @StateObject private var theme = ThemeManager.shared

    var body: some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.4)
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                    .fill(plateFill)
            )
            .overlay {
                if isFocused && isEnabled && showsFocusRing {
                    RoundedRectangle(cornerRadius: LuminaRadius.control + 3, style: .continuous)
                        .strokeBorder(theme.current.color.opacity(0.9), lineWidth: 2)
                        .padding(-3)
                }
            }
            .scaleEffect(configuration.isPressed && isEnabled ? LuminaButtonPress.scale : 1)
            .animation(LuminaButtonPress.animation, value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .focusEffectDisabled()
    }

    private var plateFill: Color {
        if !isEnabled { return .clear }
        if configuration.isPressed { return Color.luminaFillPressed }
        if isHovered { return Color.luminaFillHover }
        return .clear
    }
}

// MARK: - Icon button

struct LuminaIconButtonStyle: ButtonStyle {
    enum Size { case regular, compact }

    var active: Bool = false
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        LuminaIconButtonBody(configuration: configuration, active: active, size: size)
    }
}

private struct LuminaIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let active: Bool
    let size: LuminaIconButtonStyle.Size

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.luminaButtonFocusRing) private var showsFocusRing
    @State private var isHovered = false
    @Environment(\.isFocused) private var isFocused
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        let hit: CGFloat = size == .regular ? uiScale.touchTarget() : DisplayScale.points(26)
        let plate: CGFloat = size == .regular ? DisplayScale.points(28) : DisplayScale.points(24)
        let glyph: CGFloat = size == .regular ? uiScale.iconSize(.transport) : DisplayScale.points(11)

        configuration.label
            .font(.system(size: glyph, weight: size == .regular ? .medium : .semibold))
            .foregroundStyle(active ? theme.current.color : Color.secondary)
            .frame(width: plate, height: plate)
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                    .fill(plateFill)
            )
            .frame(width: hit, height: hit)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .overlay {
                if isFocused && isEnabled && showsFocusRing {
                    RoundedRectangle(cornerRadius: LuminaRadius.control + 3, style: .continuous)
                        .strokeBorder(theme.current.color.opacity(0.9), lineWidth: 2)
                        .padding(-3)
                }
            }
            .scaleEffect(configuration.isPressed && isEnabled ? LuminaButtonPress.scale : 1)
            .animation(LuminaButtonPress.animation, value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .focusEffectDisabled()
            .accessibilityValue(active ? "On" : "Off")
    }

    private var plateFill: Color {
        if !isEnabled { return .clear }
        if configuration.isPressed { return Color.luminaFillPressed }
        if isHovered { return Color.luminaFillHover }
        return .clear
    }
}

// MARK: - Close button

struct LuminaCloseButton: View {
    var action: () -> Void

    @StateObject private var uiScale = UIScaleManager.shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: DisplayScale.points(10), weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: DisplayScale.points(24), height: DisplayScale.points(24))
                .background(
                    Circle().fill(isHovered ? Color.luminaFillHover : Color.luminaFill)
                )
                .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .accessibilityLabel("Close")
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sheet header

struct LuminaSheetHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var onClose: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @ObservedObject private var look = LuminaLook.shared
    @Environment(\.colorScheme) private var colorScheme

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.trailing = trailing
    }

    private var headerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: LuminaRadius.floating,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: LuminaRadius.floating,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: LuminaSpace.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                        .fill(theme.current.color.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: uiScale.iconSize(.inline) + 2, weight: .semibold))
                        .foregroundStyle(theme.current.text(in: colorScheme))
                }
                .frame(width: DisplayScale.points(28), height: DisplayScale.points(28))

                VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                    Text(title)
                        .font(uiScale.font(.headline))
                    if let subtitle {
                        Text(subtitle)
                            .font(uiScale.font(.caption))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                trailing()

                if let onClose {
                    LuminaCloseButton(action: onClose)
                }
            }
            .padding(.horizontal, LuminaSpace.xl)
            .padding(.vertical, LuminaSpace.md)
            .frame(minHeight: LuminaSpace.rowHeight + DisplayScale.points(16), alignment: .center)

            LuminaDivider()
        }
        .background {
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            let solid = reduce || look.material == .solid
            Group {
                if solid {
                    Color.luminaCard
                } else {
                    Rectangle().fill(.bar)
                }
            }
            .clipShape(headerShape)
        }
    }
}

extension LuminaSheetHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, onClose: (() -> Void)? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle, onClose: onClose) { EmptyView() }
    }
}

// MARK: - Segmented picker

struct LuminaSegmentedOption<Value: Hashable>: Hashable {
    let value: Value
    let title: String
    let systemImage: String?

    init(_ value: Value, title: String, systemImage: String? = nil) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
    }
}

struct LuminaSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [LuminaSegmentedOption<Value>]

    @Namespace private var selectionNamespace
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @ObservedObject private var look = LuminaLook.shared
    @Environment(\.colorScheme) private var colorScheme

    private var trackHeight: CGFloat {
        switch look.density {
        case .tight: return DisplayScale.points(26)
        case .regular: return DisplayScale.points(28)
        case .airy: return DisplayScale.points(32)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    LuminaMotion.animate(LuminaMotion.state) { selection = option.value }
                } label: {
                    HStack(spacing: LuminaSpace.tight) {
                        if let systemImage = option.systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: uiScale.iconSize(.filter), weight: .semibold))
                        }
                        Text(option.title)
                            .font(uiScale.font(.callout).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(isSelected ? theme.current.text(in: colorScheme) : .secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                                .fill(theme.current.color.opacity(0.16))
                                .matchedGeometryEffect(id: "luminaSegmentSelection", in: selectionNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(LuminaSpace.hair)
        .frame(height: trackHeight)
        .background(
            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                .fill(Color.luminaFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                .strokeBorder(Color.luminaBorder, lineWidth: 1)
        )
        .controlSize(uiScale.controlSize())
    }
}

// MARK: - Filter chip

struct LuminaFilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let help: String
    var action: () -> Void

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: LuminaSpace.tight) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.filter), weight: .semibold))
                Text(label)
                    .font(uiScale.font(.callout).weight(.semibold))
            }
            .padding(.horizontal, LuminaSpace.chipPaddingH)
            .padding(.vertical, LuminaSpace.chipPaddingV)
            .foregroundStyle(isSelected ? theme.current.text(in: colorScheme) : .secondary)
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? theme.current.color.opacity(0.45) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if isSelected { return theme.current.color.opacity(0.14) }
        if isHovered { return Color.luminaFillHover }
        return Color.luminaFill
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

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                Text(title)
                    .font(uiScale.font(.headline))
                if let subtitle {
                    Text(subtitle)
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(uiScale.font(.caption).weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, LuminaSpace.sm)
                    .padding(.vertical, LuminaSpace.xs)
                    .background(Color.luminaFill, in: Capsule())
            }
        }
    }
}

// MARK: - Hint bubble

struct LuminaHintBubble: View {
    enum Style {
        case info, success, tip

        func iconColor(accent: Color) -> Color {
            switch self {
            case .info: return accent
            case .success: return LuminaStatusColor.playing
            case .tip: return LuminaStatusColor.paused
            }
        }

        func borderColor(accent: Color) -> Color {
            switch self {
            case .info: return accent.opacity(0.35)
            case .success: return LuminaStatusColor.playing.opacity(0.4)
            case .tip: return LuminaStatusColor.paused.opacity(0.45)
            }
        }
    }

    let icon: String
    let message: String
    var style: Style = .info
    var onDismiss: (() -> Void)? = nil

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: LuminaSpace.sm) {
            Image(systemName: icon)
                .font(uiScale.font(.callout).weight(.semibold))
                .foregroundStyle(style.iconColor(accent: theme.current.color))
                .frame(width: LuminaMetrics.iconColumn, alignment: .center)
                .padding(.top, 1)

            Text(message)
                .font(uiScale.font(.callout))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(LuminaIconButtonStyle(size: .compact))
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(LuminaSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.luminaCard.opacity(0.95),
            in: RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                .strokeBorder(style.borderColor(accent: theme.current.color), lineWidth: 1)
        )
    }
}

// MARK: - Accent swatch

struct LuminaAccentSwatch: View {
    let theme: AccentTheme
    let selected: Bool
    var action: () -> Void

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.color)
                    .frame(width: DisplayScale.points(20), height: DisplayScale.points(20))
                if selected {
                    Circle()
                        .strokeBorder(theme.color, lineWidth: 2)
                        .frame(width: DisplayScale.points(26), height: DisplayScale.points(26))
                    Image(systemName: "checkmark")
                        .font(.system(size: DisplayScale.points(9), weight: .bold))
                        .foregroundStyle(theme.onAccent)
                }
            }
            .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .accessibilityLabel(theme.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Empty / loading / error

struct LuminaEmptyState<Actions: View>: View {
    let icon: String
    let title: String
    var message: String? = nil
    var compact: Bool = false
    var prominent: Bool = false
    @ViewBuilder var actions: () -> Actions

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        VStack(spacing: LuminaSpace.md) {
            Image(systemName: icon)
                .font(.system(size: compact ? DisplayScale.points(28) : uiScale.iconSize(.hero)))
                .foregroundStyle(theme.current.color.opacity(0.4))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(compact
                      ? uiScale.font(.bodyStrong)
                      : (prominent ? uiScale.font(.title).weight(.semibold) : uiScale.font(.headline)))
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(compact ? uiScale.font(.caption) : uiScale.font(.callout))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: LuminaMetrics.emptyStateTextWidth)
            }

            if !compact {
                HStack(spacing: LuminaSpace.sm) {
                    actions()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension LuminaEmptyState where Actions == EmptyView {
    init(icon: String, title: String, message: String? = nil, compact: Bool = false, prominent: Bool = false) {
        self.init(icon: icon, title: title, message: message, compact: compact, prominent: prominent) { EmptyView() }
    }
}

struct LuminaLoadingView: View {
    var label: String
    var onMedia: Bool = false

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        HStack(spacing: LuminaSpace.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(onMedia ? .white : nil)
            Text(label)
                .font(uiScale.font(.caption))
                .foregroundStyle(onMedia ? Color.white.opacity(0.7) : Color.secondary)
        }
    }
}

struct LuminaErrorState<Actions: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var actions: () -> Actions

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        VStack(spacing: LuminaSpace.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(LuminaStatusColor.paused)
            Text(title)
                .font(uiScale.font(.bodyStrong))
            if let detail {
                Text(detail)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: LuminaSpace.sm) {
                actions()
            }
            .controlSize(.small)
        }
    }
}

extension LuminaErrorState where Actions == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

// MARK: - Overlay chip

struct LuminaOverlayChip: View {
    let text: String

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        Text(text)
            .font(uiScale.font(.callout).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, LuminaSpace.overlayChipPaddingH)
            .padding(.vertical, LuminaSpace.overlayChipPaddingV)
            .background(Color.luminaOverlay, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

struct LuminaOverlayChipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(UIScaleManager.shared.font(.callout).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, LuminaSpace.overlayChipPaddingH)
            .padding(.vertical, LuminaSpace.overlayChipPaddingV)
            .background(Color.luminaOverlay, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

extension View {
    func luminaOverlayChipStyle() -> some View {
        modifier(LuminaOverlayChipStyle())
    }
}

// MARK: - Corner picker

struct LuminaCornerPicker: View {
    @Binding var corner: MusicWidgetPreferences.Corner

    @StateObject private var theme = ThemeManager.shared
    @State private var hovered: MusicWidgetPreferences.Corner?

    private let corners: [MusicWidgetPreferences.Corner] = [
        .topLeading, .topTrailing, .bottomLeading, .bottomTrailing
    ]

    var body: some View {
        let screen = LuminaMetrics.cornerPickerScreen
        let hit = LuminaMetrics.cornerPickerHit

        ZStack {
            RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous)
                .fill(Color.luminaFill)
            RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous)
                .strokeBorder(Color.luminaBorder, lineWidth: 1)

            ForEach(corners, id: \.self) { c in
                cornerButton(c, hit: hit)
            }
        }
        .frame(width: screen.width, height: screen.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Widget corner")
    }

    private func cornerButton(_ c: MusicWidgetPreferences.Corner, hit: CGSize) -> some View {
        let selected = corner == c
        let hovering = hovered == c
        return Button {
            corner = c
        } label: {
            RoundedRectangle(cornerRadius: DisplayScale.points(3), style: .continuous)
                .fill(selected ? theme.current.color : (hovering ? Color.luminaFillHover : Color.luminaFillPressed))
                .frame(width: hit.width, height: hit.height)
        }
        .buttonStyle(.plain)
        .padding(DisplayScale.points(4))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: c))
        .onHover { hovering in
            hovered = hovering ? c : (hovered == c ? nil : hovered)
        }
        .accessibilityLabel(label(for: c))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func alignment(for c: MusicWidgetPreferences.Corner) -> Alignment {
        switch c {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    private func label(for c: MusicWidgetPreferences.Corner) -> String {
        switch c {
        case .topLeading: return "Top left"
        case .topTrailing: return "Top right"
        case .bottomLeading: return "Bottom left"
        case .bottomTrailing: return "Bottom right"
        }
    }
}

// MARK: - Secondary / prominent buttons

private struct ButtonMetrics {
    let height: CGFloat
    let paddingH: CGFloat
    let font: Font

    @MainActor
    static func resolve(controlSize: ControlSize, uiScale: UIScaleManager) -> ButtonMetrics {
        switch controlSize {
        case .mini, .small:
            return ButtonMetrics(
                height: DisplayScale.points(24),
                paddingH: DisplayScale.points(10),
                font: uiScale.font(.callout).weight(.semibold)
            )
        case .large, .extraLarge:
            return ButtonMetrics(
                height: DisplayScale.points(36),
                paddingH: DisplayScale.points(18),
                font: uiScale.font(.bodyStrong)
            )
        default:
            return ButtonMetrics(
                height: DisplayScale.points(28),
                paddingH: DisplayScale.points(14),
                font: uiScale.font(.bodyStrong)
            )
        }
    }
}

struct LuminaSecondaryButtonStyle: ButtonStyle {
    var destructive: Bool = false
    /// Filled accent style — same metrics as secondary so pairs align.
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        LuminaSecondaryButtonBody(
            configuration: configuration,
            destructive: destructive,
            prominent: prominent
        )
    }
}

private struct LuminaButtonFocusRingKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Off inside views whose container holds focus, since `isFocused` reports the ancestor's focus.
    var luminaButtonFocusRing: Bool {
        get { self[LuminaButtonFocusRingKey.self] }
        set { self[LuminaButtonFocusRingKey.self] = newValue }
    }
}

private struct LuminaSecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let destructive: Bool
    let prominent: Bool
    @Environment(\.luminaButtonFocusRing) private var showsFocusRing

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @State private var isHovered = false

    var body: some View {
        let metrics = ButtonMetrics.resolve(controlSize: controlSize, uiScale: uiScale)
        let pressed = configuration.isPressed && isEnabled

        configuration.label
            .font(metrics.font)
            .padding(.horizontal, metrics.paddingH)
            .frame(minHeight: metrics.height)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                    .fill(fill(pressed: pressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                    .strokeBorder(border(pressed: pressed), lineWidth: prominent ? 0 : 1)
            )
            .overlay {
                if prominent && isHovered && isEnabled && !pressed {
                    RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
            }
            .overlay {
                if pressed {
                    RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                        .fill(Color.black.opacity(prominent ? 0.18 : 0))
                }
            }
            .overlay {
                if isFocused && isEnabled && showsFocusRing {
                    RoundedRectangle(cornerRadius: LuminaRadius.control + 3, style: .continuous)
                        .strokeBorder(theme.current.color.opacity(0.9), lineWidth: 2)
                        .padding(-3)
                }
            }
            .scaleEffect(pressed ? LuminaButtonPress.scale : 1)
            .animation(LuminaButtonPress.animation, value: pressed)
            .onHover { isHovered = $0 }
            .focusEffectDisabled()
    }

    private var foreground: Color {
        if !isEnabled {
            if prominent { return theme.current.onAccent.opacity(0.7) }
            return Color(nsColor: .tertiaryLabelColor)
        }
        if prominent { return theme.current.onAccent }
        if destructive { return .red }
        return .primary
    }

    private func fill(pressed: Bool) -> Color {
        if prominent {
            return theme.current.color.opacity(isEnabled ? 1 : 0.45)
        }
        if !isEnabled {
            return Color.luminaFill
        }
        if pressed { return Color.luminaFillPressed }
        if isHovered {
            // rest fill +0.04
            return colorScheme == .light
                ? Color.primary.opacity(0.10)
                : Color.primary.opacity(0.16)
        }
        // rest: keep today's 0.12 dark / 0.06 light
        return colorScheme == .light
            ? Color.primary.opacity(0.06)
            : Color.primary.opacity(0.12)
    }

    private func border(pressed: Bool) -> Color {
        if prominent { return .clear }
        let base: Color
        if destructive {
            base = Color.red.opacity(colorScheme == .light ? (pressed ? 0.5 : 0.35) : (pressed ? 0.6 : 0.45))
        } else {
            base = Color.primary.opacity(colorScheme == .light ? (pressed ? 0.28 : 0.16) : (pressed ? 0.34 : 0.22))
        }
        return isEnabled ? base : base.opacity(0.5)
    }
}

/// Primary filled action (Apply, etc.) with the same press language as secondary buttons.
struct LuminaProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LuminaSecondaryButtonBody(
            configuration: configuration,
            destructive: false,
            prominent: true
        )
    }
}

// MARK: - Card surface

struct LuminaSurface<Content: View>: View {
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .luminaGlassPanel(cornerRadius: cornerRadius)
    }
}
