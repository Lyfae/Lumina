import SwiftUI

// MARK: - Decode / frame-rate UI choices (maps onto LuminaCore presets)

enum DecodeCapChoice: String, CaseIterable, Identifiable {
    case auto, uhd, qhd, fhd

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .uhd: return "4K"
        case .qhd: return "1440p"
        case .fhd: return "1080p"
        }
    }

    init(_ preset: QualityPreset) {
        switch preset {
        case .automatic, .original: self = .auto
        case .uhd2160: self = .uhd
        case .balanced: self = .qhd
        case .fhd1080, .efficient: self = .fhd
        }
    }

    var qualityPreset: QualityPreset {
        switch self {
        case .auto: return .automatic
        case .uhd: return .uhd2160
        case .qhd: return .balanced
        case .fhd: return .fhd1080
        }
    }

    static func showsLegacyEfficientCaption(_ preset: QualityPreset) -> Bool {
        preset == .efficient
    }

    var caption: String {
        switch self {
        case .auto: return "Uses only what this display needs."
        case .uhd: return "Never decodes above 2160p."
        case .qhd: return "Never decodes above 1440p. Uses less power."
        case .fhd: return "Never decodes above 1080p. Uses the least power."
        }
    }
}

enum FrameRateChoice: Hashable, Identifiable {
    case native
    case fps(Int)

    var id: String {
        switch self {
        case .native: return "native"
        case .fps(let n): return "fps-\(n)"
        }
    }

    var shortLabel: String {
        switch self {
        case .native: return "Match"
        case .fps(let n): return "\(n)"
        }
    }

    var longLabel: String {
        switch self {
        case .native: return "Match video"
        case .fps(let n): return "\(n) fps"
        }
    }

    init(_ cap: FrameRateCap) {
        switch cap {
        case .native: self = .native
        case .fps(let n): self = .fps(n)
        }
    }

    var frameRateCap: FrameRateCap {
        switch self {
        case .native: return .native
        case .fps(let n): return .fps(n)
        }
    }

    /// Standard segments; appends 8 only while that value is selected.
    static func choices(includingSelected selected: FrameRateCap) -> [FrameRateChoice] {
        var list: [FrameRateChoice] = [.native, .fps(60), .fps(30), .fps(24), .fps(15)]
        if case .fps(8) = selected, !list.contains(.fps(8)) {
            list.append(.fps(8))
        }
        return list
    }
}

// MARK: - Display / playback state

enum LuminaDisplayState: Equatable {
    case playing(fps: Int?)
    case paused(PauseReasons)
    case failed(String)
    case off
    case empty

    static func from(plan: PlaybackPlan, key: DisplayKey) -> LuminaDisplayState {
        guard let surface = plan.surfaces[.desktop(key)] else { return .empty }
        switch surface.content {
        case .empty:
            return .empty
        case .failed(let message):
            return .failed(message)
        case .source(let sourceKey, _):
            switch surface.run {
            case .playing:
                let fps = plan.sources[sourceKey]?.budget.maxFPS
                return .playing(fps: fps)
            case .paused(let reasons):
                if reasons.contains(.disabled) { return .off }
                return .paused(reasons)
            case .idle:
                return .empty
            }
        }
    }

    func pillText(batteryThreshold: Int? = nil) -> String {
        switch self {
        case .playing:
            return "Playing"
        case .paused(let reasons):
            return Self.pausePillText(reasons, batteryThreshold: batteryThreshold)
        case .failed:
            return "Can’t play"
        case .off:
            return "Off"
        case .empty:
            return ""
        }
    }

    func helpText(batteryThreshold: Int?, usesAdjustCopy: Bool) -> String {
        let changeHint = usesAdjustCopy
            ? "Change this in Adjust → Quality & Power."
            : "Change this in Settings → Power."
        switch self {
        case .playing(let fps):
            if let fps {
                return "Playing at \(fps) fps."
            }
            return "Playing at full frame rate."
        case .paused(let reasons):
            return Self.pauseHelp(reasons, batteryThreshold: batteryThreshold, changeHint: changeHint)
        case .failed(let message):
            return message
        case .off:
            return "This display’s wallpaper is turned off."
        case .empty:
            return ""
        }
    }

    var dotColor: Color {
        switch self {
        case .playing: return LuminaStatusColor.playing
        case .paused(let reasons):
            if reasons.contains(.disabled) || reasons.contains(.displayInactive) {
                return LuminaStatusColor.off
            }
            return LuminaStatusColor.paused
        case .failed: return LuminaStatusColor.error
        case .off: return LuminaStatusColor.off
        case .empty: return LuminaStatusColor.off
        }
    }

    private static func pausePillText(_ reasons: PauseReasons, batteryThreshold: Int?) -> String {
        switch reasons.headline {
        case .manual?: return "Paused"
        case .displayInactive?: return "Asleep"
        case .lowPowerMode?: return "Paused · Low Power Mode"
        case .batteryLow?:
            let n = batteryThreshold.map { "\($0)%" } ?? "threshold"
            return "Paused · Battery below \(n)"
        case .onBattery?: return "Paused · On battery"
        case .thermal?: return "Paused · Mac is hot"
        case .covered?: return "Paused · Covered"
        case .disabled?: return "Off"
        default: return "Paused"
        }
    }

    private static func pauseHelp(
        _ reasons: PauseReasons,
        batteryThreshold: Int?,
        changeHint: String
    ) -> String {
        switch reasons.headline {
        case .manual?:
            return "You paused all wallpapers. Resume from the menu bar or press ⌥⌘P."
        case .displayInactive?:
            return "This display is asleep or your Mac is locked."
        case .lowPowerMode?:
            return "Low Power Mode is on. \(changeHint)"
        case .batteryLow?:
            let n = batteryThreshold.map { "\($0)%" } ?? "the threshold"
            return "Battery is below \(n). \(changeHint)"
        case .onBattery?:
            return "Your Mac is on battery. \(changeHint)"
        case .thermal?:
            return "Your Mac is running hot. Playback resumes when it cools down."
        case .covered?:
            return "A window covers this display."
        case .disabled?:
            return "This display’s wallpaper is turned off."
        default:
            return "Paused."
        }
    }
}

enum LuminaPlaybackHeadline {
    static func text(plan: PlaybackPlan, displays: [DisplaySnapshot]) -> String {
        let keys = displays.map(\.key)
        var playing = 0
        var paused = 0
        var failed = 0
        var content = 0
        var pauseReasons: [PauseReasons] = []

        for key in keys {
            let state = LuminaDisplayState.from(plan: plan, key: key)
            switch state {
            case .empty:
                continue
            case .playing:
                content += 1
                playing += 1
            case .paused(let reasons):
                content += 1
                paused += 1
                pauseReasons.append(reasons)
            case .failed:
                content += 1
                failed += 1
            case .off:
                content += 1
                paused += 1
                pauseReasons.append(.disabled)
            }
        }

        if content == 0 { return "No wallpapers set" }
        if failed > 0 && playing == 0 { return "Can’t play a wallpaper" }
        if playing > 0 && paused == 0 && failed == 0 {
            return playing == 1 ? "Playing on 1 display" : "Playing on \(playing) displays"
        }
        if playing > 0 {
            return "Playing on \(playing) of \(content) displays"
        }

        // All paused (or off)
        if pauseReasons.contains(where: { $0.contains(.manual) }) {
            return "Paused"
        }
        let headlines = Set(pauseReasons.compactMap(\.headline))
        if headlines.count == 1, let only = headlines.first {
            let state = LuminaDisplayState.paused(only)
            return state.pillText()
        }
        return "Paused on \(paused) displays"
    }

    static func isEverythingPaused(plan: PlaybackPlan) -> Bool {
        let desktops = plan.surfaces.filter { if case .desktop = $0.key { return true }; return false }
        guard !desktops.isEmpty else { return false }
        var sawContent = false
        for (_, surface) in desktops {
            switch surface.content {
            case .empty:
                continue
            case .failed, .source:
                sawContent = true
                if case .playing = surface.run { return false }
            }
        }
        return sawContent
    }

    static func isManuallyPaused(plan: PlaybackPlan) -> Bool {
        plan.surfaces.values.contains { surface in
            if case .paused(let reasons) = surface.run {
                return reasons.contains(.manual)
            }
            return false
        }
    }
}

// MARK: - Status pill

struct LuminaStatusPill: View {
    enum Style: Equatable {
        case status(LuminaDisplayState)
        case accent
        case neutral
    }

    var style: Style
    var icon: String? = nil
    var text: String? = nil
    var help: String? = nil
    var batteryThreshold: Int? = nil
    var usesAdjustCopy: Bool = false
    var onTap: (() -> Void)? = nil

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @State private var isHovered = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let label = resolvedText
        let tip = resolvedHelp
        Group {
            if let onTap, !label.isEmpty {
                Button(action: onTap) {
                    pillContent(label: label, tappable: true)
                }
                .buttonStyle(LuminaPressableButtonStyle())
                .focusEffectDisabled()
            } else if !label.isEmpty {
                pillContent(label: label, tappable: false)
            }
        }
        .help(tip)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }

    private var resolvedText: String {
        if let text { return text }
        if case .status(let state) = style {
            return state.pillText(batteryThreshold: batteryThreshold)
        }
        return ""
    }

    private var resolvedHelp: String {
        if let help { return help }
        if case .status(let state) = style {
            return state.helpText(batteryThreshold: batteryThreshold, usesAdjustCopy: usesAdjustCopy)
        }
        return resolvedText
    }

    private var fillColor: Color {
        switch style {
        case .status(let state):
            return state.dotColor.opacity(0.14)
        case .accent:
            return theme.current.color.opacity(0.14)
        case .neutral:
            return Color.luminaFill
        }
    }

    private var labelColor: Color {
        switch style {
        case .neutral: return .secondary
        default: return .primary
        }
    }

    @ViewBuilder
    private func pillContent(label: String, tappable: Bool) -> some View {
        HStack(spacing: LuminaSpace.xs) {
            if case .status(let state) = style {
                Circle()
                    .fill(state.dotColor)
                    .frame(width: DisplayScale.points(6), height: DisplayScale.points(6))
            } else if let icon {
                Image(systemName: icon)
                    .font(uiScale.scaledFont(10, weight: .semibold))
                    .foregroundStyle(style == .accent ? theme.current.text(in: colorScheme) : labelColor)
            }

            Text(label)
                .font(uiScale.font(.caption).weight(.semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)

            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: DisplayScale.points(8), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, LuminaSpace.statusPillPaddingH)
        .padding(.vertical, LuminaSpace.statusPillPaddingV)
        .background(Capsule(style: .continuous).fill(fillColor))
        .overlay {
            if tappable && (isHovered || isFocused) {
                Capsule(style: .continuous)
                    .strokeBorder(theme.current.color.opacity(0.9), lineWidth: 2)
                    .padding(-3)
            }
        }
        .contentShape(Capsule(style: .continuous))
    }
}
