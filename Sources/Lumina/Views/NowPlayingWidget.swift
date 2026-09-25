import SwiftUI
import AppKit
import LuminaCore

/// Floating always-on-top mini-player for Lumina ambient audio.
@MainActor
final class NowPlayingWidgetController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = NowPlayingWidgetController()

    @Published private(set) var isVisible: Bool = false

    private var panel: NSPanel?
    private var currentSize: NSSize = DisplayScale.musicWidgetSize
    /// User closed the widget during this playback session — blocks auto-show until stop.
    private var userDismissedThisSession = false
    private var wasPlaying = false
    private var playingObservation: NSKeyValueObservation?
    private var prefsObservationTask: Task<Void, Never>?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioPlayingChanged),
            name: .init("Lumina.AmbientAudio.PlayingDidChange"),
            object: nil
        )
    }

    private var preferences: PreferencesStore? {
        (NSApp.delegate as? LuminaApp)?.preferencesStore
    }

    func show() {
        let isNew = panel == nil
        let sizePref = preferences?.widget.size ?? .regular
        if isNew {
            currentSize = DisplayScale.musicWidgetSize(for: sizePref)
            panel = makePanel()
        }
        guard let panel else { return }
        if isNew {
            syncPanelSize(panel, size: currentSize)
        }
        if !panel.isVisible {
            position(panel, placement: preferences?.widget.placement ?? .init())
        }
        panel.orderFrontRegardless()
        isVisible = true
        userDismissedThisSession = false
        updateVisualizer()
        observePreferences()
    }

    func hide(userInitiated: Bool = true) {
        panel?.orderOut(nil)
        isVisible = false
        if userInitiated {
            userDismissedThisSession = true
        }
        AmbientAudioManager.shared.setVisualizerActive(false)
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func setContentSize(width: CGFloat, height: CGFloat) {
        let size = NSSize(width: width, height: height)
        guard abs(currentSize.width - size.width) > 0.5
                || abs(currentSize.height - size.height) > 0.5 else { return }
        currentSize = size
        guard let panel else { return }
        syncPanelSize(panel, size: size)
    }

    func applySizePreference(_ size: MusicWidgetPreferences.Size) {
        guard var widget = preferences?.widget else { return }
        widget.size = size
        preferences?.widget = widget
        currentSize = DisplayScale.musicWidgetSize(for: size)
        if let panel {
            syncPanelSize(panel, size: currentSize)
            refreshHostingView()
        }
    }

    func snapToCorner() {
        guard var widget = preferences?.widget else { return }
        widget.placement.customOrigin = nil
        preferences?.widget = widget
        if let panel {
            position(panel, placement: widget.placement)
        }
    }

    private func makePanel() -> NSPanel {
        let size = currentSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Music Widget"
        panel.delegate = self
        self.panel = panel
        refreshHostingView()
        return panel
    }

    private func refreshHostingView() {
        guard let panel else { return }
        let size = currentSize
        let root = NowPlayingWidgetView(
            onClose: { [weak self] in self?.hide() },
            onSizeChange: { [weak self] size in
                self?.setContentSize(width: size.width, height: size.height)
            },
            onSnapToCorner: { [weak self] in self?.snapToCorner() },
            onSelectSize: { [weak self] size in self?.applySizePreference(size) }
        )
        let host: NSHostingView<AnyView>
        if let preferences {
            host = NSHostingView(rootView: AnyView(root.environment(preferences)))
        } else {
            host = NSHostingView(rootView: AnyView(root))
        }
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    private func syncPanelSize(_ panel: NSPanel, size: NSSize) {
        guard abs(panel.frame.width - size.width) > 0.5
                || abs(panel.frame.height - size.height) > 0.5 else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        panel.contentView?.setFrameSize(size)
        panel.setFrame(frame, display: true)
    }

    private func position(_ panel: NSPanel, placement: MusicWidgetPreferences.Placement) {
        let size = panel.frame.size
        if let custom = placement.customOrigin {
            let origin = clampOrigin(NSPoint(x: custom.x, y: custom.y), size: size)
            panel.setFrameOrigin(origin)
            return
        }

        let screen = screen(for: placement.display) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let inset = DisplayScale.points(placement.inset)
        let origin: NSPoint
        switch placement.corner {
        case .topLeading:
            origin = NSPoint(x: visible.minX + inset, y: visible.maxY - size.height - inset)
        case .topTrailing:
            origin = NSPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset)
        case .bottomLeading:
            origin = NSPoint(x: visible.minX + inset, y: visible.minY + inset)
        case .bottomTrailing:
            origin = NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset)
        }
        panel.setFrameOrigin(origin)
    }

    private func screen(for key: DisplayKey?) -> NSScreen? {
        guard let key else { return NSScreen.main }
        return NSScreen.screens.enumerated().first { index, screen in
            DisplayKey(MonitorInfo.identifier(for: screen, index: index)) == key
        }?.element
    }

    private func clampOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return origin }
        var best = origin
        var bestArea: CGFloat = -1
        let proposed = NSRect(origin: origin, size: size)
        for screen in screens {
            let visible = screen.visibleFrame
            let intersection = proposed.intersection(visible)
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                best = NSPoint(
                    x: min(max(origin.x, visible.minX), visible.maxX - size.width),
                    y: min(max(origin.y, visible.minY), visible.maxY - size.height)
                )
            }
        }
        return best
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, panel.isVisible, var widget = preferences?.widget else { return }
        let origin = panel.frame.origin
        widget.placement.customOrigin = CodablePoint(x: origin.x, y: origin.y)
        preferences?.widget = widget
    }

    @objc private func audioPlayingChanged() {
        handlePlaybackTransition()
    }

    private func handlePlaybackTransition() {
        let playing = AmbientAudioManager.shared.isPlaying
        defer { wasPlaying = playing }
        guard playing, !wasPlaying else {
            if !playing { userDismissedThisSession = false }
            return
        }
        let autoShow = preferences?.widget.autoShow.whenPlaybackStarts ?? false
        if autoShow, !userDismissedThisSession, !isVisible {
            show()
        }
    }

    private func updateVisualizer() {
        let showsWave = preferences?.widget.showsWaveform ?? true
        AmbientAudioManager.shared.setVisualizerActive(isVisible && showsWave)
    }

    private func observePreferences() {
        prefsObservationTask?.cancel()
        prefsObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let prefs = self.preferences else {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                withObservationTracking {
                    _ = prefs.widget.size
                    _ = prefs.widget.showsWaveform
                    _ = prefs.widget.placement
                } onChange: { [weak self] in
                    Task { @MainActor in
                        self?.handlePrefsChange()
                    }
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        // Also poll playing state since AmbientAudioManager may not post the custom notification.
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.handlePlaybackTransition()
                self?.updateVisualizer()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private func handlePrefsChange() {
        guard let prefs = preferences else { return }
        let desired = DisplayScale.musicWidgetSize(for: prefs.widget.size)
        if abs(desired.width - currentSize.width) > 0.5 {
            currentSize = desired
            if let panel {
                syncPanelSize(panel, size: currentSize)
                refreshHostingView()
            }
        }
        updateVisualizer()
    }
}

// MARK: - Metrics

@MainActor
private struct WidgetMetrics {
    let width: CGFloat
    let baseHeight: CGFloat
    let sidePad: CGFloat
    let art: CGFloat
    let waveBand: CGFloat
    let controlsBand: CGFloat
    let play: CGFloat
    let volume: CGFloat
    let titleFont: LuminaTextStyle

    init(size: MusicWidgetPreferences.Size) {
        switch size {
        case .compact:
            width = DisplayScale.points(248)
            baseHeight = DisplayScale.points(112)
            sidePad = DisplayScale.points(10)
            art = DisplayScale.points(40)
            waveBand = DisplayScale.points(22)
            controlsBand = DisplayScale.points(24)
            play = DisplayScale.points(28)
            volume = DisplayScale.points(44)
            titleFont = .callout
        case .regular:
            width = DisplayScale.points(288)
            baseHeight = DisplayScale.points(140)
            sidePad = DisplayScale.points(12)
            art = DisplayScale.points(56)
            waveBand = DisplayScale.points(30)
            controlsBand = DisplayScale.points(24)
            play = DisplayScale.points(34)
            volume = DisplayScale.points(56)
            titleFont = .bodyStrong
        case .expanded:
            width = DisplayScale.points(336)
            baseHeight = DisplayScale.points(168)
            sidePad = DisplayScale.points(14)
            art = DisplayScale.points(72)
            waveBand = DisplayScale.points(36)
            controlsBand = DisplayScale.points(28)
            play = DisplayScale.points(40)
            volume = DisplayScale.points(72)
            titleFont = .headline
        }
    }
}

// MARK: - Widget View

struct NowPlayingWidgetView: View {
    var onClose: () -> Void = {}
    var onSizeChange: (CGSize) -> Void = { _ in }
    var onSnapToCorner: () -> Void = {}
    var onSelectSize: (MusicWidgetPreferences.Size) -> Void = { _ in }

    @Environment(PreferencesStore.self) private var prefs: PreferencesStore?
    @ObservedObject private var audio = AmbientAudioManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @State private var isHovering: Bool = false
    @State private var showQueue: Bool = false
    @State private var scrubPreview: Double? = nil
    @State private var isPanelKey: Bool = false

    private var accent: Color { theme.current.color }
    private var hasTrack: Bool { audio.trackURL != nil }
    private var metrics: WidgetMetrics {
        WidgetMetrics(size: prefs?.widget.size ?? .regular)
    }

    private var queueRowHeight: CGFloat { DisplayScale.points(24) }

    private var upcomingTracks: [AmbientAudioManager.AudioTrack] {
        guard prefs?.widget.showsUpNext != false else { return [] }
        guard !audio.library.isEmpty else { return [] }
        guard let current = audio.trackURL,
              let idx = audio.library.firstIndex(where: { $0.url == current }) else {
            return Array(audio.library.prefix(3))
        }
        var result: [AmbientAudioManager.AudioTrack] = []
        for offset in 1..<audio.library.count {
            result.append(audio.library[(idx + offset) % audio.library.count])
            if result.count >= 3 { break }
        }
        return result
    }

    private var queueHeight: CGFloat {
        guard showQueue, !upcomingTracks.isEmpty, prefs?.widget.showsUpNext != false else { return 0 }
        let gap = LuminaSpace.hair
        let label = LuminaMetrics.upNextLabel
        let rows = CGFloat(upcomingTracks.count) * queueRowHeight
        let gaps = CGFloat(upcomingTracks.count) * gap
        return label + gaps + rows + LuminaSpace.sm
    }

    private var cardHeight: CGFloat { metrics.baseHeight + queueHeight }

    private var chromeVisible: Bool {
        isHovering
            || isPanelKey
            || NSWorkspace.shared.isVoiceOverEnabled
            || NSApp.isFullKeyboardAccessEnabled
            || !hasTrack
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: LuminaRadius.widget, style: .continuous)
        let m = metrics

        VStack(spacing: 0) {
            headerRow(m)
                .padding(.horizontal, m.sidePad)
                .padding(.top, LuminaSpace.md)

            Spacer(minLength: LuminaSpace.xs)

            waveformRow(m)
                .frame(height: m.waveBand)
                .padding(.horizontal, m.sidePad)

            if showQueue, !upcomingTracks.isEmpty {
                upNextList
                    .padding(.horizontal, m.sidePad)
                    .padding(.top, LuminaSpace.tight)
                    .transition(.opacity)
            }

            controlsRow(m)
                .frame(height: m.controlsBand)
                .padding(.horizontal, m.sidePad)
                .padding(.bottom, LuminaSpace.barPaddingV)
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
        }
        .frame(width: m.width, height: cardHeight, alignment: .top)
        .background(Color.luminaCard, in: cardShape)
        .overlay(cardShape.strokeBorder(Color.luminaBorder, lineWidth: 1))
        .clipShape(cardShape)
        .contextMenu { widgetContextMenu }
        .onHover { hovering in
            LuminaMotion.animate(LuminaMotion.hover) {
                isHovering = hovering
                if !hovering { showQueue = false }
            }
        }
        .onAppear {
            onSizeChange(CGSize(width: m.width, height: cardHeight))
            syncPanelKey()
        }
        .onChange(of: cardHeight) { _, height in
            onSizeChange(CGSize(width: m.width, height: height))
        }
        .onChange(of: prefs?.widget.size) { _, _ in
            onSizeChange(CGSize(width: metrics.width, height: cardHeight))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            syncPanelKey()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            syncPanelKey()
        }
        .focusable()
        .onKeyPress(.space) {
            guard hasTrack else { return .ignored }
            audio.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard hasTrack, audio.duration > 0 else { return .ignored }
            audio.seekToTime(max(0, audio.currentTime - 5))
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard hasTrack, audio.duration > 0 else { return .ignored }
            audio.seekToTime(min(audio.duration, audio.currentTime + 5))
            return .handled
        }
    }

    @ViewBuilder
    private var widgetContextMenu: some View {
        Button("Snap to Corner") { onSnapToCorner() }
            .disabled(prefs?.widget.placement.customOrigin == nil)

        Menu("Size") {
            ForEach([MusicWidgetPreferences.Size.compact, .regular, .expanded], id: \.self) { size in
                Button {
                    onSelectSize(size)
                } label: {
                    if prefs?.widget.size == size {
                        Label(sizeMenuLabel(size), systemImage: "checkmark")
                    } else {
                        Text(sizeMenuLabel(size))
                    }
                }
            }
        }

        Divider()
        Button("Close", action: onClose)
    }

    private func sizeMenuLabel(_ size: MusicWidgetPreferences.Size) -> String {
        switch size {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .expanded: return "Large"
        }
    }

    private func syncPanelKey() {
        isPanelKey = NSApp.keyWindow?.title == "Music Widget"
    }

    // MARK: Header

    private func headerRow(_ m: WidgetMetrics) -> some View {
        HStack(spacing: LuminaSpace.md) {
            albumArt(m)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                Text(hasTrack ? audio.trackTitle : "No music")
                    .font(uiScale.font(m.titleFont).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitleLine)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)

            if hasTrack {
                playButton(m)
            }
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .help("Drag to move")
        )
        .frame(height: m.art)
    }

    private func playButton(_ m: WidgetMetrics) -> some View {
        Button {
            audio.toggle()
        } label: {
            ZStack {
                Circle().fill(accent.opacity(0.16))
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: uiScale.iconSize(.inline) + 1, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: m.play, height: m.play)
            .contentShape(Circle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .help(audio.isPlaying ? "Pause" : "Play")
        .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
    }

    private func albumArt(_ m: WidgetMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
        return ZStack {
            shape.fill(
                LinearGradient(
                    colors: [accent.opacity(0.9), accent.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            if let art = audio.trackArtwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: uiScale.iconSize(.card) + 4, weight: .medium))
                    .foregroundStyle(theme.current.onAccent)
            }
        }
        .frame(width: m.art, height: m.art)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.luminaBorder.opacity(0.5), lineWidth: 1))
        .accessibilityHidden(true)
    }

    // MARK: Waveform

    private func waveformRow(_ m: WidgetMetrics) -> some View {
        let seed = audio.trackURL?.absoluteString.hashValue ?? 0
        let showsWave = prefs?.widget.showsWaveform ?? true
        return HStack(spacing: LuminaSpace.sm) {
            Text(formatTime(scrubPreview ?? audio.currentTime))
                .font(uiScale.font(.micro).monospacedDigit())
                .foregroundStyle(scrubPreview == nil ? Color.secondary : accent)

            LuminaWaveformScrubber(
                currentTime: audio.currentTime,
                duration: max(audio.duration, 0),
                isPlaying: audio.isPlaying,
                style: .widget,
                source: showsWave ? .live : .staticSeed(seed),
                preview: $scrubPreview,
                onSeek: { audio.seekToTime($0) }
            )
            .frame(height: m.waveBand)

            Text(formatTime(audio.duration))
                .font(uiScale.font(.micro).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func controlsRow(_ m: WidgetMetrics) -> some View {
        HStack(spacing: LuminaSpace.hair) {
            if hasTrack {
                iconButton(
                    "shuffle",
                    label: "Shuffle",
                    value: audio.shuffle ? "On" : "Off",
                    active: audio.shuffle,
                    disabled: audio.library.count < 2
                ) {
                    audio.setShuffle(!audio.shuffle)
                }

                iconButton("backward.end.fill", label: "Previous", disabled: audio.library.count < 2) {
                    audio.previousTrack()
                }

                iconButton("forward.end.fill", label: "Next", disabled: audio.library.count < 2) {
                    audio.nextTrack()
                }

                iconButton(
                    "repeat",
                    label: "Repeat",
                    value: audio.loops ? "On" : "Off",
                    active: audio.loops
                ) {
                    audio.setLoops(!audio.loops)
                }

                Image(systemName: audio.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(uiScale.font(.micro).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, LuminaSpace.hair)
                    .accessibilityHidden(true)

                Slider(
                    value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }),
                    in: 0...1
                )
                .controlSize(.mini)
                .tint(accent)
                .frame(width: m.volume)
                .accessibilityLabel("Volume")

                if prefs?.widget.showsUpNext != false {
                    iconButton(
                        "list.bullet",
                        label: "Up Next",
                        value: showQueue ? "Shown" : "Hidden",
                        active: showQueue,
                        disabled: upcomingTracks.isEmpty
                    ) {
                        LuminaMotion.animate(LuminaMotion.hover) { showQueue.toggle() }
                    }
                }
            }

            iconButton("plus", label: "Add Music…") {
                audio.chooseTrack()
            }

            iconButton("xmark", label: "Close", action: onClose)
        }
    }

    private var upNextList: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.hair) {
            Text("Up Next")
                .font(uiScale.font(.micro).weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            ForEach(Array(upcomingTracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    let wasPlaying = audio.isPlaying
                    audio.selectTrack(track)
                    if wasPlaying { audio.play() }
                    LuminaMotion.animate(LuminaMotion.hover) { showQueue = false }
                } label: {
                    HStack(spacing: LuminaSpace.xs) {
                        Text("\(index + 1)")
                            .font(uiScale.font(.micro).weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: DisplayScale.points(12), alignment: .trailing)
                        Text(track.title)
                            .font(uiScale.font(.caption).weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, LuminaSpace.tight)
                    .frame(height: queueRowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous)
                            .fill(Color.luminaFill)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(LuminaPressableButtonStyle())
                .luminaHoverPlate()
                .help("Play \(track.title)")
                .accessibilityLabel("Play \(track.title)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitleLine: String {
        if !hasTrack { return "Add a song to start" }
        if !audio.trackArtist.isEmpty { return audio.trackArtist }
        if !audio.trackAlbum.isEmpty { return audio.trackAlbum }
        return "Ambient music"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func iconButton(
        _ symbol: String,
        label: String,
        value: String? = nil,
        active: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(LuminaIconButtonStyle(active: active, size: .compact))
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}
