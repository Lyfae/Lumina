import SwiftUI
import AppKit

// MARK: - Library Filter

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, videos, images, gifs, favorites
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .videos: return "Video"
        case .images: return "Image"
        case .gifs: return "GIF"
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
        case .all:       return "Show all wallpapers in your library"
        case .videos:    return "Show only video wallpapers"
        case .images:    return "Show only static images"
        case .gifs:      return "Show only animated GIFs"
        case .favorites: return "Show wallpapers you have starred"
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

    @State private var searchQuery: String = ""
    @State private var selectedFilter: LibraryFilter = .all
    @State private var showSettings: Bool = false
    /// Library column is expanded by default; collapse to give the preview more room.
    @State private var showLibraryColumn: Bool = true

    private static let libraryToggleDuration: TimeInterval = 0.35

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
        HStack(alignment: .center, spacing: DisplayScale.points(12)) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: DisplayScale.points(16), weight: .semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wallpaper is straining this Mac")
                    .font(.system(size: DisplayScale.points(13), weight: .semibold))
                Text(playbackHealthBannerDetail)
                    .font(.system(size: DisplayScale.points(11)))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DisplayScale.points(8))

            Button("Settings") { showSettings = true }
                .buttonStyle(LuminaSecondaryButtonStyle())

            Button {
                playbackHealth.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: DisplayScale.points(11), weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                    .contentShape(Rectangle())
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .help("Dismiss for now")
            .accessibilityLabel("Dismiss performance warning")
        }
        .padding(.horizontal, LuminaLayout.contentPadding)
        .padding(.vertical, DisplayScale.points(10))
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.orange.opacity(0.35)).frame(height: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: playbackHealth.isStruggling)
    }

    private var playbackHealthBannerDetail: String {
        let tip = "Try Compress in Adjust → Performance, or Settings → Battery → Max Battery."
        if playbackHealth.reason.isEmpty { return tip }
        return "\(playbackHealth.reason). \(tip)"
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: DisplayScale.points(14)) {
            HStack(spacing: DisplayScale.points(10)) {
                LuminaBrandMark(side: DisplayScale.points(36))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lumina Studio")
                        .font(.system(size: DisplayScale.points(17), weight: .bold))
                    Text("Live wallpapers")
                        .font(.system(size: DisplayScale.points(11)))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: DisplayScale.points(12))

            LuminaToolbarButton(title: "Settings", icon: "gearshape.fill") {
                showSettings = true
            }
        }
        .padding(.horizontal, LuminaLayout.contentPadding)
        .padding(.vertical, DisplayScale.points(12))
        .luminaGlassChrome()
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store, onClose: { showSettings = false })
        }
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
            .animation(
                .timingCurve(0.25, 0.1, 0.25, 1.0, duration: Self.libraryToggleDuration),
                value: showLibraryColumn
            )

            Rectangle()
                .fill(Color.luminaBorder)
                .frame(width: 1)

            configurationColumn
        }
        .frame(maxHeight: .infinity)
    }

    /// Slim strip shown while the library is collapsed — one click brings it back.
    private var libraryRail: some View {
        VStack(spacing: DisplayScale.points(10)) {
            Button {
                withAnimation(
                    .timingCurve(0.25, 0.1, 0.25, 1.0, duration: Self.libraryToggleDuration)
                ) {
                    showLibraryColumn = true
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: uiScale.iconSize(.toolbar), weight: .semibold))
                    .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                    .contentShape(Rectangle())
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .help("Show library")
            .accessibilityLabel("Show library")
            .padding(.top, DisplayScale.points(10))

            Text("Library")
                .font(.system(size: DisplayScale.points(10), weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: LuminaLayout.libraryRailWidth)

            Spacer(minLength: 0)

            if !filteredMedia.isEmpty {
                Text("\(filteredMedia.count)")
                    .font(.system(size: DisplayScale.points(10), weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, DisplayScale.points(12))
            }
        }
        .frame(width: LuminaLayout.libraryRailWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(
                .timingCurve(0.25, 0.1, 0.25, 1.0, duration: Self.libraryToggleDuration)
            ) {
                showLibraryColumn = true
            }
        }
    }

    // MARK: - Library Column (left)

    private var libraryColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DisplayScale.points(12)) {
                HStack(alignment: .center, spacing: DisplayScale.points(8)) {
                    Button {
                        withAnimation(
                            .timingCurve(0.25, 0.1, 0.25, 1.0, duration: Self.libraryToggleDuration)
                        ) {
                            showLibraryColumn = false
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(LuminaPressableButtonStyle())
                    .help("Hide library")
                    .accessibilityLabel("Hide library")

                    LuminaSectionHeader(
                        title: "Library",
                        subtitle: "Click a wallpaper to apply it to the selected display",
                        trailing: "\(filteredMedia.count)"
                    )
                }

                HStack(spacing: DisplayScale.points(8)) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: uiScale.iconSize(.card)))
                        .foregroundStyle(.secondary)
                    TextField("Search library…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: DisplayScale.points(14)))
                }
                .padding(.horizontal, DisplayScale.points(12))
                .padding(.vertical, DisplayScale.points(8))
                .luminaGlassPanel(cornerRadius: 10)

                // Wrap chips — never horizontal-scroll. AppKit overlay scrollers were
                // flashing as a stray nub under the row on first layout.
                LuminaWrappingHStack(spacing: DisplayScale.points(8)) {
                    ForEach(LibraryFilter.allCases) { filter in
                        LuminaFilterChip(
                            label: filter.label,
                            icon: filter.icon,
                            isSelected: selectedFilter == filter,
                            help: filter.helpText
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedFilter = filter }
                        }
                    }
                }
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.top, DisplayScale.points(16))
            .padding(.bottom, DisplayScale.points(12))

            LuminaDivider()

            ScrollView {
                if filteredMedia.isEmpty {
                    emptyLibraryView
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: LuminaLayout.thumbnailWidth, maximum: LuminaLayout.thumbnailWidth + DisplayScale.points(24)),
                                spacing: LuminaLayout.sectionSpacing
                            )
                        ],
                        spacing: LuminaLayout.sectionSpacing
                    ) {
                        ForEach(filteredMedia) { recent in
                            let isCurrent = isCurrentWallpaper(recent: recent)
                            WallpaperGridItem(
                                recent: recent,
                                isSelected: isCurrent,
                                isFavorite: favoritesManager.isFavorite(recent.id),
                                onApply: { applyRecentToSelected(recent: recent) },
                                onFavorite: { favoritesManager.toggle(recent.id) },
                                onRemove: { store.removeFromLibrary(id: recent.id) }
                            )
                            .padding(DisplayScale.points(4))
                        }
                    }
                    .padding(.horizontal, LuminaLayout.contentPadding)
                    .padding(.vertical, DisplayScale.points(16))
                }
            }
            .frame(maxHeight: .infinity)

            LuminaDivider()

            VStack(spacing: DisplayScale.points(8)) {
                Button { addMediaToLibrary() } label: {
                    Label("Add to Library", systemImage: "plus.circle.fill")
                        .font(.system(size: DisplayScale.points(14), weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DisplayScale.points(10))
                }
                .buttonStyle(LuminaProminentButtonStyle())
                .controlSize(.large)
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, DisplayScale.points(14))
            .luminaGlassChrome()
        }
        .frame(width: LuminaLayout.libraryColumnWidth)
        .luminaWindowBackdrop()
    }

    // MARK: - Configuration Column (right)

    private var configurationColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: DisplayScale.points(12)) {
                if let monitor = currentTargetMonitor {
                    HStack(spacing: DisplayScale.points(10)) {
                        Image(systemName: "display")
                            .font(.system(size: UIScaleManager.shared.iconSize(.filter), weight: .semibold))
                            .foregroundStyle(themeManager.current.color)
                            .frame(width: UIScaleManager.shared.touchTarget(), height: UIScaleManager.shared.touchTarget())
                            .background(themeManager.current.color.opacity(0.1), in: RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Display")
                                .font(.system(size: DisplayScale.points(11)))
                                .foregroundStyle(.tertiary)
                            Text(monitorLabel(for: monitor))
                                .font(.system(size: DisplayScale.points(15), weight: .bold))
                            Text(monitor.resolution)
                                .font(.system(size: DisplayScale.points(11)))
                                .foregroundStyle(.secondary)
                        }

                        if let assignment = store.assignment(for: monitor.id),
                           assignment.keepOnStartup {
                            HStack(spacing: 4) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: DisplayScale.points(11), weight: .bold))
                                Text("Pinned")
                                    .font(.system(size: DisplayScale.points(11), weight: .semibold))
                            }
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, DisplayScale.points(9))
                            .padding(.vertical, DisplayScale.points(4))
                            .background(.yellow.opacity(0.15), in: Capsule())
                            .help("Restores automatically when Lumina launches")
                        }
                    }
                } else {
                    Label("No Display Selected", systemImage: "display.trianglebadge.exclamationmark")
                        .font(.system(size: DisplayScale.points(14), weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .togglePhysicalSetupWindow, object: nil)
                } label: {
                    Label("Choose Display…", systemImage: "display.2")
                        .font(.system(size: DisplayScale.points(13), weight: .semibold))
                }
                .buttonStyle(LuminaSecondaryButtonStyle())
                .controlSize(uiScale.controlSize())
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, DisplayScale.points(14))
            .luminaGlassChrome()

            LuminaDivider()

            if let monitor = currentTargetMonitor {
                // No outer ScrollView: the panel pins its preview + action bar and scrolls
                // only the settings in between.
                MonitorDetailPanel(monitor: monitor, store: store, showHeader: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
                VStack(spacing: DisplayScale.points(18)) {
                    Image(systemName: "display.2")
                        .font(.system(size: UIScaleManager.shared.iconSize(.hero)))
                        .foregroundStyle(themeManager.current.color.opacity(0.35))
                    Text("Choose a display")
                        .font(.system(size: DisplayScale.points(20), weight: .semibold))
                    Text("Pick which monitor you want to configure, then select a wallpaper from your library.")
                        .font(.system(size: DisplayScale.points(13)))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: DisplayScale.points(320))
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

    // MARK: - Helpers (preserved verbatim from original)

    private func autoSelectFirstMonitor() {
        if store.selectedMonitorID == nil && selectedMonitorID == nil,
           let first = store.monitors.first {
            selectedMonitorID = first.id
            store.selectedMonitorID = first.id
        }
    }

    private func monitorLabel(for monitor: MonitorInfo) -> String {
        if let index = store.monitors.firstIndex(where: { $0.id == monitor.id }) {
            return "S\(index + 1) • \(monitor.name)"
        }
        return monitor.name
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
            title: "Add wallpaper to library",
            message: "This adds the file to your collection on the left so you can re-use it on any display. It will not change what is currently playing."
        ).first else { return }
        store.addMediaToLibrary(url: url)
    }

    // MARK: - Empty Library View

    @ViewBuilder private var emptyLibraryView: some View {
        VStack(spacing: DisplayScale.points(16)) {
            Image(systemName: selectedFilter == .favorites ? "star.fill" : "photo.badge.plus.fill")
                .font(.system(size: UIScaleManager.shared.iconSize(.hero)))
                .foregroundStyle(themeManager.current.color.opacity(0.4))
            Text(selectedFilter == .favorites ? "No favorites yet" :
                 searchQuery.isEmpty ? "Your library is empty" : "No results for \"\(searchQuery)\"")
                .font(.system(size: DisplayScale.points(15), weight: .semibold))
            Text(emptyLibrarySubtitle)
                .font(.system(size: DisplayScale.points(12)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: DisplayScale.points(260))

            HStack(spacing: DisplayScale.points(10)) {
                if !searchQuery.isEmpty {
                    Button("Clear Search") { searchQuery = "" }
                        .buttonStyle(LuminaSecondaryButtonStyle())
                }
                if selectedFilter != .all {
                    Button("Show All") { selectedFilter = .all }
                        .buttonStyle(LuminaSecondaryButtonStyle())
                }
                if searchQuery.isEmpty && selectedFilter == .all {
                    Button("Add to Library") { addMediaToLibrary() }
                        .buttonStyle(LuminaProminentButtonStyle())
                        .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: DisplayScale.points(240))
        .padding(LuminaLayout.contentPadding)
    }

    private var emptyLibrarySubtitle: String {
        if selectedFilter == .favorites {
            return "Star wallpapers in the grid to find them quickly here."
        }
        if !searchQuery.isEmpty {
            return "Try a different search, or clear it to see everything."
        }
        if selectedFilter != .all {
            return "Nothing matches this filter — show all wallpapers or add media."
        }
        return "Add videos, GIFs, or images — then tap one to set it on the selected display."
    }
}

// MARK: - Audio Footer Bar

/// The now-playing / queue footer. Kept as a separate view so that the 4 Hz `currentTime`
/// publisher from AmbientAudioManager only re-renders this small bar — not the whole
/// manager window (library grid, live preview, crop editor, …).
private struct AudioFooterBar: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var audioManager = AmbientAudioManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @StateObject private var musicWidget = NowPlayingWidgetController.shared
    @State private var showQueue: Bool = false
    @State private var queueFavoritesOnly: Bool = false
    @State private var confirmClearQueue: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Queue panel — collapsible above the controls row
            if !audioManager.library.isEmpty && showQueue {
                LuminaDivider()
                queuePanel
            }

            // Now-playing bar — larger, roomier, adaptive (the progress track absorbs
            // any extra width as the window grows).
            HStack(spacing: DisplayScale.points(16)) {
                nowPlayingArtwork

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlayingTitle)
                        .font(.system(size: DisplayScale.points(14), weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(audioManager.trackURL != nil ? .primary : .secondary)
                    Text(nowPlayingSubtitle)
                        .font(.system(size: DisplayScale.points(11))).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: DisplayScale.points(120), idealWidth: DisplayScale.points(170), maxWidth: DisplayScale.points(220), alignment: .leading)

                HStack(spacing: DisplayScale.points(14)) {
                    transportIcon(
                        "shuffle",
                        active: audioManager.shuffle,
                        help: audioManager.shuffle ? "Shuffle on" : "Shuffle off"
                    ) {
                        audioManager.setShuffle(!audioManager.shuffle)
                    }
                    .disabled(audioManager.library.count < 2)

                    transportIcon(
                        "repeat",
                        active: audioManager.loops,
                        help: audioManager.loops ? "Loop on — track repeats" : "Loop off — play through queue"
                    ) {
                        audioManager.setLoops(!audioManager.loops)
                    }

                    transportIcon("backward.end.fill", help: "Previous track") {
                        audioManager.previousTrack()
                    }
                    .disabled(audioManager.library.count < 2)

                    transportIcon("gobackward.10", help: "Skip back 10 seconds") {
                        audioManager.seek(by: -10)
                    }
                    .disabled(audioManager.trackURL == nil)

                    Button { audioManager.toggle() } label: {
                        Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: DisplayScale.points(28)))
                            .foregroundStyle(audioManager.trackURL != nil ? themeManager.current.color : .secondary)
                    }
                    .buttonStyle(LuminaPressableButtonStyle())
                    .help(audioManager.isPlaying ? "Pause" : "Play")
                    .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
                    .disabled(audioManager.trackURL == nil)

                    transportIcon("goforward.10", help: "Skip forward 10 seconds") {
                        audioManager.seek(by: 10)
                    }
                    .disabled(audioManager.trackURL == nil)

                    transportIcon("forward.end.fill", help: "Skip to next track") {
                        if audioManager.library.count >= 2 {
                            audioManager.nextTrack()
                        } else {
                            audioManager.seekToTime(0)
                        }
                    }
                    .disabled(audioManager.trackURL == nil)
                }

                // Progress — expands to fill available width. Local scrub preview so the
                // thumb doesn't fight the 4 Hz timer (and seek only commits on release).
                if audioManager.duration > 0 {
                    AudioProgressScrubber(
                        currentTime: audioManager.currentTime,
                        duration: audioManager.duration,
                        accent: themeManager.current.color,
                        onSeek: { audioManager.seekToTime($0) }
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: DisplayScale.points(12))
                }

                // Volume
                HStack(spacing: DisplayScale.points(8)) {
                    Image(systemName: audioManager.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: uiScale.iconSize(.card)))
                        .foregroundStyle(.secondary)
                        .frame(width: DisplayScale.points(18), alignment: .leading)
                    LuminaSlider(
                        value: Binding(get: { audioManager.volume }, set: { audioManager.setVolume($0) }),
                        range: 0...1,
                        compact: true
                    )
                        .frame(width: 84).help("Ambient audio volume")
                }

                LuminaVerticalDivider().frame(height: 26)

                // Library actions
                Button { audioManager.chooseTrack() } label: {
                    Label("Add Track", systemImage: "plus.circle.fill")
                        .font(uiScale.scaledFont(13, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                        .frame(minHeight: uiScale.touchTarget() * 0.85)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LuminaPressableButtonStyle())
                .help("Add audio tracks to your music library")

                if audioManager.trackURL != nil {
                    transportIcon("xmark.circle.fill", help: "Stop and clear current track") {
                        audioManager.clearTrack()
                    }
                }

                transportIcon(
                    "list.bullet.rectangle",
                    active: showQueue,
                    help: showQueue ? "Hide queue" : "Show music queue"
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) { showQueue.toggle() }
                }

                transportIcon(
                    "rectangle.on.rectangle",
                    active: musicWidget.isVisible,
                    help: musicWidget.isVisible
                        ? "Hide floating music widget"
                        : "Show floating music widget on the desktop"
                ) {
                    musicWidget.toggle()
                }
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, DisplayScale.points(10))
            .luminaGlassChrome()
        }
    }

    /// Small rounded album-art tile used in the now-playing bar.
    private var nowPlayingArtwork: some View {
        let side = DisplayScale.points(40)
        return Group {
            if let art = audioManager.trackArtwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [themeManager.current.color.opacity(0.9),
                                     themeManager.current.color.opacity(0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: side, height: side)
                    .overlay(
                        Image(systemName: audioManager.isPlaying ? "waveform" : "music.note")
                            .font(.system(size: uiScale.iconSize(.filter), weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .opacity(audioManager.trackURL != nil ? 1 : 0.5)
    }

    private var nowPlayingTitle: String {
        guard audioManager.trackURL != nil else { return "No track selected" }
        return audioManager.trackTitle
    }

    private var nowPlayingSubtitle: String {
        if audioManager.trackURL == nil { return "Ambient Audio" }
        if !audioManager.trackArtist.isEmpty { return audioManager.trackArtist }
        return "Ambient Audio"
    }

    /// A flat icon button for the now-playing bar with a consistent hit target.
    private func transportIcon(
        _ symbol: String,
        active: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: uiScale.iconSize(.transport), weight: .medium))
                .foregroundStyle(active ? themeManager.current.color : .secondary)
                .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressableButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Music Queue Panel

    private var queueTracks: [AmbientAudioManager.AudioTrack] {
        if queueFavoritesOnly {
            return audioManager.library.filter { audioManager.isFavorite($0) }
        }
        return audioManager.library
    }

    @ViewBuilder private var queuePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: DisplayScale.points(10)) {
                Text("Queue")
                    .font(uiScale.scaledFont(12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(queueTracks.count)")
                    .font(uiScale.scaledFont(10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, DisplayScale.points(6))
                    .padding(.vertical, DisplayScale.points(2))
                    .background(Color.primary.opacity(0.06), in: Capsule())

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        queueFavoritesOnly.toggle()
                    }
                } label: {
                    Label(
                        queueFavoritesOnly ? "Favorites" : "All",
                        systemImage: queueFavoritesOnly ? "star.fill" : "star"
                    )
                    .font(uiScale.scaledFont(11, weight: .semibold))
                    .foregroundStyle(queueFavoritesOnly ? themeManager.current.color : .secondary)
                }
                .buttonStyle(LuminaPressableButtonStyle())
                .help(queueFavoritesOnly ? "Show all tracks" : "Show starred favorites only")

                Button("Clear All") { confirmClearQueue = true }
                    .font(uiScale.scaledFont(11))
                    .buttonStyle(LuminaPressableButtonStyle())
                    .foregroundStyle(.secondary)
                    .disabled(audioManager.library.isEmpty)
                    .confirmationDialog(
                        "Clear music queue?",
                        isPresented: $confirmClearQueue,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All", role: .destructive) {
                            audioManager.clearLibrary()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Removes all tracks from the queue. This can’t be undone.")
                    }
            }
            .padding(.horizontal, DisplayScale.points(16))
            .padding(.vertical, DisplayScale.points(8))

            if queueTracks.isEmpty {
                Text(queueFavoritesOnly ? "No starred tracks yet — tap the star on a song." : "Queue is empty")
                    .font(uiScale.scaledFont(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DisplayScale.points(16))
                    .padding(.bottom, DisplayScale.points(12))
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
                    CGFloat(queueTracks.count) * DisplayScale.points(56) + 8,
                    DisplayScale.points(220)
                ))
            }
        }
        .luminaWindowBackdrop()
    }

    private func queueRow(track: AmbientAudioManager.AudioTrack, index: Int) -> some View {
        let isActive = audioManager.trackURL == track.url
        let starred = audioManager.isFavorite(track)
        let art = audioManager.artwork(for: track)
        let artSide = DisplayScale.points(40)

        return HStack(spacing: DisplayScale.points(10)) {
            ZStack {
                RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous)
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
                        .font(.system(size: DisplayScale.points(14), weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(uiScale.scaledFont(12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: artSide, height: artSide)
            .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(8), style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(uiScale.scaledFont(13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isActive ? themeManager.current.color : .primary)

                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(uiScale.scaledFont(11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatQueueDuration(track))
                .font(uiScale.scaledFont(11).monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                audioManager.toggleFavorite(track)
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.system(size: DisplayScale.points(13), weight: .semibold))
                    .foregroundStyle(starred ? themeManager.current.color : .secondary)
                    .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                    .contentShape(Rectangle())
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .help(starred ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(starred ? "Unstar \(track.title)" : "Star \(track.title)")

            Button {
                audioManager.removeFromLibrary(track: track)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DisplayScale.points(14)))
                    .foregroundStyle(.secondary)
                    .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                    .contentShape(Rectangle())
            }
            .buttonStyle(LuminaPressableButtonStyle())
            .accessibilityLabel("Remove \(track.title) from queue")
        }
        .padding(.vertical, DisplayScale.points(4))
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

// MARK: - Wallpaper Grid Item

struct WallpaperGridItem: View {
    let recent: WallpaperManagerStore.RecentMedia
    let isSelected: Bool
    let isFavorite: Bool
    let onApply: () -> Void
    let onFavorite: () -> Void
    var onRemove: (() -> Void)? = nil

    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    @State private var isHovered = false
    @StateObject private var uiScale = UIScaleManager.shared

    var body: some View {
        let thumbW = LuminaLayout.thumbnailWidth
        let thumbH = LuminaLayout.thumbnailHeight

        ZStack(alignment: .bottomLeading) {
            // Thumbnail
            thumbnailContent
                .frame(width: thumbW, height: thumbH)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Type badge (bottom-leading)
            typeBadge
                .padding(5)

            // Hover overlay
            if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.45))
                    .frame(width: thumbW, height: thumbH)
                    .overlay(
                        HStack(spacing: DisplayScale.points(16)) {
                            Button { onApply() } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: uiScale.iconSize(.transport)))
                                    .foregroundStyle(.white)
                                    .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(LuminaPressableButtonStyle())
                            .help("Set as Wallpaper")
                            .accessibilityLabel("Set as Wallpaper")

                            Button { onFavorite() } label: {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.system(size: uiScale.iconSize(.filter)))
                                    .foregroundStyle(isFavorite ? Color.yellow : .white)
                                    .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(LuminaPressableButtonStyle())
                            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                        }
                    )
                    .transition(.opacity)
            }

            // Selection indicator
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .frame(width: thumbW, height: thumbH)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: DisplayScale.points(15)))
                            .foregroundStyle(Color.accentColor)
                            .background(Circle().fill(Color.black).padding(2))
                            .padding(5)
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    .frame(width: thumbW, height: thumbH)
            }

            // Favorite star (always visible if favorited and not hovered)
            if isFavorite && !isHovered {
                Image(systemName: "star.fill")
                    .font(.system(size: DisplayScale.points(12)))
                    .foregroundStyle(Color.yellow)
                    .padding(5)
                    .frame(width: thumbW, height: thumbH, alignment: .topTrailing)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture { onApply() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recent.displayName)
        .accessibilityHint(isSelected ? "Currently assigned wallpaper" : "Set as wallpaper")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(isFavorite ? "Remove from Favorites" : "Add to Favorites")) {
            onFavorite()
        }
        .accessibilityAction(named: Text("Set as Wallpaper")) {
            onApply()
        }
        .overlay(alignment: .bottom) {
            Text(recent.displayName)
                .font(uiScale.scaledFont(12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, DisplayScale.points(6))
                .padding(.vertical, DisplayScale.points(3))
                .frame(width: thumbW, alignment: .leading)
                .offset(y: DisplayScale.points(20))
        }
        .padding(.bottom, DisplayScale.points(20))
        .contextMenu {
            Button { onApply() } label: {
                Label("Set as Wallpaper", systemImage: "photo.on.rectangle")
            }
            Button { onFavorite() } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
            Divider()
            Button(role: .destructive) { onRemove?() } label: {
                Label("Remove from Library", systemImage: "trash")
            }
            .disabled(onRemove == nil)
        }
        // id: reload when the underlying file changes even if SwiftUI reuses this view's identity.
        .task(id: recent.url) { await loadThumbnail() }
    }

    @ViewBuilder private var thumbnailContent: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    VStack(spacing: DisplayScale.points(4)) {
                        Image(systemName: recent.mediaType == .video ? "video.slash" : "photo")
                            .font(.system(size: uiScale.iconSize(.card)))
                            .foregroundStyle(.secondary)
                        Text("No preview")
                            .font(uiScale.scaledFont(11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }

    @ViewBuilder private var typeBadge: some View {
        let (icon, color): (String, Color) = {
            switch recent.mediaType {
            case .video: return ("play.fill", .blue)
            case .animatedImage: return ("photo.stack.fill", .green)
            case .image: return ("photo.fill", .gray)
            default: return ("questionmark", .gray)
            }
        }()
        Image(systemName: icon)
            .font(.system(size: DisplayScale.points(10), weight: .bold))
            .foregroundStyle(.white)
            .padding(DisplayScale.points(5))
            .background(color.opacity(0.8), in: RoundedRectangle(cornerRadius: DisplayScale.points(4)))
    }

    private func loadThumbnail() async {
        isLoading = true
        nonisolated(unsafe) let mt = recent.mediaType
        let img = await ThumbnailService.shared.smallThumbnail(for: recent.url, mediaType: mt)
        await MainActor.run {
            thumbnail = img
            isLoading = false
        }
    }
}
