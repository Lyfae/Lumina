// Lumina/Engine/Signals — thin adapters from OS notifications to SystemSnapshot fields.
import AppKit
import IOKit.ps
import LuminaCore

/// Write handle to exactly one field of SystemSnapshot.
public struct SignalSink<T>: Sendable {
    let apply: @MainActor (_ update: (inout T) -> Void) -> Void
    @MainActor public func update(_ change: (inout T) -> Void) { apply(change) }
}

@MainActor
final class PowerSignals {
    private let sink: SignalSink<PowerState>
    private var observers: [NSObjectProtocol] = []

    init(sink: SignalSink<PowerState>) {
        self.sink = sink
        seed()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.seed() }
        })
        observers.append(nc.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.seed() }
        })
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let signals = Unmanaged<PowerSignals>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { signals.seed() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceLoop = source
        }
    }

    nonisolated(unsafe) private var powerSourceLoop: CFRunLoopSource?

    deinit {
        if let powerSourceLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceLoop, .defaultMode)
        }
    }

    private func seed() {
        let info = ProcessInfo.processInfo
        sink.update { state in
            state.lowPowerMode = info.isLowPowerModeEnabled
            state.thermal = ThermalLevel(info.thermalState)
            state.source = Self.readPowerSource()
        }
    }

    nonisolated static func source(isOnAC: Bool?, currentCapacity: Int?, maxCapacity: Int?) -> PowerState.Source {
        if isOnAC == true { return .ac }
        if let cur = currentCapacity, let max = maxCapacity, max > 0 {
            return .battery(percent: Double(cur) / Double(max) * 100.0)
        }
        if isOnAC == false { return .battery(percent: 100) }
        return .unknown
    }

    nonisolated private static func readPowerSource() -> PowerState.Source {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return .ac // desktops / missing IOKit → treat as AC
        }
        let isAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let cur = desc[kIOPSCurrentCapacityKey] as? Int
        let max = desc[kIOPSMaxCapacityKey] as? Int
        return source(isOnAC: isAC, currentCapacity: cur, maxCapacity: max)
    }
}

@MainActor
final class SessionSignals {
    private let sink: SignalSink<ActivityState>
    private var observers: [NSObjectProtocol] = []

    init(sink: SignalSink<ActivityState>) {
        self.sink = sink
        let wsnc = NSWorkspace.shared.notificationCenter
        observers.append(wsnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sink.update { $0.screensAsleep = true } }
        })
        observers.append(wsnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sink.update { $0.screensAsleep = false } }
        })
        observers.append(wsnc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sink.update { $0.sessionInactive = true } }
        })
        observers.append(wsnc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sink.update { $0.sessionInactive = false } }
        })
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sink.update { $0.screenLocked = true }
                AmbientAudioManager.shared.handleScreenLock(true)
            }
        })
        observers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sink.update { $0.screenLocked = false }
                AmbientAudioManager.shared.handleScreenLock(false)
            }
        })
    }

    deinit {}
}

@MainActor
final class OcclusionSignals: NSObject {
    private var sink: SignalSink<OcclusionState>?
    private var tracked: [DisplayKey: NSWindow] = [:]
    private var covered: Set<DisplayKey> = []
    private var trusted = false
    private var debounceWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(trustAfter: Duration) {
        super.init()
        Task { @MainActor in
            try? await Task.sleep(for: trustAfter)
            self.trusted = true
            self.publish()
        }
        let wsnc = NSWorkspace.shared.notificationCenter
        observers.append(wsnc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRescan() }
        })
        observers.append(wsnc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRescan() }
        })
    }

    func attach(sink: SignalSink<OcclusionState>) {
        self.sink = sink
        publish()
    }

    func track(_ window: NSWindow, display: DisplayKey) {
        tracked[display] = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowOcclusionChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
    }

    func untrack(display: DisplayKey) {
        if let window = tracked.removeValue(forKey: display) {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
        }
        covered.remove(display)
        publish()
    }

    @objc private func windowOcclusionChanged(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              let key = tracked.first(where: { $0.value === window })?.key else { return }
        let visible = window.occlusionState.contains(.visible)
        if visible {
            covered.remove(key)
            publish()
        } else if trusted {
            covered.insert(key)
            publish()
        }
        // Untrusted: ignore cover events (fail-open).
    }

    private func scheduleRescan() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescan() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func rescan() {
        for (key, window) in tracked {
            if window.occlusionState.contains(.visible) {
                covered.remove(key)
            } else if trusted {
                covered.insert(key)
            }
        }
        publish()
    }

    private func publish() {
        let snapshotCovered = covered
        let snapshotTrusted = trusted
        sink?.update {
            $0.covered = snapshotCovered
            $0.trusted = snapshotTrusted
        }
    }
}

@MainActor
final class DisplaySignals {
    private let onChange: @MainActor ([DisplaySnapshot]) -> Void
    private var workItem: DispatchWorkItem?
    private var last: [DisplaySnapshot] = []
    private var observer: NSObjectProtocol?

    init(onChange: @escaping @MainActor ([DisplaySnapshot]) -> Void) {
        self.onChange = onChange
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        publish()
    }

    deinit {}

    private func schedule() {
        workItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.publish() }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func publish() {
        let next = NSScreen.screens.enumerated().map { Self.snapshot($0.element, index: $0.offset) }
        guard next != last else {
            // Geometry-only refresh still notifies when frames change with same IDs.
            if zip(next, last).contains(where: { $0.frame != $1.frame }) {
                last = next
                onChange(next)
            }
            return
        }
        last = next
        onChange(next)
    }

    static func snapshot(_ screen: NSScreen, index: Int) -> DisplaySnapshot {
        let id = MonitorInfo.identifier(for: screen, index: index)
        let displayID = MonitorInfo.displayID(for: screen)
        let scale = screen.backingScaleFactor
        let pixels = PixelSize(
            width: max(1, Int(screen.frame.width * scale)),
            height: max(1, Int(screen.frame.height * scale))
        )!
        return DisplaySnapshot(
            key: DisplayKey(id),
            runtimeID: displayID,
            name: screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName,
            frame: screen.frame,
            backingPixels: pixels,
            maxRefreshHz: max(30, screen.maximumFramesPerSecond),
            isBuiltIn: index == 0
        )
    }

    static func legacyKey(_ screen: NSScreen, index: Int) -> DisplayKey {
        DisplayKey(MonitorInfo.legacyIdentifier(for: screen, index: index))
    }
}
