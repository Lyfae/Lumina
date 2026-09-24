// LuminaCore/Identity — keys shared by preferences, plan inputs, and the plan.
import Foundation

/// Stable identifier for a physical monitor, e.g. the value of `MonitorInfo.identifier(for:index:)`.
/// Survives resolution changes and relaunch. Legacy (resolution-dependent) keys are adopted into
/// this form at the boundary by `DisplaySignals` + `WallpaperPreferences.adoptLegacyKey(_:as:)`.
public struct DisplayKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One render target. Desktop surfaces exist for every connected display (black when empty);
/// preview surfaces exist while a Studio preview view is on screen.
public enum SurfaceID: Hashable, Sendable {
    case desktop(DisplayKey)
    case preview(PreviewID)
}

public struct PreviewID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID = UUID()) { self.raw = raw }
}

/// Canonical identity of a media file: the expanded, standardized absolute path.
/// Two assignments naming the same file (via `~/…` or absolute) produce equal identities —
/// this equality is what makes decode sharing fall out of the plan.
public struct MediaIdentity: Hashable, Codable, Sendable {
    public let path: String
    /// Invariant: `path` is absolute, tilde-expanded, and `standardizingPath`-normalized.
    public init(normalizing path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        self.path = (expanded as NSString).standardizingPath
    }
}

/// A validated reference to a user-chosen file. Only constructible through
/// `MediaReference.make(from:policy:)` in the app target (which runs MediaAccessPolicy and
/// creates the security-scoped bookmark) or by `LegacyMigration` from persisted data.
public struct MediaReference: Hashable, Codable, Sendable {
    public let identity: MediaIdentity
    /// Human-readable path as stored today (`~/…` when under home). Kept for wire compatibility.
    public let displayPath: String
    public let bookmark: Data?
    public let kind: MediaKind

    /// Package-internal so only boundary code (factory, migration) can mint references.
    public init(identity: MediaIdentity, displayPath: String, bookmark: Data?, kind: MediaKind) {
        self.identity = identity
        self.displayPath = displayPath
        self.bookmark = bookmark
        self.kind = kind
    }
}

/// Mirrors today's `MediaType` minus `.unknown` (unknown files are rejected at the boundary).
public enum MediaKind: String, Codable, Sendable {
    case image, animatedImage, video
}

/// Pixel dimensions. Always positive; construct via `init?(width:height:)`.
public struct PixelSize: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int
    public init?(width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
    }
    public var longestSide: Int { max(width, height) }
}

/// Normalized rect, origin top-left, all components in 0...1, non-empty. Replaces raw CGRect
/// crop values so the planner can trust them (validated at decode time).
public struct NormalizedRect: Hashable, Codable, Sendable {
    public let x, y, width, height: Double
    public static let full = NormalizedRect(unchecked: 0, 0, 1, 1)
    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard width > 0, height > 0,
              x >= 0, y >= 0,
              x + width <= 1.0 + 1e-9,
              y + height <= 1.0 + 1e-9 else { return nil }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    public init(unchecked x: Double, _ y: Double, _ w: Double, _ h: Double) {
        self.x = x
        self.y = y
        self.width = w
        self.height = h
    }
}
