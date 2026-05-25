# Lumina Roadmap

This document outlines the current phase and future direction of Lumina.

## Current Phase: Wallpaper Manager Redesign (Phase 1)

**Goal**: Deliver a functional, user-friendly per-monitor wallpaper configuration experience.

### In Progress / Recently Completed

- [x] Move Wallpaper Manager to SwiftUI
- [x] Spatial (physical) monitor layout visualization
- [x] Side panel for per-monitor settings
- [x] Basic per-monitor video assignment
- [x] "Keep this on startup" toggle per monitor
- [x] Robust `MonitorAssignment` data model with bookmark + path support
- [x] `AssignmentStore` with fail-safe awareness
- [ ] Live preview inside the side panel
- [ ] Draggable crop + zoom editor with preview
- [ ] Proper per-monitor state restoration on launch
- [ ] Basic image support (static + GIF looping)

### Near-term Goals (Next 1–2 Iterations)

- Full end-to-end per-monitor persistence and restoration
- Live wallpaper preview inside the manager
- Functional crop rectangle editor
- Cleaner unification of `WallpaperManagerStore` and `AssignmentStore`
- Improved monitor identification (stable IDs across reconnects)

---

## Future Phases

### Phase 2: Media & Polish

- Unified renderer supporting images + video + animated GIFs
- Smooth transitions when changing wallpapers
- Per-monitor volume and mute controls
- Better error handling and fail-safes in the UI

### Phase 3: Advanced Features

- Playlist / folder support per monitor
- Subtle movement effects for static images
- Procedural / shader-based wallpapers (SpriteKit / Metal)
- Hotkeys and global shortcuts
- Multiple profiles or themes

### Phase 4: Distribution & Community

- Homebrew cask + GitHub Releases
- App icon and branding
- Documentation and contribution guide
- Community wallpaper sharing format (future)

---

## Guiding Principles

- **Battery & performance first**
- **Native and delightful**
- **Accessible to all users** (not just power users)
- **Fail-safe by default**
- **Per-monitor by design**

---

*This roadmap is living and will be updated as development progresses.*