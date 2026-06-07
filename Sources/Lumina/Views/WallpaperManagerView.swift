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
    @StateObject private var audioManager = AmbientAudioManager.shared
    @StateObject private var favoritesManager = FavoritesManager.shared

    @State private var searchQuery: String = ""
    @State private var selectedFilter: LibraryFilter = .all
    @State private var showQueue: Bool = false
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
            .frame(minWidth: 960, minHeight: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.luminaBase)
            .tint(themeManager.current.color)
            .onAppear { autoSelectFirstMonitor() }
    }

    private var coreContent: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            mainContent
            Divider()
            footerBar
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "water.waves")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.current.color)
                Text("Lumina Studio")
                    .font(.title3.bold())
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary).font(.caption)
                TextField("Search library…", text: $searchQuery)
                    .textFieldStyle(.plain).font(.callout)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 200)

            Button {
                // Simple, on-demand alignment: restart every matching video/GIF wallpaper
                // together so displays that drifted (or started at different times) line up.
                store.restartDisplaysInSync()
            } label: {
                Label("Sync Displays", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Restart all matching video/GIF wallpapers together so they play in sync")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill").font(.callout)
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
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
            // Filter tabs — full-area hit targets with underline selection indicator
            HStack(spacing: 0) {
                ForEach(LibraryFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedFilter = filter }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: filter.icon).font(.callout)
                            Text(filter.label).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .foregroundStyle(selectedFilter == filter ? themeManager.current.color : .secondary)
                        .background(
                            selectedFilter == filter
                                ? themeManager.current.color.opacity(0.08)
                                : Color.clear
                        )
                        .overlay(alignment: .bottom) {
                            if selectedFilter == filter {
                                Rectangle()
                                    .fill(themeManager.current.color)
                                    .frame(height: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(filter.helpText)
                }
            }
            .background(.quaternary.opacity(0.4))

            Divider()

            // Grid
            ScrollView {
                if filteredMedia.isEmpty {
                    emptyLibraryView
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
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
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxHeight: .infinity)

            // Bottom toolbar
            HStack(spacing: 10) {
                Button { addMediaToLibrary() } label: {
                    Label("Add to Library", systemImage: "plus.circle.fill").font(.caption)
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("\(filteredMedia.count) item\(filteredMedia.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.bar)
        }
        .frame(width: 400)
        .background(Color.luminaBase)
    }

    // MARK: - Configuration Column (right)

    private var configurationColumn: some View {
        VStack(spacing: 0) {
            // Monitor header
            HStack(spacing: 10) {
                if let monitor = currentTargetMonitor {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Configuring").font(.caption).foregroundStyle(.tertiary)
                            Text(monitorLabel(for: monitor)).font(.subheadline.bold())
                        }

                        // Prominent "pinned" status — best practice for surfacing
                        // important persistence state at the top of the context.
                        if let assignment = store.assignment(for: monitor.id),
                           assignment.keepOnStartup {
                            HStack(spacing: 4) {
                                Image(systemName: "pin.fill")
                                    .font(.caption2.weight(.bold))
                                Text("Pinned")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.15))
                            .clipShape(Capsule())
                            .help("This wallpaper will automatically restore when Lumina launches")
                        }
                    }
                } else {
                    Text("No Display Selected").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .togglePhysicalSetupWindow, object: nil)
                } label: {
                    Label("Switch Display", systemImage: "display.2").font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)

            Divider()

            if let monitor = currentTargetMonitor {
                // No outer ScrollView: the panel pins its preview + action bar and scrolls
                // only the settings in between.
                MonitorDetailPanel(monitor: monitor, store: store, showHeader: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "display.2").font(.system(size: 44)).foregroundStyle(.quaternary)
                    Text("Choose a display to configure").font(.title3).foregroundStyle(.secondary)
                    Button("Choose Display…") {
                        NotificationCenter.default.post(name: .togglePhysicalSetupWindow, object: nil)
                    }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        VStack(spacing: 0) {
            // Queue panel — collapsible above the controls row
            if !audioManager.library.isEmpty && showQueue {
                Divider()
                queuePanel
            }

            // Now-playing bar — larger, roomier, adaptive (the progress track absorbs
            // any extra width as the window grows).
            HStack(spacing: 16) {
                nowPlayingArtwork

                // Title + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlayingTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(audioManager.trackURL != nil ? .primary : .secondary)
                    Text("Ambient Audio")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(minWidth: 120, idealWidth: 170, maxWidth: 220, alignment: .leading)

                // Transport — bigger, evenly spaced controls
                HStack(spacing: 18) {
                    transportIcon("backward.end.fill", size: 15, help: "Previous track") {
                        audioManager.previousTrack()
                    }
                    .disabled(audioManager.library.count < 2)

                    transportIcon("gobackward.10", size: 15, help: "Skip back 10 seconds") {
                        audioManager.seek(by: -10)
                    }
                    .disabled(audioManager.trackURL == nil)

                    Button { audioManager.toggle() } label: {
                        Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(audioManager.trackURL != nil ? themeManager.current.color : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(audioManager.isPlaying ? "Pause" : "Play")
                    .disabled(audioManager.trackURL == nil)

                    transportIcon("goforward.10", size: 15, help: "Skip forward 10 seconds") {
                        audioManager.seek(by: 10)
                    }
                    .disabled(audioManager.trackURL == nil)

                    transportIcon("forward.end.fill", size: 15, help: "Next track") {
                        audioManager.nextTrack()
                    }
                    .disabled(audioManager.library.count < 2)
                }

                // Progress — expands to fill available width
                if audioManager.duration > 0 {
                    HStack(spacing: 8) {
                        Text(formatAudioTime(audioManager.currentTime))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                        Slider(
                            value: Binding(
                                get: { audioManager.currentTime },
                                set: { audioManager.seekToTime($0) }
                            ),
                            in: 0...max(audioManager.duration, 1)
                        )
                        .help("Seek")
                        Text(formatAudioTime(audioManager.duration))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 12)
                }

                // Volume
                HStack(spacing: 8) {
                    Image(systemName: audioManager.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .leading)
                    Slider(value: Binding(get: { audioManager.volume }, set: { audioManager.setVolume($0) }), in: 0...1)
                        .frame(width: 84).help("Ambient audio volume")
                }

                Divider().frame(height: 26)

                // Library actions
                Button { audioManager.chooseTrack() } label: {
                    Label("Add Track", systemImage: "plus.circle.fill").font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Add audio tracks to your music library")

                if audioManager.trackURL != nil {
                    transportIcon("xmark.circle.fill", size: 16, help: "Stop and clear current track") {
                        audioManager.clearTrack()
                    }
                }

                transportIcon(
                    "list.bullet.rectangle",
                    size: 16,
                    active: showQueue,
                    help: showQueue ? "Hide queue" : "Show music queue"
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) { showQueue.toggle() }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    /// Small rounded album-art tile used in the now-playing bar.
    private var nowPlayingArtwork: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [themeManager.current.color.opacity(0.9),
                             themeManager.current.color.opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: 46, height: 46)
            .overlay(
                Image(systemName: audioManager.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 18, weight: .semibold))
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
        size: CGFloat,
        active: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? themeManager.current.color : .secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Music Queue Panel

    @ViewBuilder private var queuePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { audioManager.clearLibrary() }
                    .font(.caption2)
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
                                .font(.system(size: 10))
                                .foregroundStyle(themeManager.current.color)
                                .frame(width: 14)
                        } else {
                            Text("\(idx + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 14)
                        }

                        Text(track.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(isActive ? themeManager.current.color : .primary)

                        Spacer()

                        Text(formatQueueDuration(track))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)

                        Button {
                            audioManager.removeFromLibrary(track: track)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
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
            .frame(height: min(CGFloat(audioManager.library.count) * 30 + 8, 130))
        }
        .background(Color.luminaBase)
    }

    private func formatQueueDuration(_ track: AmbientAudioManager.AudioTrack) -> String {
        guard track.duration > 0 else { return "" }
        let s = Int(track.duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Empty Library View

    @ViewBuilder private var emptyLibraryView: some View {
        VStack(spacing: 14) {
            Image(systemName: selectedFilter == .favorites ? "star" : "photo.badge.plus")
                .font(.system(size: 40)).foregroundStyle(.quaternary)
            Text(selectedFilter == .favorites ? "No favorites yet" :
                 searchQuery.isEmpty ? "Library is empty" : "No results for \"\(searchQuery)\"")
                .font(.callout).foregroundStyle(.secondary)
            if searchQuery.isEmpty && selectedFilter == .all {
                Button("Add to Library") { addMediaToLibrary() }.buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(40)
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

    private func formatAudioTime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func addMediaToLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Add wallpaper to library"
        panel.message = "This adds the file to your collection on the left so you can easily re-use it on any display. It will not change what is currently playing."
        panel.allowedContentTypes = [.movie, .image, .gif]
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addMediaToLibrary(url: url)
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail
            thumbnailContent
                .frame(width: 155, height: 87)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Type badge (bottom-leading)
            typeBadge
                .padding(5)

            // Hover overlay
            if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.45))
                    .frame(width: 155, height: 87)
                    .overlay(
                        HStack(spacing: 12) {
                            Button { onApply() } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2).foregroundStyle(.white)
                            }.buttonStyle(.plain).help("Set as Wallpaper")

                            Button { onFavorite() } label: {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.title3)
                                    .foregroundStyle(isFavorite ? Color.yellow : .white)
                            }.buttonStyle(.plain).help("Favorite")
                        }
                    )
                    .transition(.opacity)
            }

            // Selection indicator
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .frame(width: 155, height: 87)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.accentColor)
                            .background(Circle().fill(Color.black).padding(2))
                            .padding(5)
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    .frame(width: 155, height: 87)
            }

            // Favorite star (always visible if favorited and not hovered)
            if isFavorite && !isHovered {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.yellow)
                    .padding(5)
                    .frame(width: 155, height: 87, alignment: .topTrailing)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture { onApply() }
        .overlay(alignment: .bottom) {
            Text(recent.displayName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: 155, alignment: .leading)
                .offset(y: 18)
        }
        .padding(.bottom, 18)
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
        .task { await loadThumbnail() }
    }

    @ViewBuilder private var thumbnailContent: some View {
        if let thumb = thumbnail {
            Image(nsImage: thumb).resizable().aspectRatio(16/9, contentMode: .fill)
        } else if isLoading {
            Color.gray.opacity(0.15).overlay(ProgressView().scaleEffect(0.6))
        } else {
            Color.gray.opacity(0.12).overlay(
                VStack(spacing: 4) {
                    Image(systemName: recent.mediaType == .video ? "video.slash" : "photo")
                        .font(.title3).foregroundStyle(.secondary)
                    Text("No preview").font(.caption2).foregroundStyle(.tertiary)
                }
            )
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
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(color.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
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
