<p align="center">
  <img src="Sources/Lumina/Resources/Icons/LuminaMenuIcon@2x.png" width="72" alt="Lumina">
</p>

<h1 align="center">Lumina Studio</h1>

<p align="center">
  <strong>Native live wallpaper engine for macOS — free, fast, and beautiful.</strong>
</p>

<p align="center">
  <a href="https://github.com/Lyfae/Lumina/releases"><img src="https://img.shields.io/github/v/release/Lyfae/Lumina?color=blue&label=Download" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <img src="https://img.shields.io/badge/Dock%20icon-none-lightgrey" alt="Menu-bar only">
</p>

---

Lumina Studio brings the best of Wallpaper Engine to the Mac — completely native, completely free, and built to run 24/7 without draining your battery. Set live video wallpapers, animated GIFs, or image slideshows on every display independently, then tune every detail from a single polished interface.

---

## Install

**Easiest — download the DMG:**

1. Go to [Releases](https://github.com/Lyfae/Lumina/releases) and download `Lumina-x.y.z.dmg`
2. Open the DMG, drag **Lumina** into **Applications**
3. Launch Lumina — look for its icon in the menu bar

> Lumina is a menu-bar app. No Dock icon, no bloat.

**Build from source:**

```bash
git clone https://github.com/Lyfae/Lumina.git
cd Lumina
swift build -c release --arch arm64
./scripts/build-dmg.sh          # produces dist/Lumina-1.0.0.dmg
```

Requirements: macOS 13+, Xcode Command Line Tools, Swift 6

---

## Features

### Playback
| Feature | Detail |
|---|---|
| **Video wallpapers** | MP4, MOV, M4V, MKV, WebM, AVI and more |
| **Animated GIFs** | Smooth native loop via AVFoundation |
| **Static images** | PNG, JPEG, HEIC, WebP, TIFF |
| **Seamless looping** | AVQueuePlayer + AVPlayerLooper — zero-gap |
| **Loop crossfade** | Fade between loop points (0.25 s – 5 s) |
| **Playback speed** | 0.25× – 4.0× per display |
| **Loop modes** | Loop continuously, Play once, or Bounce (forward ↔ reverse) |
| **Video audio** | Per-display volume control (defaults to muted) |

### Visual Effects
| Effect | Range |
|---|---|
| **Brightness** | −50 % to +50 % |
| **Opacity** | 0 – 100 % |
| **Saturation** | 0 (grayscale) – 200 % (vivid) |
| **Hue rotation** | −180 ° to +180 ° |
| **Grayscale** | One-tap toggle |

All effects are GPU-accelerated via Core Image filters — zero CPU overhead.

### Crop & Zoom
- Draggable crop rectangle with four corner handles
- Stays within bounds, clamped at all edges
- Video preview scrubber for frame-accurate crop setup
- "Reset to Full" one-click

### Performance & Compression
- **Video compression** — Re-encode any wallpaper to 4K / 1080p / 720p / 480p using Apple's hardware encoder (fast on Apple Silicon)
- Shows current file size, resolution, and duration
- Estimated output size before you start
- Live progress bar with cancel support
- Compressed files saved to `~/Library/Application Support/Lumina/Compressed/`

### Multi-Monitor
- Independent wallpaper and settings on every display
- Visual monitor selection cards with highlight bounding box
- "Configuring S2 • Built-in Retina Display" header always shows active target
- Sync playback across displays — keeps all videos in lockstep at the same frame
- Per-monitor brightness, crop, speed, and effects

### Library & Favorites
- Drag-and-drop or file picker to add wallpapers
- Filter by **All / Video / Image / GIF / ★ Starred**
- Search by filename
- Star any wallpaper — persists across launches
- Right-click context menu: Set as Wallpaper / Favourite / Remove
- Library items cached between sessions (never need to re-add)

### Ambient Audio
- Add an unlimited number of MP3, AAC, or FLAC tracks to a persistent music library
- Scrollable library strip in the footer — click any chip to play it
- Per-track volume and loop toggle
- Plays independently of video audio
- Remembers last track and position between launches

### Slideshow
- Add multiple images to any display's slideshow queue
- Configurable interval (3 s – 60 s)
- Fade or cut transition
- Remove individual images from the queue

### Power Management
- Auto-pause on Low Power Mode
- Auto-pause on high thermal pressure
- Auto-pause when fullscreen apps are active
- Performance profiles: Maximum Battery / Balanced / High Quality
- Resumes automatically when conditions clear

### UI / UX
- **Lumina Studio** — clean two-column layout
- Collapsible settings sections with SF Symbol icons
- **9 accent colour themes**: System, Ocean, Aurora, Blossom, Ember, Sunset, Gold, Forest, Teal
- Filter tabs with full-area hit targets and underline selection indicator
- Hover cards showing quick-action overlay (apply, favourite)
- Settings snap instantly when switching displays — no animated glitch
- **Reset Settings** button restores all effects to defaults
- Tooltips on every non-obvious control
- Loop mode description shown live below the mode picker
- Pure menu-bar accessory app — no Dock icon

---

## Quick Start

1. Click the Lumina icon in the menu bar → **Lumina Studio…** (`⌘M`)
2. Click **Choose Display…** and select a monitor
3. Click **Add to Library** (bottom of the library panel) and pick a video or image
4. Click any thumbnail to apply it to the selected display immediately
5. Tune brightness, speed, crop, and effects in the right panel

---

## Building a DMG

```bash
# Default: arm64 release, unsigned
./scripts/build-dmg.sh

# Universal binary (arm64 + x86_64)
ARCH=universal ./scripts/build-dmg.sh

# Signed (requires Developer ID certificate in keychain)
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh

# Custom version
VERSION=1.2.0 BUILD_NUMBER=42 ./scripts/build-dmg.sh
```

The script builds a release binary, assembles a proper `.app` bundle with `Info.plist` and icons, optionally signs it, and produces `dist/Lumina-x.y.z.dmg` with a drag-to-Applications layout.

For notarization:
```bash
xcrun notarytool submit dist/Lumina-1.0.0.dmg --keychain-profile AC_PASSWORD --wait
xcrun stapler staple dist/Lumina-1.0.0.dmg
```

---

## Architecture

```
Sources/Lumina/
├── main.swift                          # App entry, menu bar, LuminaApp delegate
├── AssignmentStore.swift               # Dual-bucket persistence (monitor + library)
├── WallpaperManagerStore.swift         # View model / presenter layer
├── Models/
│   ├── MonitorAssignment.swift         # All per-monitor settings
│   ├── AppTheme.swift                  # 9 accent themes
│   └── FavoritesManager.swift
├── WallpaperEngine/
│   ├── VideoRenderer.swift             # AVQueuePlayer, crop, color effects
│   ├── VideoCompressor.swift           # AVAssetExportSession transcoding
│   ├── SlideshowEngine.swift           # Timer-driven image cycling
│   ├── AmbientAudioManager.swift       # Persistent music library
│   ├── PowerManager.swift
│   └── FullscreenDetector.swift
└── Views/
    ├── WallpaperManagerView.swift      # Main two-column UI, library grid
    ├── MonitorDetailPanel.swift        # Per-monitor settings (collapsible sections)
    ├── ChooseDisplayView.swift         # Monitor selection cards
    ├── WallpaperPreview.swift          # Live video preview + crop overlay
    └── CropRectangle.swift             # Draggable crop editor
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for deeper design decisions.

---

## Roadmap

- [ ] **v1.0** — Signed + notarized DMG, Sparkle auto-update
- [ ] Homebrew Cask formula
- [ ] iCloud library sync
- [ ] Playlist mode (multiple wallpapers cycling per display)
- [ ] Schedule wallpapers by time of day
- [ ] HDR video support
- [ ] Metal shader / particle wallpapers

See [docs/ROADMAP.md](docs/ROADMAP.md) for the detailed plan.

---

## Contributing

Pull requests are welcome. See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

Bug reports → [GitHub Issues](https://github.com/Lyfae/Lumina/issues)  
Feature ideas → [Discussions](https://github.com/Lyfae/Lumina/discussions)

---

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">Made with ♥ for macOS</p>
