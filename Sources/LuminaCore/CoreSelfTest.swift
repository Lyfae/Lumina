// LuminaCore/SelfTest — headless checks run by `Lumina --self-test`.
import Foundation
import CoreGraphics

public enum CoreSelfTest {
    public static func run() -> [String] {
        runDetailed().compactMap { $0.ok ? nil : $0.name }
    }

    public static func runDetailed() -> [(name: String, ok: Bool)] {
        var results: [(String, Bool)] = []
        func check(_ name: String, _ condition: Bool) {
            results.append((name, condition))
        }

        // ── Key coverage ──
        let dropped = Set(LegacyMigration.intentionallyDropped.keys)
        let expectedMigrated = Set(LegacyKey.allCases).subtracting(dropped)
        check("intentionallyDropped has exactly 4 keys", dropped.count == 4)
        check("every LegacyKey is migrated or dropped",
              dropped.union(expectedMigrated) == Set(LegacyKey.allCases))
        check("migratable key set non-empty", !expectedMigrated.isEmpty)

        // ── Power migration ──
        do {
            let legacy = LegacyDefaults(values: [
                .pauseThermal: .bool(false),
                .respectFullscreen: .bool(false),
            ])
            let (doc, _) = LegacyMigration.migrate(legacy)
            check("PauseOnHighThermal=false → pauseAt nil", doc.power.defaults.thermal.pauseAt == nil)
            check("RespectFullscreenApps=false → pauseWhenCovered false",
                  doc.power.defaults.pauseWhenCovered == false)
        }

        do {
            let legacy = LegacyDefaults(values: [
                .performanceProfile: .string("maximumBattery"),
                .pauseLowPower: .bool(false),
            ])
            let (doc, _) = LegacyMigration.migrate(legacy)
            check("Max Battery profile → frameCap 30", doc.power.defaults.frameCap == .fps(30))
            check("overlay PauseOnLowPowerMode=false", doc.power.defaults.pauseInLowPowerMode == false)
        }

        do {
            let wire = MonitorAssignmentWire(monitorIdentifier: "D0")
            var pinned = wire
            pinned.keepOnStartup = true
            pinned.filePath = "~/Movies/a.mov"
            pinned.mediaType = .video
            let encoded = try! JSONEncoder().encode(["D0": pinned])
            let legacy = LegacyDefaults(values: [
                .persistAssignments: .bool(false),
                .monitorAssignments: .data(encoded),
            ])
            let (doc, _) = LegacyMigration.migrate(legacy)
            check("PersistAssignments=false → restoreAtLaunch false", doc.startup.restoreAtLaunch == false)
            check("pins retained when master off", doc.wallpapers[display: DisplayKey("D0")].pinned == true)
        }

        // ── v1 round-trip ──
        do {
            var full = MonitorAssignmentWire(monitorIdentifier: "Built-in-2560x1440")
            full.filePath = "~/Pictures/wall.png"
            full.mediaType = .image
            full.scaling = .fit
            full.opacity = 0.42
            full.loopFadeEnabled = true
            full.loopFadeDuration = 2.5
            full.loopFadeEasing = .easeOut
            full.slideshowItems = ["/a.png", "/b.png"]
            full.slideshowInterval = 15
            full.slideshowKenBurnsEnabled = true
            full.keepOnStartup = true
            full.brightness = -0.1
            full.cropRect = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)

            let data = try JSONEncoder().encode(full)
            let back = try JSONDecoder().decode(MonitorAssignmentWire.self, from: data)
            check("v1 full round-trip Equatable", back == full)

            let wallpaper = LegacyMigration.wallpaper(from: full)
            let wire2 = LegacyMigration.wire(from: wallpaper, key: DisplayKey(full.monitorIdentifier))
            let data2 = try JSONEncoder().encode(wire2)
            let back2 = try JSONDecoder().decode(MonitorAssignmentWire.self, from: data2)
            check("domain round-trip scaling", back2.scaling == full.scaling)
            check("domain round-trip opacity", abs(back2.opacity - full.opacity) < 0.0001)
            check("domain round-trip fade easing", back2.loopFadeEasing == full.loopFadeEasing)
            check("domain round-trip slideshow", back2.slideshowItems == full.slideshowItems)
            check("domain round-trip Ken Burns", back2.slideshowKenBurnsEnabled == full.slideshowKenBurnsEnabled)
            check("domain round-trip pinned", back2.keepOnStartup == full.keepOnStartup)
        } catch {
            check("v1 full round-trip Equatable", false)
        }

        do {
            let minimal = Data(#"{"monitorIdentifier":"Only-ID"}"#.utf8)
            let a = try JSONDecoder().decode(MonitorAssignmentWire.self, from: minimal)
            check("minimal wire defaults",
                  a.scaling == .fill && abs(a.opacity - 1.0) < 0.0001
                  && a.slideshowItems.isEmpty && a.loopFadeEnabled == false
                  && a.slideshowKenBurnsEnabled == true)
        } catch {
            check("minimal wire decodes", false)
        }

        do {
            var wire = MonitorAssignmentWire(monitorIdentifier: "D1")
            wire.filePath = "~/a.mov"
            wire.mediaType = .video
            wire.slideshowItems = ["~/a.png", "~/b.png"]
            let wallpaper = LegacyMigration.wallpaper(from: wire)
            if case .slideshow = wallpaper.content {
                check("slideshowItems + filePath → .slideshow", true)
            } else {
                check("slideshowItems + filePath → .slideshow", false)
            }
        }

        do {
            var item = MonitorAssignmentWire(monitorIdentifier: "library-import-1")
            item.filePath = "~/lib.png"
            item.mediaType = .image
            let data = try! JSONEncoder().encode(["library-import-1": item])
            let legacy = LegacyDefaults(values: [.libraryItems: .data(data)])
            let (doc, _) = LegacyMigration.migrate(legacy)
            check("library-import lands in library", doc.wallpapers.library.contains { $0.id == "library-import-1" })
            check("library-import not in byDisplay", doc.wallpapers.byDisplay[DisplayKey("library-import-1")] == nil)
        }

        do {
            let legacy = LegacyDefaults(values: [
                .pauseLowPower: .bool(false),
                .accentTheme: .string("teal"),
                .audioVolume: .double(0.3),
            ])
            let (a, _) = LegacyMigration.migrate(legacy)
            let (b, _) = LegacyMigration.migrate(legacy)
            check("migrate twice → equal documents", a == b)
        }

        do {
            var power = PowerPreferences()
            let key = DisplayKey("D1")
            let before = power.overrides.count
            let effective = power[display: key]
            check("get missing override == defaults", effective == power.defaults)
            check("get creates nothing", power.overrides.count == before)
            power[display: key] = {
                var r = power.defaults
                r.pauseWhenCovered = false
                return r
            }()
            check("set creates override", power.hasOverride(for: key))
            check("override value", power[display: key].pauseWhenCovered == false)
            power.clearOverride(for: key)
            check("clear removes override", !power.hasOverride(for: key))
        }

        do {
            var power = PowerPreferences()
            power.apply(.maximumBattery)
            check("apply maximumBattery → profile", power.profile == .maximumBattery)
            power.defaults.pauseInLowPowerMode = false
            check("edit rule → Custom", power.profileLabel == "Custom")
        }

        do {
            var shortcuts = ShortcutPreferences()
            let combo = KeyCombo(keyCode: 35, modifiers: [.command, .option])
            let conflict = shortcuts.bind(combo, to: .restartInSync, scope: .global)
            if case .usedBy(.togglePause) = conflict {
                check("⌥⌘P duplicate → usedBy togglePause", true)
            } else {
                check("⌥⌘P duplicate → usedBy togglePause", false)
            }
            let reserved = shortcuts.bind(
                KeyCombo(keyCode: 12, modifiers: .command),
                to: .openStudio,
                scope: .menu
            )
            check("⌘Q reserved", reserved == .reservedBySystem)
        }

        check("keepsPlayingWhenLocked default true", AmbientAudioPreferences().keepsPlayingWhenLocked)

        // ── Planner / Diff fixtures ──
        plannerAndDiffChecks(check)

        return results
    }

    private static func plannerAndDiffChecks(_ check: (String, Bool) -> Void) {
        let mediaPath = "/tmp/lumina-test/a.mov"
        let identity = MediaIdentity(normalizing: mediaPath)
        let ref = MediaReference(identity: identity, displayPath: mediaPath, bookmark: nil, kind: .video)

        func display(_ i: Int) -> DisplaySnapshot {
            DisplaySnapshot(
                key: DisplayKey("D\(i)"),
                runtimeID: UInt32(i),
                name: "Display \(i)",
                frame: CGRect(x: i * 2560, y: 0, width: 2560, height: 1440),
                backingPixels: PixelSize(width: 2560, height: 1440)!,
                maxRefreshHz: 60,
                isBuiltIn: i == 0
            )
        }

        func baseInputs(displays: Int = 3) -> PlanInputs {
            var prefs = PlanningPreferences(
                power: PowerPreferences(),
                playback: PlaybackPreferences(),
                wallpapers: WallpaperPreferences(),
                startup: StartupPreferences()
            )
            prefs.startup.restoreAtLaunch = true
            var wallpapers = WallpaperPreferences()
            for i in 0..<displays {
                var wp = DisplayWallpaper()
                wp.content = .media(ref)
                wp.pinned = true
                wallpapers[display: DisplayKey("D\(i)")] = wp
            }
            prefs.wallpapers = wallpapers
            var media = MediaInventory()
            media.facts[identity] = MediaFacts(
                availability: .available,
                pixels: PixelSize(width: 3840, height: 2160),
                nominalFPS: 60
            )
            var session = SessionState()
            session.isLaunching = false
            return PlanInputs(
                preferences: prefs,
                displays: (0..<displays).map(display),
                system: SystemSnapshot(),
                session: session,
                media: media
            )
        }

        // Sharing
        do {
            let plan = Planner.plan(baseInputs(displays: 3))
            check("same file on 3 displays → 1 source", plan.sources.count == 1)
            check("3 consumers", plan.sources.values.first?.consumers.count == 3)
            check("validate empty", plan.validate().isEmpty)
            check("SourceKey excludes quality: still 1 source", plan.sources.count == 1)
        }

        do {
            var inputs = baseInputs(displays: 2)
            var wp = inputs.preferences.wallpapers[display: DisplayKey("D1")]
            wp.timing.speed = 0.5
            inputs.preferences.wallpapers[display: DisplayKey("D1")] = wp
            let plan = Planner.plan(inputs)
            check("same file different speed → 2 sources", plan.sources.count == 2)
        }

        do {
            var inputs = baseInputs(displays: 2)
            inputs.preferences.playback[display: DisplayKey("D0")] = .efficient
            inputs.preferences.playback[display: DisplayKey("D1")] = .original
            let plan = Planner.plan(inputs)
            check("quality differs → still 1 source", plan.sources.count == 1)
            let source = plan.sources.values.first!
            // max consumer wins: original has no height cap, so decode target from D1's 2560×1440 demand
            check("shared source decode at max demand",
                  (source.decodeTarget?.height ?? 0) >= 1080)
        }

        // Power / occlusion
        do {
            var inputs = baseInputs(displays: 2)
            inputs.system.occlusion.trusted = true
            inputs.system.occlusion.covered = [DisplayKey("D1")]
            let plan = Planner.plan(inputs)
            if case .paused(let r) = plan.surfaces[.desktop(DisplayKey("D1"))]?.run {
                check("D1 covered → paused covered", r.contains(.covered))
            } else {
                check("D1 covered → paused covered", false)
            }
            check("D0 playing while D1 covered", plan.surfaces[.desktop(DisplayKey("D0"))]?.run == .playing)
            check("source still running with one playing consumer", plan.sources.values.first?.running == true)
        }

        do {
            var inputs = baseInputs(displays: 1)
            inputs.system.occlusion.trusted = false
            inputs.system.occlusion.covered = [DisplayKey("D0")]
            let plan = Planner.plan(inputs)
            check("covered but untrusted → playing", plan.surfaces[.desktop(DisplayKey("D0"))]?.run == .playing)
        }

        do {
            var inputs = baseInputs(displays: 1)
            inputs.system.power.source = .battery(percent: 18)
            inputs.preferences.power.defaults.battery.pauseBelowEnabled = true
            inputs.preferences.power.defaults.battery.pauseBelowPercent = 20
            let plan = Planner.plan(inputs)
            if case .paused(let r) = plan.surfaces[.desktop(DisplayKey("D0"))]?.run {
                check("battery 18% → batteryLow", r.contains(.batteryLow))
            } else {
                check("battery 18% → batteryLow", false)
            }
        }

        do {
            var inputs = baseInputs(displays: 1)
            inputs.system.power.lowPowerMode = true
            inputs.session.manualPause = true
            let plan = Planner.plan(inputs)
            if case .paused(let r) = plan.surfaces[.desktop(DisplayKey("D0"))]?.run {
                check("LPM+manual headline is manual", r.headline == .manual)
                check("LPM+manual contains both", r.contains(.manual) && r.contains(.lowPowerMode))
            } else {
                check("LPM+manual headline is manual", false)
                check("LPM+manual contains both", false)
            }
        }

        // Quantize
        check("quantize 60→30", Planner.quantize(cap: .fps(30), mediaFPS: 60, displayRefreshHz: 60) == 30)
        check("quantize 60→24 yields 20", Planner.quantize(cap: .fps(24), mediaFPS: 60, displayRefreshHz: 60) == 20)
        check("quantize 24→15 yields 12", Planner.quantize(cap: .fps(15), mediaFPS: 24, displayRefreshHz: 60) == 12)
        check("quantize native @60 nil", Planner.quantize(cap: .native, mediaFPS: 30, displayRefreshHz: 60) == nil)
        check("quantize native @30Hz → 30", Planner.quantize(cap: .native, mediaFPS: 60, displayRefreshHz: 30) == 30)
        check("uhd2160 caps at 2160", Planner.qualityLimits(.uhd2160).maxHeight == 2160)
        check("fhd1080 has native fps", Planner.qualityLimits(.fhd1080).fps == .native)

        // decodeTarget
        do {
            let target = Planner.decodeTarget(
                surfacePixels: PixelSize(width: 2560, height: 1440)!,
                crop: .full,
                scaling: .fill,
                mediaPixels: PixelSize(width: 3840, height: 2160),
                quality: .automatic,
                globalMaxHeight: nil
            )
            check("decodeTarget 4K on 1440p", target.width == 2560 && target.height == 1440)
        }
        do {
            let crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)!
            let target = Planner.decodeTarget(
                surfacePixels: PixelSize(width: 2560, height: 1440)!,
                crop: crop,
                scaling: .fill,
                mediaPixels: PixelSize(width: 3840, height: 2160),
                quality: .automatic,
                globalMaxHeight: nil
            )
            check("decodeTarget 50% crop clamps to source",
                  target.width <= 3840 && target.height <= 2160 && target.longestSide >= 2160)
        }
        do {
            let target = Planner.decodeTarget(
                surfacePixels: PixelSize(width: 2560, height: 1440)!,
                crop: .full,
                scaling: .fill,
                mediaPixels: PixelSize(width: 3840, height: 2160),
                quality: .efficient,
                globalMaxHeight: nil
            )
            check("decodeTarget efficient ≤1080", target.height <= 1080)
        }

        // chooseVariant
        do {
            let facts = MediaFacts(
                availability: .available,
                pixels: PixelSize(width: 3840, height: 2160),
                nominalFPS: 60,
                variants: [VariantFacts(spec: ProxySpec(maxHeight: 1080, fps: 30), path: "/proxy.mov")]
            )
            let (variant, budget, req) = Planner.chooseVariant(
                original: identity,
                facts: facts,
                target: PixelSize(width: 1920, height: 1080),
                maxFPS: 30,
                policy: .never,
                power: .ac
            )
            check("chooseVariant picks proxy", {
                if case .proxy = variant { return true }
                return false
            }())
            check("chooseVariant enforcement variant", budget.enforcement == .variant)
            check("chooseVariant no request", req == nil)
        }
        do {
            let facts = MediaFacts(
                availability: .available,
                pixels: PixelSize(width: 3840, height: 2160),
                nominalFPS: 60
            )
            let (_, budget, req) = Planner.chooseVariant(
                original: identity,
                facts: facts,
                target: PixelSize(width: 1920, height: 1080),
                maxFPS: 30,
                policy: .never,
                power: .ac
            )
            check("no variant → renderCap", budget.enforcement == .renderCap)
            check("policy never → no buildProxy", req == nil)
        }
        do {
            let facts = MediaFacts(
                availability: .available,
                pixels: PixelSize(width: 3840, height: 2160),
                nominalFPS: 60
            )
            let (_, _, req) = Planner.chooseVariant(
                original: identity,
                facts: facts,
                target: PixelSize(width: 1920, height: 1080),
                maxFPS: 30,
                policy: .whenPluggedIn,
                power: .ac
            )
            check("whenPluggedIn on AC → buildProxy", {
                if case .buildProxy = req { return true }
                return false
            }())
            let (_, _, req2) = Planner.chooseVariant(
                original: identity,
                facts: facts,
                target: PixelSize(width: 1920, height: 1080),
                maxFPS: 30,
                policy: .whenPluggedIn,
                power: .battery(percent: 50)
            )
            check("whenPluggedIn on battery → no request", req2 == nil)
        }

        // GIF decimate
        do {
            let delays = Array(repeating: 0.02, count: 10)
            let out = FrameDecimation.decimate(delays: delays, maxFPS: 25)
            check("GIF decimate 10→5", out.count == 5)
            check("GIF decimate merged delay", abs(out[0].delay - 0.04) < 0.001)
        }

        // Diff invariants
        do {
            let plan = Planner.plan(baseInputs(displays: 2))
            check("ops(p,p)==[]", PlanDiff.ops(from: plan, to: plan).isEmpty)
            check("validate fixture", plan.validate().isEmpty)

            let createOps = PlanDiff.ops(from: .empty, to: plan)
            let firstBind = createOps.firstIndex { if case .bind = $0 { return true }; return false } ?? .max
            let lastCreate = createOps.lastIndex { if case .createSource = $0 { return true }; return false } ?? 0
            check("createSource before bind", lastCreate < firstBind)

            let destroyOps = PlanDiff.ops(from: plan, to: .empty)
            let lastUnbind = destroyOps.lastIndex { if case .unbind = $0 { return true }; return false } ?? 0
            let firstDestroy = destroyOps.firstIndex { if case .destroySource = $0 { return true }; return false } ?? .max
            check("unbind before destroySource", lastUnbind < firstDestroy)
        }

        do {
            let plan = Planner.plan(baseInputs(displays: 1))
            var next = plan
            if var surface = next.surfaces[.desktop(DisplayKey("D0"))],
               case .source(let key, var look) = surface.content {
                look.brightness = 0.2
                surface.content = .source(key, look)
                next.surfaces[.desktop(DisplayKey("D0"))] = surface
            }
            let ops = PlanDiff.ops(from: plan, to: next)
            check("brightness → setLook only", ops.count == 1 && {
                if case .setLook = ops.first { return true }
                return false
            }())
        }

        do {
            // Retime: single consumer, speed change
            var inputs = baseInputs(displays: 1)
            let planA = Planner.plan(inputs)
            var wp = inputs.preferences.wallpapers[display: DisplayKey("D0")]
            wp.timing.speed = 0.5
            inputs.preferences.wallpapers[display: DisplayKey("D0")] = wp
            let planB = Planner.plan(inputs)
            let ops = PlanDiff.ops(from: planA, to: planB)
            let hasRetime = ops.contains { if case .retimeSource = $0 { return true }; return false }
            check("speed change → retimeSource", hasRetime)
            check("retime has no destroySource", !ops.contains { if case .destroySource = $0 { return true }; return false })
        }

        do {
            check("SourceKey isRetimable speed", {
                let a = SourceKey.video(identity, .playing(speed: 1, loop: .loop))
                let b = SourceKey.video(identity, .playing(speed: 0.5, loop: .loop))
                return a.isRetimable(to: b)
            }())
            check("SourceKey not retimable different media", {
                let a = SourceKey.video(identity, .playing(speed: 1, loop: .loop))
                let b = SourceKey.video(MediaIdentity(normalizing: "/other.mov"), .playing(speed: 0.5, loop: .loop))
                return !a.isRetimable(to: b)
            }())
        }

        do {
            var inputs = baseInputs(displays: 1)
            inputs.session.isLaunching = true
            inputs.preferences.startup.restoreAtLaunch = false
            let plan = Planner.plan(inputs)
            check("launch restoreAtLaunch false → no desktop window",
                  plan.surfaces[.desktop(DisplayKey("D0"))] == nil)
        }

        // ops idempotent under reapply (ops(p,p) already; also applying empty→p→p)
        do {
            let plan = Planner.plan(baseInputs(displays: 1))
            let again = PlanDiff.ops(from: plan, to: plan)
            check("ops idempotent under reapply", again.isEmpty)
        }

        // Frozen video → still source key (AVAssetImageGenerator path in reconciler)
        do {
            var inputs = baseInputs(displays: 1)
            var wp = inputs.preferences.wallpapers[display: DisplayKey("D0")]
            wp.timing.freezeAtStartFrame = true
            wp.timing.startFrame = 0.25
            inputs.preferences.wallpapers[display: DisplayKey("D0")] = wp
            let frozen = Planner.plan(inputs)
            check("frozen plan uses .frozen timing", {
                guard let key = frozen.sources.keys.first else { return false }
                if case .video(_, .frozen(let at)) = key { return abs(at - 0.25) < 0.001 }
                return false
            }())
            check("frozen SourceKey is not retimable to playing", {
                guard let key = frozen.sources.keys.first else { return false }
                let playing = SourceKey.video(identity, .playing(speed: 1, loop: .loop))
                return !key.isRetimable(to: playing)
            }())

            let live = Planner.plan(baseInputs(displays: 1))
            let ops = PlanDiff.ops(from: live, to: frozen)
            let destroysVideo = ops.contains { if case .destroySource = $0 { return true }; return false }
            let createsStillish = ops.contains { op in
                if case .createSource(let spec) = op {
                    if case .video(_, .frozen) = spec.key { return true }
                }
                return false
            }
            check("live→frozen: destroySource + createSource(.frozen)", destroysVideo && createsStillish)
        }

        // Animated GIF → animated SourceKey (not still / frozen)
        do {
            var inputs = baseInputs(displays: 1)
            let gifID = MediaIdentity(normalizing: "/tmp/loop.gif")
            let gifRef = MediaReference(identity: gifID, displayPath: "/tmp/loop.gif", bookmark: nil, kind: .animatedImage)
            var wp = inputs.preferences.wallpapers[display: DisplayKey("D0")]
            wp.content = .media(gifRef)
            inputs.preferences.wallpapers[display: DisplayKey("D0")] = wp
            inputs.media.facts[gifID] = MediaFacts(
                availability: .available,
                pixels: PixelSize(width: 480, height: 270),
                nominalFPS: 10
            )
            let plan = Planner.plan(inputs)
            check("gif wallpaper → .animated source key", {
                guard let key = plan.sources.keys.first else { return false }
                if case .animated(let id, _) = key { return id == gifID }
                return false
            }())
            check("gif sourceKey helper", {
                guard let key = Planner.sourceKey(for: wp) else { return false }
                if case .animated = key { return true }
                return false
            }())
            check("gif surface is playing when no pause reasons", {
                if case .playing = plan.surfaces[.desktop(DisplayKey("D0"))]?.run { return true }
                return false
            }())
        }

        // experimentalRenderCap default off (no data loss / safe default)
        check("experimentalRenderCap default false", PowerPreferences().experimentalRenderCap == false)

        // ── AdjustCapability (engine-honored Adjust controls) ──
        do {
            let video = AdjustCapability.for(.video)
            check("video capability: speed", video.playbackSpeed)
            check("video capability: loop", video.loopMode && video.loopFade)
            check("video capability: audio", video.audioVolume)
            check("video capability: frame pick", video.videoFramePick)
            check("video capability: quality+fps", video.decodeQuality && video.frameRate)
            check("video capability: compress", video.videoCompression)
            check("video playback footnote nil", video.playbackFootnote(mediaType: .video, isSlideshow: false) == nil)

            let gif = AdjustCapability.for(.animatedImage)
            check("gif capability: speed", gif.playbackSpeed)
            check("gif capability: no loop/audio/freeze", !gif.loopMode && !gif.audioVolume && !gif.videoFramePick)
            check("gif capability: no compress", !gif.videoCompression)
            check("gif capability: quality+fps", gif.decodeQuality && gif.frameRate)
            check("gif playback applies", gif.playbackApplies)

            let still = AdjustCapability.for(.image)
            check("still capability: none", still == .none)
            check("still playback footnote", still.playbackFootnote(mediaType: .image, isSlideshow: false) == "Not available for still images")
            check("still quality footnote", still.qualityMotionFootnote(mediaType: .image, isSlideshow: false) == "Not available for still images")

            let show = AdjustCapability.forSlideshow()
            check("slideshow: fps only", show.frameRate && !show.playbackApplies && !show.decodeQuality)
            check("slideshow label", AdjustCapability.unavailableLabel(mediaType: .image, isSlideshow: true) == "slideshows")
        }

        // ── WallpaperGeometry (preview ↔ desktop WYSIWYG) ──
        do {
            func approx(_ a: CGRect, _ b: CGRect, tol: CGFloat = 0.02) -> Bool {
                abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol
                    && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
            }
            // 4:3 media → 16:9 display
            let media43 = CGSize(width: 400, height: 300)
            let disp169 = CGSize(width: 1600, height: 900)
            let fill43 = WallpaperGeometry.layout(
                mediaSize: media43, displaySize: disp169, scaling: .fill, crop: .full
            )
            check("4:3→16:9 Fill height covers (zoomed)", fill43.mediaFrame.height > disp169.height + 1)
            check("4:3→16:9 Fill width matches display", abs(fill43.mediaFrame.width - disp169.width) < 0.5)
            check("4:3→16:9 Fill Y offset crops top/bottom", fill43.mediaFrame.minY < -1)

            let fit43 = WallpaperGeometry.layout(
                mediaSize: media43, displaySize: disp169, scaling: .fit, crop: .full
            )
            check("4:3→16:9 Fit height matches display", abs(fit43.mediaFrame.height - disp169.height) < 0.5)
            check("4:3→16:9 Fit X pillarbox", fit43.mediaFrame.minX > 1)

            let stretch43 = WallpaperGeometry.layout(
                mediaSize: media43, displaySize: disp169, scaling: .stretch, crop: .full
            )
            check("4:3→16:9 Stretch fills exactly",
                  abs(stretch43.mediaFrame.width - disp169.width) < 0.5
                  && abs(stretch43.mediaFrame.height - disp169.height) < 0.5
                  && abs(stretch43.mediaFrame.minX) < 0.5
                  && abs(stretch43.mediaFrame.minY) < 0.5)

            // 16:9 media → 16:10 display
            let media169 = CGSize(width: 1920, height: 1080)
            let disp1610 = CGSize(width: 1440, height: 900)
            let fill169 = WallpaperGeometry.layout(
                mediaSize: media169, displaySize: disp1610, scaling: .fill, crop: .full
            )
            check("16:9→16:10 Fill width covers", fill169.mediaFrame.width > disp1610.width + 1)
            check("16:9→16:10 Fill height matches", abs(fill169.mediaFrame.height - disp1610.height) < 0.5)

            let fit169 = WallpaperGeometry.layout(
                mediaSize: media169, displaySize: disp1610, scaling: .fit, crop: .full
            )
            check("16:9→16:10 Fit width matches", abs(fit169.mediaFrame.width - disp1610.width) < 0.5)
            check("16:9→16:10 Fit Y letterbox", fit169.mediaFrame.minY > 1)

            // Crop + contentsRect Y-flip
            let half = NormalizedRect(unchecked: 0, 0, 0.5, 0.5)
            check("contentsRect Y-flip top-left half",
                  approx(WallpaperGeometry.contentsRect(crop: half),
                         CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)))
            let parent = CGRect(x: 0, y: 0, width: 1000, height: 800)
            let expanded = WallpaperGeometry.expandedFrame(parent: parent, crop: half)
            check("expandedFrame 2× size", abs(expanded.width - 2000) < 0.001 && abs(expanded.height - 1600) < 0.001)
            check("expandedFrame Y origin", abs(expanded.minY - (-800)) < 0.001)

            let cropFill = WallpaperGeometry.layout(
                mediaSize: media43,
                displaySize: disp169,
                scaling: .fill,
                crop: NormalizedRect(unchecked: 0.1, 0.1, 0.8, 0.45)
            )
            check("crop Fill maps crop into display",
                  abs(cropFill.mediaFrame.width / media43.width - cropFill.mediaFrame.height / media43.height) < 0.001)
        }
    }
}
