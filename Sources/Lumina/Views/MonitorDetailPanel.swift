import SwiftUI
import AppKit

/// Side panel that appears when a user selects a monitor in the layout.
/// Contains live preview + all per-monitor settings, organized into collapsible sections.
struct MonitorDetailPanel: View {
    let monitor: MonitorInfo
    @ObservedObject var store: WallpaperManagerStore

    var onClose: () -> Void = {}
    var showHeader: Bool = true

    // Preview resize state
    @State private var previewHeight: CGFloat = 220
    @State private var previewOpacity: Double = 1.0

    // Local state for settings (synced with store)
    @State private var selectedScaling: VideoScaling = .fill
    @State private var keepOnStartup: Bool = false
    @State private var playbackSpeed: Double = 1.0
    @State private var localCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var videoPreviewTime: Double = 0.15
    @State private var loopFadeEnabled: Bool = false
    @State private var loopFadeDuration: Double = 1.5
    @State private var loopFadeEasing: MonitorAssignment.FadeEasing = .easeInOut
    @State private var brightness: Double = 0.0
    @State private var slideshowItems: [String] = []
    @State private var slideshowInterval: Double = 10.0
    @State private var slideshowTransition: MonitorAssignment.SlideshowTransition = .fade

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
                Divider()
            }

            livePreviewSection

            // Prominent "Keep on startup" control — this is one of the most important
            // decisions the user makes. It is deliberately placed in a high-visibility
            // location with strong visual weight (best practice for primary persistence actions).
            keepOnStartupControl
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Settings groups.
            // Note: We intentionally do *not* wrap these in another ScrollView here.
            // The parent `configurationColumn` already provides a single ScrollView
            // around the entire MonitorDetailPanel. Nested scroll views are a major
            // source of janky scrolling and fighting gestures on macOS.
            VStack(spacing: 16) {
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
            .padding(.vertical, 8)

            Divider()

            actionButtons
                .padding(16)
        }
        .onAppear { loadCurrentValues() }
        .onChange(of: monitor.id) { _, _ in loadCurrentValues() }
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

    private var livePreviewSection: some View {
        VStack(spacing: 0) {
            if let a = assignment {
                WallpaperPreview(
                    assignment: a,
                    liveCropRect: localCropRect,
                    liveScaling: selectedScaling,
                    targetAspect: 16.0 / 9.0,
                    isLivePlayback: true,
                    previewTime: nil
                )
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .cornerRadius(10)
                .opacity(previewOpacity)
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Visual hint that the desktop is running a slideshow even though
                // the inline preview only shows single-media at the moment.
                if let a = assignment, !a.slideshowItems.isEmpty {
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
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        previewHeight = max(140, min(500, previewHeight + drag.translation.height))
                    }
            )
        }
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
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(keepOnStartup ? Color.yellow.opacity(0.35) : Color.gray.opacity(0.25), lineWidth: 1)
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
                    .onChange(of: playbackSpeed) { _, v in store.setPlaybackSpeed(for: monitor, speed: v) }
            }

            // Loop Crossfade (video only)
            if assignment?.mediaType == .video {
                Toggle("Fade at loop point", isOn: $loopFadeEnabled)
                    .toggleStyle(.switch)
                    .font(.subheadline)
                    .onChange(of: loopFadeEnabled) { _, v in
                        store.setLoopFade(for: monitor, enabled: v, duration: loopFadeDuration)
                    }

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
                            .onChange(of: loopFadeEasing) { _, e in
                                store.setLoopFade(for: monitor, enabled: loopFadeEnabled,
                                                  duration: loopFadeDuration, easing: e)
                            }
                        }
                        .help("Controls how the opacity ramps in and out during the fade")

                        HStack(spacing: 8) {
                            Button("Preview") { previewFadeInPreview() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Simulate this fade in the preview above")

                            Button("Apply to Wallpaper") {
                                store.setLoopFade(for: monitor, enabled: loopFadeEnabled,
                                                  duration: loopFadeDuration, easing: loopFadeEasing)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .help("Apply the current fade settings to the live desktop wallpaper")
                        }
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
                        .onChange(of: audioVolume) { _, v in store.setVolume(for: monitor, volume: v) }
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
                .onChange(of: selectedScaling) { _, v in store.setScaling(for: monitor, scaling: v) }
                Text(scalingDescription)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .animation(.easeInOut(duration: 0.15), value: selectedScaling)
            }

            // Crop / Zoom editor
            if assignment != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Crop / Zoom").font(.subheadline).foregroundStyle(.secondary)

                    let currentAssignment = store.assignment(for: monitor.id)
                    CropRectangle(
                        cropRect: $localCropRect,
                        onChange: { newRect in
                            localCropRect = newRect
                            store.setCropRect(for: monitor, cropRect: newRect)
                        },
                        assignment: currentAssignment,
                        previewTime: currentAssignment?.mediaType == .video ? videoPreviewTime : nil
                    )
                    .frame(height: 160)
                    .padding(.vertical, 2)

                    HStack {
                        Button("Reset to Full") {
                            localCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                            store.setCropRect(for: monitor, cropRect: localCropRect)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Text("Drag to move • Drag corners to resize")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
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
                    .onChange(of: brightness) { _, v in store.setBrightness(for: monitor, brightness: v) }
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
                    .onChange(of: opacity) { _, v in store.setOpacity(for: monitor, opacity: v) }
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
                    .onChange(of: saturation) { _, v in
                        store.setColorCorrection(for: monitor, saturation: v, hue: hue, grayscale: grayscale)
                    }
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
                    .onChange(of: hue) { _, v in
                        store.setColorCorrection(for: monitor, saturation: saturation, hue: v, grayscale: grayscale)
                    }
            }

            // Grayscale
            Toggle("Grayscale", isOn: $grayscale)
                .toggleStyle(.switch)
                .onChange(of: grayscale) { _, v in
                    store.setColorCorrection(for: monitor, saturation: saturation, hue: hue, grayscale: v)
                }
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
                .onChange(of: loopMode) { _, newMode in
                    store.setLoopMode(for: monitor, mode: newMode)
                }
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
                Text("Add two or more images to cycle through them automatically on this display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("^[\(slideshowItems.count) image](inflect: true)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All") {
                        slideshowItems.removeAll()
                        store.setSlideshowItems(for: monitor, items: slideshowItems)
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(slideshowItems, id: \.self) { path in
                            HStack(spacing: 4) {
                                Text((path as NSString).lastPathComponent)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button {
                                    slideshowItems.removeAll { $0 == path }
                                    store.setSlideshowItems(for: monitor, items: slideshowItems)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Interval").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0fs", slideshowInterval))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: $slideshowInterval, in: 3...60, step: 1)
                        .onChange(of: slideshowInterval) { _, v in
                            store.setSlideshowInterval(for: monitor, interval: v)
                        }
                }

                Picker("Transition", selection: $slideshowTransition) {
                    ForEach(MonitorAssignment.SlideshowTransition.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: slideshowTransition) { _, v in
                    store.setSlideshowTransition(for: monitor, transition: v)
                }

                Text("Slideshow images fill the screen (aspect-fill). Per-monitor crop and color effects above don't apply while a slideshow is running.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button("Add Images…") {
                let panel = NSOpenPanel()
                panel.title = "Add images to slideshow"
                panel.allowedContentTypes = [.image]
                panel.canChooseFiles = true
                panel.allowsMultipleSelection = true
                guard panel.runModal() == .OK else { return }
                let newPaths = panel.urls.map { $0.path }
                slideshowItems.append(contentsOf: newPaths.filter { !slideshowItems.contains($0) })
                store.setSlideshowItems(for: monitor, items: slideshowItems)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            Button("Choose Different Media…") {
                store.chooseVideo(for: monitor)
            }
            .buttonStyle(.borderedProminent)

            if monitor.assignedVideoName != nil {
                Button("Clear Wallpaper", role: .destructive) {
                    store.clearAssignment(for: monitor)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Reset Settings") {
                resetToDefaults()
            }
            .buttonStyle(.bordered)
            .help("Reset all display settings (scaling, effects, crop, speed) to their defaults")

            if showHeader {
                Button("Done") { onClose() }
                    .buttonStyle(.borderedProminent)
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
        store.setScaling(for: monitor, scaling: .fill)
        store.setPlaybackSpeed(for: monitor, speed: 1.0)
        store.setCropRect(for: monitor, cropRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        store.setLoopFade(for: monitor, enabled: false, duration: 1.5, easing: .easeInOut)
        store.setBrightness(for: monitor, brightness: 0.0)
        store.setOpacity(for: monitor, opacity: 1.0)
        store.setColorCorrection(for: monitor, saturation: 1.0, hue: 0.0, grayscale: false)
        store.setVolume(for: monitor, volume: 0.0)
        store.setLoopMode(for: monitor, mode: .loop)
    }

    // MARK: - Load Current Values

    private func loadCurrentValues() {
        // Disable SwiftUI animations so slider/toggle values snap instantly
        // when the user switches monitors — no distracting animated transitions.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { _loadCurrentValuesInner() }
    }

    private func _loadCurrentValuesInner() {
        if let a = store.assignment(for: monitor.id) {
            selectedScaling = a.scaling
            keepOnStartup = a.keepOnStartup
            playbackSpeed = a.playbackSpeed
            localCropRect = a.cropRect
            loopFadeEnabled = a.loopFadeEnabled
            loopFadeDuration = a.loopFadeDuration
            loopFadeEasing = a.loopFadeEasing
            brightness = a.brightness
            slideshowItems = a.slideshowItems
            slideshowInterval = a.slideshowInterval
            slideshowTransition = a.slideshowTransition
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
            loopFadeEnabled = false
            loopFadeDuration = 1.5
            loopFadeEasing = .easeInOut
            brightness = 0.0
            slideshowItems = []
            slideshowInterval = 10.0
            slideshowTransition = .fade
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

            Divider()

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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 6)

            // Content area.
            // We give the whole group a minHeight so that even the shorter boxes
            // (Slideshow in empty state, Advanced) participate in the same visual
            // scaling as the taller ones (Display, Visual Effects, etc.).
            // Content stays top-aligned via the spacer.
            VStack(alignment: .leading, spacing: 10) {
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 13)
        }
        .frame(minHeight: 155)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.6))
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
