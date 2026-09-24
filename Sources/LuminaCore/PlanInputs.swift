// LuminaCore/Plan/PlanInputs — everything that affects playback, as one immutable snapshot.
import Foundation
import CoreGraphics

public struct PlanInputs: Equatable, Sendable {
    public var preferences: PlanningPreferences
    public var displays: [DisplaySnapshot]
    public var system: SystemSnapshot
    public var session: SessionState
    public var media: MediaInventory

    public init(
        preferences: PlanningPreferences,
        displays: [DisplaySnapshot],
        system: SystemSnapshot,
        session: SessionState,
        media: MediaInventory
    ) {
        self.preferences = preferences
        self.displays = displays
        self.system = system
        self.session = session
        self.media = media
    }
}

public struct DisplaySnapshot: Hashable, Sendable {
    public var key: DisplayKey
    public var runtimeID: UInt32
    public var name: String
    public var frame: CGRect
    public var backingPixels: PixelSize
    public var maxRefreshHz: Int
    public var isBuiltIn: Bool

    public init(
        key: DisplayKey,
        runtimeID: UInt32,
        name: String,
        frame: CGRect,
        backingPixels: PixelSize,
        maxRefreshHz: Int,
        isBuiltIn: Bool
    ) {
        self.key = key
        self.runtimeID = runtimeID
        self.name = name
        self.frame = frame
        self.backingPixels = backingPixels
        self.maxRefreshHz = maxRefreshHz
        self.isBuiltIn = isBuiltIn
    }
}

public struct SystemSnapshot: Equatable, Sendable {
    public var power = PowerState()
    public var activity = ActivityState()
    public var occlusion = OcclusionState()
    public var studioVisible = false
    public init() {}
}

public struct PowerState: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case ac, battery(percent: Double), unknown
    }
    public var source: Source = .unknown
    public var lowPowerMode = false
    public var thermal: ThermalLevel = .nominal
    public init() {}
}

public struct ActivityState: Equatable, Sendable {
    public var screensAsleep = false
    public var sessionInactive = false
    public var screenLocked = false
    public var isInactive: Bool { screensAsleep || sessionInactive || screenLocked }
    public init() {}
}

public struct OcclusionState: Equatable, Sendable {
    public var covered: Set<DisplayKey> = []
    public var trusted = false
    public init() {}
}

public struct SessionState: Equatable, Sendable {
    public var manualPause = false
    public var previews: [PreviewID: PreviewRequest] = [:]
    public var isLaunching = true
    public init() {}
}

public struct PreviewRequest: Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        case live
        case scrub(at: Double)
    }
    public var display: DisplayKey
    public var mode: Mode
    public var pixels: PixelSize
    public init(display: DisplayKey, mode: Mode, pixels: PixelSize) {
        self.display = display
        self.mode = mode
        self.pixels = pixels
    }
}

public struct MediaInventory: Equatable, Sendable {
    public var facts: [MediaIdentity: MediaFacts] = [:]
    public init() {}
    public init(facts: [MediaIdentity: MediaFacts]) { self.facts = facts }
}

public struct MediaFacts: Equatable, Sendable {
    public enum Availability: Equatable, Sendable {
        case available, missing, failed(String)
    }
    public var availability: Availability
    public var pixels: PixelSize?
    public var nominalFPS: Double?
    public var duration: Double?
    public var variants: [VariantFacts] = []
    public init(
        availability: Availability,
        pixels: PixelSize? = nil,
        nominalFPS: Double? = nil,
        duration: Double? = nil,
        variants: [VariantFacts] = []
    ) {
        self.availability = availability
        self.pixels = pixels
        self.nominalFPS = nominalFPS
        self.duration = duration
        self.variants = variants
    }
}

public struct VariantFacts: Hashable, Sendable {
    public var spec: ProxySpec
    public var path: String
    public init(spec: ProxySpec, path: String) {
        self.spec = spec
        self.path = path
    }
}

public struct ProxySpec: Hashable, Sendable, Comparable {
    public var maxHeight: Int
    public var fps: Int?
    public init(maxHeight: Int, fps: Int? = nil) {
        self.maxHeight = maxHeight
        self.fps = fps
    }
    public static func < (a: Self, b: Self) -> Bool {
        if a.maxHeight != b.maxHeight { return a.maxHeight < b.maxHeight }
        switch (a.fps, b.fps) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x < y
        }
    }
}
