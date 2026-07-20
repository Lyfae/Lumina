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
    // NOTE: AmbientAudioManager is deliberately NOT observed here. It publishes currentTime
    // 4×/sec during playback, which would invalidate the entire manager tree (library grid,
    // live preview, crop UI) on every tick. Only AudioFooterBar observes it.
    @StateObject private var favoritesManager = FavoritesManager.shared

    @State private var searchQuery: String = ""
    @State private var selectedFilter: LibraryFilter = .all
    @State private var showSettings: Bool = false

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
            .background(Color.luminaBase)
            .tint(themeManager.current.color)
            .onAppear { autoSelectFirstMonitor() }
    }

    private var coreContent: some View {
        VStack(spacing: 0) {
            headerBar
            LuminaDivider()
            mainContent
            LuminaDivider()
            AudioFooterBar()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: DisplayScale.points(14)) {
            HStack(spacing: DisplayScale.points(10)) {
                LuminaBrandMark(side: DisplayScale.points(36))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lumina Studio")
                        .font(.system(size: DisplayScale.points(17), weight: .bold))
                    Text("Wallpaper Manager")
                        .font(.system(size: DisplayScale.points(11)))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: DisplayScale.points(12))

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
            .background(Color.luminaCard, in: RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
                    .strokeBorder(Color.luminaBorder, lineWidth: 1)
            )
            .frame(minWidth: DisplayScale.points(180), maxWidth: DisplayScale.points(280))
            .layoutPriority(-1)

            LuminaToolbarButton(
                title: "Sync",
                icon: "arrow.triangle.2.circlepath",
                help: "Restart matching video/GIF wallpapers in sync across displays"
            ) {
                store.restartDisplaysInSync()
            }

            LuminaToolbarButton(title: "Settings", icon: "gearshape.fill") {
                showSettings = true
            }
        }
        .padding(.horizontal, LuminaLayout.contentPadding)
        .padding(.vertical, DisplayScale.points(12))
        .background(.bar)
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store, onClose: { showSettings = false })
        }
    }

    // MARK: - Main Two-Column Content

    private var mainContent: some View {
        HStack(spacing: 0) {
            libraryColumn
            // Prominent seam between the library and configuration columns. The system
            // Divider all but vanishes on the pure-black theme, so use a clear border line.
            Rectangle()
                .fill(Color.luminaBorder)
                .frame(width: 1)
            configurationColumn
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Library Column (left)

    private var libraryColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DisplayScale.points(12)) {
                LuminaSectionHeader(
                    title: "Library",
                    subtitle: "Click a wallpaper to apply it to the selected display",
                    trailing: "\(filteredMedia.count)"
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DisplayScale.points(8)) {
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
                    .padding(.horizontal, 1)
                }
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.top, DisplayScale.points(16))
            .padding(.bottom, DisplayScale.points(12))
            .background(Color.luminaBase)

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
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, DisplayScale.points(14))
            .background(.bar)
        }
        .frame(width: LuminaLayout.libraryColumnWidth)
        .background(Color.luminaBase)
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
                .buttonStyle(.bordered)
                .controlSize(uiScale.controlSize())
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, DisplayScale.points(14))
            .background(.bar)

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
                    .buttonStyle(.borderedProminent)
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
            Text(selectedFilter == .favorites
                 ? "Star wallpapers in the grid to find them quickly here."
                 : "Add videos, GIFs, or images — then tap one to set it on the selected display.")
                .font(.system(size: DisplayScale.points(12)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: DisplayScale.points(260))
            if searchQuery.isEmpty && selectedFilter == .all {
                Button("Add to Library") { addMediaToLibrary() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DisplayScale.points(240))
        .padding(LuminaLayout.contentPadding)
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
    @State private var showQueue: Bool = false

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
                    Text("Ambient Audio")
                        .font(.system(size: DisplayScale.points(11))).foregroundStyle(.secondary)
                }
                .frame(minWidth: DisplayScale.points(120), idealWidth: DisplayScale.points(170), maxWidth: DisplayScale.points(220), alignment: .leading)

                HStack(spacing: DisplayScale.points(14)) {
                    transportIcon(
                        "repeat",
                        active: audioManager.loops,
                        help: audioManager.loops ? "Looping on — track repeats" : "Looping off"
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
                    .buttonStyle(.plain)
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

                // Progress — expands to fill available width
                if audioManager.duration > 0 {
                    HStack(spacing: DisplayScale.points(8)) {
                        Text(formatAudioTime(audioManager.currentTime))
                            .font(uiScale.scaledFont(11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: DisplayScale.points(38), alignment: .trailing)
                        LuminaSlider(
                            value: Binding(
                                get: { audioManager.currentTime },
                                set: { audioManager.seekToTime($0) }
                            ),
                            range: 0...max(audioManager.duration, 1),
                            compact: true
                        )
                        .help("Seek")
                        Text(formatAudioTime(audioManager.duration))
                            .font(uiScale.scaledFont(11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: DisplayScale.points(38), alignment: .leading)
                    }
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
                    Label("Add Track", systemImage: "plus.circle.fill").font(.callout)
                }
                .buttonStyle(.borderless)
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
            }
            .padding(.horizontal, LuminaLayout.contentPadding)
            .padding(.vertical, DisplayScale.points(10))
        }
    }

    /// Small rounded album-art tile used in the now-playing bar.
    private var nowPlayingArtwork: some View {
        let side = DisplayScale.points(40)
        return RoundedRectangle(cornerRadius: DisplayScale.points(10), style: .continuous)
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
            .opacity(audioManager.trackURL != nil ? 1 : 0.5)
    }

    private var nowPlayingTitle: String {
        guard audioManager.trackURL != nil else { return "No track selected" }
        let stem = (audioManager.trackName as NSString).deletingPathExtension
        return stem.isEmpty ? audioManager.trackName : stem
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
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Music Queue Panel

    @ViewBuilder private var queuePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(uiScale.scaledFont(12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { audioManager.clearLibrary() }
                    .font(uiScale.scaledFont(11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(audioManager.library.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            List {
                ForEach(Array(audioManager.library.enumerated()), id: \.element.id) { idx, track in
                    let isActive = audioManager.trackURL == track.url
                    HStack(spacing: 8) {
                        // Now-playing indicator
                        if isActive {
                            Image(systemName: audioManager.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                .font(.system(size: DisplayScale.points(11)))
                                .foregroundStyle(themeManager.current.color)
                                .frame(width: DisplayScale.points(16))
                        } else {
                            Text("\(idx + 1)")
                                .font(uiScale.scaledFont(11).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: DisplayScale.points(16))
                        }

                        Text(track.name)
                            .font(uiScale.scaledFont(13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(isActive ? themeManager.current.color : .primary)

                        Spacer()

                        Text(formatQueueDuration(track))
                            .font(uiScale.scaledFont(11).monospacedDigit())
                            .foregroundStyle(.secondary)

                        Button {
                            audioManager.removeFromLibrary(track: track)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: DisplayScale.points(14)))
                                .foregroundStyle(.secondary)
                                .frame(width: uiScale.touchTarget() * 0.7, height: uiScale.touchTarget() * 0.7)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(track.name) from queue")
                    }
                    .padding(.vertical, DisplayScale.points(2))
                    .listRowBackground(
                        isActive ? themeManager.current.color.opacity(0.08) : Color.clear
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.selectTrack(track)
                        if !audioManager.isPlaying { audioManager.play() }
                    }
                }
                .onMove { audioManager.moveTrack(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .frame(height: min(CGFloat(audioManager.library.count) * DisplayScale.points(34) + 8, DisplayScale.points(150)))
        }
        .background(Color.luminaBase)
    }

    private func formatQueueDuration(_ track: AmbientAudioManager.AudioTrack) -> String {
        guard track.duration > 0 else { return "" }
        let s = Int(track.duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func formatAudioTime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
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
    @State private var loadFailed = false
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
                            .buttonStyle(.plain)
                            .help("Set as Wallpaper")
                            .accessibilityLabel("Set as Wallpaper")

                            Button { onFavorite() } label: {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.system(size: uiScale.iconSize(.filter)))
                                    .foregroundStyle(isFavorite ? Color.yellow : .white)
                                    .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
        isLoading = true; loadFailed = false
        nonisolated(unsafe) let mt = recent.mediaType
        let img = await ThumbnailService.shared.smallThumbnail(for: recent.url, mediaType: mt)
        await MainActor.run {
            thumbnail = img; isLoading = false; loadFailed = (img == nil)
        }
    }
}
