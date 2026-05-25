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
- `DesktopWallpaperWindow`: Borderless, non-activating windows placed at the desktop window level.
- `VideoRenderer` (and future `ImageRenderer`): Handles playback and layer hosting using `AVPlayerLayer`.
- `PowerManager`: Observes system power/thermal state and decides when to pause or throttle.
- `FullscreenDetector`: Uses `CGWindowList` to detect when a fullscreen app is active.

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

## Future Directions

- Unified media renderer (images + video + future procedural content)
- Live preview inside the manager
- Drag-to-crop editor with real-time feedback
- Transitions between wallpapers
- Playlist / multi-file support per monitor

## Technology Choices

- **Swift 6** + strict concurrency
- **SwiftUI** for the manager (modern, declarative, easier to iterate)
- **AppKit** for the core wallpaper windows and status item (full control over window levels)
- **AVFoundation** for video playback (hardware decode + `AVPlayerLooper`)
- **UserDefaults + JSON** for lightweight persistence (with bookmark data)

---

This document will evolve as the architecture matures.