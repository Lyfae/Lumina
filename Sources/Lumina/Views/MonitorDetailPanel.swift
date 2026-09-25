import SwiftUI
import AppKit
import AVFoundation

/// Library tile staged for Studio preview — not yet on the desktop.
struct StagedWallpaperPick: Equatable {
    let url: URL
    let mediaType: MediaType
    let libraryID: String
}

/// Side panel for the selected monitor: full-height live preview by default, with a
/// Per-display Adjust column that slides in for Pin / Display / Effects / etc.
struct MonitorDetailPanel: View {
    let monitor: MonitorInfo
    @ObservedObject var store: WallpaperManagerStore
    @Binding var stagedPick: StagedWallpaperPick?

    var onClose: () -> Void = {}
    var showHeader: Bool = true

    // When true, the live preview becomes an interactive crop editor (drag to move,
    // corners to resize) — no separate crop preview needed.
    @State private var cropEditMode: Bool = false
    @State private var previewSourceAspect: CGFloat = 16.0 / 9.0
    @State private var previewOpacity: Double = 1.0

    // Presents the dedicated slideshow queue/configuration sheet.
    @State private var showSlideshowConfig: Bool = false

    /// Wallpaper adjustments inspector: closed by default so the preview owns the body.
    @State private var showSettingsColumn: Bool = false
    /// Measured preview width while flexible; locked during open/close so GeometryReader
    /// (and the AVPlayer layer) don't reflow every animation frame.
    @State private var measuredPreviewWidth: CGFloat = 0
    @State private var lockedPreviewWidth: CGFloat? = nil
    @State private var previewUnlockTask: Task<Void, Never>? = nil
    /// Skip one assignment reload when Apply commits a staged library pick (keeps local edits).
    @State private var suppressAssignmentReload = false

    /// Must match the window growth delta so the preview width stays stable while toggling.
    private static var settingsInspectorWidth: CGFloat { LuminaMetrics.adjustColumnWidth }

    // Local state for settings (synced with store)
    @State private var selectedScaling: VideoScaling = .fill
    @State private var keepOnStartup: Bool = false
    @State private var playbackSpeed: Double = 1.0
    @State private var localCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var videoPreviewTime: Double = 0.15
    @State private var videoDuration: Double = 0
    @State private var committedUseStaticFrame: Bool = false
    @State private var pendingFrameCommit: (time: Double, useStatic: Bool)? = nil
    @State private var showVideoFrameGuide: Bool = true
    @State private var frameActionFeedback: String?
    @State private var frameFeedbackTask: Task<Void, Never>?
    @State private var loopFadeEnabled: Bool = false
    @State private var loopFadeDuration: Double = 1.5
    @State private var loopFadeEasing: FadeEasing = .easeInOut
    @State private var brightness: Double = 0.0
    @State private var slideshowItems: [String] = []
    @State private var slideshowInterval: Double = 10.0
    @State private var slideshowTransition: SlideshowTransition = .fade
    @State private var slideshowKenBurnsEnabled: Bool = true

    // Compressor
    @StateObject private var compressor = VideoCompressor.shared

    // Compression UI state
    @State private var selectedPreset: VideoCompressor.QualityPreset = .fullHD
    @State private var videoInfo: VideoCompressor.VideoInfo = .init()
    @State private var showCompressError: Bool = false
    @State private var compressErrorMessage: String = ""
    @State private var showUseCompressedAlert: Bool = false
    @State private var pendingCompressedURL: URL? = nil

    // New visual effect state
    @State private var opacity: Double = 1.0
    @State private var saturation: Double = 1.0
    @State private var hue: Double = 0.0
    @State private var grayscale: Bool = false
    @State private var audioVolume: Double = 0.0
    @State private var loopMode: LoopMode = .loop

    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(PlaybackEngine.self) private var playbackEngine: PlaybackEngine?
    @Environment(PreferencesStore.self) private var prefs: PreferencesStore?
    @State private var qualityPowerFlash = false
    @State private var previewHovered = false
    @FocusState private var previewFocused: Bool

    // MARK: - Computed

    private var assignment: MonitorAssignment? {
        store.assignment(for: monitor.id)
    }

    private var scalingDescription: String {
        switch selectedScaling {
        case .fit:     return "Shows the whole video, with bars if needed."
        case .fill:    return "Fills the screen. Edges may be cut off."
        case .stretch: return "Stretches to fill the screen. May look squashed."
        }
    }

    private var displayKey: DisplayKey { DisplayKey(monitor.id) }

    private var isSlideshowContext: Bool {
        stagedPick == nil && !(assignment?.slideshowItems.isEmpty ?? true)
    }

    private var adjustMediaType: MediaType {
        if let staged = stagedPick { return staged.mediaType }
        if isSlideshowContext { return assignment?.mediaType ?? .image }
        return assignment?.mediaType ?? .unknown
    }

    private var adjustCapability: AdjustCapability {
        if stagedPick != nil {
            return .for(adjustMediaType)
        }
        if isSlideshowContext {
            return .forSlideshow()
        }
        return .for(adjustMediaType)
    }

    private func formatSpeed(_ v: Double) -> String {
        let s = String(format: "%g", v)
        return "\(s)×"
    }

    private func formatBrightness(_ v: Double) -> String {
        let pct = Int((v * 200).rounded())
        if pct == 0 { return "0%" }
        let sign = pct > 0 ? "+" : "−"
        return "\(sign)\(abs(pct))%"
    }

    private func formatSaturation(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }

    private func formatFade(_ v: Double) -> String {
        let s = String(format: "%g", v)
        return "\(s) s"
    }

    private func aspectLockLabel() -> String {
        let normalized = monitor.resolution
            .replacingOccurrences(of: "×", with: "x")
            .lowercased()
        let components = normalized.split(separator: "x")
        let w = Int(components.first.flatMap { Double($0) } ?? 0)
        let h = Int(components.dropFirst().first.flatMap { Double($0) } ?? 0)
        if w > 0, h > 0 {
            func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
            let g = max(1, gcd(w, h))
            let rw = max(1, w / g)
            let rh = max(1, h / g)
            if rw <= 32, rh <= 32 {
                return "Locked to \(rw):\(rh)"
            }
            return String(format: "Locked to %.2g:1", Double(w) / Double(h))
        }
        return String(format: "Locked to %.2g:1", Double(monitor.aspectRatio))
    }

    /// Monitor aspect expressed in normalized crop coordinates (width ÷ height in 0–1 space).
    private var normalizedCropAspect: CGFloat {
        guard previewSourceAspect > 0 else { return monitor.aspectRatio }
        return monitor.aspectRatio / previewSourceAspect
    }

    private func resetCropToDefault() {
        localCropRect = CropRectangle.centeredCrop(
            normalizedAspect: normalizedCropAspect,
            scale: 0.88
        )
        videoPreviewTime = 0.15
    }

    private func formattedVideoTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : String(format: "0:%02d", s)
    }

    private func showFrameFeedback(_ message: String) {
        frameFeedbackTask?.cancel()
        frameActionFeedback = message
        frameFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { frameActionFeedback = nil }
        }
    }

    private func commitVideoFrame(useStatic: Bool) {
        committedUseStaticFrame = useStatic
        let label = formattedVideoTime(videoPreviewTime * max(videoDuration, 0))
        if stagedPick != nil {
            pendingFrameCommit = (videoPreviewTime, useStatic)
            if useStatic {
                showFrameFeedback("Still from \(label) — Apply to set on desktop.")
            } else {
                showFrameFeedback("Start at \(label) — Apply to set on desktop.")
            }
            return
        }
        pendingFrameCommit = nil
        store.setVideoFrameTime(for: monitor, time: videoPreviewTime, useStatic: useStatic)
        if useStatic {
            showFrameFeedback("Your desktop now shows a still from \(label).")
        } else {
            showFrameFeedback("Your desktop video now starts at \(label).")
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                headerSection
                LuminaDivider()
            }

            HStack(spacing: 0) {
                previewColumn
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: PreviewColumnWidthKey.self,
                                value: geo.size.width
                            )
                        }
                    )
                    // Lock width while the adjustments column animates so the live preview
                    // doesn't reflow (that was the open/close glitch).
                    .frame(
                        width: lockedPreviewWidth,
                        alignment: .center
                    )
                    .frame(
                        maxWidth: lockedPreviewWidth == nil ? .infinity : nil,
                        maxHeight: .infinity
                    )
                    .layoutPriority(1)
                    // Don't animate size changes on the preview itself.
                    .transaction { $0.animation = nil }

                settingsColumn
                    .frame(
                        width: showSettingsColumn ? Self.settingsInspectorWidth : 0,
                        alignment: .topLeading
                    )
                    .clipped()
                    .opacity(showSettingsColumn ? 1 : 0)
                    .allowsHitTesting(showSettingsColumn)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.luminaBorder)
                            .frame(width: 1)
                            .opacity(showSettingsColumn ? 1 : 0)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(PreviewColumnWidthKey.self) { width in
                guard lockedPreviewWidth == nil, width > 1 else { return }
                measuredPreviewWidth = width
            }

            LuminaDivider()

            actionButtons
                .padding(.horizontal, LuminaSpace.xl)
                .padding(.vertical, LuminaSpace.barPaddingV)
        }
        .onAppear {
            loadCurrentValues()
            maybeAutoOpenAdjustColumn(
                hasMedia: hasPreviewMedia
            )
        }
        .onChange(of: monitor.id) { _, _ in
            stagedPick = nil
            loadCurrentValues()
        }
        // Reloading when the media itself changes resets the staged adjustments to the new
        // assignment's values (so picking new media doesn't leave stale pending edits).
        .onChange(of: assignment?.filePath) { _, newPath in
            if suppressAssignmentReload {
                suppressAssignmentReload = false
                maybeAutoOpenAdjustColumn(hasMedia: newPath.map { !$0.isEmpty } ?? false)
                return
            }
            stagedPick = nil
            loadCurrentValues()
            maybeAutoOpenAdjustColumn(hasMedia: newPath.map { !$0.isEmpty } ?? false)
        }
        .onChange(of: stagedPick?.url) { _, _ in
            maybeAutoOpenAdjustColumn(hasMedia: hasPreviewMedia)
            if cropEditMode { cropEditMode = false }
        }
        .task(id: previewAssignment?.filePath) {
            if let a = previewAssignment,
               let aspect = await CropRectangle.resolveSourceAspect(for: a),
               aspect > 0 {
                previewSourceAspect = aspect
            }
        }
        // Slideshow builder. On dismiss, resync local state from the (possibly updated) assignment.
        .sheet(isPresented: $showSlideshowConfig, onDismiss: { loadCurrentValues() }) {
            SlideshowConfigView(monitor: monitor, store: store,
                                onClose: { showSlideshowConfig = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .luminaRevealAdjustSection)) { note in
            guard (note.object as? String) == "qualityPower" else { return }
            revealQualityPower()
        }
        .onChange(of: cropEditMode) { _, visible in
            NotificationCenter.default.post(
                name: .cropEditorVisibilityChanged,
                object: nil,
                userInfo: ["visible": visible]
            )
        }
        .onKeyPress(.return) {
            guard hasUnappliedChanges else { return .ignored }
            applyToWallpaper()
            return .handled
        }
        .onKeyPress(.escape) {
            if cropEditMode {
                LuminaMotion.animate(LuminaMotion.state) { cropEditMode = false }
                return .handled
            }
            guard hasUnappliedChanges else { return .ignored }
            discardStagedChanges()
            return .handled
        }
        // Adjust column window resize is driven explicitly from `toggleConfigColumn`
        // (instant grow on open; column out then soft window shrink on close).
        .onDisappear {
            stagedPick = nil
            pendingFrameCommit = nil
            frameFeedbackTask?.cancel()
            frameFeedbackTask = nil
            previewUnlockTask?.cancel()
            lockedPreviewWidth = nil
            // If the panel goes away while crop mode is open, tell the window controller to
            // shrink back — otherwise the grown window frame sticks around.
            if cropEditMode {
                NotificationCenter.default.post(
                    name: .cropEditorVisibilityChanged,
                    object: nil,
                    userInfo: ["visible": false]
                )
            }
            if showSettingsColumn {
                NotificationCenter.default.post(
                    name: .configColumnVisibilityChanged,
                    object: nil,
                    userInfo: [
                        "visible": false,
                        "animateWindow": false,
                        "width": Self.settingsInspectorWidth
                    ]
                )
            }
        }
    }

    // MARK: - Preview column (majority of the body)

    private var previewColumn: some View {
        VStack(spacing: 0) {
            livePreviewSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let a = previewAssignment, cropEditMode {
                LuminaDivider()
                cropEditorToolbar(assignment: a)
            } else if let a = previewAssignment, !a.slideshowItems.isEmpty {
                HStack(spacing: LuminaSpace.tight) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: uiScale.iconSize(.inline)))
                    Text("Slideshow · \(a.slideshowItems.count) images")
                        .font(uiScale.font(.caption))
                }
                .foregroundStyle(.secondary)
                .padding(LuminaSpace.sm)
            }
        }
        .padding(.horizontal, LuminaSpace.sm)
        .padding(.bottom, LuminaSpace.tight)
    }

    private var settingsColumn: some View {
        let caps = adjustCapability
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: LuminaSpace.cardGap) {
                    if hasPreviewMedia {
                        keepOnStartupControl
                            .disabled(stagedPick != nil && assignment == nil)
                            .opacity(stagedPick != nil && assignment == nil ? 0.4 : 1)

                        SettingsGroup(icon: "aspectratio", title: "Framing") {
                            displayContent
                        }

                        SettingsGroup(icon: "camera.filters", title: "Color") {
                            visualEffectsContent
                        }

                        SettingsGroup(
                            icon: "play.fill",
                            title: "Playback",
                            footnote: caps.playbackFootnote(
                                mediaType: adjustMediaType,
                                isSlideshow: isSlideshowContext
                            )
                        ) {
                            playbackContent
                        }
                    }

                    SettingsGroup(
                        icon: "photo.on.rectangle.angled",
                        title: "Slideshow"
                    ) {
                        slideshowContent
                    }

                    SettingsGroup(
                        icon: "gauge.with.dots.needle.50percent",
                        title: "Quality & Power",
                        flash: qualityPowerFlash
                    ) {
                        qualityPowerContent
                    }
                    .id("qualityPower")
                }
                .padding(.horizontal, LuminaSpace.sm)
                .padding(.vertical, LuminaSpace.sm)
            }
            .onChange(of: qualityPowerFlash) { _, flashing in
                if flashing {
                    withAnimation(nil) {
                        proxy.scrollTo("qualityPower", anchor: .top)
                    }
                }
            }
        }
        .luminaWindowBackdrop()
    }

    private var hasPreviewMedia: Bool {
        stagedPick != nil || (assignment?.hasMedia ?? false)
    }

    private var hasAdjustmentChanges: Bool {
        guard let a = assignment else {
            // No desktop assignment yet — any non-default local tweak counts once media is staged.
            guard stagedPick != nil else { return false }
            return selectedScaling != .fill
                || abs(playbackSpeed - 1.0) > 0.001
                || localCropRect != CGRect(x: 0, y: 0, width: 1, height: 1)
                || abs(brightness) > 0.001
                || abs(opacity - 1.0) > 0.001
                || abs(saturation - 1.0) > 0.001
                || abs(hue) > 0.001
                || grayscale
                || abs(audioVolume) > 0.001
                || loopMode != .loop
                || loopFadeEnabled
                || abs(loopFadeDuration - 1.5) > 0.001
                || loopFadeEasing != .easeInOut
        }
        return selectedScaling != a.scaling
            || abs(playbackSpeed - a.playbackSpeed) > 0.001
            || localCropRect != a.cropRect
            || abs(brightness - a.brightness) > 0.001
            || abs(opacity - a.opacity) > 0.001
            || abs(saturation - a.saturation) > 0.001
            || abs(hue - a.hue) > 0.001
            || grayscale != a.grayscale
            || abs(audioVolume - a.audioVolume) > 0.001
            || loopMode != a.loopMode
            || loopFadeEnabled != a.loopFadeEnabled
            || abs(loopFadeDuration - a.loopFadeDuration) > 0.001
            || loopFadeEasing != a.loopFadeEasing
    }

    /// True when the staged (preview) settings or media differ from what's on the desktop.
    private var hasUnappliedChanges: Bool {
        stagedPick != nil || hasAdjustmentChanges
    }

    /// Pushes staged media (if any) and every staged adjustment to the live desktop wallpaper.
    private func applyToWallpaper() {
        if let pick = stagedPick {
            stagedPick = nil
            suppressAssignmentReload = true
            store.applyRecentMedia(to: monitor.id, url: pick.url)
        }

        store.setScaling(for: monitor, scaling: selectedScaling)
        store.setPlaybackSpeed(for: monitor, speed: playbackSpeed)
        store.setCropRect(for: monitor, cropRect: localCropRect)
        if let pending = pendingFrameCommit {
            store.setVideoFrameTime(for: monitor, time: pending.time, useStatic: pending.useStatic)
            pendingFrameCommit = nil
        }
        store.setBrightness(for: monitor, brightness: brightness)
        store.setOpacity(for: monitor, opacity: opacity)
        store.setColorCorrection(for: monitor, saturation: saturation, hue: hue, grayscale: grayscale)
        store.setVolume(for: monitor, volume: audioVolume)
        store.setLoopMode(for: monitor, mode: loopMode)
        store.setLoopFade(for: monitor, enabled: loopFadeEnabled,
                          duration: loopFadeDuration, easing: loopFadeEasing)

        // `hasUnappliedChanges` is derived from the assignment, which lives in the separate
        // AssignmentStore. The setters above mutate that store but don't publish a change on
        // `store` (the @ObservedObject driving this view), so without this nudge the panel
        // wouldn't re-render and the "Apply" bar would stay green/active even though the
        // changes are now applied. Forcing a publish re-evaluates the dirty state → the bar
        // correctly fades to "Applied — Up to Date".
        store.objectWillChange.send()
    }

    private func discardStagedChanges() {
        stagedPick = nil
        pendingFrameCommit = nil
        loadCurrentValues()
    }

    // MARK: - Header (optional)

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: DisplayScale.points(2)) {
                Text(monitor.name)
                    .font(uiScale.font(.title))
                Text(monitor.resolution)
                    .font(uiScale.font(.callout))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LuminaCloseButton(action: onClose)
        }
        .padding(LuminaSpace.xl)
    }

    // MARK: - Live Preview

    /// The assignment to show in the preview. Staged library picks override the desktop
    /// media so Adjust + preview operate on the candidate before Apply. For a slideshow
    /// monitor (no single filePath, but image items present) we preview the first image.
    private var previewAssignment: MonitorAssignment? {
        if let staged = stagedPick {
            var a = assignment ?? MonitorAssignment(monitorIdentifier: monitor.id)
            a.filePath = staged.url.path
            a.mediaType = staged.mediaType
            a.slideshowItems = []
            a.scaling = selectedScaling
            a.cropRect = localCropRect
            a.brightness = brightness
            a.opacity = opacity
            a.saturation = saturation
            a.hue = hue
            a.grayscale = grayscale
            a.playbackSpeed = playbackSpeed
            a.audioVolume = audioVolume
            a.loopMode = loopMode
            a.loopFadeEnabled = loopFadeEnabled
            a.loopFadeDuration = loopFadeDuration
            a.loopFadeEasing = loopFadeEasing
            return a
        }
        guard var a = assignment else { return nil }
        if a.filePath == nil, let first = a.slideshowItems.first {
            a.filePath = first
            a.mediaType = .image
        }
        if a.filePath == nil && a.slideshowItems.isEmpty { return nil }
        return a
    }

    private var livePreviewSection: some View {
        Group {
            if let a = previewAssignment {
                GeometryReader { geo in
                    let aspect = max(
                        cropEditMode ? previewSourceAspect : monitor.aspectRatio,
                        0.01
                    )
                    let maxW = max(geo.size.width, 1)
                    let maxH = max(geo.size.height, 1)
                    let fittedWidth = min(maxW, maxH * aspect)
                    let fittedHeight = fittedWidth / aspect
                    let failedMessage: String? = {
                        guard let engine = playbackEngine else { return nil }
                        if case .failed(let msg) = engine.plan.surfaces[.desktop(displayKey)]?.content {
                            return msg
                        }
                        return nil
                    }()

                    ZStack(alignment: .topTrailing) {
                        Group {
                            if cropEditMode {
                                CropRectangle(
                                    cropRect: $localCropRect,
                                    onChange: { newRect in
                                        localCropRect = newRect
                                    },
                                    assignment: a,
                                    previewTime: a.mediaType == .video ? videoPreviewTime : nil,
                                    targetAspect: monitor.aspectRatio,
                                    sourceAspect: previewSourceAspect,
                                    brightness: brightness,
                                    previewOpacity: opacity,
                                    saturation: saturation,
                                    hueDegrees: hue,
                                    grayscale: grayscale
                                )
                                .overlay(alignment: .topLeading) {
                                    LuminaOverlayChip(text: aspectLockLabel())
                                        .padding(LuminaSpace.sm)
                                }
                            } else {
                                WallpaperPreview(
                                    assignment: a,
                                    liveCropRect: localCropRect,
                                    liveScaling: selectedScaling,
                                    targetAspect: monitor.aspectRatio,
                                    isLivePlayback: true,
                                    previewTime: nil,
                                    ignoreAspectRatio: true,
                                    brightness: brightness,
                                    previewOpacity: opacity,
                                    saturation: saturation,
                                    hueDegrees: hue,
                                    grayscale: grayscale,
                                    playbackSpeed: playbackSpeed
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
                        .opacity(previewOpacity)

                        if let msg = failedMessage, !cropEditMode {
                            LuminaErrorState(title: "Can’t play this file", detail: msg) {
                                Button("Choose Another…") {
                                    store.chooseVideo(for: monitor)
                                }
                                .buttonStyle(LuminaSecondaryButtonStyle())
                                Button("Clear Display") {
                                    store.clearAssignment(for: monitor)
                                }
                                .buttonStyle(LuminaSecondaryButtonStyle(destructive: true))
                            }
                            .padding(LuminaSpace.md)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        if !cropEditMode {
                            cropToggleButton
                                .padding(LuminaSpace.sm)
                                .opacity(
                                    previewHovered || previewFocused || NSWorkspace.shared.isVoiceOverEnabled
                                    ? 1 : 0
                                )
                                .allowsHitTesting(previewHovered || previewFocused || NSWorkspace.shared.isVoiceOverEnabled)
                        }
                    }
                    .frame(width: fittedWidth, height: fittedHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .focusable()
                    .focused($previewFocused)
                    .onHover { previewHovered = $0 }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Preview of \(a.displayName) on \(monitor.name)")
                    .accessibilityAddTraits(.isImage)
                }
                .padding(LuminaSpace.sm)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                        .fill(Color.luminaCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                                .strokeBorder(Color.luminaBorder, lineWidth: 1)
                        )
                    VStack(spacing: LuminaSpace.sm) {
                        Image(systemName: "display")
                            .font(.system(size: DisplayScale.points(36)))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                        Text("No wallpaper yet")
                            .font(uiScale.font(.headline))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        Text("Choose one from the library.")
                            .font(uiScale.font(.callout))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(LuminaSpace.sm)
            }
        }
    }

    /// Floating button on the preview that enters interactive crop editing.
    private var cropToggleButton: some View {
        Button {
            LuminaMotion.animate(LuminaMotion.state) {
                cropEditMode = true
                if localCropRect == CGRect(x: 0, y: 0, width: 1, height: 1) {
                    resetCropToDefault()
                }
            }
        } label: {
            Label("Crop", systemImage: "crop")
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .luminaOverlayChipStyle()
        .help("Crop and position")
        .accessibilityLabel("Crop")
    }

    @ViewBuilder
    private func cropEditorToolbar(assignment a: MonitorAssignment) -> some View {
        VStack(alignment: .leading, spacing: LuminaSpace.sm) {
            HStack(alignment: .center, spacing: LuminaSpace.sm) {
                Text("Drag to move. Drag a corner to resize.")
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)

                Button { resetCropToDefault() } label: {
                    Text("Reset")
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .help("Center the crop")

                Button {
                    LuminaMotion.animate(LuminaMotion.state) { cropEditMode = false }
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(LuminaSecondaryButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, LuminaSpace.md)

            if adjustCapability.videoFramePick {
                cropVideoFrameControls(assignment: a)
            }
        }
        .padding(.horizontal, LuminaSpace.md)
        .padding(.bottom, LuminaSpace.barPaddingV)
        .onExitCommand {
            LuminaMotion.animate(LuminaMotion.state) { cropEditMode = false }
        }
    }

    @ViewBuilder
    private func cropVideoFrameControls(assignment a: MonitorAssignment) -> some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(8)) {
            LuminaDivider()

            if showVideoFrameGuide {
                LuminaHintBubble(
                    icon: "lightbulb.fill",
                    message: "Drag to find a frame. Then use it as a still, or start the video there.",
                    style: .tip,
                    onDismiss: { showVideoFrameGuide = false }
                )
            }

            VStack(alignment: .leading, spacing: DisplayScale.points(8)) {
                HStack(alignment: .firstTextBaseline, spacing: DisplayScale.points(8)) {
                    Label("Frame", systemImage: "film")
                        .font(uiScale.scaledFont(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if videoDuration > 0 {
                        Text("\(formattedVideoTime(videoPreviewTime * videoDuration)) / \(formattedVideoTime(videoDuration))")
                            .font(uiScale.scaledFont(12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                LuminaSlider(value: $videoPreviewTime, range: 0...1)
                    .help("Preview only. Your desktop changes when you pick an option.")

                HStack(spacing: LuminaSpace.sm) {
                    Button { commitVideoFrame(useStatic: true) } label: {
                        Label("Use as Still", systemImage: "photo.fill")
                    }
                    .buttonStyle(LuminaSecondaryButtonStyle(prominent: committedUseStaticFrame))
                    .controlSize(.small)
                    .help("Show this frame as a still image")

                    Button { commitVideoFrame(useStatic: false) } label: {
                        Label("Start Here", systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(LuminaSecondaryButtonStyle(
                        prominent: !committedUseStaticFrame && a.videoFrameTime != nil
                    ))
                    .controlSize(.small)
                    .help("Play the video from this frame")
                }
            }

            if let feedback = frameActionFeedback {
                LuminaHintBubble(icon: "checkmark.circle.fill", message: feedback, style: .success)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let saved = a.videoFrameTime, videoDuration > 0 {
                let label = formattedVideoTime(saved * videoDuration)
                LuminaHintBubble(
                    icon: committedUseStaticFrame ? "photo.fill" : "play.fill",
                    message: committedUseStaticFrame
                        ? "Desktop: still at \(label)"
                        : "Desktop: plays from \(label)",
                    style: .info
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: frameActionFeedback)
        .task(id: a.filePath) {
            guard let url = a.resolvedURL()
                ?? a.filePath.map({ URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
            else { return }
            let asset = AVURLAsset(url: url)
            if let dur = try? await asset.load(.duration) {
                videoDuration = dur.seconds
            }
        }
    }

    // MARK: - Prominent Keep on Startup Control
    // This is deliberately placed in a high-visibility position directly under the
    // live preview. "Keep on startup" is one of the highest-stakes decisions in the
    // entire app (it controls whether the wallpaper survives relaunch). It deserves
    // strong visual weight and clear explanation — classic best practice for
    // primary persistence / power-user toggles.

    private var keepOnStartupControl: some View {
        HStack(alignment: .center, spacing: LuminaSpace.sm) {
            Image(systemName: keepOnStartup ? "pin.fill" : "pin")
                .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                .foregroundStyle(keepOnStartup ? themeManager.current.color : .secondary)
                .frame(width: DisplayScale.points(20), alignment: .center)

            VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                Text("Restore at launch")
                    .font(uiScale.font(.bodyStrong))

                Text(keepOnStartup
                     ? "Comes back when Lumina starts. Saves right away."
                     : "Stays until you quit Lumina.")
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $keepOnStartup)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(uiScale.controlSize())
                .accessibilityLabel("Restore at launch")
        }
        .onChange(of: keepOnStartup) { _, newValue in
            store.setKeepOnStartup(for: monitor, enabled: newValue)
        }
        .padding(LuminaSpace.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luminaGlassPanel(cornerRadius: LuminaRadius.panel)
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                .strokeBorder(
                    keepOnStartup ? themeManager.current.color.opacity(0.5) : Color.luminaBorder,
                    lineWidth: 1
                )
        )
        .help("Saves right away. Turning it off doesn’t clear the wallpaper.")
    }

    // MARK: - Playback Section Content

    private var playbackContent: some View {
        let caps = adjustCapability
        return VStack(alignment: .leading, spacing: LuminaSpace.md) {
            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                LuminaSliderLabel(title: "Speed", value: formatSpeed(playbackSpeed))
                    .help("Double-click to reset")
                    .onTapGesture(count: 2) { if caps.playbackSpeed { playbackSpeed = 1.0 } }
                LuminaSlider(value: $playbackSpeed, range: 0.25...4.0, step: 0.25, label: formatSpeed(playbackSpeed))
            }
            .disabled(!caps.playbackSpeed)
            .opacity(caps.playbackSpeed ? 1 : 0.4)

            VStack(alignment: .leading, spacing: LuminaSpace.tight) {
                Text("At the end").font(uiScale.font(.body)).foregroundStyle(.secondary)
                LuminaSegmentedPicker(
                    selection: $loopMode,
                    options: LoopMode.allCases.map {
                        LuminaSegmentedOption($0, title: $0.label)
                    }
                )
                Text(loopMode.uiDescription)
                    .font(uiScale.font(.caption)).foregroundStyle(.secondary)
                    .animation(LuminaMotion.state, value: loopMode)
            }
            .disabled(!caps.loopMode)
            .opacity(caps.loopMode ? 1 : 0.4)

            VStack(alignment: .leading, spacing: LuminaSpace.sm) {
                HStack {
                    Text("Fade between loops")
                        .font(uiScale.font(.body))
                    Spacer(minLength: 0)
                    Toggle("", isOn: $loopFadeEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(uiScale.controlSize())
                        .accessibilityLabel("Fade between loops")
                }
                .disabled(!caps.loopFade || loopMode != .loop)
                .help(caps.loopFade
                      ? (loopMode == .loop
                         ? "Fades out and back in at each loop."
                         : "Needs Loop.")
                      : "Not available for this media")

                if caps.loopFade, loopMode != .loop {
                    Text("Needs Loop.")
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                }

                if caps.loopFade, loopFadeEnabled, loopMode == .loop {
                    VStack(alignment: .leading, spacing: LuminaSpace.sm) {
                        VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                            LuminaSliderLabel(title: "Fade length", value: formatFade(loopFadeDuration))
                            LuminaSlider(value: $loopFadeDuration, range: 0.1...5.0, step: 0.05, label: formatFade(loopFadeDuration))
                        }

                        VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                            LuminaSliderLabel(title: "Curve")
                            LuminaSegmentedPicker(
                                selection: $loopFadeEasing,
                                options: FadeEasing.allCases.map {
                                    LuminaSegmentedOption($0, title: $0.label)
                                }
                            )
                        }

                        Button("Preview Fade") { previewFadeInPreview() }
                            .buttonStyle(LuminaSecondaryButtonStyle())
                            .controlSize(.small)
                            .help("Plays the fade in the preview")
                    }
                }
            }
            .opacity(caps.loopFade ? 1 : 0.4)

            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                LuminaSliderLabel(
                    title: "Video sound",
                    value: audioVolume < 0.01 ? "Muted" : "\(Int((audioVolume * 100).rounded()))%"
                )
                HStack {
                    Image(systemName: audioVolume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                        .font(uiScale.font(.callout))
                    LuminaSlider(
                        value: $audioVolume,
                        range: 0...1,
                        label: audioVolume < 0.01 ? "Muted" : "\(Int((audioVolume * 100).rounded()))%"
                    )
                }
            }
            .disabled(!caps.audioVolume)
            .opacity(caps.audioVolume ? 1 : 0.4)
        }
    }

    // MARK: - Display Section Content

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.md) {
            VStack(alignment: .leading, spacing: LuminaSpace.tight) {
                Text("Scaling").font(uiScale.font(.body)).foregroundStyle(.secondary)
                LuminaSegmentedPicker(
                    selection: $selectedScaling,
                    options: [
                        LuminaSegmentedOption(VideoScaling.fit, title: "Fit"),
                        LuminaSegmentedOption(VideoScaling.fill, title: "Fill"),
                        LuminaSegmentedOption(VideoScaling.stretch, title: "Stretch"),
                    ]
                )
                Text(scalingDescription)
                    .font(uiScale.font(.caption)).foregroundStyle(.secondary)
                    .animation(LuminaMotion.state, value: selectedScaling)
            }

            if hasPreviewMedia, !cropEditMode {
                Button {
                    LuminaMotion.animate(LuminaMotion.state) {
                        cropEditMode = true
                        if localCropRect == CGRect(x: 0, y: 0, width: 1, height: 1) {
                            resetCropToDefault()
                        }
                    }
                } label: {
                    Label("Crop…", systemImage: "crop")
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .controlSize(.small)
                .help("Crop and position")
                .accessibilityLabel("Crop")
            }
        }
    }

    // MARK: - Visual Effects Section Content

    private var visualEffectsContent: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.sm) {
            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                LuminaSliderLabel(title: "Brightness", value: formatBrightness(brightness))
                    .help("Double-click to reset")
                    .onTapGesture(count: 2) { brightness = 0 }
                LuminaSlider(value: $brightness, range: -0.5...0.5, label: formatBrightness(brightness))
            }

            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                LuminaSliderLabel(title: "Opacity", value: "\(Int((opacity * 100).rounded()))%")
                    .help("Double-click to reset")
                    .onTapGesture(count: 2) { opacity = 1 }
                LuminaSlider(value: $opacity, range: 0...1, label: "\(Int((opacity * 100).rounded()))%")
            }

            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                LuminaSliderLabel(title: "Saturation", value: formatSaturation(saturation))
                    .help("Double-click to reset")
                    .onTapGesture(count: 2) { saturation = 1 }
                LuminaSlider(value: $saturation, range: 0...2, label: formatSaturation(saturation))
            }

            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                LuminaSliderLabel(title: "Hue", value: "\(Int(hue.rounded()))°")
                    .help("Double-click to reset")
                    .onTapGesture(count: 2) { hue = 0 }
                LuminaSlider(value: $hue, range: -180...180, label: "\(Int(hue.rounded()))°")
            }

            HStack {
                Text("Black and white")
                    .font(uiScale.font(.body))
                Spacer(minLength: 0)
                Toggle("", isOn: $grayscale)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(uiScale.controlSize())
                    .accessibilityLabel("Black and white")
            }
        }
    }

    // MARK: - Slideshow Section Content

    private var slideshowContent: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.sm) {
            if slideshowItems.isEmpty {
                Text("Show a rotating set of images on this display.")
                    .font(uiScale.font(.callout))
                    .foregroundStyle(.secondary)
            } else {
                let transitionLabel = slideshowTransition.rawValue.capitalized
                let ken = slideshowKenBurnsEnabled ? " · Pan and zoom" : ""
                Text("\(slideshowItems.count) images · every \(Int(slideshowInterval)) s · \(transitionLabel)\(ken)")
                    .font(uiScale.font(.callout).weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: LuminaSpace.sm) {
                Button {
                    showSlideshowConfig = true
                } label: {
                    Label(
                        slideshowItems.isEmpty ? "Create Slideshow…" : "Edit Slideshow…",
                        systemImage: "slider.horizontal.below.rectangle"
                    )
                }
                .buttonStyle(LuminaProminentButtonStyle())
                .controlSize(.small)

                if !slideshowItems.isEmpty {
                    Button("Remove") {
                        slideshowItems.removeAll()
                        store.setSlideshowItems(for: monitor, items: [])
                    }
                    .buttonStyle(LuminaSecondaryButtonStyle(destructive: true))
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Action Buttons

    private func postConfigColumnVisibility(
        _ visible: Bool,
        animateWindow: Bool,
        duration: TimeInterval
    ) {
        NotificationCenter.default.post(
            name: .configColumnVisibilityChanged,
            object: nil,
            userInfo: [
                "visible": visible,
                "animateWindow": animateWindow,
                "duration": duration,
                "width": Self.settingsInspectorWidth
            ]
        )
    }

    private func toggleConfigColumn() {
        previewUnlockTask?.cancel()
        let opening = !showSettingsColumn

        if opening {
            openAdjustColumn()
        } else {
            // Column out first while the window stays wide (mirrors expand). Shrinking
            // both together desyncs AppKit/SwiftUI and glitches the preview/header.
            let columnDuration = LuminaMotion.adjustClose.map { _ in 0.55 } ?? 0
            let windowDuration = LuminaMotion.adjustCloseWindow
            let animateWindow = windowDuration > 0
            if let anim = LuminaMotion.adjustClose {
                withAnimation(anim) { showSettingsColumn = false }
            } else {
                showSettingsColumn = false
            }
            previewUnlockTask = Task { @MainActor in
                let columnNs = UInt64(max(columnDuration, 0.01) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: columnNs)
                guard !Task.isCancelled else { return }
                postConfigColumnVisibility(false, animateWindow: animateWindow, duration: max(windowDuration, 0.01))
                let windowNs = UInt64(max(windowDuration, 0.01) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: windowNs)
                guard !Task.isCancelled else { return }
                lockedPreviewWidth = nil
            }
        }
    }

    /// Opens Adjust once when the user first assigns media, so Display / Effects aren't hidden.
    private func maybeAutoOpenAdjustColumn(hasMedia: Bool) {
        guard hasMedia, !showSettingsColumn else { return }
        if store.appDelegate?.preferencesStore?.milestones.hasDiscoveredAdjust == true { return }
        // Defer so layout has measured the preview width before we lock it.
        DispatchQueue.main.async {
            guard !self.showSettingsColumn else { return }
            self.openAdjustColumn()
        }
    }

    private func openAdjustColumn() {
        // Freeze preview, grow the window immediately so layout has room, then
        // slide the Adjust column into the new space — avoids the header squeeze.
        let width = measuredPreviewWidth > 1 ? measuredPreviewWidth : nil
        lockedPreviewWidth = width
        postConfigColumnVisibility(
            true,
            animateWindow: false,
            duration: 0.42
        )
        if let anim = LuminaMotion.adjustOpen {
            withAnimation(anim) { showSettingsColumn = true }
        } else {
            showSettingsColumn = true
        }
        if let prefs = store.appDelegate?.preferencesStore {
            prefs.milestones.hasDiscoveredAdjust = true
        }
    }

    private var actionButtons: some View {
        HStack(spacing: LuminaSpace.sm) {
            if hasUnappliedChanges, hasPreviewMedia {
                HStack(spacing: LuminaSpace.xs) {
                    Circle()
                        .fill(LuminaStatusColor.paused)
                        .frame(width: DisplayScale.points(6), height: DisplayScale.points(6))
                    Text(stagedPick != nil ? "Preview only" : "Not applied")
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    applyToWallpaper()
                } label: {
                    Text("Apply")
                }
                .buttonStyle(LuminaProminentButtonStyle())
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: .command)
                .help(applyButtonHelp)
                Button("Discard") {
                    discardStagedChanges()
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .controlSize(.regular)
                .help("Revert the preview to the current desktop wallpaper")
            } else if hasPreviewMedia {
                HStack(spacing: LuminaSpace.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LuminaStatusColor.playing)
                    Text("Up to date")
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Up to date")
            }

            if hasPreviewMedia {
                Button("Reset") {
                    resetToDefaults()
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .controlSize(.regular)
                .help("Reset crop, speed, and color. Click Apply to use it.")
                .transition(.opacity)
            }

            if hasPreviewMedia || monitor.assignedVideoName != nil {
                Button("Clear Display", role: .destructive) {
                    stagedPick = nil
                    pendingFrameCommit = nil
                    store.clearAssignment(for: monitor)
                }
                .buttonStyle(LuminaSecondaryButtonStyle(destructive: true))
                .controlSize(.regular)
                .help("Remove the wallpaper from this display")
            }

            Spacer(minLength: LuminaSpace.xs)

            Button {
                toggleConfigColumn()
            } label: {
                Label("Adjust", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(LuminaSecondaryButtonStyle(prominent: showSettingsColumn))
            .controlSize(.regular)
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(showSettingsColumn ? "Hide Adjust (⌥⌘I)" : "Show Adjust (⌥⌘I)")
            .accessibilityLabel(showSettingsColumn ? "Hide Adjust" : "Show Adjust")
            .accessibilityAddTraits(showSettingsColumn ? .isSelected : [])

            if showHeader {
                Button("Done") { onClose() }
                    .buttonStyle(LuminaSecondaryButtonStyle())
                    .controlSize(.regular)
            }
        }
        .animation(LuminaMotion.state, value: assignment != nil)
        .animation(LuminaMotion.state, value: hasUnappliedChanges)
        .animation(LuminaMotion.state, value: stagedPick != nil)
    }

    /// Help text for the Apply control.
    private var applyButtonHelp: String {
        if !hasPreviewMedia {
            return "Choose a wallpaper first"
        }
        if !hasUnappliedChanges {
            return "Your desktop matches the preview"
        }
        if stagedPick != nil {
            return "Set this wallpaper on your desktop (⌘↩)"
        }
        return "Use these settings on your desktop (⌘↩)"
    }

    /// Simulates the loop crossfade in the live preview panel so the user can
    /// see the duration and easing before committing to the desktop wallpaper.
    private func previewFadeInPreview() {
        guard loopFadeDuration > 0 else { return }
        let half = loopFadeDuration / 2.0
        let curve = Animation.timingCurve(
            loopFadeEasing == .easeIn || loopFadeEasing == .easeInOut ? 0.42 : 0,
            0,
            loopFadeEasing == .easeOut || loopFadeEasing == .easeInOut ? 0.58 : 1,
            1,
            duration: half
        )
        withAnimation(curve) { previewOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + half / max(0.25, playbackSpeed)) {
            withAnimation(curve) { previewOpacity = opacity }
        }
    }

    private func resetToDefaults() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            selectedScaling = .fill
            playbackSpeed = 1.0
            localCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            videoPreviewTime = 0.15
            committedUseStaticFrame = false
            pendingFrameCommit = nil
            frameActionFeedback = nil
            loopFadeEnabled = false
            loopFadeDuration = 1.5
            loopFadeEasing = .easeInOut
            brightness = 0.0
            opacity = 1.0
            saturation = 1.0
            hue = 0.0
            grayscale = false
            audioVolume = 0.0
            loopMode = .loop
        }
        // Staged only — the preview updates immediately; "Apply to Wallpaper" commits to the desktop.
    }

    // MARK: - Load Current Values

    private func loadCurrentValues() {
        // Disable SwiftUI animations so slider/toggle values snap instantly
        // when the user switches monitors — no distracting animated transitions.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { _loadCurrentValuesInner() }
    }

    private func _loadCurrentValuesInner() {
        // Leaving crop mode when the target display changes prevents stale crop UI and
        // ensures cropEditorVisibilityChanged fires so the window can shrink if needed.
        if cropEditMode { cropEditMode = false }
        pendingFrameCommit = nil
        frameActionFeedback = nil

        if let a = store.assignment(for: monitor.id) {
            selectedScaling = a.scaling
            keepOnStartup = a.keepOnStartup
            playbackSpeed = a.playbackSpeed
            localCropRect = a.cropRect
            committedUseStaticFrame = a.useStaticVideoFrame
            if let ft = a.videoFrameTime {
                videoPreviewTime = ft
            }
            loopFadeEnabled = a.loopFadeEnabled
            loopFadeDuration = a.loopFadeDuration
            loopFadeEasing = a.loopFadeEasing
            brightness = a.brightness
            slideshowItems = a.slideshowItems
            slideshowInterval = a.slideshowInterval
            slideshowTransition = a.slideshowTransition
            slideshowKenBurnsEnabled = a.slideshowKenBurnsEnabled
            opacity = a.opacity
            saturation = a.saturation
            hue = a.hue
            grayscale = a.grayscale
            audioVolume = a.audioVolume
            loopMode = a.loopMode
        } else {
            selectedScaling = .fill
            keepOnStartup = false
            playbackSpeed = 1.0
            localCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            videoPreviewTime = 0.15
            committedUseStaticFrame = false
            loopFadeEnabled = false
            loopFadeDuration = 1.5
            loopFadeEasing = .easeInOut
            brightness = 0.0
            slideshowItems = []
            slideshowInterval = 10.0
            slideshowTransition = .fade
            slideshowKenBurnsEnabled = true
            opacity = 1.0
            saturation = 1.0
            hue = 0.0
            grayscale = false
            audioVolume = 0.0
            loopMode = .loop
        }
    }

    private func revealQualityPower() {
        if !showSettingsColumn {
            openAdjustColumn()
        }
        qualityPowerFlash = true
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0.05 : 0.6)) {
            qualityPowerFlash = false
        }
    }

    // MARK: - Quality & Power

    private var usesGlobalQualityPower: Bool {
        guard let prefs else { return true }
        return !prefs.power.hasOverride(for: displayKey) && prefs.playback.qualityOverrides[displayKey] == nil
    }

    private var qualityPowerContent: some View {
        let key = displayKey
        return VStack(alignment: .leading, spacing: LuminaSpace.md) {
            HStack {
                Text("Use global settings")
                    .font(uiScale.font(.bodyStrong))
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { usesGlobalQualityPower },
                    set: { on in
                        guard let prefs else { return }
                        if on {
                            var power = prefs.power
                            power.clearOverride(for: key)
                            prefs.power = power
                            var playback = prefs.playback
                            playback.clearOverride(for: key)
                            prefs.playback = playback
                        } else {
                            var power = prefs.power
                            power[display: key] = power.defaults
                            prefs.power = power
                            var playback = prefs.playback
                            playback[display: key] = playback.defaultQuality
                            prefs.playback = playback
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(uiScale.controlSize())
                .accessibilityLabel("Use global settings")
            }

            if usesGlobalQualityPower {
                HStack(spacing: LuminaSpace.xs) {
                    Text("Same as Settings → Power.")
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        SettingsRouter.shared.open(.power)
                    }
                    .buttonStyle(LuminaPressableButtonStyle())
                    .font(uiScale.font(.caption))
                    .foregroundStyle(themeManager.current.color)
                }
            } else {
                HStack(spacing: LuminaSpace.xs) {
                    Text("Only this display.")
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                    Button("Reset to Global") {
                        guard let prefs else { return }
                        var power = prefs.power
                        power.clearOverride(for: key)
                        prefs.power = power
                        var playback = prefs.playback
                        playback.clearOverride(for: key)
                        prefs.playback = playback
                    }
                    .buttonStyle(LuminaSecondaryButtonStyle())
                    .controlSize(.small)
                }
            }

            LuminaDivider()

            if let footnote = adjustCapability.qualityMotionFootnote(
                mediaType: adjustMediaType,
                isSlideshow: isSlideshowContext
            ) {
                Text(footnote)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
            }

            qualityResolutionControls(disabled: usesGlobalQualityPower || !adjustCapability.decodeQuality)
                .opacity(adjustCapability.decodeQuality ? 1 : 0.4)
            qualityFrameRateControls(disabled: usesGlobalQualityPower || !adjustCapability.frameRate)
                .opacity(adjustCapability.frameRate ? 1 : 0.4)

            LuminaDivider()

            Text("Pause this display when")
                .font(uiScale.font(.callout).weight(.semibold))
                .foregroundStyle(.secondary)

            qualityPauseControls(disabled: usesGlobalQualityPower)

            if let engine = playbackEngine {
                let state = LuminaDisplayState.from(plan: engine.plan, key: key)
                if case .paused = state {
                    let threshold = Int(prefs?.power[display: key].battery.pauseBelowPercent ?? 20)
                    LuminaStatusPill(
                        style: .status(state),
                        batteryThreshold: threshold,
                        usesAdjustCopy: !usesGlobalQualityPower
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func qualityResolutionControls(disabled: Bool) -> some View {
        let key = displayKey
        let preset = prefs?.playback[display: key] ?? .automatic
        let choice = DecodeCapChoice(preset)
        VStack(alignment: .leading, spacing: LuminaSpace.xs) {
            LuminaSliderLabel(title: "Resolution")
            LuminaSegmentedPicker(
                selection: Binding(
                    get: { DecodeCapChoice(prefs?.playback[display: key] ?? .automatic) },
                    set: { newChoice in
                        guard let prefs else { return }
                        var playback = prefs.playback
                        playback[display: key] = newChoice.qualityPreset
                        prefs.playback = playback
                    }
                ),
                options: DecodeCapChoice.allCases.map {
                    LuminaSegmentedOption($0, title: $0.label)
                }
            )
            .disabled(disabled)
            Text(choice.caption)
                .font(uiScale.font(.caption))
                .foregroundStyle(.secondary)
            if DecodeCapChoice.showsLegacyEfficientCaption(preset) {
                Text("Also limited to 30 fps by an older setting. Pick a resolution to remove the limit.")
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func qualityFrameRateControls(disabled: Bool) -> some View {
        let key = displayKey
        let cap = prefs?.power[display: key].frameCap ?? .native
        let choice = FrameRateChoice(cap)
        VStack(alignment: .leading, spacing: LuminaSpace.xs) {
            LuminaSliderLabel(title: "Frame rate", value: choice.longLabel)
            LuminaSegmentedPicker(
                selection: Binding(
                    get: { FrameRateChoice(prefs?.power[display: key].frameCap ?? .native) },
                    set: { newChoice in
                        guard let prefs else { return }
                        var power = prefs.power
                        var rules = power[display: key]
                        rules.frameCap = newChoice.frameRateCap
                        power[display: key] = rules
                        prefs.power = power
                    }
                ),
                options: FrameRateChoice.choices(includingSelected: cap).map {
                    LuminaSegmentedOption($0, title: $0.shortLabel)
                }
            )
            .disabled(disabled)
            Text("Caps GIFs and slideshows. Videos save the most power when paused.")
                .font(uiScale.font(.caption))
                .foregroundStyle(.secondary)
            if prefs?.power[display: key].fullQualityWhileStudioOpen == true {
                Text("Studio shows full quality while it’s open.")
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func qualityPauseControls(disabled: Bool) -> some View {
        let key = displayKey
        let pauseOnBattery = prefs?.power[display: key].battery.pauseOnBattery ?? false
        let pauseBelowEnabled = prefs?.power[display: key].battery.pauseBelowEnabled ?? false

        HStack {
            Text("On battery")
                .font(uiScale.font(.body))
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { prefs?.power[display: key].battery.pauseOnBattery ?? false },
                set: { val in
                    guard let prefs else { return }
                    var power = prefs.power
                    var rules = power[display: key]
                    rules.battery.pauseOnBattery = val
                    power[display: key] = rules
                    prefs.power = power
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(uiScale.controlSize())
            .accessibilityLabel("On battery")
        }
        .disabled(disabled)

        HStack {
            Text("Battery is below")
                .font(uiScale.font(.body))
            Spacer(minLength: 0)
            if pauseBelowEnabled {
                Text("\(Int(prefs?.power[display: key].battery.pauseBelowPercent ?? 20))%")
                    .font(uiScale.font(.callout).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(
                get: { prefs?.power[display: key].battery.pauseBelowEnabled ?? false },
                set: { val in
                    guard let prefs else { return }
                    var power = prefs.power
                    var rules = power[display: key]
                    rules.battery.pauseBelowEnabled = val
                    power[display: key] = rules
                    prefs.power = power
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(uiScale.controlSize())
            .accessibilityLabel("Battery is below")
        }
        .disabled(disabled || pauseOnBattery)

        if pauseOnBattery {
            Text("Already paused on battery.")
                .font(uiScale.font(.caption))
                .foregroundStyle(.secondary)
        }

        if pauseBelowEnabled && !pauseOnBattery {
            LuminaSlider(
                value: Binding(
                    get: { prefs?.power[display: key].battery.pauseBelowPercent ?? 20 },
                    set: { val in
                        guard let prefs else { return }
                        var power = prefs.power
                        var rules = power[display: key]
                        rules.battery.pauseBelowPercent = val
                        power[display: key] = rules
                        prefs.power = power
                    }
                ),
                range: 5...80,
                step: 5,
                label: "Battery threshold"
            )
            .disabled(disabled)
        }

        HStack {
            Text("A window covers it")
                .font(uiScale.font(.body))
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { prefs?.power[display: key].pauseWhenCovered ?? true },
                set: { val in
                    guard let prefs else { return }
                    var power = prefs.power
                    var rules = power[display: key]
                    rules.pauseWhenCovered = val
                    power[display: key] = rules
                    prefs.power = power
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(uiScale.controlSize())
            .accessibilityLabel("A window covers it")
        }
        .disabled(disabled)

        HStack {
            Text("Low Power Mode is on")
                .font(uiScale.font(.body))
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { prefs?.power[display: key].pauseInLowPowerMode ?? true },
                set: { val in
                    guard let prefs else { return }
                    var power = prefs.power
                    var rules = power[display: key]
                    rules.pauseInLowPowerMode = val
                    power[display: key] = rules
                    prefs.power = power
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(uiScale.controlSize())
            .accessibilityLabel("Low Power Mode is on")
        }
        .disabled(disabled)
    }

    // MARK: - Performance / Compression Content

    @ViewBuilder private var performanceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // File info row
            HStack(spacing: 16) {
                infoChip(icon: "doc.fill",         label: videoInfo.fileSize)
                infoChip(icon: "aspectratio.fill",  label: videoInfo.resolution)
                infoChip(icon: "clock.fill",        label: videoInfo.duration)
            }
            .task(id: assignment?.filePath) {
                guard let url = assignment.flatMap({ $0.resolvedURL() ?? $0.filePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } }) else { return }
                videoInfo = await compressor.loadInfo(for: url)
            }

            LuminaDivider()

            // Preset picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Target Quality")
                    .font(uiScale.scaledFont(13))
                    .foregroundStyle(.secondary)

                LuminaSegmentedPicker(
                    selection: $selectedPreset,
                    options: VideoCompressor.QualityPreset.allCases.map {
                        LuminaSegmentedOption($0, title: $0.label)
                    }
                )

                // Dynamic description + size estimate
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPreset.shortDescription)
                        .font(uiScale.scaledFont(11))
                        .foregroundStyle(.secondary)
                    if videoInfo.fileSizeBytes > 0 {
                        let est = Int64(Double(videoInfo.fileSizeBytes) * selectedPreset.estimatedSizeRatio)
                        Text("Estimated output: ~\(ByteCountFormatter.string(fromByteCount: est, countStyle: .file))")
                            .font(uiScale.scaledFont(11))
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: selectedPreset)
            }

            // Compress / progress / result
            if compressor.isCompressing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(compressor.statusMessage)
                            .font(uiScale.scaledFont(12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", compressor.progress * 100))
                            .font(uiScale.scaledFont(12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: compressor.progress)
                    Button("Cancel") { compressor.cancel() }
                        .buttonStyle(LuminaSecondaryButtonStyle()).controlSize(uiScale.controlSize())
                        .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        Task { await runCompression() }
                    } label: {
                        Label("Compress Video", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(LuminaProminentButtonStyle())
                    .controlSize(uiScale.controlSize())
                    .help("Re-encode this video at the selected quality to reduce GPU load and file size")

                    if let lastURL = compressor.lastCompressedURL {
                        Button("Use Compressed") {
                            pendingCompressedURL = lastURL
                            showUseCompressedAlert = true
                        }
                        .buttonStyle(LuminaSecondaryButtonStyle()).controlSize(uiScale.controlSize())
                        .help("Switch this monitor to use the already-compressed version")
                    }
                }
            }
        }
        .alert("Use Compressed Version?", isPresented: $showUseCompressedAlert, presenting: pendingCompressedURL) { url in
            Button("Use Compressed") {
                store.chooseVideoForMonitorID(monitorID: monitor.id, url: url)
            }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("This will switch the wallpaper on this display to the compressed copy at \(url.lastPathComponent).")
        }
        .alert("Compression Failed", isPresented: $showCompressError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(compressErrorMessage)
        }
    }

    private func runCompression() async {
        guard let url = assignment.flatMap({ $0.resolvedURL() ?? $0.filePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } }) else { return }
        do {
            let out = try await compressor.compress(sourceURL: url, preset: selectedPreset)
            // Reload file info for the compressed copy
            let newInfo = await compressor.loadInfo(for: out)
            let origBytes = videoInfo.fileSizeBytes
            let savedBytes = origBytes - newInfo.fileSizeBytes
            if savedBytes > 0 {
                compressor.statusMessage = "Saved ~\(ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file))"
            }
            // Immediately add the compressed copy to the persistent library so it ALWAYS stays
            // reachable in the grid — even after compressing other presets or switching the
            // display's wallpaper. This is what prevents compressed files from "disappearing".
            store.addMediaToLibrary(url: out, enforceAccessPolicy: false)
            pendingCompressedURL = out
            showUseCompressedAlert = true
        } catch VideoCompressor.CompressionError.cancelled {
            // user cancelled — no alert needed
        } catch {
            compressErrorMessage = error.localizedDescription
            showCompressError = true
        }
    }

    @ViewBuilder private func infoChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: DisplayScale.points(10)))
                .foregroundStyle(.secondary)
            Text(label)
                .font(uiScale.scaledFont(11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DisplayScale.points(8))
        .padding(.vertical, DisplayScale.points(4))
        .background(Color.luminaCard.opacity(0.8), in: RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous).strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

} // end MonitorDetailPanel

private enum PreviewColumnWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Settings Group

private struct SettingsGroup<Content: View>: View {
    let icon: String
    let title: String
    var caption: String? = nil
    var footnote: String? = nil
    var flash: Bool = false

    @ViewBuilder let content: () -> Content

    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LuminaSpace.sm) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                    .foregroundStyle(theme.current.color)
                    .frame(width: DisplayScale.points(20), alignment: .center)
                Text(title)
                    .font(uiScale.font(.bodyStrong))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let caption {
                    Text(caption)
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, LuminaSpace.sm)

            if let footnote {
                Text(footnote)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, LuminaSpace.sm)
            }

            VStack(alignment: .leading, spacing: LuminaSpace.md) {
                content()
            }
        }
        .padding(LuminaSpace.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .luminaGlassPanel(cornerRadius: LuminaRadius.panel)
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                .strokeBorder(
                    flash && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                        ? theme.current.color
                        : Color.clear,
                    lineWidth: flash && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 2 : 0
                )
        )
    }
}

// MARK: - VideoScaling display name extension

extension VideoScaling {
    var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill (Crop)"
        case .stretch: return "Stretch"
        }
    }
}

private extension LoopMode {
    var uiDescription: String {
        switch self {
        case .loop: return "Starts over."
        case .once: return "Plays once, then shows black."
        case .bounce: return "Plays forward, then backward."
        }
    }
}
