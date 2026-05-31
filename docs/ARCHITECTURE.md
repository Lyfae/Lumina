# Lumina Architecture

This document describes the high-level architecture of Lumina, a native macOS live wallpaper engine.

## Core Principles

- **Native first**: Built with Swift, AppKit/SwiftUI, AVFoundation, and Metal/SpriteKit where needed.
- **Battery & performance first**: The `PowerManager` is a first-class citizen.
- **Per-monitor design**: Each display should be independently configurable.
- **User-friendly for all levels**: The Wallpaper Manager should feel approachable while offering power-user features.
- **Fail-safe by default**: The system should degrade gracefully (black screen, clear errors, easy reset).

## High-Level Components

### 1. Application Layer (`LuminaApp`)
- Menu-bar-only accessory app (`LSUIElement`).
- Owns the status item, global menu, and window management.
- Hosts the `AssignmentStore` and coordinates between the manager and the engine.

### 2. Wallpaper Engine (`WallpaperEngine/`)
- `DesktopWallpaperWindow`: Borderless, non-activating windows placed at the desktop window level. Supports live `updateFrame` for display reconfiguration.
- `AVVideoRenderer`: The single per-display renderer. Dispatches by `MediaType`:
  - **Video** → `AVQueuePlayer` + `AVPlayerLooper` (seamless loops, hardware decode).
  - **Static image** → `CALayer` contents, decoded at display resolution via ImageIO.
  - **Animated GIF** → ImageIO frames driven by a discrete `CAKeyframeAnimation`.
  - **Slideshow** → owns a `SlideshowEngine` that cycles images on the host layer.
  - All paths share scaling, crop (pure `expandedVideoFrame` / `imageContentsRect` transforms), opacity, brightness, color correction, and loop-fade.
- `SlideshowEngine`: Timer-driven image playlist with crossfade transitions.
- `PowerManager`: Observes system power/thermal/low-power state and decides the global playback policy (normal / throttled / paused). No polling — notification-driven.
- **Occlusion-based per-display pausing** (in `LuminaApp`): native `NSWindow` occlusion (`didChangeOcclusionStateNotification` + launch seed + app-activation/space-change re-checks) pauses only the display a fullscreen app actually covers. This replaced the old `CGWindowList`-polling `FullscreenDetector` (kept in-tree as a revert fallback, no longer wired).
- `VideoCompressor`: Optional transcoding to lighter resolutions; outputs are permanent (never auto-deleted).

### 3. Wallpaper Manager (SwiftUI)
- Located in `Views/`.
- `WallpaperManagerView`: Main view with spatial monitor layout + side panel.
- `MonitorLayoutView`: Visual representation of physical monitor arrangement.
- `MonitorDetailPanel`: Per-monitor settings (scaling, crop, keep on startup, etc.).
- `WallpaperManagerStore`: UI-facing store that talks to `AssignmentStore`.

### 4. Data & Persistence Layer
- `MonitorAssignment`: Core model for per-monitor configuration (media, scaling, crop, persistence flags).
- `AssignmentStore`: Central store for loading/saving assignments with fail-safes.
- Uses security-scoped bookmarks + relative file paths for reliable local file access.

### 5. Models
- `MonitorInfo`: Lightweight display representation for the UI.
- `StoredAssignment`: Compact format used for persistence.

## Data Flow (Simplified)

1. User opens **Wallpaper Manager** (⌘M).
2. `WallpaperManagerStore` loads current monitors via `NSScreen`.
3. User selects a monitor → side panel opens.
4. User chooses media + settings → `MonitorAssignment` is created/updated.
5. Assignment is saved via `AssignmentStore` (if "Keep on startup" is enabled).
6. `LuminaApp` applies the assignment to the corresponding `AVVideoRenderer`.
7. On next launch, `AssignmentStore` restores assignments where `keepOnStartup == true`.

## Display Reconfiguration

`LuminaApp.reconcileDisplays()` (debounced behind `didChangeScreenParameters` and wake-from-sleep)
keeps the window/renderer set in sync with the live display set, keyed by `CGDirectDisplayID`:
displays still present are reused (geometry refreshed via `updateFrame` / `relayout`), newly attached
displays get fresh surfaces with their in-session assignment restored, and removed displays are torn
down (including their occlusion observers). This is what makes hot-plug / dock / rearrange reliable.

## Testing

`Lumina --self-test` runs a headless suite (`SelfTest.swift`) validating the rendering/decoding
pipeline, downsampling, GIF decode, persistence round-trip + schema resilience, and crop geometry —
no WindowServer required. On-screen compositing and `NSWindow` occlusion still need a real session
to verify; use the **⌘D Debug status** (per-display occlusion + what each display renders) for that.

## Future Directions

- Web / shader / procedural wallpapers
- Drag-to-crop editor with real-time feedback
- Audio-reactive effects
- Per-monitor effects/crop applied to slideshow images
- Decoder release on sustained global pause (memory) if measured worthwhile

## Technology Choices

- **Swift 6** + strict concurrency
- **SwiftUI** for the manager (modern, declarative, easier to iterate)
- **AppKit** for the core wallpaper windows and status item (full control over window levels)
- **AVFoundation** for video playback (hardware decode + `AVPlayerLooper`)
- **UserDefaults + JSON** for lightweight persistence (with bookmark data)

---

This document will evolve as the architecture matures.