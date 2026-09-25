import SwiftUI
import AppKit

// MARK: - Library Filter

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, videos, images, gifs, favorites
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .videos: return "Videos"
        case .images: return "Images"
        case .gifs: return "GIFs"
        case .favorites: return "Starred"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .videos: return "play.rectangle"
        case .images: return "photo"
        case .gifs: return "photo.stack"
        case .favorites: return "star.fill"
        }
    }
    var helpText: String {
        switch self {
        case .all:       return "All wallpapers"
        case .videos:    return "Videos only"
        case .images:    return "Images only"
        case .gifs:      return "GIFs only"
        case .favorites: return "Starred only"
        }
    }
}

// MARK: - Main View

/// The main view for Lumina's Wallpaper Manager.
/// Designed with clarity, visual hierarchy, and forgiveness in mind.
struct WallpaperManagerView: View {
    @ObservedObject var store: WallpaperManagerStore

    // Selection state is owned higher up so it can be shared with the floating physical setup window
    @Binding var selectedMonitorID: String?

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var playbackHealth = PlaybackHealthMonitor.shared
    // NOTE: AmbientAudioManager is deliberately NOT observed here. It publishes currentTime
    // 4×/sec during playback, which would invalidate the entire manager tree (library grid,
    // live preview, crop UI) on every tick. Only AudioFooterBar observes it.
    @StateObject private var favoritesManager = FavoritesManager.shared
    @Environment(PlaybackEngine.self) private var playbackEngine: PlaybackEngine?

    @State private var searchQuery: String = ""
    @State private var selectedFilter: LibraryFilter = .all
    @State private var showSettings: Bool = false
    /// Library column is expanded by default; collapse to give the preview more room.
    @State private var showLibraryColumn: Bool = true
    @FocusState private var isSearchFocused: Bool
    @State private var libraryRailHovered = false

    // MARK: - Computed

    private var filteredMedia: [WallpaperManagerStore.RecentMedia] {
        var items = store.recentMedia
        switch selectedFilter {
        case .all: break
        case .videos: items = items.filter { $0.mediaType == .video }
        case .images: items = items.filter { $0.mediaType == .image }
        case .gifs:   items = items.filter { $0.mediaType == .animatedImage }
        case .favorites: items = items.filter { favoritesManager.isFavorite($0.id) }
        }
        if !searchQuery.isEmpty {
            items = items.filter { $0.displayName.localizedCaseInsensitiveContains(searchQuery) }
        }
        return items
    }

    // Currently targeted monitor — prefer the store as single source of truth
    private var currentTargetMonitor: MonitorInfo? {
        let id = store.selectedMonitorID ?? selectedMonitorID
        guard let id else { return nil }
        return store.monitors.first { $0.id == id }
    }

    private var showGlobalStatusPill: Bool {
        guard let engine = playbackEngine else { return false }
        return store.monitors.contains { monitor in
            switch LuminaDisplayState.from(plan: engine.plan, key: DisplayKey(monitor.id)) {
            case .paused, .failed, .off: return true
            default: return false
            }
        }
    }

    // MARK: - Body

    var body: some View {
        // Adaptive: the view fills whatever size the user resizes the window to. We only set a
        // floor so the two-column layout never collapses (mirrors the window's contentMinSize).
        coreContent
            .scaledMinFrame(width: 1080, height: 740)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .luminaWindowBackdrop()
            .tint(themeManager.current.color)
            .onAppear { autoSelectFirstMonitor() }
            .onReceive(NotificationCenter.default.publisher(for: .luminaOpenSettings)) { _ in
                showSettings = true
            }
    }

    private var coreContent: some View {
        VStack(spacing: 0) {
            headerBar
            if playbackHealth.isStruggling, !playbackHealth.bannerDismissed {
                playbackHealthBanner
            }
            LuminaDivider()
            mainContent
            LuminaDivider()
            AudioFooterBar()
        }
    }

    private var playbackHealthBanner: some View {
        HStack(alignment: .center, spacing: LuminaSpace.md) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                .foregroundStyle(LuminaStatusColor.paused)

            VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                Text("This wallpaper is heavy for this Mac")
                    .font(uiScale.font(.bodyStrong))
                Text(playbackHealthBannerDetail)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: LuminaSpace.sm)

            Button("Adjust Quality") {
                NotificationCenter.default.post(
                    name: .luminaRevealAdjustSection,
                    object: "qualityPower"
                )
            }
            .buttonStyle(LuminaSecondaryButtonStyle())
            .controlSize(.small)

            LuminaCloseButton {
                playbackHealth.dismissBanner()
            }
            .accessibilityLabel("Hide warning")
            .help("Hide")
        }
        .padding(.horizontal, LuminaLayout.contentPadding)
        .padding(.vertical, LuminaSpace.barPaddingV)
        .background(LuminaStatusColor.paused.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LuminaStatusColor.paused.opacity(0.35)).frame(height: 1)
        }
        .transition(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? .opacity
                : .move(edge: .top).combined(with: .opacity)
        )
        .animation(LuminaMotion.reveal, value: playbackHealth.isStruggling)
    }

    private var playbackHealthBannerDetail: String {
        let tip = "Try a smaller video, or lower its resolution in Adjust."
        if playbackHealth.reason.isEmpty { return tip }
        return "\(playbackHealth.reason). \(tip)"
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: LuminaSpace.md) {
            HStack(alignment: .center, spacing: LuminaSpace.sm) {
                LuminaBrandMark(side: LuminaMetrics.brandMark)
                    .accessibilityHidden(true)
                Text("Lumina Studio")
                    .font(uiScale.font(.title))
            }

            Spacer(minLength: LuminaSpace.md)

            if showGlobalStatusPill, let engine = playbackEngine {
                let manual = LuminaPlaybackHeadline.isManuallyPaused(plan: engine.plan)
                LuminaStatusPill(
                    style: .status(manual ? .paused(.manual) : representativePausedState(engine: engine)),
                    text: LuminaPlaybackHeadline.text(plan: engine.plan, displays: engine.displays),
                    help: manual ? "Resume all wallpapers." : nil,
                    onTap: {
                        if manual {
                            engine.togglePause()
                        } else {
                            SettingsRouter.shared.open(.power)
                        }
                    }
                )
                LuminaVerticalDivider()
                    .frame(height: DisplayScale.points(24))
            }

            if let engine = playbackEngine {
                let paused = LuminaPlaybackHeadline.isManuallyPaused(plan: engine.plan)
                LuminaToolbarButton(
                    title: paused ? "Resume" : "Pause All",
                    icon: paused ? "play.fill" : "pause.fill"
                ) {
                    engine.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }

            LuminaToolbarButton(title: "Settings", icon: "gearshape.fill") {
                showSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, LuminaLayout.contentPadding)
        .padding(.vertical, LuminaSpace.barPaddingV + LuminaSpace.hair)
        .luminaGlassChrome()
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store, onClose: { showSettings = false })
        }
    }

    private func representativePausedState(engine: PlaybackEngine) -> LuminaDisplayState {
        for monitor in store.monitors {
            let state = LuminaDisplayState.from(plan: engine.plan, key: DisplayKey(monitor.id))
            if case .paused = state { return state }
            if case .failed = state { return state }
            if case .off = state { return state }
        }
        return .paused(.manual)
    }

    // MARK: - Main Two-Column Content

    private var mainContent: some View {
        HStack(spacing: 0) {
            // Swap views — don't clip a full-width column into the rail (that centered
            // the library, hid the expand control, and left a thumbnail sliver).
            Group {
                if showLibraryColumn {
                    libraryColumn
                } else {
                    libraryRail
                }
            }
            .frame(
                width: showLibraryColumn
                    ? LuminaLayout.libraryColumnWidth
                    : LuminaLayout.libraryRailWidth,
                alignment: .leading
            )
            .animation(LuminaMotion.panel, value: showLibraryColumn)

            Rectangle()
                .fill(Color.luminaBorder)
                .frame(width: 1)

            configurationColumn
        }
        .frame(maxHeight: .infinity)
    }

    /// Slim strip shown while the library is collapsed — one click brings it back.
    private var libraryRail: some View {
        VStack(spacing: LuminaSpace.sm) {
            Button {
                LuminaMotion.animate(LuminaMotion.panel) {
                    showLibraryColumn = true
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(LuminaIconButtonStyle())
            .keyboardShortcut("s", modifiers: [.control, .command])
            .help("Show library (⌃⌘S)")
            .accessibilityLabel("Show library")
            .padding(.top, LuminaSpace.md)

            Text("Library")
                .font(uiScale.font(.micro).weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: LuminaLayout.libraryRailWidth)

            Spacer(minLength: 0)

            if !filteredMedia.isEmpty {
                Text("\(filteredMedia.count)")
                    .font(uiScale.font(.micro).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, LuminaSpace.md)
            }
        }
        .frame(width: LuminaLayout.libraryRailWidth)
        .frame(maxHeight: .infinity)
        .background(libraryRailHovered ? Color.luminaFillHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { libraryRailHovered = $0 }
        .onTapGesture {
            LuminaMotion.animate(LuminaMotion.panel) {
                showLibraryColumn = true
            }
        }
    }

    // MARK: - Library Column (left)

    private var libraryColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: LuminaSpace.md) {
                HStack(alignment: .center, spacing: LuminaSpace.sm) {
                    Button {
                        LuminaMotion.animate(LuminaMotion.panel) {
                            showLibraryColumn = false
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(LuminaIconButtonStyle())
                    .keyboardShortcut("s", modifiers: [.control, .command])
                    .help("Hide library (⌃⌘S)")
                    .accessibilityLabel("Hide library")

                    LuminaSectionHeader(
                        title: "Library",
                        trailing: "\(filteredMedia.count)"
                    )
                }

                HStack(spacing: LuminaSpace.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: uiScale.iconSize(.inline)))
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(uiScale.font(.body))
                        .focused($isSearchFocused)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: DisplayScale.points(12)))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(LuminaPressableButtonStyle())
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, LuminaSpace.md)
                .frame(height: DisplayScale.points(32))
                .background(
                    RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                        .fill(Color.luminaFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                        .strokeBorder(Color.luminaBorder, lineWidth: 1)
                )

                Button("") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)

                libraryFilterChips
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.top, LuminaSpace.md)
            .padding(.bottom, LuminaSpace.md)

            LuminaDivider()

            ScrollView {
                if filteredMedia.isEmpty {
                    emptyLibraryView
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: DisplayScale.points(120)),
                                spacing: LuminaSpace.md
                            )
                        ],
                        spacing: LuminaSpace.md
                    ) {
                        ForEach(Array(filteredMedia.enumerated()), id: \.element.id) { index, recent in
                            let isCurrent = isCurrentWallpaper(recent: recent)
                            WallpaperGridItem(
                                recent: recent,
                                isSelected: isCurrent,
                                isFavorite: favoritesManager.isFavorite(recent.id),
                                onApply: { applyRecentToSelected(recent: recent) },
                                onFavorite: { favoritesManager.toggle(recent.id) },
                                onRemove: { store.removeFromLibrary(id: recent.id) },
                                onMoveFocus: { direction in
                                    moveLibraryFocus(from: index, direction: direction)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, LuminaLayout.contentPadding)
                    .padding(.vertical, LuminaSpace.md)
                }
            }
            .frame(maxHeight: .infinity)

            LuminaDivider()

            VStack(spacing: LuminaSpace.sm) {
                Button { addMediaToLibrary() } label: {
                    Label("Add Wallpaper…", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LuminaProminentButtonStyle())
                .controlSize(.large)
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, LuminaSpace.md)
            .luminaGlassChrome()
        }
        .frame(width: LuminaLayout.libraryColumnWidth)
        .background(Color.luminaCard)
    }

    private var libraryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LuminaSpace.xs) {
                ForEach(LibraryFilter.allCases) { filter in
                    CompactLibraryFilterChip(
                        label: filter.label,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        help: filter.helpText
                    ) {
                        LuminaMotion.animate(LuminaMotion.state) { selectedFilter = filter }
                    }
                }
            }
            .padding(.trailing, LuminaSpace.xl)
        }
        .mask(
            HStack(spacing: 0) {
                Color.white
                LinearGradient(
                    colors: [.white, .white.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: LuminaSpace.xl)
            }
        )
    }

    private func moveLibraryFocus(from index: Int, direction: MoveCommandDirection) {
        // Focus movement is handled per-item via onMoveCommand; apply stays on Space/Return.
        _ = (index, direction)
    }

    // MARK: - Configuration Column (right)

    private var configurationColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: LuminaSpace.md) {
                if let monitor = currentTargetMonitor {
                    HStack(spacing: LuminaSpace.sm) {
                        Image(systemName: "display")
                            .font(.system(size: UIScaleManager.shared.iconSize(.filter), weight: .semibold))
                            .foregroundStyle(themeManager.current.color)
                            .frame(width: UIScaleManager.shared.touchTarget(), height: UIScaleManager.shared.touchTarget())
                            .background(
                                themeManager.current.color.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                            Text(monitor.name)
                                .font(uiScale.font(.headline))
                            Text("\(monitor.resolution) · \(displayCaption(for: monitor))")
                                .font(uiScale.font(.caption))
                                .foregroundStyle(.secondary)
                        }

                        if let engine = playbackEngine {
                            let state = LuminaDisplayState.from(plan: engine.plan, key: DisplayKey(monitor.id))
                            if state != .empty {
                                let key = DisplayKey(monitor.id)
                                let threshold = Int(
                                    store.appDelegate?.preferencesStore?.power[display: key].battery.pauseBelowPercent
                                    ?? 20
                                )
                                let hasOverride = store.appDelegate?.preferencesStore?.power.hasOverride(for: key) == true
                                    || store.appDelegate?.preferencesStore?.playback.qualityOverrides[key] != nil
                                LuminaStatusPill(
                                    style: .status(state),
                                    batteryThreshold: threshold,
                                    usesAdjustCopy: hasOverride,
                                    onTap: {
                                        NotificationCenter.default.post(
                                            name: .luminaRevealAdjustSection,
                                            object: "qualityPower"
                                        )
                                    }
                                )
                            }
                        }

                        if let assignment = store.assignment(for: monitor.id),
                           assignment.keepOnStartup {
                            LuminaStatusPill(
                                style: .accent,
                                icon: "pin.fill",
                                text: "Pinned",
                                help: "Comes back when Lumina starts"
                            )
                        }
                    }
                } else {
                    Label("No display selected", systemImage: "display.trianglebadge.exclamationmark")
                        .font(uiScale.font(.body))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .togglePhysicalSetupWindow, object: nil)
                } label: {
                    Label("Choose Display…", systemImage: "display.2")
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .controlSize(.regular)
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, LuminaSpace.barPaddingV)
            .luminaGlassChrome()

            LuminaDivider()

            if let monitor = currentTargetMonitor {
                MonitorDetailPanel(monitor: monitor, store: store, showHeader: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
                LuminaEmptyState(
                    icon: "display.2",
                    title: "Pick a display",
                    message: "Choose a display to set up, then pick a wallpaper from the library.",
                    prominent: true
                ) {
                    Button("Choose Display…") {
                        NotificationCenter.default.post(name: .togglePhysicalSetupWindow, object: nil)
                    }
                    .buttonStyle(LuminaProminentButtonStyle())
                    .controlSize(.large)
                }
                .padding(LuminaLayout.contentPadding)
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func displayCaption(for monitor: MonitorInfo) -> String {
        let count = store.monitors.count
        if count <= 1 { return "Display" }
        if let index = store.monitors.firstIndex(where: { $0.id == monitor.id }) {
            return "Display \(index + 1) of \(count)"
        }
        return "Display"
    }

    // MARK: - Helpers (preserved verbatim from original)

    private func autoSelectFirstMonitor() {
        if store.selectedMonitorID == nil && selectedMonitorID == nil,
           let first = store.monitors.first {
            selectedMonitorID = first.id
            store.selectedMonitorID = first.id
        }
    }

    /// Returns whether this recent item is the one currently assigned to the active target display.
    private func isCurrentWallpaper(recent: WallpaperManagerStore.RecentMedia) -> Bool {
        let targetID = store.selectedMonitorID ?? selectedMonitorID
        guard let targetID,
              let assignment = store.assignment(for: targetID),
              let currentPath = assignment.filePath else {
            return false
        }
        let expandedCurrent = (currentPath as NSString).expandingTildeInPath
        return expandedCurrent == recent.url.path || expandedCurrent == recent.id
    }

    // Apply a recent wallpaper to the currently targeted display
    private func applyRecentToSelected(recent: WallpaperManagerStore.RecentMedia) {
        let targetID = store.selectedMonitorID ?? selectedMonitorID ?? store.monitors.first?.id
        guard let targetID else {
            NSSound.beep()
            return
        }
        if selectedMonitorID != targetID { selectedMonitorID = targetID }
        if store.selectedMonitorID != targetID { store.selectedMonitorID = targetID }
        store.applyRecentMedia(to: targetID, url: recent.url)
    }

    private func addMediaToLibrary() {
        guard let url = MediaAccessPolicy.runWallpaperPicker(
            title: "Add Wallpaper",
            message: "Adds the file to your library. Your desktop doesn’t change."
        ).first else { return }
        store.addMediaToLibrary(url: url)
    }

    // MARK: - Empty Library View

    @ViewBuilder private var emptyLibraryView: some View {
        let icon: String = {
            if selectedFilter == .favorites { return "star" }
            if !searchQuery.isEmpty { return "magnifyingglass" }
            return "photo.badge.plus"
        }()
        let title: String = {
            if selectedFilter == .favorites { return "Nothing starred yet" }
            if !searchQuery.isEmpty { return "No matches for “\(searchQuery)”" }
            return "No wallpapers yet"
        }()

        LuminaEmptyState(icon: icon, title: title, message: emptyLibrarySubtitle) {
            HStack(spacing: LuminaSpace.sm) {
                if !searchQuery.isEmpty {
                    Button("Clear Search") { searchQuery = "" }
                        .buttonStyle(LuminaSecondaryButtonStyle())
                }
                if selectedFilter != .all {
                    Button("Show All") { selectedFilter = .all }
                        .buttonStyle(LuminaSecondaryButtonStyle())
                }
                if searchQuery.isEmpty && selectedFilter == .all {
                    Button("Add Wallpaper…") { addMediaToLibrary() }
                        .buttonStyle(LuminaProminentButtonStyle())
                        .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: LuminaMetrics.emptyStateMinHeight)
        .padding(LuminaLayout.contentPadding)
    }

    private var emptyLibrarySubtitle: String {
        if selectedFilter == .favorites {
            return "Hover a wallpaper and click the star to keep it here."
        }
        if !searchQuery.isEmpty {
            return "Try another word."
        }
        if selectedFilter != .all {
            return "Nothing in this filter yet."
        }
        return "Add a video, GIF, or image, then click one to set it on the selected display."
    }

}

// MARK: - Audio Footer Bar

/// The now-playing / queue footer. Kept as a separate view so that the 4 Hz `currentTime`
/// publisher from AmbientAudioManager only re-renders this small bar — not the whole
/// manager window (library grid, live preview, crop editor, …).
private struct AudioFooterBar: View {
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var audioManager = AmbientAudioManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var musicWidget = NowPlayingWidgetController.shared
    @State private var showQueue: Bool = false
    @State private var queueFavoritesOnly: Bool = false
    @State private var confirmClearQueue: Bool = false
    @State private var scrubPreview: Double? = nil
    @State private var volumeBeforeMute: Double = 0.5

    private var hasTrack: Bool { audioManager.trackURL != nil }

    var body: some View {
        VStack(spacing: 0) {
            if !audioManager.library.isEmpty && showQueue {
                LuminaDivider()
                queuePanel
            }

            HStack(spacing: LuminaSpace.md) {
                nowPlayingArtwork
                    .opacity(hasTrack ? 1 : 0.5)

                VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                    Text(nowPlayingTitle)
                        .font(uiScale.font(.bodyStrong))
                        .lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(hasTrack ? .primary : .secondary)
                    Text(nowPlayingSubtitle)
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(
                    minWidth: LuminaMetrics.footerTitleMin,
                    idealWidth: LuminaMetrics.footerTitleIdeal,
                    maxWidth: LuminaMetrics.footerTitleMax,
                    alignment: .leading
                )

                if hasTrack {
                    HStack(spacing: LuminaSpace.xs) {
                        transportIcon("shuffle", active: audioManager.shuffle, label: "Shuffle") {
                            audioManager.setShuffle(!audioManager.shuffle)
                        }
                        .disabled(audioManager.library.count < 2)

                        transportIcon("backward.end.fill", label: "Previous") {
                            audioManager.previousTrack()
                        }
                        .disabled(audioManager.library.count < 2)

                        transportIcon("gobackward.10", label: "Back 10 seconds") {
                            audioManager.seek(by: -10)
                        }

                        Button { audioManager.toggle() } label: {
                            Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: LuminaMetrics.footerPlay))
                                .foregroundStyle(themeManager.current.color)
                        }
                        .buttonStyle(LuminaPressableButtonStyle())
                        .help(audioManager.isPlaying ? "Pause" : "Play")
                        .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")

                        transportIcon("goforward.10", label: "Forward 10 seconds") {
                            audioManager.seek(by: 10)
                        }

                        transportIcon("forward.end.fill", label: "Next") {
                            if audioManager.library.count >= 2 {
                                audioManager.nextTrack()
                            } else {
                                audioManager.seekToTime(0)
                            }
                        }

                        transportIcon("repeat", active: audioManager.loops, label: "Repeat") {
                            audioManager.setLoops(!audioManager.loops)
                        }
                    }

                    LuminaWaveformScrubber(
                        currentTime: audioManager.currentTime,
                        duration: audioManager.duration,
                        isPlaying: audioManager.isPlaying,
                        style: .footer,
                        source: .live,
                        preview: $scrubPreview,
                        onSeek: { audioManager.seekToTime($0) }
                    )
                    .frame(maxWidth: .infinity)

                    HStack(spacing: LuminaSpace.sm) {
                        Button {
                            toggleMute()
                        } label: {
                            Image(systemName: audioManager.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: uiScale.iconSize(.card)))
                                .foregroundStyle(.secondary)
                                .frame(width: LuminaMetrics.iconColumn, alignment: .leading)
                        }
                        .buttonStyle(LuminaPressableButtonStyle())
                        .accessibilityLabel(audioManager.volume < 0.01 ? "Unmute" : "Mute")

                        LuminaSlider(
                            value: Binding(get: { audioManager.volume }, set: { audioManager.setVolume($0) }),
                            range: 0...1,
                            compact: true,
                            label: "Music volume"
                        )
                        .frame(width: LuminaMetrics.footerVolumeWidth)
                    }

                    LuminaVerticalDivider().frame(height: DisplayScale.points(24))
                } else {
                    Spacer(minLength: LuminaSpace.md)
                }

                if hasTrack {
                    Button {
                        audioManager.chooseTrack()
                    } label: {
                        Label("Add Music…", systemImage: "plus")
                    }
                    .buttonStyle(LuminaSecondaryButtonStyle())
                    .controlSize(.small)
                    .help("Add songs to the queue")
                } else {
                    Button {
                        audioManager.chooseTrack()
                    } label: {
                        Label("Add Music…", systemImage: "plus")
                    }
                    .buttonStyle(LuminaProminentButtonStyle())
                    .controlSize(.small)
                    .help("Add songs to the queue")
                }

                if hasTrack {
                    Button {
                        audioManager.clearTrack()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(LuminaIconButtonStyle())
                    .accessibilityLabel("Stop")
                    .help("Stop")
                }

                Button {
                    LuminaMotion.animate(LuminaMotion.state) { showQueue.toggle() }
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(LuminaIconButtonStyle(active: showQueue))
                .accessibilityLabel("Queue")
                .accessibilityValue(showQueue ? "Shown" : "Hidden")

                Button {
                    musicWidget.toggle()
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                }
                .buttonStyle(LuminaIconButtonStyle(active: musicWidget.isVisible))
                .accessibilityLabel("Music widget")
                .accessibilityValue(musicWidget.isVisible ? "Shown" : "Hidden")
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, LuminaSpace.barPaddingV)
            .luminaGlassChrome()
            .animation(LuminaMotion.state, value: hasTrack)
        }
    }

    private func toggleMute() {
        if audioManager.volume < 0.01 {
            audioManager.setVolume(max(volumeBeforeMute, 0.05))
        } else {
            volumeBeforeMute = audioManager.volume
            audioManager.setVolume(0)
        }
    }

    private var nowPlayingArtwork: some View {
        let side = DisplayScale.points(40)
        return Group {
            if let art = audioManager.trackArtwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                themeManager.current.color.opacity(0.9),
                                themeManager.current.color.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: side, height: side)
                    .overlay(
                        Image(systemName: audioManager.isPlaying ? "waveform" : "music.note")
                            .font(.system(size: uiScale.iconSize(.filter), weight: .semibold))
                            .foregroundStyle(themeManager.current.onAccent)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private var nowPlayingTitle: String {
        guard hasTrack else { return "No music" }
        return audioManager.trackTitle
    }

    private var nowPlayingSubtitle: String {
        if !hasTrack { return "Add a song to play in the background" }
        if !audioManager.trackArtist.isEmpty { return audioManager.trackArtist }
        return "Ambient music"
    }

    private func transportIcon(
        _ symbol: String,
        active: Bool = false,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(LuminaIconButtonStyle(active: active))
        .help(label)
        .accessibilityLabel(label)
    }

    private var queueTracks: [AmbientAudioManager.AudioTrack] {
        if queueFavoritesOnly {
            return audioManager.library.filter { audioManager.isFavorite($0) }
        }
        return audioManager.library
    }

    @ViewBuilder private var queuePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: LuminaSpace.sm) {
                Text("Queue")
                    .font(uiScale.font(.callout).weight(.semibold))
                    .foregroundStyle(.secondary)

                LuminaStatusPill(style: .neutral, text: "\(queueTracks.count)")

                Spacer()

                Button {
                    LuminaMotion.animate(LuminaMotion.state) {
                        queueFavoritesOnly.toggle()
                    }
                } label: {
                    Image(systemName: queueFavoritesOnly ? "star.fill" : "star")
                }
                .buttonStyle(LuminaIconButtonStyle(active: queueFavoritesOnly))
                .accessibilityLabel("Starred only")
                .accessibilityValue(queueFavoritesOnly ? "On" : "Off")
                .help(queueFavoritesOnly ? "Show all" : "Show starred only")

                Button("Clear Queue…") { confirmClearQueue = true }
                    .buttonStyle(LuminaSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(audioManager.library.isEmpty)
                    .confirmationDialog(
                        "Clear the queue?",
                        isPresented: $confirmClearQueue,
                        titleVisibility: .visible
                    ) {
                        Button("Clear Queue", role: .destructive) {
                            audioManager.clearLibrary()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("All songs leave the queue. The files stay on your Mac.")
                    }
            }
            .padding(.horizontal, LuminaSpace.lg)
            .padding(.vertical, LuminaSpace.sm)

            if queueTracks.isEmpty {
                Text(queueFavoritesOnly ? "No starred songs." : "No songs in the queue.")
                    .font(uiScale.font(.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LuminaSpace.lg)
                    .padding(.bottom, LuminaSpace.md)
            } else {
                List {
                    ForEach(Array(queueTracks.enumerated()), id: \.element.id) { idx, track in
                        queueRow(track: track, index: idx)
                    }
                    .onMove { source, dest in
                        guard !queueFavoritesOnly else { return }
                        audioManager.moveTrack(from: source, to: dest)
                    }
                }
                .listStyle(.plain)
                .frame(height: min(
                    CGFloat(queueTracks.count) * LuminaMetrics.queueRow,
                    LuminaMetrics.queuePanelMax
                ))
            }
        }
        .luminaWindowBackdrop()
    }

    private func queueRow(track: AmbientAudioManager.AudioTrack, index: Int) -> some View {
        let isActive = audioManager.trackURL == track.url
        let starred = audioManager.isFavorite(track)
        let art = audioManager.artwork(for: track)
        let artSide = DisplayScale.points(36)

        return HStack(spacing: LuminaSpace.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                themeManager.current.color.opacity(0.85),
                                themeManager.current.color.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if let art {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if isActive {
                    Image(systemName: audioManager.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: uiScale.iconSize(.inline), weight: .semibold))
                        .foregroundStyle(themeManager.current.onAccent)
                } else {
                    Text("\(index + 1)")
                        .font(uiScale.font(.callout).weight(.semibold).monospacedDigit())
                        .foregroundStyle(themeManager.current.onAccent.opacity(0.9))
                }
            }
            .frame(width: artSide, height: artSide)
            .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                Text(track.title)
                    .font(uiScale.font(.bodyStrong))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isActive ? themeManager.current.color : .primary)

                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(uiScale.font(.caption))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatQueueDuration(track))
                .font(uiScale.font(.caption).monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                audioManager.toggleFavorite(track)
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .foregroundStyle(starred ? LuminaStatusColor.star : .secondary)
            }
            .buttonStyle(LuminaIconButtonStyle(size: .compact))
            .accessibilityLabel(starred ? "Unstar \(track.title)" : "Star \(track.title)")

            Button {
                audioManager.removeFromLibrary(track: track)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(LuminaIconButtonStyle(size: .compact))
            .accessibilityLabel("Remove \(track.title)")
        }
        .frame(height: LuminaMetrics.queueRow)
        .listRowBackground(
            isActive ? themeManager.current.color.opacity(0.08) : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            audioManager.selectTrack(track)
            if !audioManager.isPlaying { audioManager.play() }
        }
    }

    private func formatQueueDuration(_ track: AmbientAudioManager.AudioTrack) -> String {
        guard track.duration > 0 else { return "" }
        let s = Int(track.duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Compact Library Filter Chip

private struct CompactLibraryFilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let help: String
    var action: () -> Void

    @StateObject private var theme = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: LuminaSpace.xs) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(.inline), weight: .semibold))
                Text(label)
                    .font(uiScale.font(.caption).weight(.semibold))
            }
            .padding(.horizontal, LuminaSpace.sm)
            .padding(.vertical, LuminaSpace.xs)
            .foregroundStyle(isSelected ? theme.current.text(in: colorScheme) : .secondary)
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? theme.current.color.opacity(0.45) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if isSelected { return theme.current.color.opacity(0.14) }
        if isHovered { return Color.luminaFillHover }
        return Color.luminaFill
    }
}

// MARK: - Wallpaper Grid Item

struct WallpaperGridItem: View {
    let recent: WallpaperManagerStore.RecentMedia
    let isSelected: Bool
    let isFavorite: Bool
    let onApply: () -> Void
    let onFavorite: () -> Void
    var onRemove: (() -> Void)? = nil
    var onMoveFocus: ((MoveCommandDirection) -> Void)? = nil

    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var theme = ThemeManager.shared

    private var typeLabel: String {
        switch recent.mediaType {
        case .video: return "Video"
        case .animatedImage: return "GIF"
        case .image: return "Image"
        default: return "Wallpaper"
        }
    }

    private var displayTitle: String {
        (recent.displayName as NSString).deletingPathExtension
    }

    var body: some View {
        let accent = theme.current.color
        let shape = RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)

        VStack(alignment: .leading, spacing: LuminaSpace.xs) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    thumbnailContent
                }
                .clipShape(shape)
                .overlay(alignment: .bottomLeading) {
                    typeBadge
                        .padding(LuminaSpace.tight)
                        .accessibilityLabel(typeLabel)
                }
                .overlay {
                    if isHovered || isFocused {
                        shape
                            .fill(Color.luminaOverlay.opacity(0.8))
                            .overlay(
                                HStack(spacing: LuminaSpace.lg) {
                                    Button { onApply() } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(LuminaIconButtonStyle())
                                    .accessibilityLabel("Set as Wallpaper")

                                    Button { onFavorite() } label: {
                                        Image(systemName: isFavorite ? "star.fill" : "star")
                                            .foregroundStyle(isFavorite ? LuminaStatusColor.star : .white)
                                    }
                                    .buttonStyle(LuminaIconButtonStyle())
                                    .accessibilityLabel(isFavorite ? "Unstar" : "Star")
                                }
                            )
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: DisplayScale.points(16)))
                            .foregroundStyle(accent)
                            .background(Circle().fill(Color.luminaCard).padding(2))
                            .padding(LuminaSpace.tight)
                    } else if isFavorite && !isHovered {
                        Image(systemName: "star.fill")
                            .font(.system(size: uiScale.iconSize(.inline)))
                            .foregroundStyle(LuminaStatusColor.star)
                            .padding(LuminaSpace.tight)
                    }
                }
                .overlay {
                    shape
                        .strokeBorder(
                            isSelected || isHovered || isFocused
                                ? accent
                                : Color.luminaBorder.opacity(0.5),
                            lineWidth: isSelected ? 2 : 1
                        )
                }

            Text(displayTitle)
                .font(uiScale.font(.caption).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusable()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .onTapGesture { onApply() }
        .onKeyPress(.space) { onApply(); return .handled }
        .onKeyPress(.return) { onApply(); return .handled }
        .onMoveCommand { direction in
            onMoveFocus?(direction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayTitle)
        .accessibilityValue(isFavorite ? "\(typeLabel), starred" : typeLabel)
        .accessibilityHint("Sets it on the selected display")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text(isFavorite ? "Unstar" : "Star")) { onFavorite() }
        .accessibilityAction(named: Text("Remove from Library")) { onRemove?() }
        .contextMenu {
            Button { onApply() } label: {
                Label("Set as Wallpaper", systemImage: "photo.on.rectangle")
            }
            Button { onFavorite() } label: {
                Label(isFavorite ? "Unstar" : "Star", systemImage: isFavorite ? "star.slash" : "star")
            }
            Divider()
            Button(role: .destructive) { onRemove?() } label: {
                Label("Remove from Library", systemImage: "trash")
            }
            .disabled(onRemove == nil)
        }
        .task(id: recent.url) { await loadThumbnail() }
    }

    @ViewBuilder private var thumbnailContent: some View {
        Color.luminaFill
            .overlay {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    VStack(spacing: LuminaSpace.xs) {
                        Image(systemName: recent.mediaType == .video ? "video.slash" : "photo")
                            .font(.system(size: uiScale.iconSize(.card)))
                            .foregroundStyle(.secondary)
                        Text("No preview")
                            .font(uiScale.font(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }

    @ViewBuilder private var typeBadge: some View {
        let icon: String = {
            switch recent.mediaType {
            case .video: return "play.fill"
            case .animatedImage: return "photo.stack.fill"
            case .image: return "photo.fill"
            default: return "questionmark"
            }
        }()
        Image(systemName: icon)
            .font(uiScale.font(.micro).weight(.bold))
            .foregroundStyle(.white)
            .padding(LuminaSpace.xs)
            .background(
                Color.luminaOverlay,
                in: RoundedRectangle(cornerRadius: LuminaRadius.badge, style: .continuous)
            )
    }

    private func loadThumbnail() async {
        isLoading = true
        let img = await ThumbnailService.shared.smallThumbnail(for: recent.url, mediaType: recent.mediaType)
        await MainActor.run {
            thumbnail = img
            isLoading = false
        }
    }
}
