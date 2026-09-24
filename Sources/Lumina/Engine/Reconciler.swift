// Lumina/Engine/Reconciler — executes PlanOps against live sources and surfaces.
import AppKit
import AVFoundation
import LuminaCore

@MainActor
final class Reconciler {
    static let lingerInterval: TimeInterval = 2.0

    private(set) var current: PlaybackPlan = .empty
    private var sources: [SourceKey: any MediaSource] = [:]
    private var surfaces: [SurfaceID: Surface] = [:]
    private var lingering: [SourceKey: (source: any MediaSource, expiresAt: Date)] = [:]
    private var lingerWork: DispatchWorkItem?
    private var primaryConsumer: [SourceKey: SurfaceID] = [:]
    private var previewHosts: [PreviewID: NSView] = [:]

    /// When true, VideoSource enables FramePump for `.renderCap` budgets.
    var experimentalRenderCap = false

    private let catalog: MediaCatalog
    private let occlusion: OcclusionSignals
    private let screens: () -> [UInt32: NSScreen]

    init(
        catalog: MediaCatalog,
        occlusion: OcclusionSignals,
        screens: @escaping () -> [UInt32: NSScreen]
    ) {
        self.catalog = catalog
        self.occlusion = occlusion
        self.screens = screens
    }

    func apply(_ next: PlaybackPlan) {
        for op in PlanDiff.ops(from: current, to: next) {
            switch op {
            case let .createSource(spec):
                if let lingeringSource = revive(spec.key) {
                    sources[spec.key] = lingeringSource
                    if let video = lingeringSource as? VideoSource {
                        video.setExperimentalRenderCap(experimentalRenderCap)
                    }
                    lingeringSource.retune(spec)
                } else {
                    let source = makeSource(spec)
                    source.onFailure = { [weak self] msg in
                        if let id = spec.key.identity {
                            self?.catalog.recordFailure(id, msg)
                        }
                    }
                    sources[spec.key] = source
                }
            case let .retuneSource(key, spec):
                if let video = sources[key] as? VideoSource {
                    video.setExperimentalRenderCap(experimentalRenderCap)
                }
                sources[key]?.retune(spec)
            case let .retimeSource(old, new, plan):
                if let source = sources.removeValue(forKey: old) {
                    source.retime(to: new, plan: plan)
                    sources[new] = source
                    if let consumer = primaryConsumer.removeValue(forKey: old) {
                        primaryConsumer[new] = consumer
                    }
                } else {
                    sources[new] = makeSource(plan)
                }
            case let .setSourceRunning(key, on):
                sources[key]?.setRunning(on)
            case let .destroySource(key):
                if let source = sources.removeValue(forKey: key) {
                    primaryConsumer.removeValue(forKey: key)
                    lingering[key] = (source, Date().addingTimeInterval(Self.lingerInterval))
                    scheduleLingerSweep()
                }
            case let .createSurface(id, geo):
                createSurface(id, geo)
            case let .setGeometry(id, geo):
                surfaces[id]?.setGeometry(geo)
            case let .bind(id, key, fade):
                guard let surface = surfaces[id], let source = sources[key] else { break }
                let isPrimary = primaryConsumer[key] == nil || primaryConsumer[key] == id
                if isPrimary {
                    primaryConsumer[key] = id
                }
                surface.attach(source, crossfade: fade, asPrimary: isPrimary)
            case let .unbind(id):
                if let key = primaryConsumer.first(where: { $0.value == id })?.key {
                    primaryConsumer.removeValue(forKey: key)
                }
                surfaces[id]?.detach()
            case let .setLook(id, look):
                surfaces[id]?.setLook(look)
            case let .setSurfaceRun(id, run):
                surfaces[id]?.setRun(run)
            case let .showFailure(id, msg):
                surfaces[id]?.showFailure(msg)
            case let .destroySurface(id):
                if case .desktop(let key) = id {
                    occlusion.untrack(display: key)
                }
                surfaces.removeValue(forKey: id)?.teardown()
            }
        }
        current = next
    }

    func registerPreviewHost(_ id: PreviewID, _ host: NSView?) {
        if let host {
            previewHosts[id] = host
            // Create surface if plan already expects it.
            if surfaces[.preview(id)] == nil {
                surfaces[.preview(id)] = PreviewSurface(hostView: host)
            }
        } else {
            previewHosts.removeValue(forKey: id)
            surfaces.removeValue(forKey: .preview(id))?.teardown()
        }
    }

    func restartAllInSync() {
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 10, timescale: 100))
        let layerBegin = CACurrentMediaTime() + 0.1
        for source in sources.values {
            source.restart(atHostTime: host, layerBeginTime: layerBegin)
        }
    }

    func healthSnapshots() -> [PlaybackHealthSnapshot] {
        sources.values.map { $0.playbackHealthSnapshot() }
    }

    var liveDecoderCount: Int { sources.count }

    func teardownAll() {
        for id in Array(surfaces.keys) {
            surfaces[id]?.teardown()
        }
        surfaces.removeAll()
        for key in Array(sources.keys) {
            sources[key]?.teardown()
        }
        sources.removeAll()
        for (_, entry) in lingering {
            entry.source.teardown()
        }
        lingering.removeAll()
        previewHosts.removeAll()
    }

    private func createSurface(_ id: SurfaceID, _ geo: SurfaceGeometry) {
        switch id {
        case .desktop(let key):
            let screenMap = screens()
            let screen: NSScreen? = {
                if let frame = geo.frame {
                    return NSScreen.screens.first { $0.frame.equalTo(frame) }
                        ?? screenMap.values.first { $0.frame.equalTo(frame) }
                }
                return NSScreen.main
            }()
            guard let screen else { return }
            let runtime = MonitorInfo.displayID(for: screen)
            let surface = DesktopSurface(screen: screen, displayKey: key, runtimeID: runtime)
            surfaces[id] = surface
            occlusion.track(surface.window, display: key)
        case .preview(let previewID):
            if let host = previewHosts[previewID] {
                surfaces[id] = PreviewSurface(hostView: host)
            }
            // Host not registered yet — PreviewSurfaceView will call registerPreviewHost.
        }
    }

    private func makeSource(_ spec: SourcePlan) -> any MediaSource {
        switch spec.key {
        case .video(_, .frozen):
            // Frozen video is a still extracted via AVAssetImageGenerator — no paused player.
            return StillImageSource(spec: spec)
        case .video:
            return VideoSource(spec: spec, experimentalRenderCap: experimentalRenderCap)
        case .still:
            return StillImageSource(spec: spec)
        case .animated:
            return AnimatedImageSource(spec: spec)
        case .slideshow:
            return SlideshowSource(spec: spec)
        }
    }

    private func revive(_ key: SourceKey) -> (any MediaSource)? {
        lingering.removeValue(forKey: key)?.source
    }

    private func scheduleLingerSweep() {
        lingerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sweepLingering() }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerInterval, execute: work)
    }

    private func sweepLingering() {
        let now = Date()
        for (key, entry) in lingering where entry.expiresAt <= now {
            entry.source.teardown()
            lingering.removeValue(forKey: key)
        }
        if !lingering.isEmpty {
            scheduleLingerSweep()
        }
    }
}
