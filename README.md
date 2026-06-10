<p align="center">
  <img src="Sources/Lumina/Resources/Icons/LuminaMenuIcon@2x.png" width="72" alt="Lumina">
</p>

<h1 align="center">Lumina Studio</h1>

<p align="center">
  <strong>Native live wallpaper engine for macOS — free, fast, and beautiful.</strong>
</p>

<p align="center">
  <a href="https://github.com/Lyfae/Lumina/releases"><img src="https://img.shields.io/github/v/release/Lyfae/Lumina?color=blue&label=Download" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <img src="https://img.shields.io/badge/Dock%20icon-none-lightgrey" alt="Menu-bar only">
</p>

---

Lumina Studio brings cinematic live wallpapers to the Mac — completely native, completely free, and built to run 24/7 without draining your battery. Set live video wallpapers, animated GIFs, or image slideshows on every display independently, then tune every detail from a single polished interface.

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

Requirements: macOS 15+, Xcode Command Line Tools, Swift 6

**Self-test (headless, no display required):**

```bash
swift build
.build/debug/Lumina --self-test   # 27 checks
```

---

## Quick Start

1. Click the Lumina icon in the menu bar → **Lumina Studio** (`⌘M`)
2. Click **Switch Display** and pick a monitor in the physical layout window
3. Click **Add to Library** and choose a video or image
4. Click any thumbnail to **preview** it on the selected display
5. Tune brightness, crop, speed, and effects in the right panel
6. Click **Apply to Wallpaper** to commit staged edits to the live desktop

---

## Lumina Studio

Lumina Studio is a resizable two-column control hub. The window remembers its size across launches and enforces a sensible minimum (960 × 720) so the layout never collapses.

| Area | What it does |
|---|---|
| **Library (left)** | Filterable grid of all wallpapers you've used — All / Video / Image / GIF / ★ Starred. Search by filename. Click to preview; hover for quick actions. |
| **Configuration (right)** | Live WYSIWYG preview, per-monitor settings, and the **Apply to Wallpaper** commit bar. |
| **Footer** | Ambient audio transport, volume, seek bar, and collapsible music queue. |
| **Header** | Search, **Sync Displays**, and **Settings** (gear icon). |

### Preview → Apply workflow

Edits in the right panel are **staged** — they update the live preview immediately but do not touch the desktop until you commit.

- The preview is resizable (drag the handle below it)
- Crop editing happens inline on the preview (crop button, top-right)
- **Apply to Wallpaper** turns green when there are uncommitted changes
- **Reset Adjustments** reverts staged values without touching the desktop
- **Keep this wallpaper on startup** (promoted toggle under the preview) pins the assignment for relaunch

### Settings sheet

Opened from the gear icon in the header. Covers app-wide preferences — distinct from per-monitor wallpaper settings.

| Section | Options |
|---|---|
| **Appearance** | Theme (Match System / Light / Dark), 9 accent colors |
| **General** | Launch at login, remember wallpapers on startup, sync playback across displays, show music widget when minimized |
| **Battery & Performance** | Pause in Low Power Mode, pause when running hot, pause behind fullscreen apps, performance profile (Maximum Battery / Balanced / High Quality) |
| **About & Help** | About & Status, Welcome, What's New |

### Slideshow builder

Configure a still-image slideshow per display from the **Slideshow** section in the right panel.

- **Drag & drop** images onto the queue canvas
- Pick images from your Library strip or via **Add Images…**
- Reorder by dragging rows in the queue
- Set interval (3 s – 60 s) and transition (Fade / Cut)
- **Ken Burns effect** — slow cinematic pan & zoom on each image (on by default)
- **Save & Play** commits immediately to the desktop

### Floating now-playing widget

When **Show music widget when minimized** is enabled in Settings, minimizing Lumina Studio pops a floating mini-player in the top-right corner. It mirrors the footer transport controls for ambient audio and can be dismissed independently.

### Theme & accessibility

- **Dark theme** uses pure black (`luminaBase`) and near-black cards (`luminaCard`) with high-contrast borders (`luminaBorder`) — dividers stay visible on black
- **9 accent themes**: System, Ocean, Aurora, Blossom, Ember, Sunset, Gold, Forest, Teal
- Accessibility labels on library filter tabs, wallpaper grid items, settings controls, and transport buttons

---

## Features

### Playback
| Feature | Detail |
|---|---|
| **Video wallpapers** | MP4, MOV, M4V, MKV, WebM, AVI and more |
| **Animated GIFs** | Smooth loop via ImageIO frame decode + `CAKeyframeAnimation` on a `CALayer` |
| **Static images** | PNG, JPEG, HEIC, WebP, TIFF |
| **Seamless looping** | AVQueuePlayer + AVPlayerLooper — zero-gap |
| **Loop crossfade** | Fade between loop points (0 – 5 s) |
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
- Inline crop editing directly on the live preview
- Draggable crop rectangle with four corner handles
- Video preview scrubber for frame-accurate crop setup
- "Reset to Full" one-click
- Window auto-grows when crop mode opens (if needed)

### Slideshow
| Feature | Detail |
|---|---|
| **Image queue** | Drag-drop, library picker, reorder |
| **Interval** | 3 s – 60 s per image |
| **Transition** | Fade or cut |
| **Ken Burns** | Slow cinematic pan/zoom per slide (toggleable) |

### Performance & Compression
- **Video compression** — Re-encode any wallpaper to 4K / 1080p / 720p / 480p using Apple's hardware encoder
- Shows current file size, resolution, and duration
- Estimated output size before you start
- Live progress bar with cancel support
- Compressed files saved to `~/Library/Application Support/Lumina/Compressed/`

### Multi-Monitor
- Independent wallpaper and settings on every display
- Visual monitor selection via floating physical layout window
- "Configuring S1 • Built-in Retina Display" header shows active target
- Sync playback across displays — restart all videos in lockstep
- Per-monitor brightness, crop, speed, and effects

### Library & Favorites
- Add wallpapers via file picker or slideshow builder (auto-saved to library)
- Filter by **All / Video / Image / GIF / ★ Starred**
- Search by filename
- Star any wallpaper — persists across launches
- Right-click context menu: Set as Wallpaper / Favourite / Remove
- Library items cached between sessions

### Ambient Audio
- Add MP3 and other standard audio formats (`.audio`, `.mp3`) to a persistent music library
- Footer transport bar with seek, skip, loop, and volume
- Collapsible queue panel with reorder and remove
- Plays independently of video audio
- Remembers last track and position between launches

### Power Management
- Auto-pause on Low Power Mode
- Auto-pause on high thermal pressure
- Auto-pause when fullscreen apps are active
- Performance profiles: Maximum Battery / Balanced / High Quality
- Resumes automatically when conditions clear

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
│   ├── AppTheme.swift                  # Accent themes, luminaBase/luminaCard dividers
│   ├── AppearanceManager.swift         # Light / Dark / Match System
│   ├── FavoritesManager.swift
│   └── MonitorInfo.swift
├── WallpaperEngine/
│   ├── VideoRenderer.swift             # AVQueuePlayer, crop, color effects
│   ├── VideoCompressor.swift           # AVAssetExportSession transcoding
│   ├── SlideshowEngine.swift           # Timer-driven cycling + Ken Burns
│   ├── AmbientAudioManager.swift       # Persistent music library
│   ├── PowerManager.swift
│   ├── FullscreenDetector.swift
│   └── DesktopWallpaperWindow.swift
└── Views/
    ├── WallpaperManagerView.swift      # Main two-column UI, library grid
    ├── MonitorDetailPanel.swift        # Per-monitor settings + WYSIWYG preview
    ├── SettingsView.swift              # App-wide preferences sheet
    ├── SlideshowConfigView.swift       # Slideshow builder sheet
    ├── NowPlayingWidget.swift          # Floating mini-player on minimize
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