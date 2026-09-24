import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records a keyboard shortcut. Bindings go through `HotKeyCenter.shared`.
struct LuminaShortcutRecorder: View {
    let actionLabel: String
    var combo: KeyCombo?
    var isFixed: Bool = false
    var onRecord: (KeyCombo?) -> Void

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var monitor = ShortcutRecorderMonitor()
    @State private var isHovered = false
    @State private var cautionMessage: String? = nil

    private var isRecording: Bool { monitor.isRecording }

    var body: some View {
        HStack(spacing: LuminaSpace.xs) {
            Button {
                guard !isFixed else { return }
                startRecording()
            } label: {
                Text(displayText)
                    .font(uiScale.font(.callout).weight(.semibold).monospaced())
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(isFixed)

            if isHovered, combo != nil, !isFixed, !isRecording {
                Button {
                    onRecord(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DisplayScale.points(14)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear shortcut")
            }
        }
        .padding(.horizontal, LuminaSpace.sm)
        .frame(height: DisplayScale.points(28))
        .frame(minWidth: DisplayScale.points(112))
        .background(
            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                .fill(isRecording ? theme.current.color.opacity(0.08) : Color.luminaFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isRecording ? 1.5 : 1)
        )
        .onHover { isHovered = $0 }
        .help(isFixed ? "Quit is always ⌘Q." : actionLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(actionLabel) shortcut")
        .accessibilityValue(combo?.spokenDescription ?? "None")
        .accessibilityHint("Press to record a new shortcut")
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .bottom) {
            if let cautionMessage {
                Text(cautionMessage)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(LuminaStatusColor.paused)
                    .fixedSize()
                    .offset(y: DisplayScale.points(16))
            }
        }
        .onDisappear { monitor.stop() }
    }

    private var displayText: String {
        if isRecording {
            if monitor.liveModifiers.isEmpty {
                return "Type shortcut…"
            }
            return monitor.liveModifiers.symbolString + "…"
        }
        if let combo {
            return combo.displayString
        }
        return "None"
    }

    private var textColor: Color {
        if isRecording { return theme.current.color }
        if combo == nil { return .secondary }
        return .primary
    }

    private var borderColor: Color {
        if isRecording { return theme.current.color }
        if isHovered { return Color.luminaFillPressed }
        return Color.luminaBorder
    }

    private func startRecording() {
        cautionMessage = nil
        monitor.start { event in
            handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        let mods = KeyCombo.Modifiers(nsFlags: event.modifierFlags)

        if event.type == .flagsChanged {
            monitor.liveModifiers = mods
            return
        }

        guard event.type == .keyDown else { return }

        let keyCode = UInt16(event.keyCode)

        if keyCode == 53 {
            monitor.stop()
            return
        }

        if (keyCode == 51 || keyCode == 117), mods.isEmpty {
            onRecord(nil)
            monitor.stop()
            return
        }

        let hasChord = mods.contains(.command) || mods.contains(.option) || mods.contains(.control)
        if !hasChord {
            showCaution("Add ⌘, ⌥, or ⌃")
            monitor.liveModifiers = mods
            return
        }

        onRecord(KeyCombo(keyCode: keyCode, modifiers: mods))
        monitor.stop()
    }

    private func showCaution(_ message: String) {
        cautionMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if cautionMessage == message { cautionMessage = nil }
        }
    }
}

@MainActor
private final class ShortcutRecorderMonitor: ObservableObject {
    @Published var isRecording = false
    @Published var liveModifiers: KeyCombo.Modifiers = []
    private var monitor: Any?

    func start(handler: @escaping (NSEvent) -> Void) {
        stop()
        isRecording = true
        liveModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handler(event)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        liveModifiers = []
    }
}

// MARK: - KeyCombo display

extension KeyCombo {
    var displayString: String {
        modifiers.symbolString + KeyCombo.keyName(keyCode: keyCode)
    }

    var spokenDescription: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(KeyCombo.spokenKeyName(keyCode: keyCode))
        return parts.joined(separator: " ")
    }

    static func keyName(keyCode: UInt16) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        return translatedCharacter(keyCode: keyCode)?.uppercased() ?? "Key\(keyCode)"
    }

    static func spokenKeyName(keyCode: UInt16) -> String {
        if let spoken = spokenSpecialKeys[keyCode] { return spoken }
        return translatedCharacter(keyCode: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    private static let specialKeyNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let spokenSpecialKeys: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        117: "Forward Delete", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func translatedCharacter(keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            var deadKeyState: UInt32 = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}

extension KeyCombo.Modifiers {
    var symbolString: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    init(nsFlags: NSEvent.ModifierFlags) {
        var mods = KeyCombo.Modifiers()
        if nsFlags.contains(.command) { mods.insert(.command) }
        if nsFlags.contains(.shift) { mods.insert(.shift) }
        if nsFlags.contains(.option) { mods.insert(.option) }
        if nsFlags.contains(.control) { mods.insert(.control) }
        self = mods
    }
}
