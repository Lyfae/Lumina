import AVFoundation
import AppKit

@MainActor
final class AmbientAudioManager: NSObject, ObservableObject {
    static let shared = AmbientAudioManager()

    @Published var isPlaying: Bool = false
    @Published var volume: Double = 0.5
    @Published var trackURL: URL? = nil
    @Published var trackName: String = "No track selected"
    /// ID3 / QuickTime title when available; falls back to the filename stem.
    @Published var trackTitle: String = "No track selected"
    @Published var trackArtist: String = ""
    @Published var trackAlbum: String = ""
    @Published var trackArtwork: NSImage? = nil
    @Published var loops: Bool = true
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    /// When on, a floating now-playing widget appears while the Studio window is minimized.
    @Published var showWidgetWhenMinimized: Bool = true {
        didSet { UserDefaults.standard.set(showWidgetWhenMinimized, forKey: widgetKey) }
    }
    /// Persistent library of audio tracks the user has added
    @Published private(set) var library: [AudioTrack] = []
    /// Album art keyed by track id (path) — kept out of `AudioTrack` for Equatable simplicity.
    @Published private(set) var artworkByID: [String: NSImage] = [:]
    /// Starred tracks in the ambient music library.
    @Published private(set) var favoriteIDs: Set<String> = []

    private var playbackTimer: Timer?
    private var metadataTask: Task<Void, Never>?
    private var libraryMetadataTask: Task<Void, Never>?

    struct AudioTrack: Identifiable, Equatable {
        let id: String   // path as stable identity
        let url: URL
        var duration: TimeInterval
        var title: String
        var artist: String
        var album: String

        var name: String { url.lastPathComponent }

        init(
            id: String,
            url: URL,
            duration: TimeInterval,
            title: String? = nil,
            artist: String = "",
            album: String = ""
        ) {
            self.id = id
            self.url = url
            self.duration = duration
            self.title = title ?? Self.defaultTitle(for: url)
            self.artist = artist
            self.album = album
        }

        static func defaultTitle(for url: URL) -> String {
            let stem = (url.lastPathComponent as NSString).deletingPathExtension
            return stem.isEmpty ? url.lastPathComponent : stem
        }
    }

    private var player: AVAudioPlayer?
    private let trackURLKey      = "Lumina.AmbientAudio.TrackPath"
    private let volumeKey        = "Lumina.AmbientAudio.Volume"
    private let loopsKey         = "Lumina.AmbientAudio.Loops"
    private let libraryKey       = "Lumina.AmbientAudio.Library"
    private let durationCacheKey = "Lumina.AmbientAudio.Durations"
    private let widgetKey        = "Lumina.AmbientAudio.ShowWidgetWhenMinimized"
    private let favoritesKey     = "Lumina.AmbientAudio.Favorites"

    private override init() {
        super.init()
        let savedVolume = UserDefaults.standard.double(forKey: volumeKey).clamped(to: 0...1)
        volume = savedVolume == 0 ? 0.5 : savedVolume
        loops = UserDefaults.standard.object(forKey: loopsKey) as? Bool ?? true
        showWidgetWhenMinimized = UserDefaults.standard.object(forKey: widgetKey) as? Bool ?? true
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        loadLibrary()
        if let path = UserDefaults.standard.string(forKey: trackURLKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = loadTrack(url: url)
            }
        }
    }

    // MARK: - Library management

    func addToLibrary(url: URL) {
        guard !library.contains(where: { $0.id == url.path }) else { return }
        let dur = (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
        library.append(AudioTrack(id: url.path, url: url, duration: dur))
        saveLibrary()
        persistDurationCache()
        scheduleLibraryMetadataLoad(for: url.path)
    }

    func removeFromLibrary(track: AudioTrack) {
        library.removeAll { $0.id == track.id }
        artworkByID.removeValue(forKey: track.id)
        favoriteIDs.remove(track.id)
        persistFavorites()
        saveLibrary()
        if trackURL == track.url { clearTrack() }
    }

    func isFavorite(_ track: AudioTrack) -> Bool { favoriteIDs.contains(track.id) }

    func toggleFavorite(_ track: AudioTrack) {
        if favoriteIDs.contains(track.id) {
            favoriteIDs.remove(track.id)
        } else {
            favoriteIDs.insert(track.id)
        }
        persistFavorites()
    }

    func artwork(for track: AudioTrack) -> NSImage? { artworkByID[track.id] }

    private func persistFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: favoritesKey)
    }

    private func loadLibrary() {
        let paths = UserDefaults.standard.stringArray(forKey: libraryKey) ?? []
        // Read durations from the cache — instant, no AVAudioPlayer construction on launch.
        let cached = UserDefaults.standard.dictionary(forKey: durationCacheKey) as? [String: Double] ?? [:]
        library = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AudioTrack(id: path, url: url, duration: cached[path] ?? 0)
        }
        // Fill in any durations we don't have cached, off the main thread.
        refreshMissingDurations()
        refreshLibraryMetadata()
    }

    /// Computes durations for any tracks missing one, without blocking the main thread.
    private func refreshMissingDurations() {
        let missing = library.filter { $0.duration <= 0 }.map { $0.url }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            var results: [String: Double] = [:]
            for url in missing {
                let asset = AVURLAsset(url: url)
                if let duration = try? await asset.load(.duration) {
                    let seconds = CMTimeGetSeconds(duration)
                    if seconds.isFinite && seconds > 0 { results[url.path] = seconds }
                }
            }
            await self.applyLoadedDurations(results)
        }
    }

    private func applyLoadedDurations(_ durations: [String: Double]) {
        guard !durations.isEmpty else { return }
        for (i, track) in library.enumerated() where track.duration <= 0 {
            if let seconds = durations[track.id] {
                library[i].duration = seconds
            }
        }
        persistDurationCache()
    }

    private func saveLibrary() {
        UserDefaults.standard.set(library.map { $0.id }, forKey: libraryKey)
    }

    /// Persists a path→duration map so subsequent launches read durations instantly.
    private func persistDurationCache() {
        let map = Dictionary(library.map { ($0.id, $0.duration) }, uniquingKeysWith: { a, _ in a })
        UserDefaults.standard.set(map, forKey: durationCacheKey)
    }

    // MARK: - Playback Timer (drives currentTime / duration updates)

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                self.duration = p.duration
                self.isPlaying = p.isPlaying
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Transport controls

    func seek(by seconds: Double) {
        guard let player else { return }
        let t = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = t
        currentTime = t
    }

    func seekToTime(_ time: Double) {
        guard let player else { return }
        let t = max(0, min(player.duration, time))
        player.currentTime = t
        // Publish immediately so the scrubber doesn't snap back to the last timer tick.
        currentTime = t
    }

    func nextTrack() {
        guard !library.isEmpty else { return }
        let wasPlaying = isPlaying
        if let current = trackURL, let idx = library.firstIndex(where: { $0.url == current }) {
            selectTrack(library[(idx + 1) % library.count])
        } else if let first = library.first {
            selectTrack(first)
        }
        if wasPlaying { play() }
    }

    func previousTrack() {
        guard !library.isEmpty else { return }
        let wasPlaying = isPlaying
        if let current = trackURL, let idx = library.firstIndex(where: { $0.url == current }) {
            let prev = idx == 0 ? library.count - 1 : idx - 1
            selectTrack(library[prev])
        } else if let last = library.last {
            selectTrack(last)
        }
        if wasPlaying { play() }
    }

    // MARK: - Track selection

    func chooseTrack() {
        let urls = MediaAccessPolicy.runWallpaperPicker(
            title: "Choose ambient audio track",
            message: "Select audio files for the Studio music player.",
            allowedTypes: [.audio, .mp3],
            allowsMultipleSelection: true
        )
        guard !urls.isEmpty else { return }
        for url in urls {
            addToLibrary(url: url)
        }
        if let first = urls.first {
            _ = loadTrack(url: first)
            UserDefaults.standard.set(first.path, forKey: trackURLKey)
        }
    }

    func selectTrack(_ track: AudioTrack) {
        _ = loadTrack(url: track.url)
        UserDefaults.standard.set(track.url.path, forKey: trackURLKey)
    }

    @discardableResult
    func loadTrack(url: URL) -> Bool {
        do {
            stopPlaybackTimer()
            let p = try AVAudioPlayer(contentsOf: url)
            // We always play the file exactly once and drive looping / auto-advance ourselves
            // in `audioPlayerDidFinishPlaying`. Using AVAudioPlayer's own `numberOfLoops = -1`
            // breaks when the user turns looping off mid-play: the player's internal play-count
            // is already exceeded, so it instantly reports "finished" (the timer jumps to the
            // end) while the audio buffer keeps draining.
            p.numberOfLoops = 0
            p.volume = Float(volume)
            p.delegate = self   // drives loop-restart / auto-advance when the track ends
            p.prepareToPlay()
            player = p
            trackURL = url
            trackName = url.lastPathComponent
            let stem = (url.lastPathComponent as NSString).deletingPathExtension
            trackTitle = stem.isEmpty ? url.lastPathComponent : stem
            trackArtist = ""
            trackAlbum = ""
            trackArtwork = nil
            currentTime = 0
            duration = p.duration
            addToLibrary(url: url)
            scheduleMetadataLoad(for: url)
            return true
        } catch {
            LuminaLog.audio.error("Failed to load: \(error)")
            return false
        }
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        library.move(fromOffsets: source, toOffset: destination)
        saveLibrary()
    }

    /// Removes every track from the queue and stops playback.
    func clearLibrary() {
        clearTrack()
        library.removeAll()
        artworkByID.removeAll()
        saveLibrary()
    }

    // MARK: - Playback controls

    func play() {
        player?.play()
        isPlaying = player?.isPlaying ?? false
        startPlaybackTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopPlaybackTimer()
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func setVolume(_ v: Double) {
        volume = v.clamped(to: 0...1)
        player?.volume = Float(volume)
        UserDefaults.standard.set(volume, forKey: volumeKey)
    }

    func setLoops(_ enabled: Bool) {
        loops = enabled
        // Looping is handled in the finish callback (player always plays once), so toggling
        // this never disturbs the currently playing track — no timer jump on unloop.
        player?.numberOfLoops = 0
        UserDefaults.standard.set(enabled, forKey: loopsKey)
    }

    func clearTrack() {
        pause()
        stopPlaybackTimer()
        metadataTask?.cancel()
        metadataTask = nil
        player = nil
        trackURL = nil
        trackName = "No track selected"
        trackTitle = "No track selected"
        trackArtist = ""
        trackAlbum = ""
        trackArtwork = nil
        currentTime = 0
        duration = 0
        UserDefaults.standard.removeObject(forKey: trackURLKey)
    }

    // MARK: - Metadata (artwork / artist / album)

    private func scheduleMetadataLoad(for url: URL) {
        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            let meta = await Self.loadTrackMetadata(from: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.trackURL == url else { return }
                if let title = meta.title, !title.isEmpty { self.trackTitle = title }
                self.trackArtist = meta.artist ?? ""
                self.trackAlbum = meta.album ?? ""
                self.trackArtwork = meta.artwork
                self.applyMetadata(meta, toTrackID: url.path)
            }
        }
    }

    private func refreshLibraryMetadata() {
        libraryMetadataTask?.cancel()
        let ids = library.map(\.id)
        libraryMetadataTask = Task { [weak self] in
            for id in ids {
                guard !Task.isCancelled else { return }
                let url = URL(fileURLWithPath: id)
                let meta = await Self.loadTrackMetadata(from: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyMetadata(meta, toTrackID: id)
                }
            }
        }
    }

    private func scheduleLibraryMetadataLoad(for id: String) {
        Task { [weak self] in
            let meta = await Self.loadTrackMetadata(from: URL(fileURLWithPath: id))
            await MainActor.run {
                self?.applyMetadata(meta, toTrackID: id)
            }
        }
    }

    private func applyMetadata(_ meta: TrackMetadata, toTrackID id: String) {
        guard let index = library.firstIndex(where: { $0.id == id }) else { return }
        if let title = meta.title, !title.isEmpty {
            library[index].title = title
        }
        if let artist = meta.artist {
            library[index].artist = artist
        }
        if let album = meta.album {
            library[index].album = album
        }
        if let artwork = meta.artwork {
            artworkByID[id] = artwork
        }
    }

    private struct TrackMetadata {
        var title: String?
        var artist: String?
        var album: String?
        var artwork: NSImage?
    }

    private static func loadTrackMetadata(from url: URL) async -> TrackMetadata {
        var result = TrackMetadata()
        let asset = AVURLAsset(url: url)
        do {
            let items = try await asset.load(.commonMetadata)
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try await item.load(.stringValue), !value.isEmpty {
                        result.title = value
                    }
                case .commonKeyArtist:
                    if let value = try await item.load(.stringValue), !value.isEmpty {
                        result.artist = value
                    }
                case .commonKeyAlbumName:
                    if let value = try await item.load(.stringValue), !value.isEmpty {
                        result.album = value
                    }
                case .commonKeyArtwork:
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        result.artwork = image
                    }
                default:
                    break
                }
            }
        } catch {
            LuminaLog.audio.debug("Metadata read failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
        return result
    }

    // MARK: - End-of-track handling

    /// Called when the current track finishes. Repeats it when looping is on, otherwise
    /// advances to the next track in the library (and stops cleanly at the end of the list).
    private func handleTrackFinished() {
        if loops {
            // Repeat the current track from the top.
            player?.currentTime = 0
            player?.play()
            isPlaying = player?.isPlaying ?? false
            startPlaybackTimer()
            return
        }

        // Auto-advance to the next track in the library.
        guard let current = trackURL,
              let idx = library.firstIndex(where: { $0.url == current }) else {
            isPlaying = false
            stopPlaybackTimer()
            return
        }

        let nextIdx = idx + 1
        if nextIdx < library.count {
            selectTrack(library[nextIdx])
            play()
        } else {
            // Reached the end of the playlist without looping — stop cleanly on the last frame.
            isPlaying = false
            currentTime = duration
            stopPlaybackTimer()
        }
    }
}

// MARK: - Loop restart / auto-advance when the current track finishes

extension AmbientAudioManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { return }
        Task { @MainActor [weak self] in
            self?.handleTrackFinished()
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
