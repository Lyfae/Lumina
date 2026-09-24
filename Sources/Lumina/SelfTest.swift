// Lumina
// SelfTest — headless validation of the rendering/decoding engine logic.
//
// Run with:  Lumina --self-test
//
// This exercises the *real* engine code paths (media-type dispatch, ImageIO downsampling,
// GIF frame decode, and AVVideoRenderer's image/GIF/slideshow dispatch) using assets we
// generate on the fly. It needs no WindowServer, video files, or user media, so it can run
// in CI / headless. It does NOT validate things that genuinely require a display server
// (actual on-screen compositing or NSWindow occlusion) — those still need a real session.

import AppKit
import AVFoundation
import CoreGraphics
import ImageIO

@MainActor
enum SelfTest {

    static func run() -> Int32 {
        var passed = 0
        var failed = 0
        func check(_ name: String, _ condition: Bool) {
            if condition { passed += 1; print("  ✓ \(name)") }
            else { failed += 1; print("  ✗ \(name)") }
        }

        print("── Lumina self-test ─────────────────────")

        // 1. Media-type dispatch
        check("MediaType .mp4 → video",  MediaType.from(url: URL(fileURLWithPath: "/x/clip.mp4")) == .video)
        check("MediaType .mov → video",  MediaType.from(url: URL(fileURLWithPath: "/x/clip.mov")) == .video)
        check("MediaType .png → image",  MediaType.from(url: URL(fileURLWithPath: "/x/pic.png")) == .image)
        check("MediaType .jpg → image",  MediaType.from(url: URL(fileURLWithPath: "/x/pic.jpg")) == .image)
        check("MediaType .gif → animated", MediaType.from(url: URL(fileURLWithPath: "/x/loop.gif")) == .animatedImage)

        // 2. Generate test assets
        let tmp = FileManager.default.temporaryDirectory
        let png = tmp.appendingPathComponent("lumina-selftest-\(UUID().uuidString).png")
        let gif = tmp.appendingPathComponent("lumina-selftest-\(UUID().uuidString).gif")
        defer {
            try? FileManager.default.removeItem(at: png)
            try? FileManager.default.removeItem(at: gif)
        }
        check("generate 3000px PNG", makePNG(side: 3000, to: png))
        check("generate 5-frame GIF", makeGIF(frames: 5, side: 80, to: gif))

        // 3. Downsampling produces a display-sized image (never the full 3000px original)
        if let source = CGImageSourceCreateWithURL(png as CFURL, nil),
           let down = AVVideoRenderer.downsampledImage(source: source, index: 0, maxPixelSize: 512) {
            check("downsample longest side ≤ 512", max(down.width, down.height) <= 512 && down.width > 0)
        } else {
            check("downsample longest side ≤ 512", false)
        }

        // 4. GIF decodes the expected number of frames
        if let source = CGImageSourceCreateWithURL(gif as CFURL, nil) {
            check("GIF frame count == 5", CGImageSourceGetCount(source) == 5)
        } else {
            check("GIF frame count == 5", false)
        }

        // 5. Renderer dispatch (headless, layer-backed view — no window required)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        view.wantsLayer = true
        if view.layer != nil {
            let renderer = AVVideoRenderer()
            renderer.install(into: view)

            renderer.load(url: png, autoPlay: false)
            check("renderer dispatches image", renderer.statusSummary.hasPrefix("image"))
            check("renderer records loadedURL", renderer.loadedURL == png)

            renderer.load(url: gif, autoPlay: false)
            check("renderer dispatches GIF", renderer.statusSummary.hasPrefix("gif"))

            renderer.loadSlideshow(items: [png.path, gif.path], interval: 5, transition: .fade,
                                   kenBurnsEnabled: true)
            check("renderer enters slideshow", renderer.isSlideshow)
            check("slideshow Ken Burns animation attached", renderer.slideshowKenBurnsAnimationActive)

            renderer.setSlideshowKenBurnsEnabled(false)
            check("slideshow Ken Burns toggled off", !renderer.slideshowKenBurnsAnimationActive)

            renderer.clear()
            check("clear() exits slideshow", !renderer.isSlideshow)
        } else {
            print("  • skipped renderer view tests (no headless layer backing)")
        }

        // 6. Downsampling never upscales beyond the source
        if let source = CGImageSourceCreateWithURL(png as CFURL, nil),
           let big = AVVideoRenderer.downsampledImage(source: source, index: 0, maxPixelSize: 9000) {
            check("downsample never upscales past source", max(big.width, big.height) <= 3000)
        } else {
            check("downsample never upscales past source", false)
        }

        // 7. Persistence: custom Codable decoder round-trips and is resilient to schema evolution
        do {
            var a = MonitorAssignment(monitorIdentifier: "Test-Display")
            a.scaling = .fit
            a.opacity = 0.42
            a.loopFadeEnabled = true
            a.loopFadeDuration = 2.5
            a.loopFadeEasing = .easeOut
            a.slideshowItems = ["/a.png", "/b.png"]
            a.slideshowInterval = 15
            a.slideshowKenBurnsEnabled = true
            let data = try JSONEncoder().encode(a)
            let back = try JSONDecoder().decode(MonitorAssignment.self, from: data)
            check("assignment round-trips scaling", back.scaling == .fit)
            check("assignment round-trips opacity", abs(back.opacity - 0.42) < 0.0001)
            check("assignment round-trips fade easing", back.loopFadeEasing == .easeOut)
            check("assignment round-trips slideshow items", back.slideshowItems == ["/a.png", "/b.png"])
            check("assignment round-trips Ken Burns", back.slideshowKenBurnsEnabled == true)
        } catch {
            check("assignment encode/decode (no throw)", false)
        }

        // 8. Resilience: a minimal/older record (only the required field) decodes with sane defaults
        let minimal = Data(#"{"monitorIdentifier":"Only-ID"}"#.utf8)
        if let a = try? JSONDecoder().decode(MonitorAssignment.self, from: minimal) {
            check("minimal record decodes with defaults",
                  a.scaling == .fill && abs(a.opacity - 1.0) < 0.0001
                  && a.slideshowItems.isEmpty && a.loopFadeEnabled == false
                  && a.slideshowKenBurnsEnabled == true)
        } else {
            check("minimal record decodes (no throw)", false)
        }

        // 9. Crop coordinate math (pure geometry — the bug-prone Y-flip transforms)
        func approxEqual(_ a: CGRect, _ b: CGRect, _ tol: CGFloat = 0.001) -> Bool {
            abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol
                && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
        }
        let parent = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Top-left quarter crop (top-left origin): contentsRect must flip Y to bottom-left origin.
        let tlQuarter = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        check("image contentsRect Y-flip (top-left crop)",
              approxEqual(AVVideoRenderer.imageContentsRect(crop: tlQuarter),
                          CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)))
        check("image contentsRect full passthrough",
              approxEqual(AVVideoRenderer.imageContentsRect(crop: CGRect(x: 0, y: 0, width: 1, height: 1)),
                          CGRect(x: 0, y: 0, width: 1, height: 1)))
        // Video frame-expansion: half-size crop → 2× parent dimensions.
        let vf = AVVideoRenderer.expandedVideoFrame(parent: parent, crop: tlQuarter)
        check("video crop expands 2× for half-size crop",
              abs(vf.width - 2000) < 0.001 && abs(vf.height - 1600) < 0.001)
        // Top-left crop should push the expanded layer up so the top-left maps to the visible top-left.
        check("video crop Y-flip origin", abs(vf.minX - 0) < 0.001 && abs(vf.minY - (-800)) < 0.001)

        // 10. Semver comparison (update checker + changelog gating)
        check("semver 0.2.0 newer than 0.1.0",
              UpdateChecker.isVersion("0.2.0", newerThan: "0.1.0"))
        check("semver 0.10.0 newer than 0.9.0",
              UpdateChecker.isVersion("0.10.0", newerThan: "0.9.0"))
        check("semver equal not newer",
              !UpdateChecker.isVersion("0.2.0", newerThan: "0.2.0"))
        check("semver strips v prefix",
              UpdateChecker.normalizeVersion("v0.2.0") == "0.2.0")

        // LuminaCore preference / migration checks (each fixture is one self-test line)
        for (name, ok) in CoreSelfTest.runDetailed() {
            check(name, ok)
        }

        // PreferencesStore round-trip (InMemoryBackend)
        do {
            let legacy = LegacyDefaults(values: [
                .pauseLowPower: .bool(false),
                .accentTheme: .string("teal"),
                .audioVolume: .double(0.3),
            ])
            let backend = InMemoryBackend(legacy: legacy)
            let store = PreferencesStore(backend: backend)
            check("store migrates pauseLowPower", store.power.defaults.pauseInLowPowerMode == false)
            check("store migrates accent", store.studio.accent == .teal)
            check("store migrates audio volume", abs(store.audio.volume - 0.3) < 0.0001)

            store.power.defaults.pauseWhenCovered = false
            store.flush()
            check("store wrote power section", backend.writeLog.contains(.power))

            let store2 = PreferencesStore(backend: backend)
            check("store round-trip pauseWhenCovered", store2.power.defaults.pauseWhenCovered == false)
            check("keepsPlayingWhenLocked default via store", store2.audio.keepsPlayingWhenLocked == true)
        }

        // Hotkey binding persistence (step 12)
        do {
            let backend = InMemoryBackend()
            let store = PreferencesStore(backend: backend)
            var shortcuts = store.shortcuts
            let combo = KeyCombo(keyCode: 15, modifiers: [.command, .option]) // ⌥⌘R
            let conflict = shortcuts.bind(combo, to: .restartInSync, scope: .global)
            check("hotkey bind restartInSync no conflict", conflict == nil)
            store.shortcuts = shortcuts
            store.flush()
            let store2 = PreferencesStore(backend: backend)
            check("hotkey binding persists keyCode", store2.shortcuts[.restartInSync].combo?.keyCode == 15)
            check("hotkey binding persists scope global", store2.shortcuts[.restartInSync].scope == .global)
            check("hotkey default togglePause still ⌥⌘P",
                  store2.shortcuts[.togglePause].combo?.keyCode == 35)
        }

        // SourceKey excludes quality + max-demand decode (engine contract)
        do {
            let identity = MediaIdentity(normalizing: "/tmp/share-q.mov")
            let ref = MediaReference(identity: identity, displayPath: "/tmp/share-q.mov", bookmark: nil, kind: .video)
            var wallpapers = WallpaperPreferences()
            for id in ["D0", "D1"] {
                var wp = DisplayWallpaper()
                wp.content = .media(ref)
                wp.pinned = true
                wallpapers[display: DisplayKey(id)] = wp
            }
            var prefs = PlanningPreferences(
                power: PowerPreferences(),
                playback: PlaybackPreferences(),
                wallpapers: wallpapers,
                startup: StartupPreferences()
            )
            prefs.startup.restoreAtLaunch = true
            prefs.playback[display: DisplayKey("D0")] = .efficient
            prefs.playback[display: DisplayKey("D1")] = .original
            var media = MediaInventory()
            media.facts[identity] = MediaFacts(
                availability: .available,
                pixels: PixelSize(width: 3840, height: 2160),
                nominalFPS: 60
            )
            var session = SessionState()
            session.isLaunching = false
            let displays = [0, 1].map { i in
                DisplaySnapshot(
                    key: DisplayKey("D\(i)"),
                    runtimeID: UInt32(i),
                    name: "D\(i)",
                    frame: CGRect(x: i * 100, y: 0, width: 100, height: 100),
                    backingPixels: PixelSize(width: 2560, height: 1440)!,
                    maxRefreshHz: 60,
                    isBuiltIn: i == 0
                )
            }
            let plan = Planner.plan(PlanInputs(
                preferences: prefs, displays: displays, system: SystemSnapshot(), session: session, media: media
            ))
            check("SourceKey excludes quality (engine self-test)", plan.sources.count == 1)
            check("max-demand decode across shared consumers",
                  (plan.sources.values.first?.decodeTarget?.height ?? 0) >= 1440)
        }

        // Wallpaper dual-write v1 (step 5)
        do {
            let backend = InMemoryBackend()
            let store = PreferencesStore(backend: backend)
            var wp = DisplayWallpaper()
            wp.pinned = true
            wp.content = .media(MediaReference(
                identity: MediaIdentity(normalizing: "/tmp/wall.mov"),
                displayPath: "/tmp/wall.mov",
                bookmark: nil,
                kind: .video
            ))
            var walls = store.wallpapers
            walls[display: DisplayKey("D0")] = wp
            store.wallpapers = walls
            store.flush()
            check("wallpapers dual-write v1 assignments", backend.v1Assignments != nil)
            check("wallpapers section in write log", backend.writeLog.contains(.wallpapers))
            let store2 = PreferencesStore(backend: backend)
            check("v1 round-trip pinned restore", store2.wallpapers[display: DisplayKey("D0")].pinned == true)
            if case .media(let ref) = store2.wallpapers[display: DisplayKey("D0")].content {
                check("v1 round-trip media path", ref.identity.path.hasSuffix("/tmp/wall.mov") || ref.identity.path == "/tmp/wall.mov")
            } else {
                check("v1 round-trip media path", false)
            }
        }

        // Reconciler smoke: shared source key → one decoder in plan
        do {
            let identity = MediaIdentity(normalizing: "/tmp/share.mov")
            let ref = MediaReference(identity: identity, displayPath: "/tmp/share.mov", bookmark: nil, kind: .video)
            var wallpapers = WallpaperPreferences()
            for id in ["D0", "D1"] {
                var wp = DisplayWallpaper()
                wp.content = .media(ref)
                wp.pinned = true
                wallpapers[display: DisplayKey(id)] = wp
            }
            var prefs = PlanningPreferences(
                power: PowerPreferences(),
                playback: PlaybackPreferences(),
                wallpapers: wallpapers,
                startup: StartupPreferences()
            )
            prefs.startup.restoreAtLaunch = true
            var media = MediaInventory()
            media.facts[identity] = MediaFacts(availability: .available, pixels: PixelSize(width: 1920, height: 1080), nominalFPS: 30)
            var session = SessionState()
            session.isLaunching = false
            let displays = [0, 1].map { i in
                DisplaySnapshot(
                    key: DisplayKey("D\(i)"),
                    runtimeID: UInt32(i),
                    name: "D\(i)",
                    frame: CGRect(x: i * 100, y: 0, width: 100, height: 100),
                    backingPixels: PixelSize(width: 1920, height: 1080)!,
                    maxRefreshHz: 60,
                    isBuiltIn: i == 0
                )
            }
            let plan = Planner.plan(PlanInputs(
                preferences: prefs, displays: displays, system: SystemSnapshot(), session: session, media: media
            ))
            check("reconciler smoke: shared plan has 1 source", plan.sources.count == 1)
            check("reconciler smoke: 2 desktop surfaces", plan.surfaces.count == 2)
            let ops = PlanDiff.ops(from: .empty, to: plan)
            let creates = ops.filter { if case .createSource = $0 { return true }; return false }.count
            let binds = ops.filter { if case .bind = $0 { return true }; return false }.count
            check("reconciler smoke: 1 createSource", creates == 1)
            check("reconciler smoke: 2 binds", binds == 2)
        }

        // Design tokens / accent contrast (Batch 1 polish foundation)
        do {
            check("LuminaSpace.sm is 8×scale",
                  abs(LuminaSpace.sm - DisplayScale.points(8)) < 0.01)
            check("LuminaRadius.panel is 10×scale",
                  abs(LuminaRadius.panel - DisplayScale.points(10)) < 0.01)
            check("LuminaLook density default regular", LuminaLook.shared.density == .regular)
            check("LuminaLook material default glass", LuminaLook.shared.material == .glass)
            check("DecodeCapChoice maps efficient → fhd", DecodeCapChoice(.efficient) == .fhd)
            check("DecodeCapChoice fhd writes fhd1080", DecodeCapChoice.fhd.qualityPreset == .fhd1080)
            check("Gold onAccent is dark (contrast)", {
                let c = NSColor(AccentTheme.yellow.onAccent)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
                return r < 0.2 && g < 0.2 && b < 0.2
            }())
            check("Ocean onAccent is white", {
                let c = NSColor(AccentTheme.blue.onAccent)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
                return r > 0.95 && g > 0.95 && b > 0.95
            }())
            check("Gold text(in: light) is darkened", {
                let c = NSColor(AccentTheme.yellow.text(in: .light))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
                return r < 0.7
            }())
            check("SettingsSection order starts Appearance",
                  SettingsSection.allCases.first == .appearance)
            check("musicWidgetSize regular matches property",
                  DisplayScale.musicWidgetSize == DisplayScale.musicWidgetSize(for: .regular))
            check("iconSize inline is 12×scale",
                  abs(UIScaleManager.shared.iconSize(.inline) - DisplayScale.points(12)) < 0.01)
            let emptyPlan = PlaybackPlan.empty
            check("headline empty plan → No wallpapers set",
                  LuminaPlaybackHeadline.text(plan: emptyPlan, displays: []) == "No wallpapers set")
            check("isManuallyPaused empty is false",
                  !LuminaPlaybackHeadline.isManuallyPaused(plan: emptyPlan))
        }

        print("─────────────────────────────────────────")
        print("Self-test: \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }

    // MARK: - On-device window + occlusion validation
    //
    // Needs a live WindowServer AND the real NSApp.run() lifecycle — AppKit only computes
    // window occlusion while the app is running its normal event loop. We create a real desktop
    // wallpaper window, let the app run briefly, verify compositing + occlusion, then exit.
    private static var retainedDelegate: NSObject?

    static func runWindowTest() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = WindowTestDelegate()
        retainedDelegate = delegate     // NSApplication.delegate is weak; keep it alive
        app.delegate = delegate
        app.run()                       // WindowTestDelegate calls exit() when done
    }

    /// Full occlusion-cycle validation: covers the wallpaper window with an opaque full-screen
    /// window and verifies occlusionState drops `.visible` (the pause trigger), then returns.
    static func runOcclusionTest() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = OcclusionTestDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    // MARK: - Asset generation

    static func makePNG(side: Int, to url: URL) -> Bool {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let cg = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest)
    }

    private static func makeGIF(frames: Int, side: Int, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, frames, nil) else {
            return false
        }
        let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        for i in 0..<frames {
            guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setFillColor(CGColor(red: CGFloat(i) / CGFloat(frames), green: 0.4, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            guard let cg = ctx.makeImage() else { return false }
            let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.1]]
            CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
        }
        return CGImageDestinationFinalize(dest)
    }
}

// MARK: - Window test delegate (runs under the real NSApp lifecycle)

@MainActor
final class WindowTestDelegate: NSObject, NSApplicationDelegate {
    private var window: DesktopWallpaperWindow?
    private let renderer = AVVideoRenderer()
    private var png: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("── Lumina on-device window test (NSApp lifecycle) ──")
        guard let screen = NSScreen.main else {
            print("  ✗ no NSScreen.main (no display session)")
            exit(1)
        }

        let window = DesktopWallpaperWindow(screen: screen)
        window.showOnDesktop()
        self.window = window

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            renderer.install(into: contentView)
        }
        let png = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-windowtest-\(UUID().uuidString).png")
        self.png = png
        _ = SelfTest.makePNG(side: 1200, to: png)
        renderer.load(url: png, autoPlay: false)

        // Give the running app a moment so AppKit computes occlusion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.finish(screen: screen)
        }
    }

    private func finish(screen: NSScreen) {
        var passed = 0, failed = 0
        func check(_ name: String, _ ok: Bool) {
            if ok { passed += 1; print("  ✓ \(name)") } else { failed += 1; print("  ✗ \(name)") }
        }
        let window = self.window

        check("window reaches a screen (compositing)", (window?.isVisible ?? false) && window?.screen != nil)
        check("window sized to display", window?.frame.size == screen.frame.size)
        let occ = window?.occlusionState.contains(.visible) ?? false
        check("occlusionState reports .visible (occlusion API live)", occ)
        check("renderer shows image on the window", renderer.statusSummary.hasPrefix("image"))
        check("display ID resolves", MonitorInfo.displayID(for: screen) != 0)

        window?.hideAndRelease()
        if let png { try? FileManager.default.removeItem(at: png) }

        print("───────────────────────────────────────────────────")
        print("Window test: \(passed) passed, \(failed) failed")
        if !occ {
            print("⚠️  occlusionState lacks .visible for a desktop-level window — occlusion-based")
            print("    pausing is UNRELIABLE here; the engine must fail-OPEN (play) and use a")
            print("    per-display fullscreen detector as the authority.")
        }
        exit(failed == 0 ? 0 : 1)
    }
}

// MARK: - Occlusion pause-trigger validation (covers the wallpaper, checks occlusionState drops)

@MainActor
final class OcclusionTestDelegate: NSObject, NSApplicationDelegate {
    private var wallpaper: DesktopWallpaperWindow?
    private var cover: NSWindow?
    private let renderer = AVVideoRenderer()
    private var png: URL?
    private var passed = 0
    private var failed = 0

    private func check(_ name: String, _ ok: Bool) {
        if ok { passed += 1; print("  ✓ \(name)") } else { failed += 1; print("  ✗ \(name)") }
    }
    private func after(_ s: Double, _ work: @escaping () -> Void) {
        // Test-only helper; main-thread delivery is guaranteed by DispatchQueue.main.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
            work()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("── Lumina occlusion pause-trigger test ──")
        guard let screen = NSScreen.main else { print("  ✗ no screen"); exit(1) }

        let w = DesktopWallpaperWindow(screen: screen)
        w.showOnDesktop()
        wallpaper = w
        if let cv = w.contentView { cv.wantsLayer = true; renderer.install(into: cv) }
        let png = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-occ-\(UUID().uuidString).png")
        self.png = png
        _ = SelfTest.makePNG(side: 1000, to: png)
        renderer.load(url: png, autoPlay: false)

        after(2.0) { self.phaseBaseline(screen: screen) }
    }

    private func phaseBaseline(screen: NSScreen) {
        check("baseline: wallpaper .visible (uncovered)",
              wallpaper?.occlusionState.contains(.visible) ?? false)

        // Cover the whole display with an opaque normal-level window (simulates a fullscreen app).
        let c = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                         backing: .buffered, defer: false)
        c.level = .normal
        c.isOpaque = true
        c.backgroundColor = .black
        c.ignoresMouseEvents = true
        c.collectionBehavior = [.canJoinAllSpaces]
        c.setFrame(screen.frame, display: true)
        c.orderFrontRegardless()
        cover = c

        after(2.0) { self.phaseCovered(screen: screen) }
    }

    private func phaseCovered(screen: NSScreen) {
        // THE pause trigger: with the desktop window fully covered, occlusionState must lose .visible.
        check("covered: wallpaper occluded (.visible drops → would pause)",
              !(wallpaper?.occlusionState.contains(.visible) ?? true))

        cover?.orderOut(nil)
        cover = nil
        after(2.0) { self.phaseRevealed() }
    }

    private func phaseRevealed() {
        check("revealed: wallpaper .visible returns (would resume)",
              wallpaper?.occlusionState.contains(.visible) ?? false)

        wallpaper?.hideAndRelease()
        if let png { try? FileManager.default.removeItem(at: png) }
        print("───────────────────────────────────────────────────")
        print("Occlusion pause-trigger test: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
