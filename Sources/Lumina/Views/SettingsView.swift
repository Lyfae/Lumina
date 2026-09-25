import SwiftUI
import AppKit
import ServiceManagement
import LuminaCore

/// Application-wide preferences, presented as a sheet from the manager's header.
struct SettingsView: View {
    @ObservedObject var store: WallpaperManagerStore
    var onClose: () -> Void = {}

    @Environment(PreferencesStore.self) private var prefs
    @Environment(PlaybackEngine.self) private var engine: PlaybackEngine?

    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var look = LuminaLook.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var audioManager = AmbientAudioManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var mediaAccess = MediaAccessSettings.shared

    @AppStorage("lumina.settings.selectedSection") private var selectedSectionRaw: String =
        SettingsSection.appearance.rawValue
    @FocusState private var focusedSidebarSection: SettingsSection?

    @State private var launchAtLogin: Bool = false
    @State private var loginItemError: String?
    @State private var shortcutConflicts: [ShortcutAction: String] = [:]
    @State private var shortcutCautions: [ShortcutAction: String] = [:]

    private var hotKeys: HotKeyCenter? {
        store.appDelegate?.hotKeyCenter ?? HotKeyCenter.shared
    }

    private var playbackEngine: PlaybackEngine? {
        engine ?? store.appDelegate?.playbackEngine
    }

    private var selectedSection: SettingsSection {
        SettingsSection(rawValue: selectedSectionRaw) ?? .appearance
    }

    private var hostWindowSize: CGSize {
        NSApp.windows.first(where: { $0.isMainWindow && $0.isVisible })?.frame.size
            ?? NSApp.mainWindow?.frame.size
            ?? NSScreen.main?.visibleFrame.size
            ?? CGSize(width: 1200, height: 800)
    }

    private var sheetWidth: CGFloat {
        let preferred = DisplayScale.points(760)
        let minimum = DisplayScale.points(640)
        let limit = hostWindowSize.width - DisplayScale.points(48)
        return min(preferred, max(minimum, limit))
    }

    private var sheetHeight: CGFloat {
        let preferred = DisplayScale.points(540)
        let minimum = DisplayScale.points(420)
        let limit = hostWindowSize.height - DisplayScale.points(48)
        return min(preferred, max(minimum, limit))
    }

    private var sidebarWidth: CGFloat { DisplayScale.points(190) }

    var body: some View {
        @Bindable var prefs = prefs
        return VStack(spacing: 0) {
            LuminaSheetHeader(icon: "gearshape.fill", title: "Settings", onClose: onClose)

            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)

                Rectangle()
                    .fill(Color.luminaBorder)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                settingsDetail(prefs: prefs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: sheetWidth, height: sheetHeight)
        .presentationSizing(.fitted)
        .luminaWindowBackdrop()
        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.floating, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.floating, style: .continuous)
                .strokeBorder(Color.luminaBorder, lineWidth: 1)
        )
        .tint(themeManager.current.color)
        .alert(
            "Couldn’t change Open at Login",
            isPresented: Binding(
                get: { loginItemError != nil },
                set: { if !$0 { loginItemError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { loginItemError = nil }
        } message: {
            Text(loginItemError ?? "")
        }
        .onExitCommand(perform: onClose)
        .onAppear(perform: prepareOnAppear)
        .onChange(of: router.pendingSection) { _, section in
            guard let section else { return }
            selectSection(section)
            router.pendingSection = nil
        }
        .onChange(of: focusedSidebarSection) { _, section in
            guard let section, section.rawValue != selectedSectionRaw else { return }
            selectedSectionRaw = section.rawValue
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.xs) {
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    section: section,
                    isSelected: selectedSection == section,
                    isKeyboardFocused: focusedSidebarSection == section,
                    focusedSection: $focusedSidebarSection
                ) {
                    selectSection(section)
                }
                .onMoveCommand { direction in
                    moveSidebarSelection(direction)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LuminaSpace.sm)
        .padding(.vertical, LuminaSpace.md)
        .environment(\.luminaButtonFocusRing, false)
    }

    @ViewBuilder
    private func settingsDetail(prefs: PreferencesStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LuminaSpace.lg) {
                Text(selectedSection.title)
                    .font(uiScale.font(.title).weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    sectionContent(selectedSection, prefs: prefs)
                }
                .padding(.horizontal, LuminaSpace.lg)
                .padding(.vertical, LuminaSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.luminaCard)
                .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                        .strokeBorder(Color.luminaBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, LuminaSpace.xl)
            .padding(.vertical, LuminaSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(selectedSection)
        .transition(.opacity)
        .animation(LuminaMotion.state, value: selectedSection)
    }

    private func selectSection(_ section: SettingsSection) {
        selectedSectionRaw = section.rawValue
        focusedSidebarSection = section
    }

    private func moveSidebarSelection(_ direction: MoveCommandDirection) {
        let all = SettingsSection.allCases
        guard let index = all.firstIndex(of: selectedSection) else { return }
        switch direction {
        case .up where index > 0:
            selectSection(all[index - 1])
        case .down where index < all.count - 1:
            selectSection(all[index + 1])
        default:
            break
        }
    }

    // MARK: - Section content

    @ViewBuilder
    private func sectionContent(_ section: SettingsSection, prefs: PreferencesStore) -> some View {
        switch section {
        case .appearance: appearanceContent
        case .size: sizeContent
        case .power: powerContent(prefs: prefs)
        case .music: musicContent(prefs: prefs)
        case .shortcuts: shortcutsContent
        case .privacy: privacyContent
        case .general: generalContent
        case .about: aboutContent
        }
    }

    // MARK: - Appearance

    @ViewBuilder private var appearanceContent: some View {
        SettingsPickerRow(
            title: "Theme",
            subtitle: "Lumina’s windows only. Your wallpaper isn’t affected.",
            placesControlBelow: true
        ) {
            LuminaSegmentedPicker(
                selection: appearanceBinding,
                options: AppAppearance.allCases.map {
                    LuminaSegmentedOption($0, title: $0.label, systemImage: $0.icon)
                }
            )
            .frame(maxWidth: .infinity)
        }

        LuminaDivider()

        VStack(alignment: .leading, spacing: LuminaSpace.sm) {
            HStack(alignment: .firstTextBaseline, spacing: LuminaSpace.sm) {
                Text("Accent color")
                    .font(uiScale.font(.bodyStrong))
                Spacer(minLength: 0)
                Text(themeManager.current.label)
                    .font(uiScale.font(.callout))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(AccentTheme.allCases) { theme in
                    LuminaAccentSwatch(
                        theme: theme,
                        selected: themeManager.current == theme
                    ) {
                        themeManager.set(theme)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minHeight: LuminaSpace.rowHeight, alignment: .top)
        .padding(.vertical, LuminaSpace.md)

        LuminaDivider()

        SettingsPickerRow(
            title: "Toolbar style",
            subtitle: "How Studio’s toolbars look.",
            placesControlBelow: true
        ) {
            LuminaSegmentedPicker(
                selection: materialBinding,
                options: [
                    LuminaSegmentedOption(.glass, title: "Glass"),
                    LuminaSegmentedOption(.solid, title: "Solid"),
                ]
            )
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Size & Spacing

    @ViewBuilder private var sizeContent: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.sm) {
            Text("Changes the size of text, buttons, and thumbnails.")
                .font(uiScale.font(.caption))
                .foregroundStyle(.secondary)

            HStack(spacing: LuminaSpace.sm) {
                ForEach(UIScaleManager.Preset.allCases) { preset in
                    Button {
                        LuminaMotion.animate(LuminaMotion.state) { uiScale.set(preset) }
                    } label: {
                        VStack(spacing: LuminaSpace.tight) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: DisplayScale.points(preset.sampleIconSize), weight: .semibold))
                                .foregroundStyle(uiScale.preset == preset ? themeManager.current.color : .secondary)
                            Text(preset.label)
                                .font(uiScale.font(.micro))
                                .foregroundStyle(uiScale.preset == preset ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LuminaSpace.md)
                        .background(
                            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                                .fill(uiScale.preset == preset
                                      ? themeManager.current.color.opacity(0.16)
                                      : Color.luminaFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                                .strokeBorder(
                                    uiScale.preset == preset
                                        ? themeManager.current.color.opacity(0.4)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LuminaPressableButtonStyle())
                    .luminaHoverPlate()
                    .accessibilityLabel(preset.label)
                    .accessibilityAddTraits(uiScale.preset == preset ? .isSelected : [])
                }
            }

            Text(uiScale.preset.subtitle)
                .font(uiScale.font(.caption))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, LuminaSpace.md)

        LuminaDivider()

        SettingsPickerRow(
            title: "Spacing",
            subtitle: "Space between rows and cards.",
            placesControlBelow: true
        ) {
            LuminaSegmentedPicker(
                selection: densityBinding,
                options: [
                    LuminaSegmentedOption(.tight, title: "Tight"),
                    LuminaSegmentedOption(.regular, title: "Regular"),
                    LuminaSegmentedOption(.airy, title: "Roomy"),
                ]
            )
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Power

    @ViewBuilder private func powerContent(prefs: PreferencesStore) -> some View {
        @Bindable var prefs = prefs

        SettingsPickerRow(
            title: "Power preset",
            subtitle: prefs.power.profileLabel == "Custom"
                ? "Custom. Pick a preset to reset."
                : "Sets the frame rate and heat rules below.",
            placesControlBelow: true
        ) {
            LuminaSegmentedPicker(
                selection: Binding(
                    get: { prefs.power.profile ?? .balanced },
                    set: { profile in
                        prefs.power.apply(profile)
                        store.reapplyPowerPolicy()
                    }
                ),
                options: PowerProfile.allCases.map {
                    LuminaSegmentedOption($0, title: $0.label)
                }
            )
            .frame(maxWidth: .infinity)
        }

        settingsSubheader("Pause wallpapers")

        SettingsToggleRow(title: "On battery", isOn: $prefs.power.defaults.battery.pauseOnBattery)
            .onChange(of: prefs.power.defaults.battery.pauseOnBattery) { _, _ in
                store.reapplyPowerPolicy()
            }

        LuminaDivider()

        SettingsToggleRow(
            title: "When battery is below",
            subtitle: prefs.power.defaults.battery.pauseOnBattery ? "Already paused on battery." : nil,
            isOn: $prefs.power.defaults.battery.pauseBelowEnabled
        )
        .disabled(prefs.power.defaults.battery.pauseOnBattery)
        .onChange(of: prefs.power.defaults.battery.pauseBelowEnabled) { _, _ in
            store.reapplyPowerPolicy()
        }

        if prefs.power.defaults.battery.pauseBelowEnabled,
           !prefs.power.defaults.battery.pauseOnBattery {
            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                LuminaSliderLabel(
                    title: "Threshold",
                    value: "\(Int(prefs.power.defaults.battery.pauseBelowPercent))%"
                )
                LuminaSlider(
                    value: $prefs.power.defaults.battery.pauseBelowPercent,
                    range: 5...80,
                    step: 5,
                    label: "Battery threshold"
                )
            }
            .padding(.vertical, LuminaSpace.md)
            .onChange(of: prefs.power.defaults.battery.pauseBelowPercent) { _, _ in
                store.reapplyPowerPolicy()
            }
        }

        LuminaDivider()

        SettingsToggleRow(
            title: "When a window covers the desktop",
            subtitle: "A full-screen app or window hides the wallpaper.",
            isOn: $prefs.power.defaults.pauseWhenCovered
        )
        .onChange(of: prefs.power.defaults.pauseWhenCovered) { _, _ in
            store.reapplyPowerPolicy()
        }

        LuminaDivider()

        SettingsToggleRow(title: "In Low Power Mode", isOn: $prefs.power.defaults.pauseInLowPowerMode)
            .onChange(of: prefs.power.defaults.pauseInLowPowerMode) { _, _ in
                store.reapplyPowerPolicy()
            }

        LuminaDivider()

        SettingsToggleRow(
            title: "When your Mac is hot",
            isOn: Binding(
                get: { prefs.power.defaults.thermal.pauseAt != nil },
                set: { enabled in
                    prefs.power.defaults.thermal.pauseAt = enabled ? .serious : nil
                    store.reapplyPowerPolicy()
                }
            )
        )

        settingsSubheader("Quality")

        SettingsPickerRow(
            title: "Resolution",
            subtitle: "Auto uses only what each display needs.",
            placesControlBelow: true
        ) {
            LuminaSegmentedPicker(
                selection: Binding(
                    get: { DecodeCapChoice(prefs.playback.defaultQuality) },
                    set: { choice in
                        prefs.playback.defaultQuality = choice.qualityPreset
                        store.reapplyPowerPolicy()
                    }
                ),
                options: DecodeCapChoice.allCases.map {
                    LuminaSegmentedOption($0, title: $0.label)
                }
            )
            .frame(maxWidth: .infinity)
        }

        LuminaDivider()

        SettingsPickerRow(
            title: "Frame rate",
            subtitle: "Caps GIFs and slideshows. Videos save the most power when paused.",
            placesControlBelow: true
        ) {
            LuminaSegmentedPicker(
                selection: Binding(
                    get: { FrameRateChoice(prefs.power.defaults.frameCap) },
                    set: { choice in
                        prefs.power.defaults.frameCap = choice.frameRateCap
                        store.reapplyPowerPolicy()
                    }
                ),
                options: FrameRateChoice.choices(includingSelected: prefs.power.defaults.frameCap).map {
                    LuminaSegmentedOption($0, title: $0.shortLabel)
                }
            )
            .frame(maxWidth: .infinity)
        }

        LuminaDivider()

        SettingsPickerRow(
            title: "On battery, limit frame rate to",
            subtitle: "Caps GIFs and slideshows. Videos save the most power when paused.",
            placesControlBelow: true
        ) {
            Picker("On battery, limit frame rate to", selection: Binding(
                get: { FrameRateChoice(prefs.power.defaults.battery.capOnBattery) },
                set: { choice in
                    prefs.power.defaults.battery.capOnBattery = choice.frameRateCap
                    store.reapplyPowerPolicy()
                }
            )) {
                ForEach([FrameRateChoice.native, .fps(30), .fps(24), .fps(15)]) { choice in
                    Text(choice.longLabel).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(uiScale.controlSize())
            .frame(maxWidth: DisplayScale.points(160))
        }

        LuminaDivider()

        SettingsToggleRow(
            title: "Full quality while Studio is open",
            subtitle: "So previews look right. Pauses still apply.",
            isOn: $prefs.power.defaults.fullQualityWhileStudioOpen
        )
        .onChange(of: prefs.power.defaults.fullQualityWhileStudioOpen) { _, _ in
            store.reapplyPowerPolicy()
        }

        settingsSubheader("Lock screen")

        SettingsToggleRow(
            title: "Keep music playing when locked",
            subtitle: "Wallpapers always pause while your Mac is locked.",
            isOn: $prefs.audio.keepsPlayingWhenLocked
        )

        Text("Displays can override these in Adjust → Quality & Power.")
            .font(uiScale.font(.caption))
            .foregroundStyle(.secondary)
            .padding(.top, LuminaSpace.xs)
    }

    // MARK: - Music

    @ViewBuilder private func musicContent(prefs: PreferencesStore) -> some View {
        @Bindable var prefs = prefs

        SettingsPickerRow(title: "Widget size", placesControlBelow: true) {
            LuminaSegmentedPicker(
                selection: $prefs.widget.size,
                options: [
                    LuminaSegmentedOption(.compact, title: "Compact"),
                    LuminaSegmentedOption(.regular, title: "Regular"),
                    LuminaSegmentedOption(.expanded, title: "Large"),
                ]
            )
            .frame(maxWidth: .infinity)
        }

        LuminaDivider()

        SettingsPickerRow(title: "Position", placesControlBelow: true) {
            HStack(spacing: LuminaSpace.sm) {
                LuminaCornerPicker(corner: $prefs.widget.placement.corner)
                Picker("Display", selection: Binding(
                    get: { prefs.widget.placement.display },
                    set: { prefs.widget.placement.display = $0 }
                )) {
                    Text("Main Display").tag(Optional<DisplayKey>.none)
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        let key = DisplayKey(MonitorInfo.identifier(for: screen, index: index))
                        Text(screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName)
                            .tag(Optional(key))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(uiScale.controlSize())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if prefs.widget.placement.customOrigin != nil {
            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                Button("Snap to Corner") {
                    prefs.widget.placement.customOrigin = nil
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .controlSize(.small)
                Text("You moved the widget. Snap it back to the corner.")
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, LuminaSpace.md)
        }

        LuminaDivider()

        SettingsToggleRow(
            title: "Show live waveform",
            subtitle: "Off uses less power. You can still drag to seek.",
            isOn: $prefs.widget.showsWaveform
        )

        LuminaDivider()

        SettingsToggleRow(title: "Show Up Next", isOn: $prefs.widget.showsUpNext)

        settingsSubheader("Show the widget")

        SettingsToggleRow(
            title: "When music starts",
            isOn: $prefs.widget.autoShow.whenPlaybackStarts
        )

        LuminaDivider()

        SettingsToggleRow(
            title: "When Studio is minimized",
            isOn: Binding(
                get: { prefs.widget.autoShow.whenStudioMinimized },
                set: { newValue in
                    prefs.widget.autoShow.whenStudioMinimized = newValue
                    audioManager.showWidgetWhenMinimized = newValue
                }
            )
        )
    }

    // MARK: - Shortcuts

    @ViewBuilder private var shortcutsContent: some View {
        let actions: [ShortcutAction] = [
            .togglePause, .openStudio, .toggleMusicWidget, .restartInSync, .nextSlide, .quit
        ]
        ForEach(Array(actions.enumerated()), id: \.element) { index, action in
            if index > 0 { LuminaDivider() }
            shortcutRow(action)
        }

        Text("Click a shortcut and press new keys. Press Delete to clear it.")
            .font(uiScale.font(.caption))
            .foregroundStyle(.secondary)
            .padding(.top, LuminaSpace.xs)

        LuminaDivider()

        SettingsButtonRow(title: "Restore Default Shortcuts", icon: "arrow.counterclockwise") {
            restoreDefaultShortcuts()
        }
    }

    @ViewBuilder
    private func shortcutRow(_ action: ShortcutAction) -> some View {
        let binding = hotKeys?.binding(for: action)
            ?? ShortcutBinding(combo: nil, scope: .menu)
        let isQuit = action == .quit

        VStack(alignment: .leading, spacing: LuminaSpace.hair) {
            HStack(alignment: .center, spacing: LuminaSpace.sm) {
                Text(action.settingsLabel)
                    .font(uiScale.font(.body))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LuminaShortcutRecorder(
                    actionLabel: action.settingsLabel,
                    combo: isQuit
                        ? KeyCombo(keyCode: 12, modifiers: .command)
                        : binding.combo,
                    isFixed: isQuit
                ) { combo in
                    recordShortcut(combo, for: action, scope: binding.scope)
                }

                if !isQuit {
                    Button {
                        toggleShortcutScope(action)
                    } label: {
                        Image(systemName: "globe")
                    }
                    .buttonStyle(LuminaIconButtonStyle(active: binding.scope == .global, size: .compact))
                    .help(binding.scope == .global
                          ? "Works in any app"
                          : "Works only while Lumina is open")
                    .accessibilityLabel("Use in any app")
                    .accessibilityValue(binding.scope == .global ? "On" : "Off")
                }
            }
            .frame(minHeight: LuminaSpace.rowHeight)

            if let conflict = shortcutConflicts[action] {
                Text(conflict)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(LuminaStatusColor.error)
            } else if hotKeys?.registrationErrors[action] != nil {
                Text("Another app is using this shortcut.")
                    .font(uiScale.font(.caption))
                    .foregroundStyle(LuminaStatusColor.error)
            } else if let caution = shortcutCautions[action] {
                Text(caution)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(LuminaStatusColor.paused)
            }
        }
        .padding(.vertical, LuminaSpace.md)
    }

    // MARK: - Privacy

    @ViewBuilder private var privacyContent: some View {
        MediaAccessLocationChecklist(settings: mediaAccess, showsHeader: true)

        LuminaDivider()

        SettingsButtonRow(title: "Reset to Pictures and Movies", icon: "arrow.counterclockwise") {
            mediaAccess.resetToDefaults()
        }
    }

    // MARK: - General

    @ViewBuilder private var generalContent: some View {
        @Bindable var prefs = prefs

        SettingsToggleRow(
            title: "Open at login",
            subtitle: "Opens Lumina when you log in.",
            isOn: $launchAtLogin
        )
        .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }

        LuminaDivider()

        SettingsToggleRow(
            title: "Restore wallpapers at launch",
            subtitle: "Brings back pinned wallpapers when Lumina starts. Pin one in Adjust.",
            isOn: Binding(
                get: { prefs.startup.restoreAtLaunch },
                set: { newValue in
                    prefs.startup.restoreAtLaunch = newValue
                    store.savePersistencePreference(newValue)
                }
            )
        )

        LuminaDivider()

        SettingsToggleRow(
            title: "Check for updates automatically",
            subtitle: "Checks GitHub when Lumina starts.",
            isOn: $prefs.startup.autoCheckUpdates
        )

        LuminaDivider()

        SettingsButtonRow(title: "Restart Videos Together", icon: "arrow.triangle.2.circlepath") {
            if let playbackEngine {
                playbackEngine.restartAllInSync()
            } else {
                store.restartDisplaysInSync()
            }
        }
    }

    // MARK: - About

    @ViewBuilder private var aboutContent: some View {
        SettingsButtonRow(title: "About Lumina", icon: "info.circle") {
            store.showAboutStatus()
        }
        LuminaDivider()
        SettingsButtonRow(title: "Check for Updates…", icon: "arrow.down.circle") {
            store.checkForUpdates()
        }
    }

    // MARK: - Bindings & helpers

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(get: { appearanceManager.current }, set: { appearanceManager.set($0) })
    }

    private var materialBinding: Binding<StudioLookPreferences.Material> {
        Binding(
            get: { look.material },
            set: { value in LuminaMotion.animate(LuminaMotion.state) { look.set(material: value) } }
        )
    }

    private var densityBinding: Binding<StudioLookPreferences.Density> {
        Binding(
            get: { look.density },
            set: { value in LuminaMotion.animate(LuminaMotion.state) { look.set(density: value) } }
        )
    }

    private func settingsSubheader(_ title: String) -> some View {
        Text(title)
            .font(uiScale.font(.callout).weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, LuminaSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prepareOnAppear() {
        if let pending = router.pendingSection {
            selectSection(pending)
            router.pendingSection = nil
        } else {
            focusedSidebarSection = selectedSection
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled || status == .requiresApproval)
    }

    private func recordShortcut(_ combo: KeyCombo?, for action: ShortcutAction, scope: ShortcutBinding.Scope) {
        guard let hotKeys else { return }
        shortcutConflicts[action] = nil
        shortcutCautions[action] = nil
        if let conflict = hotKeys.setBinding(combo, for: action, scope: scope) {
            switch conflict {
            case .usedBy(let other):
                shortcutConflicts[action] = "Already used by \(other.settingsLabel)."
            case .reservedBySystem:
                shortcutConflicts[action] = "macOS reserves this shortcut."
            }
            return
        }
        if let combo, scope == .global,
           combo.modifiers == .command || combo.modifiers == [.command, .shift],
           Self.isLetterKey(combo.keyCode) {
            shortcutCautions[action] = "This may block the same shortcut in other apps."
        }
    }

    private func toggleShortcutScope(_ action: ShortcutAction) {
        guard let hotKeys else { return }
        let binding = hotKeys.binding(for: action)
        let next: ShortcutBinding.Scope = binding.scope == .global ? .menu : .global
        shortcutConflicts[action] = nil
        shortcutCautions[action] = nil
        if let conflict = hotKeys.setBinding(binding.combo, for: action, scope: next) {
            switch conflict {
            case .usedBy(let other):
                shortcutConflicts[action] = "Already used by \(other.settingsLabel)."
            case .reservedBySystem:
                shortcutConflicts[action] = "macOS reserves this shortcut."
            }
            return
        }
        if next == .global, let combo = binding.combo,
           combo.modifiers == .command || combo.modifiers == [.command, .shift],
           Self.isLetterKey(combo.keyCode) {
            shortcutCautions[action] = "This may block the same shortcut in other apps."
        }
    }

    private func restoreDefaultShortcuts() {
        guard let hotKeys else { return }
        shortcutConflicts.removeAll()
        shortcutCautions.removeAll()
        _ = hotKeys.setBinding(
            KeyCombo(keyCode: 35, modifiers: [.command, .option]),
            for: .togglePause,
            scope: .global
        )
        _ = hotKeys.setBinding(
            KeyCombo(keyCode: 46, modifiers: .command),
            for: .openStudio,
            scope: .menu
        )
        _ = hotKeys.setBinding(
            KeyCombo(keyCode: 46, modifiers: [.command, .shift]),
            for: .toggleMusicWidget,
            scope: .menu
        )
        _ = hotKeys.setBinding(nil, for: .restartInSync, scope: .menu)
        _ = hotKeys.setBinding(nil, for: .nextSlide, scope: .menu)
        _ = hotKeys.setBinding(
            KeyCombo(keyCode: 12, modifiers: .command),
            for: .quit,
            scope: .menu
        )
    }

    private static func isLetterKey(_ keyCode: UInt16) -> Bool {
        // A–Z Carbon key codes commonly used for menu shortcuts.
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 31, 32, 34, 35, 37, 38, 40, 45, 46]
            .contains(keyCode)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    loginItemError = "macOS needs your OK. Turn on Lumina in System Settings → General → Login Items."
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let status = SMAppService.mainApp.status
            launchAtLogin = (status == .enabled || status == .requiresApproval)
            loginItemError = "macOS said: \(error.localizedDescription)"
        }
    }
}

// MARK: - Shortcut labels

private extension ShortcutAction {
    var settingsLabel: String {
        switch self {
        case .togglePause: return "Pause or resume all wallpapers"
        case .openStudio: return "Open Lumina Studio"
        case .toggleMusicWidget: return "Show or hide music widget"
        case .restartInSync: return "Restart videos together"
        case .nextSlide: return "Next slide"
        case .quit: return "Quit Lumina"
        }
    }
}

// MARK: - Row system

private struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    @StateObject private var uiScale = UIScaleManager.shared
    @ObservedObject private var look = LuminaLook.shared

    private var toggleSize: ControlSize {
        if look.density == .airy || uiScale.preset == .large { return .regular }
        return .small
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                Text(title).font(uiScale.font(.bodyStrong))
                if let subtitle {
                    Text(subtitle)
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: LuminaSpace.sm)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(toggleSize)
                .accessibilityLabel(title)
        }
        .frame(minHeight: LuminaSpace.rowHeight, alignment: .center)
        .padding(.vertical, LuminaSpace.md)
    }
}

private struct SettingsPickerRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var placesControlBelow: Bool = false
    @ViewBuilder var control: () -> Control

    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        Group {
            if placesControlBelow {
                VStack(alignment: .leading, spacing: LuminaSpace.sm) {
                    titleBlock
                    control()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: LuminaSpace.sm) {
                    titleBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                    control()
                }
            }
        }
        .frame(minHeight: LuminaSpace.rowHeight, alignment: .center)
        .padding(.vertical, LuminaSpace.md)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.xs) {
            Text(title).font(uiScale.font(.bodyStrong))
            if let subtitle {
                Text(subtitle)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsButtonRow: View {
    let title: String
    let icon: String
    var action: () -> Void

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: LuminaSpace.sm) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.card)))
                    .foregroundStyle(theme.current.color)
                    .frame(width: DisplayScale.points(24))
                Text(title).font(uiScale.font(.bodyStrong))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: uiScale.iconSize(.inline)))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: LuminaSpace.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .luminaHoverPlate()
        .padding(.vertical, LuminaSpace.md)
    }
}

// MARK: - Sidebar row

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let isKeyboardFocused: Bool
    var focusedSection: FocusState<SettingsSection?>.Binding
    var action: () -> Void

    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var theme = ThemeManager.shared
    @State private var isHovered = false

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
    }

    var body: some View {
        HStack(spacing: LuminaSpace.sm) {
            Image(systemName: section.icon)
                .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.current.color)
                .frame(width: DisplayScale.points(20))
            Text(section.title)
                .font(uiScale.font(.bodyStrong))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LuminaSpace.sm)
        .frame(minHeight: LuminaSpace.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowShape.fill(rowFill))
        .overlay {
            if isKeyboardFocused {
                RoundedRectangle(cornerRadius: LuminaRadius.control + 3, style: .continuous)
                    .strokeBorder(theme.current.color.opacity(0.9), lineWidth: 2)
                    .padding(-3)
            }
        }
        .onTapGesture(perform: action)
        .focusable()
        .focused(focusedSection, equals: section)
        .focusEffectDisabled()
        .onKeyPress(.return) { action(); return .handled }
        .onKeyPress(.space) { action(); return .handled }
        .onHover { isHovered = $0 }
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text("Select")) { action() }
    }

    private var rowFill: Color {
        if isSelected {
            return theme.current.color.opacity(0.22)
        }
        if isHovered {
            return Color.luminaFillHover
        }
        return .clear
    }
}
