import SwiftUI
import AppKit
import AVFoundation

/// Side panel that appears when a user selects a monitor in the layout.
/// Contains live preview + all per-monitor settings, organized into collapsible sections.
struct MonitorDetailPanel: View {
    let monitor: MonitorInfo
    @ObservedObject var store: WallpaperManagerStore

    var onClose: () -> Void = {}
    var showHeader: Bool = true

    // Preview resize state
    @State private var previewHeight: CGFloat = 0
    /// Height snapshot taken when the resize drag begins — DragGesture.translation is the
    /// cumulative offset from the gesture start, so it must be applied to a fixed baseline.
    @State private var previewHeightAtDragStart: CGFloat?
    @State private var resizeCursorPushed = false
    @State private var previewOpacity: Double = 1.0

    // When true, the live preview becomes an interactive crop editor (drag to move,
    // corners to resize) — no separate crop preview needed.
    @State private var cropEditMode: Bool = false
    @State private var previewSourceAspect: CGFloat = 16.0 / 9.0

    // Presents the dedicated slideshow queue/configuration sheet.
    @State private var showSlideshowConfig: Bool = false

    // Local state for settings (synced with store)
    @State private var selectedScaling: VideoScaling = .fill
    @State private var keepOnStartup: Bool = false
    @State private var playbackSpeed: Double = 1.0
    @State private var localCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var videoPreviewTime: Double = 0.15
    @State private var videoDuration: Double = 0
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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                headerSection
                LuminaDivider()
            }

            // PINNED: the live preview stays frozen at the top while the settings scroll,
            // so you can watch your changes (WYSIWYG) before committing them with Apply.
            livePreviewSection

            LuminaDivider()

            // SCROLLABLE settings.
            ScrollView {
                VStack(spacing: 16) {
                    // Prominent "Keep on startup" control.
                    keepOnStartupControl

                    // Core visual controls first (most frequently adjusted)
                    SettingsGroup(icon: "display", title: "Display") {
                        displayContent
                    }

                    SettingsGroup(icon: "wand.and.stars", title: "Visual Effects") {
                        visualEffectsContent
                    }

                    // Playback behavior (only relevant for video/animated)
                    if assignment?.mediaType == .video || assignment?.mediaType == .animatedImage {
                        SettingsGroup(icon: "play.fill", title: "Playback & Looping") {
                            playbackContent
                        }
                    }

                    // Performance tools (video only)
                    if assignment?.mediaType == .video, let _ = assignment?.filePath {
                        SettingsGroup(icon: "speedometer", title: "Performance") {
                            performanceContent
                        }
                    }

                    // Slideshow — powerful but secondary
                    SettingsGroup(icon: "photo.on.rectangle.angled", title: "Slideshow") {
                        slideshowContent
                    }

                    // Advanced / power-user options (kept small now that Keep is promoted)
                    SettingsGroup(icon: "gearshape.2", title: "Advanced") {
                        advancedContent
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            LuminaDivider()

            // PINNED: bottom action bar with the prominent "Apply to Wallpaper" commit.
            actionButtons
                .padding(16)
        }
        .onAppear {
            if previewHeight < 1 { previewHeight = DisplayScale.points(220) }
            loadCurrentValues()
        }
        .onChange(of: monitor.id) { _, _ in loadCurrentValues() }
        // Reloading when the media itself changes resets the staged adjustments to the new
        // assignment's values (so picking new media doesn't leave stale pending edits).
        .onChange(of: assignment?.filePath) { _, _ in loadCurrentValues() }
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
        .onDisappear {
            // If the panel goes away while crop mode is open, tell the window controller to
            // shrink back — otherwise the grown window frame sticks around.
            if cropEditMode {
                NotificationCenter.default.post(
                    name: .cropEditorVisibilityChanged,
                    object: nil,
                    userInfo: ["visible": false]
                )
            }
        }
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
            VStack(alignment: .leading) {
                Text(monitor.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(monitor.resolution)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(20)
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
        VStack(spacing: 0) {
            if let a = previewAssignment {
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
                                brightness: brightness,
                                previewOpacity: opacity,
                                saturation: saturation,
                                hueDegrees: hue,
                                grayscale: grayscale
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .cornerRadius(10)
                    .opacity(previewOpacity)

                    cropToggleButton
                        .padding(10)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                if cropEditMode {
                    HStack(spacing: 10) {
                        Button("Reset Crop") {
                            // Reset to full so CropRectangle auto-sets the proper horizontal crop box on the original
                            localCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                            videoPreviewTime = 0.15
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reset to a horizontal crop rect matching your monitor (smaller than full frame)")

                        Spacer()

                        Text("Horizontal crop box locked to monitor aspect • drag to move, corners to resize (smaller only recommended)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)

                    // Video time scrubber (only for video media)
                    if a.mediaType == .video {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Scrub to choose frame")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if videoDuration > 0 {
                                    let t = videoPreviewTime * videoDuration
                                    Text(String(format: "%.1fs / %.1fs", t, videoDuration))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Text("scrub to pick frame")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Slider(
                                value: $videoPreviewTime,
                                in: 0...1
                            )
                            .onChange(of: videoPreviewTime) { _, _ in
                                // Live update the preview frame in CropRectangle
                            }

                            if let a = store.assignment(for: monitor.id), let t = a.videoFrameTime {
                                let mode = a.useStaticVideoFrame ? "Static frame" : "Video start"
                                Text("Current: \(mode) at \(String(format: "%.1f", t * (videoDuration > 0 ? videoDuration : 1)))s")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Button {
                                    store.setVideoFrameTime(for: monitor, time: videoPreviewTime, useStatic: true)
                                } label: {
                                    Label("Freeze as Static Image", systemImage: "photo")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help("Use the current frame as a still wallpaper (no video playback)")

                                Button {
                                    store.setVideoFrameTime(for: monitor, time: videoPreviewTime, useStatic: false)
                                } label: {
                                    Label("Video starting at this time", systemImage: "play.rectangle")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Play the video, but start/seek to this frame with the crop applied")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .task(id: a.filePath) {
                            // Load real duration for the scrubber
                            guard let url = a.resolvedURL() ?? a.filePath.map({ URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }) else { return }
                            let asset = AVURLAsset(url: url)
                            if let dur = try? await asset.load(.duration) {
                                videoDuration = dur.seconds
                            }
                        }
                    }
                } else if !a.slideshowItems.isEmpty {
                    // Visual hint that the desktop is running a slideshow even though
                    // the inline preview only shows single-media at the moment.
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Slideshow active on desktop — \(a.slideshowItems.count) images cycling")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: previewHeight)
                    VStack(spacing: 8) {
                        Image(systemName: "display").font(.system(size: 36))
                        Text("No wallpaper assigned").font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }

            // Drag resize handle
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 32, height: 4)
                Spacer()
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    if !resizeCursorPushed {
                        NSCursor.resizeUpDown.push()
                        resizeCursorPushed = true
                    }
                } else if resizeCursorPushed {
                    NSCursor.pop()
                    resizeCursorPushed = false
                }
            }
            .onDisappear {
                // Balance the cursor stack if the view goes away while hovered —
                // otherwise the resize cursor sticks app-wide.
                if resizeCursorPushed {
                    NSCursor.pop()
                    resizeCursorPushed = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let base = previewHeightAtDragStart ?? previewHeight
                        previewHeightAtDragStart = base
                        previewHeight = max(DisplayScale.points(140), min(DisplayScale.points(500), base + drag.translation.height))
                    }
                    .onEnded { _ in
                        previewHeightAtDragStart = nil
                    }
            )
        }
    }

    /// Floating button on the preview that toggles interactive crop editing.
    private var cropToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                let wasEditing = cropEditMode
                cropEditMode.toggle()
                if !wasEditing, cropEditMode, localCropRect == CGRect(x: 0, y: 0, width: 1, height: 1) {
                    // Set to full so CropRectangle's auto-init sets the proper horizontal box on the full original
                    localCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
            }
        } label: {
            Image(systemName: cropEditMode ? "checkmark.circle.fill" : "crop")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(cropEditMode ? Color.white : Color.white)
                .padding(7)
                .background(cropEditMode ? Color.accentColor : Color.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(cropEditMode ? "Done — finish cropping" : "Crop / Zoom on the preview")
    }

    // MARK: - Prominent Keep on Startup Control
    // This is deliberately placed in a high-visibility position directly under the
    // live preview. "Keep on startup" is one of the highest-stakes decisions in the
    // entire app (it controls whether the wallpaper survives relaunch). It deserves
    // strong visual weight and clear explanation — classic best practice for
    // primary persistence / power-user toggles.

    private var keepOnStartupControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $keepOnStartup) {
                HStack(spacing: 8) {
                    Image(systemName: keepOnStartup ? "pin.fill" : "pin")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(keepOnStartup ? Color.yellow : .secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep this wallpaper on startup")
                            .font(.subheadline.weight(.semibold))

                        Text(keepOnStartup
                             ? "This display will automatically restore when Lumina launches."
                             : "Wallpaper will be black on next launch unless you enable this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .toggleStyle(.switch)
            .onChange(of: keepOnStartup) { _, newValue in
                store.setKeepOnStartup(for: monitor, enabled: newValue)
                if !newValue {
                    store.appDelegate?.clearRenderer(for: monitor.id)
                }
            }

            if keepOnStartup {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Pinned for this display")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.yellow)
                }
                .padding(.leading, 26)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.luminaCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(keepOnStartup ? Color.yellow.opacity(0.5) : Color.luminaBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Playback Section Content

    private var playbackContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Playback Speed
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Playback Speed").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2fx", playbackSpeed))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $playbackSpeed, in: 0.25...4.0, step: 0.25)
                    .controlSize(.large)
            }

            // Loop Crossfade (video only)
            if assignment?.mediaType == .video {
                Toggle("Fade at loop point", isOn: $loopFadeEnabled)
                    .toggleStyle(.switch)
                    .font(.subheadline)

                if loopFadeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Fade Duration")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(loopFadeDuration * 1000))ms")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            // 0–5000ms in 50ms steps (100 increments)
                            Slider(value: $loopFadeDuration, in: 0.0...5.0, step: 0.05)
                        }
                        .help("Total crossfade duration at each loop point (0ms = instant cut, 5000ms = slow fade)")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Easing").font(.subheadline).foregroundStyle(.secondary)
                            Picker("Easing", selection: $loopFadeEasing) {
                                ForEach(MonitorAssignment.FadeEasing.allCases, id: \.self) { e in
                                    Text(e.label).tag(e)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .help("Controls how the opacity ramps in and out during the fade")

                        Button("Preview fade") { previewFadeInPreview() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Simulate this fade in the preview above")
                    }
                }
            }

            // Volume
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(audioVolume < 0.01 ? "Muted" : String(format: "%.0f%%", audioVolume * 100))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: audioVolume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.secondary).font(.caption)
                    Slider(value: $audioVolume, in: 0...1)
                }
            }
        }
    }

    // MARK: - Display Section Content

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Scaling Mode
            VStack(alignment: .leading, spacing: 6) {
                Text("Scaling Mode").font(.subheadline).foregroundStyle(.secondary)
                Picker("Scaling", selection: $selectedScaling) {
                    Text("Fit").tag(VideoScaling.fit)
                        .help("Letterbox: shows full video with black bars on sides/top")
                    Text("Fill").tag(VideoScaling.fill)
                        .help("Crop to fill: video fills the screen, edges may be cropped")
                    Text("Stretch").tag(VideoScaling.stretch)
                        .help("Stretch: video fills screen, may appear distorted")
                }
                .pickerStyle(.segmented)
                Text(scalingDescription)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .animation(.easeInOut(duration: 0.15), value: selectedScaling)
            }

            // Crop / Zoom is now edited directly on the live preview above — tap the crop
            // button on the preview to enter edit mode (no separate editor needed).
            if assignment != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { cropEditMode = true }
                } label: {
                    Label(cropEditMode ? "Editing crop on preview…" : "Crop / Zoom on Preview",
                          systemImage: "crop")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(cropEditMode)
                .help("Edit the crop region directly on the live preview at the top")
            }
        }
    }

    // MARK: - Visual Effects Section Content

    private var visualEffectsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Brightness
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Brightness").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%+.2f", brightness))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $brightness, in: -0.5...0.5, step: 0.05)
                    .controlSize(.large)
            }

            // Opacity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", opacity * 100))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $opacity, in: 0...1)
                    .controlSize(.large)
            }

            // Saturation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Saturation").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", saturation))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $saturation, in: 0...2)
                    .controlSize(.large)
            }

            // Hue Rotation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Hue").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f°", hue))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $hue, in: -180...180)
                    .controlSize(.large)
            }

            // Grayscale
            Toggle("Grayscale", isOn: $grayscale)
                .toggleStyle(.switch)
        }
    }

    // MARK: - Advanced Section Content
    // Note: "Keep on startup" has been promoted to a high-visibility control
    // directly under the live preview for much better discoverability and importance.

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Loop Mode").font(.subheadline).foregroundStyle(.secondary)
                Picker("Loop Mode", selection: $loopMode) {
                    ForEach(MonitorAssignment.LoopMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                            .help(mode.modeDescription)
                    }
                }
                .pickerStyle(.segmented)
                Text(loopMode.modeDescription)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .animation(.easeInOut(duration: 0.15), value: loopMode)
            }
        }
    }

    // MARK: - Slideshow Section Content

    private var slideshowContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if slideshowItems.isEmpty {
                Text("Create a still-image slideshow for this display. Build a queue of images, set the timing, then play — images are also saved to your Library to reuse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo.stack.fill")
                        .foregroundStyle(.secondary)
                    Text("^[\(slideshowItems.count) image](inflect: true) • every \(Int(slideshowInterval))s • \(slideshowTransition.rawValue.capitalized)\(slideshowKenBurnsEnabled ? " • Ken Burns" : "")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text("This display is in slideshow mode (no video loaded). Per-monitor crop and color effects don't apply while a slideshow runs.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button {
                    showSlideshowConfig = true
                } label: {
                    Label(slideshowItems.isEmpty ? "Create Slideshow…" : "Configure Slideshow…",
                          systemImage: "slider.horizontal.below.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if !slideshowItems.isEmpty {
                    Button("Clear") {
                        slideshowItems.removeAll()
                        store.setSlideshowItems(for: monitor, items: [])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Prominent commit: pushes the staged (previewed) settings to the live desktop.
            // Media is assigned by clicking an item in the Library on the left — there's no
            // separate "Choose Media" here (it duplicated the library flow).
            Button {
                applyToWallpaper()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(hasUnappliedChanges ? "Apply to Wallpaper" : "Applied — Up to Date")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasUnappliedChanges || assignment == nil)
            .help("Push the previewed settings to the live desktop wallpaper")

            HStack(spacing: 10) {
                if monitor.assignedVideoName != nil {
                    Button("Clear Wallpaper", role: .destructive) {
                        store.clearAssignment(for: monitor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Button("Reset Adjustments") {
                    resetToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reset the staged display settings to their defaults (preview only — Apply to commit)")

                if showHeader {
                    Button("Done") { onClose() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + half) {
            withAnimation(curve) { previewOpacity = 1 }
        }
    }

    private func resetToDefaults() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            selectedScaling = .fill
            playbackSpeed = 1.0
            localCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            videoPreviewTime = 0.15
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
            if let ft = a.videoFrameTime {
                videoPreviewTime = ft   // initialize scrubber from saved (0 = "start at beginning" is valid)
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
                Text("Target Quality").font(.subheadline).foregroundStyle(.secondary)

                Picker("", selection: $selectedPreset) {
                    ForEach(VideoCompressor.QualityPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                // Dynamic description + size estimate
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPreset.shortDescription)
                        .font(.caption2).foregroundStyle(.tertiary)
                    if videoInfo.fileSizeBytes > 0 {
                        let est = Int64(Double(videoInfo.fileSizeBytes) * selectedPreset.estimatedSizeRatio)
                        Text("Estimated output: ~\(ByteCountFormatter.string(fromByteCount: est, countStyle: .file))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: selectedPreset)
            }

            // Compress / progress / result
            if compressor.isCompressing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(compressor.statusMessage)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", compressor.progress * 100))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: compressor.progress)
                    Button("Cancel") { compressor.cancel() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        Task { await runCompression() }
                    } label: {
                        Label("Compress Video", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Re-encode this video at the selected quality to reduce GPU load and file size")

                    if let lastURL = compressor.lastCompressedURL {
                        Button("Use Compressed") {
                            pendingCompressedURL = lastURL
                            showUseCompressedAlert = true
                        }
                        .buttonStyle(.bordered).controlSize(.small)
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
            store.addMediaToLibrary(url: out)
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
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.luminaCard.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

} // end MonitorDetailPanel

// MARK: - Settings Group
// A consistently styled visual container for a logical group of related controls.
//
// Design goals:
// - All cards share the same minHeight so short boxes (Slideshow empty state,
//   Advanced) scale visually with the taller ones (Display, Visual Effects, etc.).
// - Strong consistent rhythm (header style, padding, internal spacing).
// - Content stays top-aligned; extra space goes below via Spacer.
// - No collapse/expand — everything is always visible and scrollable in one container.

private struct SettingsGroup<Content: View>: View {
    let icon: String
    let title: String

    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Consistent header treatment across all groups (strong visual rhythm)
            HStack(spacing: DisplayScale.points(10)) {
                Image(systemName: icon)
                    .font(.system(size: UIScaleManager.shared.iconSize(.card), weight: .semibold))
                    .foregroundStyle(ThemeManager.shared.current.color)
                    .frame(width: DisplayScale.points(24), alignment: .center)
                Text(title)
                    .font(.system(size: DisplayScale.points(14), weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 6)

            // Content area. Each card hugs its own content height (no forced minHeight),
            // so short cards like Slideshow and Advanced don't leave dead space at the
            // bottom. Width is still full-bleed so all cards align to one edge-to-edge column.
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 13)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.luminaCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.luminaBorder, lineWidth: 1))
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
