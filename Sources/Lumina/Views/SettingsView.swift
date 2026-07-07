import SwiftUI
import AppKit
import ServiceManagement

/// Application-wide preferences, presented as a sheet from the manager's header.
///
/// These are *generic app settings* (appearance, startup, battery behavior) — distinct
/// from the per-monitor wallpaper settings in `MonitorDetailPanel`.
struct SettingsView: View {
    @ObservedObject var store: WallpaperManagerStore
    var onClose: () -> Void = {}

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var audioManager = AmbientAudioManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var mediaAccess = MediaAccessSettings.shared

    // Launch-at-login mirrors the system service status.
    @State private var launchAtLogin: Bool = false
    /// Non-nil when a login-item register/unregister attempt failed; drives an explanatory alert.
    @State private var loginItemError: String?

    // PowerManager toggles. PowerManager isn't observable, so we mirror its values
    // in local state and write changes straight back through `store.appDelegate`.
    @State private var pauseOnLowPower: Bool = true
    @State private var pauseOnHighThermal: Bool = true
    @State private var pauseWhenFullscreen: Bool = true
    @State private var performanceProfile: PowerManager.PerformanceProfile = .balanced

    private var powerManager: PowerManager? { store.appDelegate?.powerManager }

    var body: some View {
        VStack(spacing: 0) {
            header
            LuminaDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appearanceSection
                    interfaceSection
                    privacySection
                    generalSection
                    batterySection
                    aboutSection
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)
        }
        .scaledFrame(width: 460, height: 620)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
        .alert("Couldn’t change Launch at Login",
               isPresented: Binding(get: { loginItemError != nil },
                                    set: { if !$0 { loginItemError = nil } })) {
            Button("OK", role: .cancel) { loginItemError = nil }
        } message: {
            Text(loginItemError ?? "")
        }
        .onAppear(perform: loadCurrentValues)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Settings", systemImage: "gearshape.fill")
                .font(.title3.bold())
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close settings")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.bar)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsCard(icon: "paintbrush.fill", title: "Appearance") {
            settingRow(
                title: "Theme",
                subtitle: "Controls Lumina's windows — not the wallpaper itself."
            ) {
                Picker("", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
            }

            LuminaDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Accent Color")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    ForEach(AccentTheme.allCases) { theme in
                        Button { themeManager.set(theme) } label: {
                            Circle()
                                .fill(theme == .system ? AnyShapeStyle(Color.secondary.opacity(0.6)) : AnyShapeStyle(theme.color))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(themeManager.current == theme ? Color.primary : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(theme.label)
                        .accessibilityLabel(theme.label)
                        .accessibilityHint("Select accent color")
                        .accessibilityAddTraits(themeManager.current == theme ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: - Interface scale

    private var interfaceSection: some View {
        SettingsCard(icon: "textformat.size", title: "Interface Size") {
            settingRow(
                title: "Icon & control scale",
                subtitle: "Make buttons, thumbnails, and toolbar icons larger or more compact."
            ) {
                Picker("", selection: uiScaleBinding) {
                    ForEach(UIScaleManager.Preset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: DisplayScale.points(14)) {
                ForEach(UIScaleManager.Preset.allCases) { preset in
                    VStack(spacing: DisplayScale.points(6)) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: preset.sampleIconSize, weight: .semibold))
                            .foregroundStyle(uiScale.preset == preset ? themeManager.current.color : .secondary)
                        Text(preset.label)
                            .font(.system(size: DisplayScale.points(10), weight: .medium))
                            .foregroundStyle(uiScale.preset == preset ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DisplayScale.points(10))
                    .background(
                        RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                            .fill(uiScale.preset == preset ? themeManager.current.color.opacity(0.12) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
                            .strokeBorder(uiScale.preset == preset ? themeManager.current.color.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { uiScale.set(preset) }
                }
            }

            Text(uiScale.preset.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var uiScaleBinding: Binding<UIScaleManager.Preset> {
        Binding(get: { uiScale.preset }, set: { uiScale.set($0) })
    }

    // MARK: - Privacy

    private var privacySection: some View {
        SettingsCard(icon: "hand.raised.fill", title: "Privacy") {
            toggleRow(
                title: "Allow Documents & Downloads",
                subtitle: "When off, Lumina only uses files from Pictures and Movies (Photos & video library). Turn on to also pick wallpapers from Documents or Downloads.",
                isOn: $mediaAccess.allowDocumentsAndDownloads
            )

            Text(MediaAccessPolicy.restrictionHint())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        SettingsCard(icon: "gearshape.2.fill", title: "General") {
            toggleRow(
                title: "Launch at login",
                subtitle: "Start Lumina automatically when you sign in.",
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }

            LuminaDivider()

            toggleRow(
                title: "Remember wallpapers on startup",
                subtitle: "Restore each display's wallpaper when Lumina launches.",
                isOn: Binding(
                    get: { store.persistAssignments },
                    set: { store.savePersistencePreference($0) }
                )
            )

            LuminaDivider()

            toggleRow(
                title: "Sync playback across displays",
                subtitle: "Lock all video wallpapers to the same playback position.",
                isOn: Binding(
                    get: { store.syncPlaybackAcrossDisplays },
                    set: { store.setSyncPlayback($0) }
                )
            )

            LuminaDivider()

            toggleRow(
                title: "Show music widget when minimized",
                subtitle: "Pop a floating now-playing mini-player when you minimize the Studio window.",
                isOn: Binding(
                    get: { audioManager.showWidgetWhenMinimized },
                    set: { audioManager.showWidgetWhenMinimized = $0 }
                )
            )

            LuminaDivider()

            toggleRow(
                title: "Automatically check for updates",
                subtitle: "Check GitHub for new versions on launch (shows a notification when available).",
                isOn: Binding(
                    get: {
                        if UserDefaults.standard.object(forKey: "Lumina.AutoCheckUpdates") == nil { return true }
                        return UserDefaults.standard.bool(forKey: "Lumina.AutoCheckUpdates")
                    },
                    set: { UserDefaults.standard.set($0, forKey: "Lumina.AutoCheckUpdates") }
                )
            )
        }
    }

    // MARK: - Battery & Performance

    private var batterySection: some View {
        SettingsCard(icon: "bolt.fill", title: "Battery & Performance") {
            toggleRow(
                title: "Pause in Low Power Mode",
                subtitle: "Stop wallpaper playback while Low Power Mode is on.",
                isOn: $pauseOnLowPower
            )
            .onChange(of: pauseOnLowPower) { _, v in
                powerManager?.pauseOnLowPowerMode = v
                store.reapplyPowerPolicy()
            }

            LuminaDivider()

            toggleRow(
                title: "Pause when running hot",
                subtitle: "Stop playback if the Mac reaches a high thermal state.",
                isOn: $pauseOnHighThermal
            )
            .onChange(of: pauseOnHighThermal) { _, v in
                powerManager?.pauseOnHighThermal = v
                store.reapplyPowerPolicy()
            }

            LuminaDivider()

            toggleRow(
                title: "Pause behind fullscreen apps",
                subtitle: "Save power when a fullscreen window covers the wallpaper.",
                isOn: $pauseWhenFullscreen
            )
            .onChange(of: pauseWhenFullscreen) { _, v in
                powerManager?.respectFullscreenApps = v
                store.reapplyPowerPolicy()
            }

            LuminaDivider()

            settingRow(
                title: "Performance profile",
                subtitle: "Balance battery savings against playback smoothness."
            ) {
                Picker("", selection: $performanceProfile) {
                    ForEach(PowerManager.PerformanceProfile.allCases) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .onChange(of: performanceProfile) { _, v in
                    powerManager?.performanceProfile = v
                    store.reapplyPowerPolicy()
                }
            }
        }
    }

    // MARK: - About & Help

    private var aboutSection: some View {
        SettingsCard(icon: "info.circle.fill", title: "About & Help") {
            linkRow(title: "About & Status", icon: "info.circle") { store.showAboutStatus() }
            LuminaDivider()
            linkRow(title: "Check for Updates", icon: "arrow.down.circle") { store.checkForUpdates() }
        }
    }

    @ViewBuilder
    private func linkRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(themeManager.current.color)
                    .frame(width: 18)
                Text(title).font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable Rows

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(get: { appearanceManager.current }, set: { appearanceManager.set($0) })
    }

    @ViewBuilder
    private func settingRow<Trailing: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            trailing()
        }
    }

    @ViewBuilder
    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Actions

    private func loadCurrentValues() {
        // `.requiresApproval` means it's registered but the user must flip it on in
        // System Settings → General → Login Items; treat that as "on" so the toggle matches.
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled || status == .requiresApproval)
        if let pm = powerManager {
            pauseOnLowPower = pm.pauseOnLowPowerMode
            pauseOnHighThermal = pm.pauseOnHighThermal
            pauseWhenFullscreen = pm.respectFullscreenApps
            performanceProfile = pm.performanceProfile
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                // Registration can succeed but still need the user's approval.
                if SMAppService.mainApp.status == .requiresApproval {
                    loginItemError = "Lumina is registered, but macOS needs your approval. "
                        + "Open System Settings → General → Login Items and enable Lumina."
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle to reflect the real (unchanged) status and explain why.
            let status = SMAppService.mainApp.status
            launchAtLogin = (status == .enabled || status == .requiresApproval)
            loginItemError = "macOS reported: \(error.localizedDescription)"
        }
    }
}

// MARK: - Settings Card

/// A titled container matching the visual language of the per-monitor settings groups.
private struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DisplayScale.points(10)) {
                Image(systemName: icon)
                    .font(.system(size: UIScaleManager.shared.iconSize(.card), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: DisplayScale.points(22))
                Text(title)
                    .font(.system(size: DisplayScale.points(14), weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.luminaCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.luminaBorder, lineWidth: 1))
    }
}
