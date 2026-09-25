// Lumina — menu-bar live wallpaper (PlaybackEngine + Reconciler cutover, steps 5–8).
import AppKit
import AVFoundation
import SwiftUI

@main
@MainActor
final class LuminaApp: NSObject, NSApplicationDelegate, NSMenuDelegate {

    var preferencesStore: PreferencesStore!
    var playbackEngine: PlaybackEngine!
    /// UI binds ShortcutsSection here (`actions()`, `binding(for:)`, `setBinding`, `clearBinding`).
    var hotKeyCenter: HotKeyCenter?
    private var currentVideoURL: URL?
    private var currentVideoURLMonitorID: String?
    private var statusMenuItem: NSMenuItem!
    private var pauseAllMenuItem: NSMenuItem!
    private var statusItem: NSStatusItem!
    private var wallpaperManagerWindow: WallpaperManagerWindowController?

    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            _ = NSApplication.shared
            exit(SelfTest.run())
        }
        if CommandLine.arguments.contains("--window-test") {
            SelfTest.runWindowTest()
            return
        }
        if CommandLine.arguments.contains("--occlusion-test") {
            SelfTest.runOcclusionTest()
            return
        }
        let app = NSApplication.shared
        let delegate = LuminaApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = PreferencesStore(backend: UserDefaultsBackend(.standard))
        preferencesStore = prefs
        ThemeManager.shared.attach(preferences: prefs)
        AppearanceManager.shared.attach(preferences: prefs)
        UIScaleManager.shared.attach(preferences: prefs)
        MediaAccessSettings.shared.attach(preferences: prefs)
        AmbientAudioManager.shared.attach(preferences: prefs)
        AppChrome.apply(studio: prefs.studio)

        SplashWindowController.present { [weak self] in
            DispatchQueue.main.async {
                LuminaLog.app.info("Splash finished — opening Lumina Studio")
                self?.openWallpaperManager()
            }
        }

        setupStatusItem()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshStatusBarIcon),
            name: .luminaUIScaleDidChange, object: nil
        )

        let engine = PlaybackEngine(preferences: prefs)
        playbackEngine = engine
        engine.start()

        hotKeyCenter = HotKeyCenter(preferences: prefs) { [weak self] action in
            self?.performShortcut(action)
        }

        setupPlaybackHealthMonitor()
        updateStatusItemFromEngine()

        LuminaLog.app.info("Lumina started (PlaybackEngine). Studio opens after splash.")

        if prefs.startup.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.checkForUpdates(silent: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        preferencesStore?.flush()
        hotKeyCenter?.teardown()
        PlaybackHealthMonitor.shared.stop()
        updateCheckTask?.cancel()
        playbackEngine?.teardown()
        LuminaLog.app.info("Shutdown complete.")
    }

    /// Engine-side shortcut dispatch. Menu item titles/equivalents are a UI leftover.
    private func performShortcut(_ action: ShortcutAction) {
        switch action {
        case .togglePause:
            playbackEngine?.togglePause()
            updateStatusItemFromEngine()
        case .openStudio:
            openWallpaperManager()
        case .toggleMusicWidget:
            NowPlayingWidgetController.shared.toggle()
        case .restartInSync:
            playbackEngine?.restartAllInSync()
        case .nextSlide:
            break // Slideshow advance per-display is a UI/engine follow-up
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func setupPlaybackHealthMonitor() {
        let health = PlaybackHealthMonitor.shared
        health.snapshotProvider = { [weak self] in
            self?.playbackEngine?.healthSnapshots() ?? []
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackHealthDidChange),
            name: .luminaPlaybackHealthDidChange,
            object: nil
        )
        health.start()
    }

    @objc private func playbackHealthDidChange() {
        updateStatusItemFromEngine()
    }

    func reapplyPowerPolicy() {
        // Planner re-reads prefs via Observation; nudge a no-op write path by toggling nothing.
        // PowerSignals + prefs observation already replan. Keep API for Settings.
        updateStatusItemFromEngine()
    }

    func restartDisplaysInSync() {
        playbackEngine?.restartAllInSync()
    }

    func setPlaybackSyncEnabled(_ enabled: Bool) {
        // Shared sources replace the drift watcher (step 8).
        _ = enabled
    }

    func clearRenderer(for monitorID: String) {
        clearMonitor(monitorID: monitorID)
    }

    func clearMonitor(monitorID: String) {
        preferencesStore?.removeWallpaperAssignment(for: monitorID)
        if monitorID == currentVideoURLMonitorID { currentVideoURL = nil }
        updateStatusItemFromEngine()
        LuminaLog.app.info("Cleared wallpaper for \(monitorID)")
    }

    func assignVideoToMonitor(monitorID: String, url: URL) {
        guard MediaAccessPolicy.accept(url) else { return }
        guard let prefs = preferencesStore else { return }
        _ = FileAccess.registerUserSelectedFile(url)
        let ref = prefs.mediaReference(from: url)
        var wallpaper = prefs.wallpapers[display: DisplayKey(monitorID)]
        wallpaper.content = .media(ref)
        var next = prefs.wallpapers
        next[display: DisplayKey(monitorID)] = wallpaper
        prefs.wallpapers = next

        currentVideoURL = url
        currentVideoURLMonitorID = monitorID
        updateStatusItemFromEngine()
        LuminaLog.wallpaper.info("Assigned \(ref.kind) to \(monitorID): \(url.lastPathComponent)")
    }

    func assignVideoToMonitor(index: Int, url: URL) {
        let screens = NSScreen.screens
        guard index < screens.count else { return }
        assignVideoToMonitor(monitorID: MonitorInfo.identifier(for: screens[index], index: index), url: url)
    }

    private func updateStatusItemFromEngine() {
        let button = statusItem?.button
        button?.image = makeStatusBarIcon()
        button?.title = ""
        let headline = playbackEngine?.summary?.headline ?? "Lumina"
        let filename = currentVideoURL?.lastPathComponent
        let health = PlaybackHealthMonitor.shared
        var tip = filename.map { "\(headline) – \($0)" } ?? headline
        if health.isStruggling {
            tip += "\n⚠ \(health.reason)"
        }
        button?.toolTip = tip
        // Also drive Studio window activity flag for fullQualityWhileStudioOpen
        playbackEngine?.setStudioVisible(wallpaperManagerWindow?.window?.isVisible == true)
    }


    @objc private func openWallpaperManager() {
        if wallpaperManagerWindow == nil {
            wallpaperManagerWindow = WallpaperManagerWindowController(appDelegate: self)
        }

        guard let controller = wallpaperManagerWindow else { return }
        controller.showWindow(nil)
        // Accessory (LSUIElement) apps need an explicit key/orderFront + activate or the
        // window can stay invisible after a non-activating splash tears down.
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // First-run: onboarding only (after splash → Studio). Do not stack Choose Display
        // or About on top — those stay available from Studio / the menu.
        self.maybeShowOnboardingForManager()

        // Changelog only after onboarding has been completed (avoids a third window).
        if preferencesStore?.milestones.hasShownOnboarding == true {
            self.checkForNewVersionAndShowChangelogIfNeeded()
        }
    }

    private var onboardingWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?
    private var updateWindowController: NSWindowController?
    private var updateCheckTask: Task<Void, Never>?

    private func showOnboarding(forced: Bool = false) {
        if !forced && preferencesStore?.milestones.hasShownOnboarding == true {
            return
        }
        if let existing = onboardingWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: OnboardingView {
                if let prefs = self.preferencesStore {
                    prefs.milestones.hasShownOnboarding = true
                }
                self.onboardingWindowController?.close()
                self.onboardingWindowController = nil
                // Safe to surface version notes now that welcome is done.
                self.checkForNewVersionAndShowChangelogIfNeeded()
            }
            .environment(self.preferencesStore)
        )

        let size = DisplayScale.nsSize(width: 520, height: 640)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Lumina Studio"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        self.onboardingWindowController = controller

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Shows onboarding once when the manager opens for the first time.
    func maybeShowOnboardingForManager() {
        guard preferencesStore?.milestones.hasShownOnboarding != true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showOnboarding()
        }
    }
    
    /// Opens About & Status (welcome copy, live status, full changelog).
    @objc func showAboutStatus() {
        if let existing = aboutWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: AboutStatusView(
                appVersion: currentVersion,
                buildNumber: currentBuildNumber,
                statusSummary: buildStatusSummary(),
                onPrintDebug: { [weak self] in self?.printDebugStatus() },
                onOpenTestingGuide: { [weak self] in self?.openTestingDocInFinder() },
                onClose: { [weak self] in
                    if let self, let prefs = self.preferencesStore {
                        prefs.milestones.lastShownChangelogVersion = self.currentVersion
                    }
                    self?.aboutWindowController?.close()
                    self?.aboutWindowController = nil
                }
            )
        )

        let size = DisplayScale.nsSize(width: 540, height: 620)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Lumina Studio"
        window.contentViewController = hosting
        window.contentMinSize = size
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Lumina.AboutStatus")
        window.center()

        let controller = NSWindowController(window: window)
        aboutWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Checks GitHub for a newer release. When `silent` is true, only prompts if an update exists.
    func checkForUpdates(silent: Bool = false) {
        updateCheckTask?.cancel()
        updateCheckTask = Task { [weak self] in
            guard let self else { return }
            let result = await UpdateChecker.check(currentVersion: currentVersion)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                switch result {
                case .upToDate:
                    if !silent {
                        let alert = NSAlert()
                        alert.messageText = "You're Up to Date"
                        alert.informativeText = "Lumina \(self.currentVersion) is the latest release on GitHub."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                case .updateAvailable(let info):
                    self.presentUpdateSheet(info)
                case .error(let message):
                    if !silent {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = message
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Open Releases")
                        alert.addButton(withTitle: "Cancel")
                        if alert.runModal() == .alertFirstButtonReturn {
                            UpdateChecker.openReleasesPage()
                        }
                    } else {
                        LuminaLog.app.info("Silent update check failed: \(message)")
                    }
                }
            }
        }
    }

    private func presentUpdateSheet(_ info: UpdateChecker.ReleaseInfo) {
        if let existing = updateWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: UpdateAvailableView(
                currentVersion: currentVersion,
                newVersion: info.version,
                downloadURL: info.downloadURL,
                onInstall: { dmgURL in
                    NSWorkspace.shared.open(dmgURL)
                },
                onLater: { [weak self] in
                    self?.updateWindowController?.close()
                    self?.updateWindowController = nil
                }
            )
        )

        let size = DisplayScale.nsSize(width: 420, height: 380)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Update Available"
        window.contentViewController = hosting
        window.contentMinSize = size
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        updateWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func buildStatusSummary() -> String {
        let loaded = currentVideoURL?.lastPathComponent ?? "None"
        let decoders = playbackEngine?.liveDecoderCount ?? 0
        let headline = playbackEngine?.summary?.headline ?? "idle"
        let power = preferencesStore?.power.defaults
        let lpm = power?.pauseInLowPowerMode ?? true
        let thermal = power?.thermal.pauseAt != nil
        let covered = power?.pauseWhenCovered ?? true

        return """
        Video loaded: \(loaded)
        Engine: \(headline)
        Decoders: \(decoders)

        Power settings:
        • Pause on Low Power Mode: \(lpm ? "ON" : "OFF")
        • Pause on High Thermal: \(thermal ? "ON" : "OFF")
        • Pause when Covered: \(covered ? "ON" : "OFF")

        Displays: \(NSScreen.screens.count)
        """
    }

    // MARK: - Version & Changelog

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    /// Opens About & Status once when the app version changes since the user last viewed it.
    func checkForNewVersionAndShowChangelogIfNeeded() {
        // First-run onboarding already covers welcome content — don't stack another window.
        guard preferencesStore?.milestones.hasShownOnboarding == true else { return }

        let lastShown = preferencesStore?.milestones.lastShownChangelogVersion ?? "0.0"
        guard UpdateChecker.compareVersions(currentVersion, lastShown) == .orderedDescending else { return }

        LuminaLog.app.info("New version detected: \(currentVersion) (previously saw \(lastShown))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.showAboutStatus()
        }
    }


    // MARK: - Status Item & Menu

    private func makeStatusBarIcon() -> NSImage {
        LuminaMenuIcon.make(
            size: DisplayScale.menuBarIconSize,
            lineWidth: DisplayScale.menuBarIconLineWidth
        )
    }

    @objc private func refreshStatusBarIcon() {
        statusItem?.button?.image = makeStatusBarIcon()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = makeStatusBarIcon()
            button.title = ""
        }

        updateStatusItemFromEngine()

        // Status, Studio, Music Widget, Pause/Resume All, Settings, Quit.
        let menu = NSMenu()
        menu.delegate = self

        let status = NSMenuItem(title: "No wallpapers set", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Lumina Studio", action: #selector(openWallpaperManager), keyEquivalent: "m"))

        let musicItem = NSMenuItem(
            title: "Music Widget",
            action: #selector(toggleMusicWidget),
            keyEquivalent: "m"
        )
        musicItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(musicItem)

        let pauseItem = NSMenuItem(
            title: "Pause All",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        pauseItem.keyEquivalentModifierMask = [.command, .option]
        pauseAllMenuItem = pauseItem
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Lumina", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        refreshStatusMenuItems()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusMenuItems()
    }

    private func refreshStatusMenuItems() {
        guard let engine = playbackEngine else {
            statusMenuItem?.title = "No wallpapers set"
            pauseAllMenuItem?.title = "Pause All"
            pauseAllMenuItem?.isEnabled = false
            return
        }
        let plan = engine.plan
        let displays = engine.displays
        statusMenuItem?.title = LuminaPlaybackHeadline.text(plan: plan, displays: displays)

        let manual = LuminaPlaybackHeadline.isManuallyPaused(plan: plan)
        pauseAllMenuItem?.title = manual ? "Resume All" : "Pause All"

        let canToggle = displays.contains { display in
            switch LuminaDisplayState.from(plan: plan, key: display.key) {
            case .playing, .paused: return true
            default: return false
            }
        }
        pauseAllMenuItem?.isEnabled = canToggle
    }

    @objc private func toggleMusicWidget() {
        NowPlayingWidgetController.shared.toggle()
    }

    @objc private func openSettings() {
        openWallpaperManager()
        SettingsRouter.shared.open(.appearance)
    }

    @objc private func togglePause() {
        playbackEngine?.togglePause()
        updateStatusItemFromEngine()
    }

    @objc private func quit() {
        // Ask AppKit to terminate; applicationWillTerminate performs the actual teardown so
        // the same cleanup runs for menu Quit, ⌘Q, logout, and system shutdown alike.
        NSApplication.shared.terminate(nil)
    }

    // MARK: - About / Status + Debug

    @objc private func printDebugStatus() {
        LuminaLog.app.debug("LUMINA DEBUG @ \(Date()) decoders=\(playbackEngine?.liveDecoderCount ?? 0) plan=\(playbackEngine?.summary?.headline ?? "?")")
    }

    private func openTestingDocInFinder() {
        let docsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/PROTOTYPE_TESTING.md")
        // Fallback to workspace root if needed
        let fm = FileManager.default
        if fm.fileExists(atPath: docsURL.path) {
            NSWorkspace.shared.selectFile(docsURL.path, inFileViewerRootedAtPath: docsURL.deletingLastPathComponent().path)
        } else {
            // Open the project folder
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            NSWorkspace.shared.open(root)
            LuminaLog.app.debug("Note: docs/PROTOTYPE_TESTING.md may need to be created/visible after first build.")
        }
    }



}
