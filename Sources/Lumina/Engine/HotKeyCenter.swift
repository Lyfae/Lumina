// Lumina/Engine/HotKeyCenter — Carbon RegisterEventHotKey for global shortcuts.
import AppKit
import Carbon.HIToolbox
import Observation
import LuminaCore

/// System-wide shortcuts via Carbon `RegisterEventHotKey` (no Accessibility permission).
/// Menu keyEquivalents are derived from the same bindings for StatusMenuController.
@MainActor
final class HotKeyCenter {
    private let prefs: PreferencesStore
    private let perform: @MainActor (ShortcutAction) -> Void
    private var registered: [ShortcutAction: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private(set) var registrationErrors: [ShortcutAction: String] = [:]

    nonisolated static let signature: OSType = 0x4C554D4E // 'LUMN'
    static weak var shared: HotKeyCenter?

    init(preferences: PreferencesStore, perform: @escaping @MainActor (ShortcutAction) -> Void) {
        self.prefs = preferences
        self.perform = perform
        Self.shared = self
        installHandler()
        syncFromPreferences()
        observePreferences()
    }

    deinit {
        // Unregister on teardown path via `teardown()` — deinit can't touch MainActor state safely.
    }

    func teardown() {
        for (_, ref) in registered {
            UnregisterEventHotKey(ref)
        }
        registered.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if Self.shared === self { Self.shared = nil }
    }

    // MARK: - UI binding API (Settings ShortcutsSection binds here)

    func actions() -> [ShortcutAction] { ShortcutAction.allCases }

    func binding(for action: ShortcutAction) -> ShortcutBinding {
        prefs.shortcuts[action]
    }

    /// Sets or clears a binding. Returns a conflict if refused (prefs unchanged on conflict).
    @discardableResult
    func setBinding(
        _ combo: KeyCombo?,
        for action: ShortcutAction,
        scope: ShortcutBinding.Scope
    ) -> ShortcutPreferences.Conflict? {
        var shortcuts = prefs.shortcuts
        if let conflict = shortcuts.bind(combo, to: action, scope: scope) {
            return conflict
        }
        prefs.shortcuts = shortcuts
        syncFromPreferences()
        return nil
    }

    func clearBinding(for action: ShortcutAction) {
        _ = setBinding(nil, for: action, scope: prefs.shortcuts[action].scope)
    }

    /// For StatusMenuController: (keyEquivalent, modifierMask) for a menu-scoped action.
    func menuEquivalent(for action: ShortcutAction) -> (String, NSEvent.ModifierFlags)? {
        let binding = prefs.shortcuts[action]
        guard binding.scope == .menu, let combo = binding.combo else { return nil }
        guard let character = Self.keyEquivalentCharacter(keyCode: combo.keyCode) else { return nil }
        return (character, Self.nsModifiers(combo.modifiers))
    }

    // MARK: - Registration

    func syncFromPreferences() {
        var desired: [ShortcutAction: KeyCombo] = [:]
        registrationErrors.removeAll()
        for action in ShortcutAction.allCases {
            let binding = prefs.shortcuts[action]
            guard binding.scope == .global, let combo = binding.combo else { continue }
            desired[action] = combo
        }

        for action in registered.keys where desired[action] == nil {
            if let ref = registered.removeValue(forKey: action) {
                UnregisterEventHotKey(ref)
            }
        }

        for (action, combo) in desired {
            if let existing = registered[action] {
                // Re-register if combo changed (simplest: always replace).
                UnregisterEventHotKey(existing)
                registered.removeValue(forKey: action)
            }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(action.hotKeyID))
            let status = RegisterEventHotKey(
                UInt32(combo.keyCode),
                Self.carbonModifiers(combo.modifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registered[action] = ref
            } else {
                registrationErrors[action] = "Shortcut already in use by another app"
            }
        }
    }

    private func observePreferences() {
        withObservationTracking {
            _ = prefs.shortcuts
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncFromPreferences()
                self?.observePreferences()
            }
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        if status != noErr {
            LuminaLog.app.error("HotKeyCenter: InstallEventHandler failed (\(status))")
        }
    }

    func handleHotKey(id: UInt32) {
        guard let action = ShortcutAction.from(hotKeyID: Int(id)) else { return }
        perform(action)
    }

    private static func carbonModifiers(_ mods: KeyCombo.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if mods.contains(.command) { result |= UInt32(cmdKey) }
        if mods.contains(.shift) { result |= UInt32(shiftKey) }
        if mods.contains(.option) { result |= UInt32(optionKey) }
        if mods.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    private static func nsModifiers(_ mods: KeyCombo.Modifiers) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if mods.contains(.command) { result.insert(.command) }
        if mods.contains(.shift) { result.insert(.shift) }
        if mods.contains(.option) { result.insert(.option) }
        if mods.contains(.control) { result.insert(.control) }
        return result
    }

    private static func keyEquivalentCharacter(keyCode: UInt16) -> String? {
        // Common menu equivalents; Settings recorder UI will expand later.
        switch keyCode {
        case 12: return "q" // Q
        case 35: return "p" // P
        case 46: return "m" // M
        case 15: return "r" // R
        case 45: return "n" // N
        default: return nil
        }
    }
}

private func hotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr, hotKeyID.signature == HotKeyCenter.signature else { return noErr }
    let id = hotKeyID.id
    Task { @MainActor in
        HotKeyCenter.shared?.handleHotKey(id: id)
    }
    return noErr
}

private extension ShortcutAction {
    var hotKeyID: Int {
        switch self {
        case .togglePause: return 1
        case .openStudio: return 2
        case .toggleMusicWidget: return 3
        case .restartInSync: return 4
        case .nextSlide: return 5
        case .quit: return 6
        }
    }

    static func from(hotKeyID: Int) -> ShortcutAction? {
        switch hotKeyID {
        case 1: return .togglePause
        case 2: return .openStudio
        case 3: return .toggleMusicWidget
        case 4: return .restartInSync
        case 5: return .nextSlide
        case 6: return .quit
        default: return nil
        }
    }
}
