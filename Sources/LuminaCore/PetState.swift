import Foundation

/// Petdex / Codex atlas animation row.
public enum PetState: String, CaseIterable, Sendable, Hashable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review
}

extension PetState {
    /// Resolve JSON / atlas row names, including petdex aliases (`wave`/`waving`, `jump`/`jumping`, `run`/`running`).
    public static func fromRowKey(_ raw: String) -> PetState? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "idle", "sleep", "sleeping":
            return .idle
        case "running-right", "running_right", "runningright", "run-right", "run_right":
            return .runningRight
        case "running-left", "running_left", "runningleft", "run-left", "run_left":
            return .runningLeft
        case "waving", "wave":
            return .waving
        case "jumping", "jump":
            return .jumping
        case "failed", "fail", "error":
            return .failed
        case "waiting", "wait":
            return .waiting
        case "running", "run":
            return .running
        case "review", "held", "hold":
            return .review
        default:
            return PetState(rawValue: key)
        }
    }

    /// Map music playback signals → pet animation row (single source of truth for scrubber / widget).
    ///
    /// Priority: loadFailed → failed; no track → idle; dragging → run L/R (or review when held);
    /// transient wave → waving; jump pulse / didFinish → jumping; hover (not dragging) → review;
    /// playing → running; paused long → waiting; else idle.
    ///
    /// Transient flags (`isWaving`, `isJumping`, `pausedLong`) are time-based and owned by the view.
    public static func forPlayback(
        isPlaying: Bool,
        isDragging: Bool,
        dragDirection: Double,
        didFinish: Bool,
        loadFailed: Bool,
        hasTrack: Bool,
        isWaving: Bool = false,
        isJumping: Bool = false,
        isHovering: Bool = false,
        pausedLong: Bool = false
    ) -> PetState {
        if loadFailed { return .failed }
        if !hasTrack { return .idle }
        if isDragging {
            if dragDirection < 0 { return .runningLeft }
            if dragDirection > 0 { return .runningRight }
            return .review
        }
        if isWaving { return .waving }
        if isJumping || didFinish { return .jumping }
        if isHovering { return .review }
        if isPlaying { return .running }
        if pausedLong { return .waiting }
        return .idle
    }
}
