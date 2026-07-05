<p align="center">
  <img src="Sources/Lumina/Resources/Icons/LuminaAppIcon.png" width="160" height="160" alt="Lumina Studio">
</p>

<h1 align="center">Lumina Studio</h1>

<p align="center">
  <strong>Native live wallpapers for macOS — per-display control, battery-aware playback, and a studio-grade editing workflow.</strong>
</p>

<p align="center">
  <a href="https://github.com/Lyfae/Lumina/releases"><img src="https://img.shields.io/github/v/release/Lyfae/Lumina?color=3b82f6&label=Download" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-1e293b" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-f97316" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-22c55e" alt="MIT License">
</p>

---

**Lumina Studio** is a menu-bar application that turns your Mac desktop into a living canvas. Set independent live video, animated GIF, or image slideshow wallpapers on every display — with real-time preview, precise crop, visual effects, ambient audio, and power-smart playback that knows when to pause.

Built entirely in Swift and AppKit/SwiftUI. No Electron. No web views. No subscription.

---

## Highlights

| | |
|---|---|
| **Per-display control** | Independent wallpaper, crop, speed, effects, and volume for each monitor |
| **Live preview workflow** | Stage changes on a WYSIWYG preview, then commit with **Apply to Wallpaper** |
| **Battery-aware engine** | Auto-pauses on Low Power Mode, thermal pressure, fullscreen apps, and occlusion |
| **Display-adaptive UI** | Windows and icons scale to your screen size — readable on 13″ laptops and 27″ displays |
| **Native performance** | Hardware-accelerated video via AVFoundation; GPU filters via Core Image |

---

## Install

### Download (recommended)

1. Open **[Releases](https://github.com/Lyfae/Lumina/releases)** and download the latest `Lumina-x.y.z.dmg`
2. Open the DMG and drag **Lumina** into **Applications**
3. Launch Lumina — it lives in the menu bar (no Dock icon)

> **First launch:** macOS may show a security prompt for an unsigned build. Right-click the app → **Open**, or allow it in **System Settings → Privacy & Security**.

### Build from source

```bash
git clone https://github.com/Lyfae/Lumina.git
cd Lumina
./run                    # fast local build → dist/Lumina.app
# or
./scripts/build-dmg.sh   # release DMG in dist/
```

**Requirements:** macOS 15 (Sequoia) or later, Xcode Command Line Tools, Swift 6.

---

## Quick start

1. Click the **Lumina** menu-bar icon → **Lumina Studio** (`⌘M`)
2. Select a display in the monitor layout
3. **Add to Library** — choose a video, GIF, or still image
4. Click a thumbnail to load it into the preview panel
5. Tune brightness, crop, speed, scaling, and effects
6. Click **Apply to Wallpaper** to set it live on that display

**Tips**

- Pin wallpapers with **Keep on startup** so they restore after reboot
- Use **Sync playback across displays** to align matching videos
- Minimize the Studio window to show the floating ambient-audio widget (optional, in Settings)

---

## Features

### Media

- **Video** — MP4, MOV, M4V, MKV, WebM, AVI (hardware-accelerated)
- **Animated GIF** — smooth looping via ImageIO + Core Animation
- **Still images** — PNG, JPEG, HEIC, WebP, TIFF
- Per-display volume, playback speed (0.25×–4×), loop modes, and crossfade

### Visual editing

- Real-time brightness, saturation, hue, opacity, and grayscale
- Inline crop editor with draggable handles and video scrubber
- GPU-accelerated Core Image filters
- Crop position preserved when re-entering the editor

### Slideshows

- Drag-and-drop image queue with reordering
- Adjustable interval (3–60 s) and transitions (fade / cut)
- Optional Ken Burns pan-and-zoom

### Multi-display

- Independent settings per monitor
- Physical layout picker with live thumbnails
- Sync playback across displays

### Library & persistence

- Auto-saved library with search and favorites
- Per-monitor **Keep on startup** pinning
- Security-scoped bookmarks for reliable file access across relaunches

### Power & performance

- Auto-pause on Low Power Mode, high thermal state, fullscreen apps, and window occlusion
- Performance profiles: Battery / Balanced / High Quality
- Built-in video re-encoding with progress and size estimates

### Audio

- Independent ambient music player (MP3 and common formats)
- Transport controls, loop toggle, and track queue
- Floating mini-player when the Studio window is minimized

---

## Screenshots

_Add screenshots here before the next public release — suggested captures:_

- Main Studio window with library + monitor layout
- Live preview panel with effects sliders
- Crop editor in action
- Multi-monitor setup with different wallpapers per display
- Menu-bar icon and launch splash

---

## Development

```bash
# Debug build
swift build

# Run headless self-tests (31 checks — engine, crop math, semver, etc.)
.build/debug/Lumina --self-test

# Rebuild app bundle and launch
./run

# Release DMG (arm64)
./scripts/build-dmg.sh

# Universal binary
ARCH=universal ./scripts/build-dmg.sh

# Signed release (Developer ID certificate required)
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh
```

Distribution, signing, and notarization: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)

### Project layout

```
Sources/Lumina/
├── main.swift                  # App entry, menu bar, lifecycle
├── AssignmentStore.swift       # Per-monitor persistence
├── WallpaperManagerStore.swift # UI state + library
├── DisplayScale.swift          # Display-adaptive sizing
├── WallpaperEngine/            # VideoRenderer, SlideshowEngine, PowerManager, …
└── Views/                      # Studio UI, preview, crop, settings, splash
```

Architecture notes: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## Roadmap

- [x] Core live wallpaper engine (video, GIF, image)
- [x] Multi-monitor support with independent settings
- [x] Release splash, branding, and display-adaptive UI (v0.2)
- [ ] Signed + notarized DMG and in-app auto-updates (v1.0)
- [ ] Homebrew Cask
- [ ] Time-based wallpaper scheduling

Full plan: [docs/ROADMAP.md](docs/ROADMAP.md)

---

## Contributing

Issues and discussions are welcome.

- **Bug reports:** [GitHub Issues](https://github.com/Lyfae/Lumina/issues) — include macOS version, steps to reproduce, and debug output (`⌘D` → Print Status)
- **Feature ideas:** [GitHub Discussions](https://github.com/Lyfae/Lumina/discussions)
- **Guidelines:** [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)

---

## License

[MIT](LICENSE) — Copyright © 2026 Lumina Contributors
