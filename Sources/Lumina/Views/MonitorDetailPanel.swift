import SwiftUI
import AppKit
import AVFoundation

/// Side panel for the selected monitor: full-height live preview by default, with a
/// Per-display Adjust column that slides in for Pin / Display / Effects / etc.
struct MonitorDetailPanel: View {
    let monitor: MonitorInfo
    @ObservedObject var store: WallpaperManagerStore

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

    /// Must match the window growth delta so the preview width stays stable while toggling.
    private static var settingsInspectorWidth: CGFloat { DisplayScale.points(340) }
    private static let settingsToggleDuration: TimeInterval = 0.42
    /// Slightly longer, ease-out collapse so closing doesn't feel stepped.
    private static let settingsCollapseDuration: TimeInterval = 0.55
    private static let hasDiscoveredAdjustKey = "Lumina.HasDiscoveredAdjust"

    // Local state for settings (synced with store)
    @State private var selectedScaling: VideoScaling = .fill
    @State private var keepOnStartup: Bool = false
    @State private var playbackSpeed: Double = 1.0
    @State private var localCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var videoPreviewTime: Double = 0.15
    @State private var videoDuration: Double = 0
    @State private var committedUseStaticFrame: Bool = false
    @State private var showVideoFrameGuide: Bool = true
    @State private var frameActionFeedback: String?
    @State private var frameFeedbackTask: Task<Void, Never>?
    @State private var loopFadeEnabled: Bool = false
    @State private var loopFadeDuration: Double = 1.5
    @State private var loopFadeEasing: MonitorAssignment.FadeEasing = .easeInOut
    @State private var brightness: Double = 0.0
    @State private var slideshowItems: [String] = []
    @State private var slideshowInterval: Double = 10.0
    @State private var slideshowTransition: MonitorAssignment.SlideshowTransition = .fade
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
    @State private var loopMode: MonitorAssignment.LoopMode = .loop

    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var themeManager = ThemeManager.shared

    // MARK: - Computed

    private var assignment: MonitorAssignment? {
        store.assignment(for: monitor.id)
    }

    private var scalingDescription: String {
        switch selectedScaling {
        case .fit:     return "Full video visible with letterbox/pillarbox bars."
        case .fill:    return "Video crops to fill the screen — edges may be cut off."
        case .stretch: return "Video stretches to cover the screen — may look distorted."
        }
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
        store.setVideoFrameTime(for: monitor, time: videoPreviewTime, useStatic: useStatic)
        let label = formattedVideoTime(videoPreviewTime * max(videoDuration, 0))
        if useStatic {
            showFrameFeedback("Desktop is now a still at \(label). Your crop is applied.")
        } else {
            showFrameFeedback("Desktop video now plays from \(label).")
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
                .padding(.horizontal, DisplayScale.points(12))
                .padding(.vertical, DisplayScale.points(10))
        }
        .onAppear {
            loadCurrentValues()
            maybeAutoOpenAdjustColumn(
                hasMedia: assignment?.filePath.map { !$0.isEmpty } ?? false
            )
        }
        .onChange(of: monitor.id) { _, _ in loadCurrentValues() }
        // Reloading when the media itself changes resets the staged adjustments to the new
        // assignment's values (so picking new media doesn't leave stale pending edits).
        .onChange(of: assignment?.filePath) { _, newPath in
            loadCurrentValues()
            maybeAutoOpenAdjustColumn(hasMedia: newPath.map { !$0.isEmpty } ?? false)
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
        .onChange(of: cropEditMode) { _, visible in
            NotificationCenter.default.post(
                name: .cropEditorVisibilityChanged,
                object: nil,
                userInfo: ["visible": visible]
            )
        }
        // Adjust column window resize is driven explicitly from `toggleConfigColumn`
        // (instant grow on open; column out then soft window shrink on close).
        .onDisappear {
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
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Slideshow active on desktop — \(a.slideshowItems.count) images cycling")
                        .font(uiScale.scaledFont(11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, DisplayScale.points(10))
                .padding(.vertical, DisplayScale.points(8))
            }
        }
        .padding(.horizontal, DisplayScale.points(8))
        .padding(.bottom, DisplayScale.points(6))
    }

    private var settingsColumn: some View {
        ScrollView {
            VStack(spacing: DisplayScale.points(10)) {
                keepOnStartupControl

                SettingsGroup(icon: "display", title: "Display") {
                    displayContent
                }

                SettingsGroup(icon: "wand.and.stars", title: "Visual Effects") {
                    visualEffectsContent
                }

                if assignment?.mediaType == .video || assignment?.mediaType == .animatedImage {
                    SettingsGroup(icon: "play.fill", title: "Playback & Looping") {
                        playbackContent
                    }
                }

                if assignment?.mediaType == .video, let _ = assignment?.filePath {
                    SettingsGroup(icon: "speedometer", title: "Performance") {
                        performanceContent
                    }
                }

                SettingsGroup(icon: "photo.on.rectangle.angled", title: "Slideshow") {
                    slideshowContent
                }
            }
            .padding(.horizontal, DisplayScale.points(8))
            .padding(.vertical, DisplayScale.points(8))
        }
        .luminaWindowBackdrop()
    }

    /// True when the staged (preview) settings differ from what's currently applied to the
    /// assignment — i.e. there are changes the user hasn't pushed to the desktop yet.
    private var hasUnappliedChanges: Bool {
        guard let a = assignment else { return false }
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

    /// Pushes every staged adjustment to the live desktop wallpaper (and persistence).
    private func applyToWallpaper() {
        store.setScaling(for: monitor, scaling: selectedScaling)
        store.setPlaybackSpeed(for: monitor, speed: playbackSpeed)
        store.setCropRect(for: monitor, cropRect: localCropRect)
        // Note: videoFrameTime + static/video choice is set explicitly via the buttons in crop mode
        // (not auto-saved on every Apply, to respect the user's "Freeze" vs "Video start" choice)
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

    // MARK: - Header (optional)

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: DisplayScale.points(2)) {
                Text(monitor.name)
                    .font(uiScale.scaledFont(18, weight: .semibold))
                Text(monitor.resolution)
                    .font(uiScale.scaledFont(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DisplayScale.points(20)))
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .foregroundStyle(.secondary)
            .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
            .contentShape(Rectangle())
        }
        .padding(DisplayScale.points(20))
    }

    // MARK: - Live Preview

    /// The assignment to show in the preview. For a slideshow monitor (no single filePath,
    /// but image items present) we preview the first image so the display isn't blank.
    private var previewAssignment: MonitorAssignment? {
        guard var a = assignment else { return nil }
        if a.filePath == nil, let first = a.slideshowItems.first {
            a.filePath = first
            a.mediaType = .image
        }
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

                    ZStack(alignment: .topTrailing) {
                        Group {
                            if cropEditMode {
                                // Crop editing happens directly on the preview: the editor shows the
                                // full (uncropped) media as its background with draggable handles.
                                CropRectangle(
                                    cropRect: $localCropRect,
                                    onChange: { newRect in
                                        // Staged only — committed to the desktop on Apply.
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
                                    grayscale: grayscale
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(previewOpacity)

                        cropToggleButton
                            .padding(10)
                            .opacity(cropEditMode ? 0 : 1)
                            .allowsHitTesting(!cropEditMode)
                    }
                    .frame(width: fittedWidth, height: fittedHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .padding(DisplayScale.points(8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.luminaCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.luminaBorder, lineWidth: 1)
                        )
                    VStack(spacing: DisplayScale.points(8)) {
                        Image(systemName: "display")
                            .font(.system(size: DisplayScale.points(36)))
                            .foregroundStyle(.secondary)
                        Text("No wallpaper assigned")
                            .font(uiScale.scaledFont(13, weight: .medium))
                        Text("Pick one from the library.")
                            .font(uiScale.scaledFont(11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(DisplayScale.points(8))
            }
        }
    }

    /// Floating button on the preview that enters interactive crop editing.
    private var cropToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                cropEditMode = true
                if localCropRect == CGRect(x: 0, y: 0, width: 1, height: 1) {
                    resetCropToDefault()
                }
            }
        } label: {
            Label("Crop", systemImage: "crop")
                .font(.system(size: DisplayScale.points(12), weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, DisplayScale.points(10))
                .padding(.vertical, DisplayScale.points(6))
                .background(Color.black.opacity(0.6), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .help("Crop and position — drag inside to move, pull corners to resize")
    }

    @ViewBuilder
    private func cropEditorToolbar(assignment a: MonitorAssignment) -> some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(10)) {
            HStack(alignment: .center, spacing: DisplayScale.points(8)) {
                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { cropEditMode = false }
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(LuminaSecondaryButtonStyle(prominent: true))

                Button { resetCropToDefault() } label: {
                    Text("Reset")
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .help("Center the crop frame on the media")
            }
            .padding(.top, DisplayScale.points(12))

            if a.mediaType == .video {
                cropVideoFrameControls(assignment: a)
            }
        }
        .padding(.horizontal, DisplayScale.points(12))
        .padding(.bottom, DisplayScale.points(10))
        .help("Drag inside the crop to move · pull corners to resize")
    }

    @ViewBuilder
    private func cropVideoFrameControls(assignment a: MonitorAssignment) -> some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(8)) {
            LuminaDivider()

            if showVideoFrameGuide {
                LuminaHintBubble(
                    icon: "lightbulb.fill",
                    message: "Scrub the timeline to preview a moment, then pick how it should appear on your desktop — as a frozen still or as a playing video from that point.",
                    style: .tip,
                    onDismiss: { showVideoFrameGuide = false }
                )
            }

            VStack(alignment: .leading, spacing: DisplayScale.points(8)) {
                HStack(alignment: .firstTextBaseline, spacing: DisplayScale.points(8)) {
                    Label("Pick a frame", systemImage: "film")
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
                    .help("Scrub to preview a frame — nothing changes on your desktop until you choose an option below")

                HStack(spacing: DisplayScale.points(8)) {
                    Group {
                        if committedUseStaticFrame {
                            Button { commitVideoFrame(useStatic: true) } label: {
                                Label("Use as still", systemImage: "photo.fill")
                                    .font(uiScale.scaledFont(12, weight: .semibold))
                            }
                            .buttonStyle(LuminaProminentButtonStyle())
                        } else {
                            Button { commitVideoFrame(useStatic: true) } label: {
                                Label("Use as still", systemImage: "photo.fill")
                                    .font(uiScale.scaledFont(12, weight: .semibold))
                            }
                            .buttonStyle(LuminaSecondaryButtonStyle())
                        }
                    }
                    .controlSize(uiScale.controlSize())
                    .help("Freeze this exact frame on your desktop — no video playback")

                    Group {
                        if !committedUseStaticFrame, a.videoFrameTime != nil {
                            Button { commitVideoFrame(useStatic: false) } label: {
                                Label("Start video here", systemImage: "play.rectangle.fill")
                                    .font(uiScale.scaledFont(12, weight: .semibold))
                            }
                            .buttonStyle(LuminaProminentButtonStyle())
                        } else {
                            Button { commitVideoFrame(useStatic: false) } label: {
                                Label("Start video here", systemImage: "play.rectangle.fill")
                                    .font(uiScale.scaledFont(12, weight: .semibold))
                            }
                            .buttonStyle(LuminaSecondaryButtonStyle())
                        }
                    }
                    .controlSize(uiScale.controlSize())
                    .help("Play the video from this frame with your crop applied")
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
                        ? "Desktop: frozen still at \(label)"
                        : "Desktop: video playing from \(label)",
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
        Toggle(isOn: $keepOnStartup) {
            HStack(alignment: .center, spacing: DisplayScale.points(8)) {
                Image(systemName: keepOnStartup ? "pin.fill" : "pin")
                    .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                    .foregroundStyle(keepOnStartup ? Color.yellow : .secondary)
                    .frame(width: DisplayScale.points(20), alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep on startup")
                        .font(uiScale.scaledFont(13, weight: .semibold))

                    Text(keepOnStartup
                         ? "Restores this wallpaper on launch · saves immediately"
                         : "Wallpaper stays until you Clear · won’t restore next launch")
                        .font(uiScale.scaledFont(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toggleStyle(.switch)
        .controlSize(uiScale.controlSize())
        .onChange(of: keepOnStartup) { _, newValue in
            // Pin flag only — do not blank the live desktop (use Clear for that).
            store.setKeepOnStartup(for: monitor, enabled: newValue)
        }
        .padding(.horizontal, DisplayScale.points(10))
        .padding(.vertical, DisplayScale.points(8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.luminaCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(keepOnStartup ? Color.yellow.opacity(0.5) : Color.luminaBorder, lineWidth: 1)
                )
        )
        .help("Pin saves immediately and restores on launch. Turning off does not clear the live wallpaper — use Clear for that. Crop, effects, and playback still need Apply.")
    }

    // MARK: - Playback Section Content

    private var playbackContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Playback Speed
            VStack(alignment: .leading, spacing: 4) {
                LuminaSliderLabel(title: "Playback Speed", value: String(format: "%.2fx", playbackSpeed))
                LuminaSlider(value: $playbackSpeed, range: 0.25...4.0, step: 0.25)
            }

            // Loop Mode (video only — GIFs and stills use their own playback path)
            if assignment?.mediaType == .video {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Loop Mode").font(uiScale.scaledFont(13)).foregroundStyle(.secondary)
                    Picker("Loop Mode", selection: $loopMode) {
                        ForEach(MonitorAssignment.LoopMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                                .help(mode.modeDescription)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(uiScale.controlSize())
                    Text(loopMode.modeDescription)
                        .font(uiScale.scaledFont(11)).foregroundStyle(.secondary)
                        .animation(.easeInOut(duration: 0.15), value: loopMode)
                }
            }

            // Loop Crossfade (video only — requires Loop mode)
            if assignment?.mediaType == .video {
                Toggle("Fade at loop point", isOn: $loopFadeEnabled)
                    .toggleStyle(.switch)
                    .font(uiScale.scaledFont(13))
                    .controlSize(uiScale.controlSize())
                    .disabled(loopMode != .loop)
                    .help(loopMode == .loop
                          ? "Smoothly fade out and back in each time the video loops"
                          : "Only available when Loop Mode is set to Loop")

                if loopMode != .loop {
                    Text("Set Loop Mode to Loop to use crossfade.")
                        .font(uiScale.scaledFont(11))
                        .foregroundStyle(.secondary)
                }

                if loopFadeEnabled && loopMode == .loop {
                    VStack(alignment: .leading, spacing: 8) {
                        if hasUnappliedChanges && (assignment.map { a in
                            loopFadeEnabled != a.loopFadeEnabled
                                || abs(loopFadeDuration - a.loopFadeDuration) > 0.001
                                || loopFadeEasing != a.loopFadeEasing
                        } ?? false) {
                            LuminaHintBubble(
                                icon: "arrow.up.circle",
                                message: "Apply to Wallpaper to enable the fade on your desktop.",
                                style: .tip
                            )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            LuminaSliderLabel(title: "Fade Duration", value: "\(Int(loopFadeDuration * 1000))ms")
                            LuminaSlider(value: $loopFadeDuration, range: 0.1...5.0, step: 0.05)
                        }
                        .help("Total crossfade duration at each loop point (100ms–5000ms)")

                        VStack(alignment: .leading, spacing: 4) {
                            LuminaSliderLabel(title: "Easing")
                            Picker("Easing", selection: $loopFadeEasing) {
                                ForEach(MonitorAssignment.FadeEasing.allCases, id: \.self) { e in
                                    Text(e.label).tag(e)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .help("Controls how the opacity ramps in and out during the fade")

                        Button("Preview fade") { previewFadeInPreview() }
                            .buttonStyle(LuminaSecondaryButtonStyle())
                            .controlSize(uiScale.controlSize())
                            .help("Simulate this fade in the preview above")
                    }
                }
            }

            // Volume
            VStack(alignment: .leading, spacing: 4) {
                LuminaSliderLabel(
                    title: "Volume",
                    value: audioVolume < 0.01 ? "Muted" : String(format: "%.0f%%", audioVolume * 100)
                )
                HStack {
                    Image(systemName: audioVolume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                        .font(uiScale.scaledFont(12))
                    LuminaSlider(value: $audioVolume, range: 0...1)
                }
            }
        }
    }

    // MARK: - Display Section Content

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Scaling Mode
            VStack(alignment: .leading, spacing: 6) {
                Text("Scaling Mode").font(uiScale.scaledFont(13)).foregroundStyle(.secondary)
                Picker("Scaling", selection: $selectedScaling) {
                    Text("Fit").tag(VideoScaling.fit)
                        .help("Letterbox: shows full video with black bars on sides/top")
                    Text("Fill").tag(VideoScaling.fill)
                        .help("Crop to fill: video fills the screen, edges may be cropped")
                    Text("Stretch").tag(VideoScaling.stretch)
                        .help("Stretch: video fills screen, may appear distorted")
                }
                .pickerStyle(.segmented)
                .controlSize(uiScale.controlSize())
                Text(scalingDescription)
                    .font(uiScale.scaledFont(11)).foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.15), value: selectedScaling)
            }

            // Crop is edited on the live preview — use the Crop pill on the preview image.
            if assignment != nil, !cropEditMode {
                Text("Use Crop on the preview to position the frame.")
                    .font(uiScale.scaledFont(11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Visual Effects Section Content

    private var visualEffectsContent: some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(10)) {
            VStack(alignment: .leading, spacing: 4) {
                LuminaSliderLabel(title: "Brightness", value: String(format: "%+.2f", brightness))
                LuminaSlider(value: $brightness, range: -0.5...0.5, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                LuminaSliderLabel(title: "Opacity", value: String(format: "%.0f%%", opacity * 100))
                LuminaSlider(value: $opacity, range: 0...1)
            }

            VStack(alignment: .leading, spacing: 4) {
                LuminaSliderLabel(title: "Saturation", value: String(format: "%.1f", saturation))
                LuminaSlider(value: $saturation, range: 0...2)
            }

            VStack(alignment: .leading, spacing: 4) {
                LuminaSliderLabel(title: "Hue", value: String(format: "%.0f°", hue))
                LuminaSlider(value: $hue, range: -180...180)
            }

            // Grayscale
            Toggle("Grayscale", isOn: $grayscale)
                .toggleStyle(.switch)
                .controlSize(uiScale.controlSize())
                .font(uiScale.scaledFont(13))
        }
    }

    // MARK: - Slideshow Section Content

    private var slideshowContent: some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(8)) {
            if slideshowItems.isEmpty {
                Text("Build an image queue for this display.")
                    .font(uiScale.scaledFont(12))
                    .foregroundStyle(.secondary)
            } else {
                Text("^[\(slideshowItems.count) image](inflect: true) · \(Int(slideshowInterval))s · \(slideshowTransition.rawValue.capitalized)\(slideshowKenBurnsEnabled ? " · Ken Burns" : "")")
                    .font(uiScale.scaledFont(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    showSlideshowConfig = true
                } label: {
                    Label(slideshowItems.isEmpty ? "Create Slideshow…" : "Configure…",
                          systemImage: "slider.horizontal.below.rectangle")
                }
                .buttonStyle(LuminaProminentButtonStyle())
                .controlSize(uiScale.controlSize())

                if !slideshowItems.isEmpty {
                    Button("Clear") {
                        slideshowItems.removeAll()
                        store.setSlideshowItems(for: monitor, items: [])
                    }
                    .buttonStyle(LuminaSecondaryButtonStyle())
                    .controlSize(uiScale.controlSize())
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
            let columnDuration = Self.settingsCollapseDuration
            let windowDuration: TimeInterval = 0.40
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: columnDuration)) {
                showSettingsColumn = false
            }
            previewUnlockTask = Task { @MainActor in
                let columnNs = UInt64(columnDuration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: columnNs)
                guard !Task.isCancelled else { return }
                postConfigColumnVisibility(false, animateWindow: true, duration: windowDuration)
                let windowNs = UInt64(windowDuration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: windowNs)
                guard !Task.isCancelled else { return }
                lockedPreviewWidth = nil
            }
        }
    }

    /// Opens Adjust once when the user first assigns media, so Display / Effects aren't hidden.
    private func maybeAutoOpenAdjustColumn(hasMedia: Bool) {
        guard hasMedia, !showSettingsColumn else { return }
        guard !UserDefaults.standard.bool(forKey: Self.hasDiscoveredAdjustKey) else { return }
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
            duration: Self.settingsToggleDuration
        )
        withAnimation(
            .timingCurve(0.25, 0.1, 0.25, 1.0, duration: Self.settingsToggleDuration)
        ) {
            showSettingsColumn = true
        }
        UserDefaults.standard.set(true, forKey: Self.hasDiscoveredAdjustKey)
    }

    private var actionButtons: some View {
        HStack(spacing: DisplayScale.points(8)) {
            if hasUnappliedChanges, assignment != nil {
                Button {
                    applyToWallpaper()
                } label: {
                    Label("Apply to Wallpaper", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LuminaProminentButtonStyle())
                .help(applyButtonHelp)
            } else {
                Label(
                    assignment == nil ? "No wallpaper" : "Up to date",
                    systemImage: assignment == nil ? "photo" : "checkmark.circle.fill"
                )
                .font(uiScale.scaledFont(12, weight: .medium))
                .foregroundStyle(.secondary)
                .help(applyButtonHelp)
                .accessibilityLabel(assignment == nil ? "No wallpaper assigned" : "Applied, up to date")
            }

            if monitor.assignedVideoName != nil {
                Button("Clear", role: .destructive) {
                    store.clearAssignment(for: monitor)
                }
                .buttonStyle(LuminaSecondaryButtonStyle(destructive: true))
                .help("Remove the wallpaper from this display")
            }

            Button("Reset Adjustments") {
                resetToDefaults()
            }
            .buttonStyle(LuminaSecondaryButtonStyle())
            .help("Reset staged crop, speed, and effects to defaults (preview only — Apply to commit)")
            .disabled(assignment == nil)

            Spacer(minLength: DisplayScale.points(4))

            Button {
                toggleConfigColumn()
            } label: {
                Label("Adjust", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(LuminaSecondaryButtonStyle(prominent: showSettingsColumn))
            .help(showSettingsColumn ? "Hide wallpaper adjustments" : "Show wallpaper adjustments")
            .accessibilityLabel(showSettingsColumn ? "Hide Adjust" : "Show Adjust")
            .accessibilityAddTraits(showSettingsColumn ? .isSelected : [])

            if showHeader {
                Button("Done") { onClose() }
                    .buttonStyle(LuminaSecondaryButtonStyle())
            }
        }
    }

    /// Help text for the Apply control.
    private var applyButtonHelp: String {
        if assignment == nil {
            return "Pick a wallpaper from the library first"
        }
        if !hasUnappliedChanges {
            return "Preview already matches the live desktop"
        }
        return "Push the previewed settings to the live desktop wallpaper"
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
            frameActionFeedback = nil
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

                Picker("", selection: $selectedPreset) {
                    ForEach(VideoCompressor.QualityPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(uiScale.controlSize())

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
        .background(Color.luminaCard.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

} // end MonitorDetailPanel

private enum PreviewColumnWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Settings Group
// A consistently styled visual container for a logical group of related controls.
//
// Design goals:
// - All cards share the same minHeight so short boxes (Slideshow empty state,
//   Visual Effects) scale visually with the taller ones (Display, Visual Effects, etc.).
// - Strong consistent rhythm (header style, padding, internal spacing).
// - Content stays top-aligned; extra space goes below via Spacer.
// - No collapse/expand — everything is always visible and scrollable in one container.

private struct SettingsGroup<Content: View>: View {
    let icon: String
    let title: String

    @ViewBuilder let content: () -> Content

    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DisplayScale.points(8)) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                    .foregroundStyle(theme.current.color)
                    .frame(width: DisplayScale.points(20), alignment: .center)
                Text(title)
                    .font(uiScale.scaledFont(13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, DisplayScale.points(10))
            .padding(.top, DisplayScale.points(8))
            .padding(.bottom, DisplayScale.points(4))

            VStack(alignment: .leading, spacing: DisplayScale.points(8)) {
                content()
            }
            .padding(.horizontal, DisplayScale.points(10))
            .padding(.bottom, DisplayScale.points(10))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .luminaGlassPanel(cornerRadius: 10)
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
