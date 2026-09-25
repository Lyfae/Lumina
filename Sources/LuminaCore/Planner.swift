// LuminaCore/Plan/Planner — the one pure function that decides playback.
import Foundation
import CoreGraphics

public enum Planner {

    public static func plan(_ inputs: PlanInputs) -> PlaybackPlan {
        var surfaces: [SurfaceID: SurfacePlan] = [:]
        var wants: [SourceKey: [(SurfaceID, ConsumerDemand)]] = [:]
        var requests: Set<PlanRequest> = []

        let prefs = inputs.preferences

        for display in inputs.displays {
            let wp = prefs.wallpapers[display: display.key]
            let sid = SurfaceID.desktop(display.key)
            let geometry = SurfaceGeometry(frame: display.frame, pixels: display.backingPixels)

            if inputs.session.isLaunching && !prefs.startup.restoreAtLaunch {
                continue
            }

            let (content, baseDemand, probe) = contentFor(
                wallpaper: wp,
                display: display,
                quality: prefs.playback[display: display.key],
                globalMaxHeight: prefs.playback.maxDecodeHeight,
                media: inputs.media
            )
            if let probe { requests.insert(probe) }

            let reasons = pauseReasons(
                display: display.key,
                wallpaper: wp,
                rules: prefs.power[display: display.key],
                system: inputs.system,
                session: inputs.session
            )
            // No media: leave the system desktop. An empty window here is a black screen.
            guard case .source(let key, _) = content else { continue }

            let run: SurfaceRun = reasons.isEmpty ? .playing : .paused(reasons)

            surfaces[sid] = SurfacePlan(id: sid, geometry: geometry, content: content, run: run)
            if var demand = baseDemand {
                demand.frameCap = frameCap(
                    rules: prefs.power[display: display.key],
                    quality: prefs.playback[display: display.key],
                    system: inputs.system
                )
                wants[key, default: []].append((sid, demand))
            }
        }

        for (previewID, preview) in inputs.session.previews {
            let sid = SurfaceID.preview(previewID)
            let geometry = SurfaceGeometry(frame: nil, pixels: preview.pixels)
            guard let desktop = surfaces[.desktop(preview.display)],
                  case let .source(desktopKey, desktopLook) = desktop.content else {
                surfaces[sid] = SurfacePlan(id: sid, geometry: geometry, content: .empty, run: .idle)
                continue
            }

            var look = desktopLook
            look.crop = .full

            let run: SurfaceRun = inputs.system.activity.isInactive
                ? .paused(.displayInactive)
                : .playing

            switch preview.mode {
            case .live:
                surfaces[sid] = SurfacePlan(id: sid, geometry: geometry, content: .source(desktopKey, look), run: run)
                let demand = ConsumerDemand(
                    decodeTarget: preview.pixels,
                    frameCap: .native,
                    audio: AudioSetting(),
                    quality: .automatic
                )
                wants[desktopKey, default: []].append((sid, demand))
            case .scrub(let at):
                guard case let .video(identity, _) = desktopKey else {
                    surfaces[sid] = SurfacePlan(id: sid, geometry: geometry, content: .source(desktopKey, look), run: run)
                    continue
                }
                let scrubKey = SourceKey.video(identity, .scrub(previewID))
                surfaces[sid] = SurfacePlan(id: sid, geometry: geometry, content: .source(scrubKey, look), run: .paused([]))
                let demand = ConsumerDemand(
                    decodeTarget: preview.pixels,
                    frameCap: .native,
                    audio: AudioSetting(muted: true, volume: 0),
                    quality: .automatic
                )
                wants[scrubKey, default: []].append((sid, demand))
                _ = at
            }
        }

        var sources: [SourceKey: SourcePlan] = [:]
        for (key, consumers) in wants {
            let ids = consumers.map(\.0).sorted { PlaybackPlan.surfaceSort($0, $1) }
            let playing = consumers.filter { surfaces[$0.0]?.run == .playing }
            let demandPool = playing.isEmpty ? consumers : playing

            let target = demandPool.compactMap(\.1.decodeTarget).max { a, b in
                a.longestSide < b.longestSide
            }
            let cap = demandPool.map(\.1.frameCap).min() ?? .native
            let audio = loudestAudio(demandPool.map(\.1.audio))

            let identity = key.identity
            let facts = identity.flatMap { inputs.media.facts[$0] }
            let mediaFPS = facts?.nominalFPS
            let displayRefresh = inputs.displays.map(\.maxRefreshHz).max() ?? 60
            let quantized = quantize(cap: cap, mediaFPS: mediaFPS, displayRefreshHz: displayRefresh)

            let originalPath: String = {
                if let identity { return identity.path }
                if case .slideshow(let spec) = key {
                    return spec.items.first?.identity.path ?? ""
                }
                return ""
            }()

            let (variant, budget, request) = chooseVariant(
                original: identity ?? MediaIdentity(normalizing: originalPath.isEmpty ? "/missing" : originalPath),
                facts: facts,
                target: target,
                maxFPS: quantized,
                policy: prefs.playback.proxyPolicy,
                power: inputs.system.power.source
            )
            if let request { requests.insert(request) }
            if let identity, facts == nil {
                requests.insert(.probe(identity))
            }

            let startFrame: Double?
            switch key {
            case .video(_, .frozen(let at)): startFrame = at
            case .video(_, .playing), .video(_, .scrub): startFrame = nil
            default: startFrame = nil
            }

            sources[key] = SourcePlan(
                key: key,
                variant: variant.path.isEmpty && !originalPath.isEmpty ? .original(path: originalPath) : variant,
                budget: budget,
                decodeTarget: target,
                audio: audio,
                startFrame: startFrame,
                running: !playing.isEmpty,
                consumers: ids
            )
        }

        var plan = PlaybackPlan()
        plan.surfaces = surfaces
        plan.sources = sources
        plan.requests = requests
        return plan
    }

    // MARK: - Rules

    public static func pauseReasons(
        display: DisplayKey,
        wallpaper: DisplayWallpaper,
        rules: PowerRuleSet,
        system: SystemSnapshot,
        session: SessionState
    ) -> PauseReasons {
        var reasons: PauseReasons = []
        if session.manualPause { reasons.insert(.manual) }
        if system.activity.isInactive { reasons.insert(.displayInactive) }
        if rules.pauseInLowPowerMode && system.power.lowPowerMode { reasons.insert(.lowPowerMode) }
        if case .battery(let percent) = system.power.source {
            if rules.battery.pauseOnBattery { reasons.insert(.onBattery) }
            if rules.battery.pauseBelowEnabled && percent < rules.battery.pauseBelowPercent {
                reasons.insert(.batteryLow)
            }
        }
        if let pauseAt = rules.thermal.pauseAt, system.power.thermal >= pauseAt {
            reasons.insert(.thermal)
        }
        if rules.pauseWhenCovered && system.occlusion.trusted && system.occlusion.covered.contains(display) {
            reasons.insert(.covered)
        }
        if !wallpaper.enabled { reasons.insert(.disabled) }
        return reasons
    }

    public static func frameCap(
        rules: PowerRuleSet,
        quality: QualityPreset,
        system: SystemSnapshot
    ) -> FrameRateCap {
        if system.studioVisible && rules.fullQualityWhileStudioOpen {
            return qualityLimits(quality).fps
        }
        var caps: [FrameRateCap] = [rules.frameCap, qualityLimits(quality).fps]
        if let at = rules.thermal.capAt, system.power.thermal >= at {
            caps.append(rules.thermal.cap)
        }
        if case .battery = system.power.source {
            caps.append(rules.battery.capOnBattery)
        }
        return caps.min() ?? .native
    }

    public static func quantize(cap: FrameRateCap, mediaFPS: Double?, displayRefreshHz: Int) -> Int? {
        let capValue: Int?
        switch cap {
        case .native: capValue = nil
        case .fps(let n): capValue = n
        }
        let effective: Int
        if let capValue {
            effective = min(capValue, max(1, displayRefreshHz))
        } else {
            // Native still respects display refresh as an upper bound when media is faster.
            guard let mediaFPS, mediaFPS > Double(displayRefreshHz) + 0.1 else { return nil }
            effective = displayRefreshHz
        }

        guard let mediaFPS, mediaFPS > 0 else { return capValue == nil ? nil : effective }

        if mediaFPS <= Double(effective) + 0.1 { return capValue == nil ? nil : Int(mediaFPS.rounded()) }

        let n = Int(ceil(mediaFPS / Double(effective)))
        guard n > 1 else { return nil }
        let quantized = Int((mediaFPS / Double(n)).rounded())
        return max(1, quantized)
    }

    public static func decodeTarget(
        surfacePixels: PixelSize,
        crop: NormalizedRect,
        scaling: VideoScaling,
        mediaPixels: PixelSize?,
        quality: QualityPreset,
        globalMaxHeight: Int?
    ) -> PixelSize {
        let cropW = max(crop.width, 0.001)
        let cropH = max(crop.height, 0.001)
        var needW = Int((Double(surfacePixels.width) / cropW).rounded(.up))
        var needH = Int((Double(surfacePixels.height) / cropH).rounded(.up))

        if let media = mediaPixels {
            switch scaling {
            case .fit:
                let sx = Double(needW) / Double(media.width)
                let sy = Double(needH) / Double(media.height)
                let s = min(sx, sy)
                needW = Int((Double(media.width) * s).rounded(.up))
                needH = Int((Double(media.height) * s).rounded(.up))
            case .fill:
                let sx = Double(needW) / Double(media.width)
                let sy = Double(needH) / Double(media.height)
                let s = max(sx, sy)
                needW = min(media.width, Int((Double(media.width) * s).rounded(.up)))
                needH = min(media.height, Int((Double(media.height) * s).rounded(.up)))
            case .stretch:
                break
            }
            needW = min(needW, media.width)
            needH = min(needH, media.height)
        }

        let heightCap = [qualityLimits(quality).maxHeight, globalMaxHeight].compactMap { $0 }.min()
        if let heightCap, needH > heightCap {
            let scale = Double(heightCap) / Double(needH)
            needW = max(1, Int((Double(needW) * scale).rounded()))
            needH = heightCap
        }

        return PixelSize(width: max(1, needW), height: max(1, needH))
            ?? PixelSize(width: 1, height: 1)!
    }

    public static func qualityLimits(_ preset: QualityPreset) -> (maxHeight: Int?, fps: FrameRateCap) {
        switch preset {
        case .automatic: return (nil, .native)
        case .original: return (nil, .native)
        case .uhd2160: return (2160, .native)
        case .balanced: return (1440, .native)
        case .fhd1080: return (1080, .native)
        case .efficient: return (1080, .fps(30))
        }
    }

    public static func chooseVariant(
        original: MediaIdentity,
        facts: MediaFacts?,
        target: PixelSize?,
        maxFPS: Int?,
        policy: ProxyPolicy,
        power: PowerState.Source
    ) -> (Variant, FrameBudget, PlanRequest?) {
        let originalPath = original.path
        let sourcePixels = facts?.pixels
        let sourceFPS = facts?.nominalFPS

        if let target, let variants = facts?.variants, !variants.isEmpty {
            let neededH = target.height
            let neededFPS = maxFPS
            let candidates = variants
                .filter { $0.spec.maxHeight >= Int(Double(neededH) * 0.9) }
                .filter { v in
                    guard let neededFPS, let vfps = v.spec.fps else { return true }
                    return vfps >= neededFPS
                }
                .sorted { $0.spec < $1.spec }
            if let best = candidates.first {
                let enforcement: FrameBudget.Enforcement
                if let maxFPS, let vfps = best.spec.fps, vfps <= maxFPS {
                    enforcement = .variant
                } else if maxFPS != nil {
                    enforcement = .renderCap
                } else {
                    enforcement = .native
                }
                return (
                    .proxy(best.spec, path: best.path),
                    FrameBudget(maxFPS: maxFPS, enforcement: enforcement),
                    nil
                )
            }
        }

        var request: PlanRequest?
        let exceedsPixels: Bool = {
            guard let target, let sourcePixels else { return false }
            return Double(sourcePixels.longestSide) > Double(target.longestSide) * 1.5
        }()
        let exceedsFPS: Bool = {
            guard let maxFPS, let sourceFPS else { return false }
            return sourceFPS > Double(maxFPS) * 1.5
        }()
        let allowBuild: Bool = {
            switch policy {
            case .never: return false
            case .always: return true
            case .whenPluggedIn: return power == .ac
            }
        }()
        if allowBuild && (exceedsPixels || exceedsFPS), let target {
            let spec = ProxySpec(maxHeight: target.height, fps: maxFPS)
            request = .buildProxy(original, spec)
        }

        let budget: FrameBudget
        if let maxFPS {
            budget = FrameBudget(maxFPS: maxFPS, enforcement: .renderCap)
        } else {
            budget = .native
        }
        return (.original(path: originalPath), budget, request)
    }

    public static func sourceKey(for wallpaper: DisplayWallpaper) -> SourceKey? {
        switch wallpaper.content {
        case .none:
            return nil
        case .media(let ref):
            switch ref.kind {
            case .video:
                if wallpaper.timing.freezeAtStartFrame {
                    let at = wallpaper.timing.startFrame ?? 0
                    return .video(ref.identity, .frozen(at: at))
                }
                return .video(ref.identity, .playing(speed: wallpaper.timing.speed, loop: wallpaper.timing.loopMode))
            case .image:
                return .still(ref.identity)
            case .animatedImage:
                return .animated(ref.identity, speed: wallpaper.timing.speed)
            }
        case .slideshow(let spec):
            return .slideshow(spec)
        }
    }

    public static func look(for wallpaper: DisplayWallpaper, isPreview: Bool) -> SurfaceLook {
        SurfaceLook(
            scaling: wallpaper.look.scaling,
            crop: isPreview ? .full : wallpaper.look.crop,
            brightness: wallpaper.look.brightness,
            opacity: wallpaper.look.opacity,
            saturation: wallpaper.look.saturation,
            hue: wallpaper.look.hue,
            grayscale: wallpaper.look.grayscale,
            loopFade: wallpaper.look.loopFade,
            crossfade: wallpaper.look.crossfadeDuration,
            crossfadeEasing: wallpaper.look.crossfadeEasing
        )
    }

    // MARK: - Helpers

    struct ConsumerDemand {
        var decodeTarget: PixelSize?
        var frameCap: FrameRateCap
        var audio: AudioSetting
        var quality: QualityPreset
    }

    private static func contentFor(
        wallpaper: DisplayWallpaper,
        display: DisplaySnapshot,
        quality: QualityPreset,
        globalMaxHeight: Int?,
        media: MediaInventory
    ) -> (SurfaceContent, ConsumerDemand?, PlanRequest?) {
        guard let key = sourceKey(for: wallpaper) else {
            return (.empty, nil, nil)
        }

        if let identity = key.identity, let facts = media.facts[identity] {
            switch facts.availability {
            case .missing:
                return (.failed("Media missing"), nil, nil)
            case .failed(let msg):
                return (.failed(msg), nil, nil)
            case .available:
                break
            }
        }

        let surfaceLook = look(for: wallpaper, isPreview: false)
        let target = decodeTarget(
            surfacePixels: display.backingPixels,
            crop: wallpaper.look.crop,
            scaling: wallpaper.look.scaling,
            mediaPixels: key.identity.flatMap { media.facts[$0]?.pixels },
            quality: quality,
            globalMaxHeight: globalMaxHeight
        )
        // frameCap filled later by caller via rules; store quality here for source aggregation.
        let demand = ConsumerDemand(
            decodeTarget: target,
            frameCap: qualityLimits(quality).fps,
            audio: wallpaper.audio,
            quality: quality
        )
        var probe: PlanRequest?
        if let identity = key.identity, media.facts[identity] == nil {
            probe = .probe(identity)
        }
        return (.source(key, surfaceLook), demand, probe)
    }

    private static func loudestAudio(_ settings: [AudioSetting]) -> AudioSetting {
        let unmuted = settings.filter { !$0.muted }
        guard let loudest = unmuted.max(by: { $0.volume < $1.volume }) else {
            return AudioSetting(muted: true, volume: 0)
        }
        return loudest
    }
}
