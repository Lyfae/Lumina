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
    @StateObject private var sizeManager = WindowSizeManager.shared

    // Launch-at-login mirrors the system service status.
    @State private var launchAtLogin: Bool = false

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
                    generalSection
                    batterySection
                    aboutSection
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 460, height: 560)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
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
                    }
                }
            }

            LuminaDivider()

            settingRow(
                title: "Window size",
                subtitle: "Pick a native resolution for the Studio window — crisp at every size, up to the largest your display supports."
            ) {
                Picker("", selection: Binding(
                    get: { sizeManager.size },
                    set: { sizeManager.size = $0 }
                )) {
                    ForEach(sizeOptions, id: \.self) { s in
                        Text("\(Int(s.width)) × \(Int(s.height))").tag(s)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
        }
    }

    /// Window-size presets for the current display, always including the active selection.
    private var sizeOptions: [CGSize] {
        var opts = sizeManager.presets(for: NSScreen.main)
        if !opts.contains(where: { $0 == sizeManager.size }) {
            opts.insert(sizeManager.size, at: 0)
        }
        return opts
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
            linkRow(title: "Welcome to Lumina", icon: "hand.wave") { store.showWelcomeScreen() }
            LuminaDivider()
            linkRow(title: "What's New", icon: "sparkles") { store.showCurrentChangelog() }
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
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
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
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle to reflect the real (unchanged) status on failure.
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            NSSound.beep()
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.subheadline.weight(.semibold))
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
