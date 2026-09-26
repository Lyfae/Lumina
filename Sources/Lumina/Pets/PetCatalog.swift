import AppKit
import Combine
import Foundation
import LuminaCore

/// One installed pet (bundled or Application Support). Frame crops are cached after the atlas decode.
final class PetInfo: Identifiable, @unchecked Sendable {
    var id: String { slug }

    let slug: String
    let name: String
    let cellWidth: Int
    let cellHeight: Int
    let thumbURL: URL?

    private let atlasURL: URL
    private let rows: [PetState: RowSpec]
    private let lock = NSLock()
    private var atlasImage: CGImage?
    private var frameCache: [PetState: [CGImage]] = [:]

    struct RowSpec: Sendable {
        let row: Int
        let frames: Int
        let fps: Double
    }

    init(
        slug: String,
        name: String,
        cellWidth: Int,
        cellHeight: Int,
        atlasURL: URL,
        thumbURL: URL?,
        rows: [PetState: RowSpec]
    ) {
        self.slug = slug
        self.name = name
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.atlasURL = atlasURL
        self.thumbURL = thumbURL
        self.rows = rows
    }

    var cellSize: CGSize {
        CGSize(width: cellWidth, height: cellHeight)
    }

    func fps(for state: PetState) -> Double {
        let value = rows[state]?.fps ?? rows[.idle]?.fps ?? 8
        return value > 0 ? value : 8
    }

    /// Whether this pet’s atlas JSON defines the given row (no inventing missing art).
    func hasState(_ state: PetState) -> Bool {
        rows[state] != nil
    }

    /// Atlas rows present for this pet, in `PetState.allCases` order.
    var availableStates: [PetState] {
        PetState.allCases.filter { rows[$0] != nil }
    }

    func frameCount(for state: PetState) -> Int {
        frames(for: state).count
    }

    func frames(for state: PetState) -> [CGImage] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = frameCache[state] { return cached }
        let resolved = rows[state] != nil ? state : .idle
        guard let spec = rows[resolved] else {
            frameCache[state] = []
            return []
        }
        guard let atlas = loadAtlasUnlocked() else {
            frameCache[state] = []
            return []
        }
        let count = max(0, min(spec.frames, 8))
        var cropped: [CGImage] = []
        cropped.reserveCapacity(count)
        for col in 0..<count {
            if let frame = Self.crop(
                atlas: atlas,
                column: col,
                row: spec.row,
                cellWidth: cellWidth,
                cellHeight: cellHeight
            ) {
                cropped.append(frame)
            }
        }
        frameCache[state] = cropped
        if resolved != state {
            frameCache[resolved] = cropped
        }
        return cropped
    }

    func thumbnailImage() -> NSImage? {
        if let thumbURL,
           FileManager.default.fileExists(atPath: thumbURL.path),
           let image = NSImage(contentsOf: thumbURL) {
            return image
        }
        if let frame = frames(for: .idle).first {
            return NSImage(cgImage: frame, size: NSSize(width: cellWidth, height: cellHeight))
        }
        return nil
    }

    private func loadAtlasUnlocked() -> CGImage? {
        if let atlasImage { return atlasImage }
        guard let source = CGImageSourceCreateWithURL(atlasURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: true
              ] as CFDictionary) else {
            return nil
        }
        atlasImage = image
        return image
    }

    /// These atlas PNGs crop with y = 0 at the top row. Row 0 in the JSON is the top of the file.
    private static func crop(
        atlas: CGImage,
        column: Int,
        row: Int,
        cellWidth: Int,
        cellHeight: Int
    ) -> CGImage? {
        let rect = CGRect(
            x: column * cellWidth,
            y: row * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        guard rect.maxX <= CGFloat(atlas.width), rect.maxY <= CGFloat(atlas.height) else { return nil }
        return atlas.cropping(to: rect)
    }
}

/// Loads bundled + user petdex pets. Scrubber: `PetCatalog.shared.currentPet` / `isEnabled` / `selectedSlug`.
@MainActor
final class PetCatalog: ObservableObject {
    static let shared = PetCatalog()

    private static let slugKey = "music.pet.slug"
    private static let enabledKey = "music.pet.enabled"
    private static let studioKey = "music.pet.studio"
    private static let studioScaleKey = "music.pet.studio.scale"
    private static let bundledSlugs = ["lumi", "mochi", "nimbus", "ember", "pip", "koi"]

    @Published private(set) var pets: [PetInfo] = []

    @Published var selectedSlug: String {
        didSet {
            guard selectedSlug != oldValue else { return }
            UserDefaults.standard.set(selectedSlug, forKey: Self.slugKey)
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    /// Free-floating companion overlay in Lumina Studio (`music.pet.studio`).
    @Published var showInStudio: Bool {
        didSet {
            guard showInStudio != oldValue else { return }
            UserDefaults.standard.set(showInStudio, forKey: Self.studioKey)
        }
    }

    /// Size of the floating Studio pet. 1 is the default; range is 0.5...2.
    @Published var studioScale: Double {
        didSet {
            let clamped = min(2, max(0.5, studioScale))
            if clamped != studioScale {
                studioScale = clamped
                return
            }
            guard studioScale != oldValue else { return }
            UserDefaults.standard.set(studioScale, forKey: Self.studioScaleKey)
        }
    }

    /// Selected pet, falling back to `lumi` then first available. Nil only when nothing loaded.
    var currentPet: PetInfo? {
        if let match = pets.first(where: { $0.slug == selectedSlug }) { return match }
        if let lumi = pets.first(where: { $0.slug == "lumi" }) { return lumi }
        return pets.first
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(true, forKey: Self.enabledKey)
        }
        if defaults.object(forKey: Self.studioKey) == nil {
            defaults.set(true, forKey: Self.studioKey)
        }
        if defaults.object(forKey: Self.slugKey) == nil {
            defaults.set("lumi", forKey: Self.slugKey)
        }
        selectedSlug = defaults.string(forKey: Self.slugKey) ?? "lumi"
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        showInStudio = defaults.object(forKey: Self.studioKey) as? Bool ?? true
        let storedScale = defaults.object(forKey: Self.studioScaleKey) as? Double ?? 1
        studioScale = min(2, max(0.5, storedScale))
        reload()
    }

    func reload() {
        var loaded: [PetInfo] = []
        var seen = Set<String>()

        for slug in Self.bundledSlugs {
            if let pet = Self.loadBundled(slug: slug), seen.insert(pet.slug).inserted {
                loaded.append(pet)
            }
        }

        for pet in Self.loadUserPets() where seen.insert(pet.slug).inserted {
            loaded.append(pet)
        }

        pets = loaded
        if !loaded.contains(where: { $0.slug == selectedSlug }), let first = loaded.first {
            selectedSlug = first.slug
        }
    }

    private static func loadBundled(slug: String) -> PetInfo? {
        let jsonURL = resourceURL(name: slug, ext: "json", subdirectory: "Pets")
        let atlasURL = resourceURL(name: slug, ext: "png", subdirectory: "Pets")
        let thumbURL = resourceURL(name: "\(slug)-thumb", ext: "png", subdirectory: "Pets")
        guard let jsonURL, let atlasURL else { return nil }
        return loadPet(jsonURL: jsonURL, atlasURL: atlasURL, thumbURL: thumbURL, fallbackSlug: slug)
    }

    private static func resourceURL(name: String, ext: String, subdirectory: String) -> URL? {
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        // Assembled app: Resources/Lumina_Lumina.bundle/Contents/Resources/<file>
        if let resourceURL = Bundle.main.resourceURL {
            let bundleName = "Lumina_Lumina.bundle"
            let candidates = [
                resourceURL
                    .appendingPathComponent(bundleName)
                    .appendingPathComponent("Contents/Resources/\(name).\(ext)"),
                resourceURL
                    .appendingPathComponent(bundleName)
                    .appendingPathComponent("Contents/Resources/\(subdirectory)/\(name).\(ext)"),
                resourceURL.appendingPathComponent("\(subdirectory)/\(name).\(ext)"),
                resourceURL.appendingPathComponent("\(name).\(ext)"),
            ]
            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func loadUserPets() -> [PetInfo] {
        let root = userPetsDirectory()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var pets: [PetInfo] = []
        for dir in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue
            else { continue }
            let slug = dir.lastPathComponent
            let jsonURL = dir.appendingPathComponent("\(slug).json")
            let atlasURL = dir.appendingPathComponent("\(slug).png")
            let thumbURL = dir.appendingPathComponent("\(slug)-thumb.png")
            guard FileManager.default.fileExists(atPath: jsonURL.path),
                  FileManager.default.fileExists(atPath: atlasURL.path),
                  let pet = loadPet(
                      jsonURL: jsonURL,
                      atlasURL: atlasURL,
                      thumbURL: FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : nil,
                      fallbackSlug: slug
                  )
            else { continue }
            pets.append(pet)
        }
        return pets.sorted { $0.slug < $1.slug }
    }

    private static func userPetsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Lumina/Pets", isDirectory: true)
    }

    private static func loadPet(
        jsonURL: URL,
        atlasURL: URL,
        thumbURL: URL?,
        fallbackSlug: String
    ) -> PetInfo? {
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              FileManager.default.fileExists(atPath: atlasURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let slug = (root["slug"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSlug = (slug?.isEmpty == false ? slug! : fallbackSlug)
        let name = (root["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false ? name! : resolvedSlug.capitalized)

        var cellW = 192
        var cellH = 208
        if let cell = root["cell"] as? [Any], cell.count >= 2 {
            cellW = intValue(cell[0]) ?? cellW
            cellH = intValue(cell[1]) ?? cellH
        }
        guard cellW > 0, cellH > 0 else { return nil }

        var rows: [PetState: PetInfo.RowSpec] = [:]
        if let rowMap = root["rows"] as? [String: Any] {
            for (key, value) in rowMap {
                guard let state = PetState.fromRowKey(key),
                      let spec = value as? [String: Any]
                else { continue }
                let row = intValue(spec["row"]) ?? state.defaultRow
                let frames = intValue(spec["frames"]) ?? 1
                let fps = doubleValue(spec["fps"]) ?? 8
                rows[state] = PetInfo.RowSpec(row: row, frames: max(1, frames), fps: fps)
            }
        }
        if rows[.idle] == nil {
            rows[.idle] = PetInfo.RowSpec(row: 0, frames: 1, fps: 6)
        }

        return PetInfo(
            slug: resolvedSlug,
            name: resolvedName,
            cellWidth: cellW,
            cellHeight: cellH,
            atlasURL: atlasURL,
            thumbURL: thumbURL,
            rows: rows
        )
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let v as Int: return v
        case let v as Double: return Int(v)
        case let v as NSNumber: return v.intValue
        case let v as String: return Int(v)
        default: return nil
        }
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as NSNumber: return v.doubleValue
        case let v as String: return Double(v)
        default: return nil
        }
    }
}

private extension PetState {
    var defaultRow: Int {
        switch self {
        case .idle: return 0
        case .runningRight: return 1
        case .runningLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .running: return 7
        case .review: return 8
        }
    }
}
