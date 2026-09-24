// LuminaCore/Plan/PlanDiff — minimal, ordered, idempotent operations from one plan to the next.
import Foundation

public enum PlanOp: Equatable, Sendable {
    case createSource(SourcePlan)
    case retuneSource(SourceKey, SourcePlan)
    /// Timing-only re-key of an existing single-consumer source (speed/loop slider). Graft from A.
    case retimeSource(old: SourceKey, new: SourceKey, plan: SourcePlan)
    case setSourceRunning(SourceKey, Bool)
    case destroySource(SourceKey)

    case createSurface(SurfaceID, SurfaceGeometry)
    case setGeometry(SurfaceID, SurfaceGeometry)
    case bind(SurfaceID, SourceKey, crossfade: Double)
    case unbind(SurfaceID)
    case setLook(SurfaceID, SurfaceLook)
    case setSurfaceRun(SurfaceID, SurfaceRun)
    case showFailure(SurfaceID, String?)
    case destroySurface(SurfaceID)
}

public enum PlanDiff {
    public static func ops(from old: PlaybackPlan, to new: PlaybackPlan) -> [PlanOp] {
        if old == new { return [] }

        var ops: [PlanOp] = []

        let oldSurfaceIDs = Set(old.surfaces.keys)
        let newSurfaceIDs = Set(new.surfaces.keys)
        let goneSurfaces = oldSurfaceIDs.subtracting(newSurfaceIDs)
        let addedSurfaces = newSurfaceIDs.subtracting(oldSurfaceIDs)
        let keptSurfaces = oldSurfaceIDs.intersection(newSurfaceIDs)

        // Detect retime candidates: old key disappearing, new key appearing, same media timing-only change,
        // and the sole consumer of the old key is the sole consumer of the new key.
        var retimedOldKeys: Set<SourceKey> = []
        var retimedNewKeys: Set<SourceKey> = []
        var retimeOps: [(SourceKey, SourceKey, SourcePlan)] = []

        let removedKeys = Set(old.sources.keys).subtracting(new.sources.keys)
        let addedKeys = Set(new.sources.keys).subtracting(old.sources.keys)

        for oldKey in removedKeys {
            guard let oldPlan = old.sources[oldKey], oldPlan.consumers.count == 1,
                  let consumer = oldPlan.consumers.first else { continue }
            for newKey in addedKeys where !retimedNewKeys.contains(newKey) {
                guard oldKey.isRetimable(to: newKey),
                      let newPlan = new.sources[newKey],
                      newPlan.consumers == [consumer] else { continue }
                retimeOps.append((oldKey, newKey, newPlan))
                retimedOldKeys.insert(oldKey)
                retimedNewKeys.insert(newKey)
                break
            }
        }

        // 1. Gone surfaces: unbind then destroy
        for id in goneSurfaces.sorted(by: PlaybackPlan.surfaceSort) {
            if case .source = old.surfaces[id]?.content {
                ops.append(.unbind(id))
            }
            ops.append(.destroySurface(id))
        }

        // 2. Create / retime sources
        for (oldKey, newKey, plan) in retimeOps {
            ops.append(.retimeSource(old: oldKey, new: newKey, plan: plan))
        }
        for key in addedKeys.subtracting(retimedNewKeys).sorted(by: sourceKeySort) {
            if let plan = new.sources[key] {
                ops.append(.createSource(plan))
            }
        }

        // 3. Retune kept sources (ignore running/consumers)
        let keptKeys = Set(old.sources.keys).intersection(new.sources.keys)
        for key in keptKeys.sorted(by: sourceKeySort) {
            guard let o = old.sources[key], let n = new.sources[key] else { continue }
            if !o.retuneEquals(n) {
                ops.append(.retuneSource(key, n))
            }
        }

        // 4. Create new surfaces
        for id in addedSurfaces.sorted(by: PlaybackPlan.surfaceSort) {
            if let surface = new.surfaces[id] {
                ops.append(.createSurface(id, surface.geometry))
            }
        }

        // 5. Geometry changes
        for id in keptSurfaces.sorted(by: PlaybackPlan.surfaceSort) {
            guard let o = old.surfaces[id], let n = new.surfaces[id] else { continue }
            if o.geometry != n.geometry {
                ops.append(.setGeometry(id, n.geometry))
            }
        }

        // 6. Bind / unbind / look / run / failure for all new+kept surfaces
        let activeSurfaces = addedSurfaces.union(keptSurfaces)
        for id in activeSurfaces.sorted(by: PlaybackPlan.surfaceSort) {
            let oldSurface = old.surfaces[id]
            let newSurface = new.surfaces[id]!
            let oldKey = Self.sourceKey(of: oldSurface?.content)
            let newKey = Self.sourceKey(of: newSurface.content)

            if oldKey != newKey {
                if newKey == nil, oldKey != nil {
                    ops.append(.unbind(id))
                } else if let newKey {
                    let fade: Double
                    if oldKey != nil {
                        fade = newSurface.look?.crossfade ?? 0
                    } else {
                        fade = 0
                    }
                    ops.append(.bind(id, newKey, crossfade: fade))
                }
            }

            if case .failed(let msg) = newSurface.content {
                ops.append(.showFailure(id, msg))
            } else if case .failed = oldSurface?.content {
                ops.append(.showFailure(id, nil))
            }

            if let look = newSurface.look, look != oldSurface?.look {
                ops.append(.setLook(id, look))
            }

            if newSurface.run != oldSurface?.run {
                ops.append(.setSurfaceRun(id, newSurface.run))
            }
        }

        // 7. Source running flags
        for key in Set(new.sources.keys).sorted(by: sourceKeySort) {
            let oldRunning = old.sources[key]?.running
            let newRunning = new.sources[key]!.running
            if oldRunning != newRunning {
                ops.append(.setSourceRunning(key, newRunning))
            }
        }
        // Retimed sources: running handled via new key above once present in `new`.

        // 8. Destroy removed sources (not retimed)
        for key in removedKeys.subtracting(retimedOldKeys).sorted(by: sourceKeySort) {
            ops.append(.destroySource(key))
        }

        return ops
    }

    private static func sourceKey(of content: SurfaceContent?) -> SourceKey? {
        guard case let .source(key, _) = content else { return nil }
        return key
    }
}

extension SurfacePlan {
    var look: SurfaceLook? {
        if case let .source(_, look) = content { return look }
        return nil
    }
}

private func sourceKeySort(_ a: SourceKey, _ b: SourceKey) -> Bool {
    String(describing: a) < String(describing: b)
}

/// Derived, user-facing status for the menu-bar tooltip and Studio badges.
public struct PlanSummary: Equatable, Sendable {
    public var decoders: Int
    public var perDisplay: [DisplayKey: String]
    public var headline: String

    public init(plan: PlaybackPlan, displays: [DisplaySnapshot]) {
        decoders = plan.sources.count
        var per: [DisplayKey: String] = [:]
        for display in displays {
            let sid = SurfaceID.desktop(display.key)
            guard let surface = plan.surfaces[sid] else {
                per[display.key] = "Empty"
                continue
            }
            switch surface.run {
            case .playing:
                if case let .source(key, _) = surface.content, let source = plan.sources[key] {
                    let fps = source.budget.maxFPS.map { "\($0) fps" } ?? "native"
                    per[display.key] = "Playing · \(fps)"
                } else {
                    per[display.key] = "Playing"
                }
            case .paused(let reasons):
                per[display.key] = reasons.label
            case .idle:
                if case .failed(let msg) = surface.content {
                    per[display.key] = "Failed: \(msg)"
                } else {
                    per[display.key] = "Empty"
                }
            }
        }
        perDisplay = per
        if plan.sources.values.contains(where: \.running) {
            headline = "Lumina · \(decoders) decoder\(decoders == 1 ? "" : "s")"
        } else if let first = per.values.first(where: { $0.hasPrefix("Paused") }) {
            headline = first
        } else {
            headline = "Lumina · idle"
        }
    }
}
