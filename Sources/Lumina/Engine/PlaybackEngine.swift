// Lumina/Engine/PlaybackEngine — owns inputs, runs the planner, hands plans to the reconciler.
import AppKit
import Observation
import LuminaCore

@MainActor
@Observable
final class PlaybackEngine {
    private(set) var plan: PlaybackPlan = .empty
    private(set) var summary: PlanSummary?
    private(set) var displays: [DisplaySnapshot] = []

    @ObservationIgnored private let prefs: PreferencesStore
    @ObservationIgnored private let reconciler: Reconciler
    @ObservationIgnored private let catalog: MediaCatalog
    @ObservationIgnored private let occlusion: OcclusionSignals
    @ObservationIgnored private var system = SystemSnapshot()
    @ObservationIgnored private var session = SessionState()
    @ObservationIgnored private var signalKeepAlive: [AnyObject] = []
    @ObservationIgnored private var replanScheduled = false
    @ObservationIgnored private var started = false

    init(preferences: PreferencesStore) {
        self.prefs = preferences
        let catalog = MediaCatalog()
        self.catalog = catalog
        let occlusion = OcclusionSignals(trustAfter: .seconds(1.5))
        self.occlusion = occlusion
        self.reconciler = Reconciler(
            catalog: catalog,
            occlusion: occlusion,
            screens: {
                var map: [UInt32: NSScreen] = [:]
                for screen in NSScreen.screens {
                    map[MonitorInfo.displayID(for: screen)] = screen
                }
                return map
            }
        )
        catalog.onChange = { [weak self] in self?.setNeedsPlan() }
        occlusion.attach(sink: sink(\.occlusion))
    }

    var liveDecoderCount: Int { reconciler.liveDecoderCount }

    func start() {
        guard !started else { return }
        started = true

        signalKeepAlive = [
            PowerSignals(sink: sink(\.power)),
            SessionSignals(sink: sink(\.activity)),
        ]
        let displaySignals = DisplaySignals { [weak self] displays in
            guard let self else { return }
            self.adoptLegacyKeys(displays)
            self.displays = displays
            self.setNeedsPlan()
        }
        signalKeepAlive.append(displaySignals)

        // Seed displays immediately.
        let seeded = NSScreen.screens.enumerated().map { DisplaySignals.snapshot($0.element, index: $0.offset) }
        adoptLegacyKeys(seeded)
        displays = seeded
        replanNow()
        session.isLaunching = false
        setNeedsPlan()
    }

    func togglePause() {
        session.manualPause.toggle()
        setNeedsPlan()
    }

    var isManuallyPaused: Bool { session.manualPause }

    func restartAllInSync() {
        reconciler.restartAllInSync()
    }

    func setStudioVisible(_ visible: Bool) {
        system.studioVisible = visible
        setNeedsPlan()
    }

    /// Settings calls this after power/quality toggles so nested Binding writes still replan
    /// even if Observation did not see a top-level `power` / `playback` assignment.
    func forceReplan() {
        setNeedsPlan()
    }

    /// Studio preview surface hook. `nil` request removes the preview from the plan.
    func setPreview(id: PreviewID, request: PreviewRequest?, host: NSView?) {
        reconciler.registerPreviewHost(id, host)
        if let request {
            session.previews[id] = request
        } else {
            session.previews.removeValue(forKey: id)
        }
        setNeedsPlan()
    }

    /// Health-banner "use a smaller video" → quality `.efficient` (triggers proxy request).
    func requestEfficientQuality(for display: DisplayKey) {
        catalog.requestEfficientQuality(for: display, prefs: prefs)
        setNeedsPlan()
    }

    func healthSnapshots() -> [PlaybackHealthSnapshot] {
        reconciler.healthSnapshots()
    }

    func teardown() {
        reconciler.teardownAll()
    }

    private func sink<T: Equatable>(_ field: WritableKeyPath<SystemSnapshot, T>) -> SignalSink<T> {
        SignalSink { [weak self] update in
            guard let self else { return }
            var value = self.system[keyPath: field]
            update(&value)
            guard value != self.system[keyPath: field] else { return }
            self.system[keyPath: field] = value
            self.setNeedsPlan()
        }
    }

    private func setNeedsPlan() {
        guard !replanScheduled else { return }
        replanScheduled = true
        Task { @MainActor [weak self] in
            self?.replanNow()
        }
    }

    private func replanNow() {
        replanScheduled = false
        let inputs = withObservationTracking {
            PlanInputs(
                preferences: prefs.planning,
                displays: displays,
                system: system,
                session: session,
                media: catalog.inventory
            )
        } onChange: { [weak self] in
            Task { @MainActor in self?.setNeedsPlan() }
        }
        let next = Planner.plan(inputs)
        #if DEBUG
        let violations = next.validate()
        if !violations.isEmpty {
            LuminaLog.app.error("Plan validation failed: \(violations)")
        }
        #endif
        reconciler.experimentalRenderCap = prefs.power.experimentalRenderCap
        reconciler.apply(next)
        catalog.handle(next.requests)
        plan = next
        summary = PlanSummary(plan: next, displays: displays)
        LuminaLog.wallpaper.debug("Plan applied — decoders=\(next.sources.count) surfaces=\(next.surfaces.count)")
    }

    private func adoptLegacyKeys(_ displays: [DisplaySnapshot]) {
        var wallpapers = prefs.wallpapers
        var changed = false
        for (index, display) in displays.enumerated() {
            let screen = NSScreen.screens.first {
                MonitorInfo.identifier(for: $0, index: index) == display.key.rawValue
            }
            guard let screen else { continue }
            let legacy = DisplaySignals.legacyKey(screen, index: index)
            if wallpapers.byDisplay[display.key] == nil, wallpapers.byDisplay[legacy] != nil {
                wallpapers.adoptLegacyKey(legacy, as: display.key)
                changed = true
            }
        }
        if changed {
            prefs.wallpapers = wallpapers
        }
    }
}
