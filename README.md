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
  <img src="https://img.shields.io/badge/status-production-lightgreen" alt="Production Ready">
</p>

---

Lumina Studio brings cinematic live wallpapers to the Mac — completely native, completely free, and built to run 24/7 without draining your battery. Set live video wallpapers, animated GIFs, or image slideshows on every display independently.

---

## Install

**Recommended — Download the DMG:**

1. Go to [Releases](https://github.com/Lyfae/Lumina/releases) and download the latest `Lumina-x.y.z.dmg`
2. Open the DMG and drag **Lumina** into **Applications**
3. Launch Lumina — it appears in the menu bar

**Build from source:**

```bash
git clone https://github.com/Lyfae/Lumina.git
cd Lumina
swift build -c release --arch arm64
./scripts/build-dmg.sh          # produces dist/Lumina-x.y.z.dmg
```

Requirements: macOS 15+, Xcode Command Line Tools, Swift 6.

---

## Quick Start

1. Click the Lumina icon in the menu bar → **Lumina Studio** (`⌘M`)
2. Select a display using the monitor layout
3. Click **Add to Library** and choose a video, GIF, or image
4. Click any thumbnail to preview
5. Adjust brightness, crop, speed, and effects
6. Click **Apply to Wallpaper** to set it live

---

## Features

### Media Support
- **Video**: MP4, MOV, M4V, MKV, WebM, AVI (hardware accelerated)
- **Animated GIFs**: Smooth looping via ImageIO + Core Animation
- **Images**: PNG, JPEG, HEIC, WebP, TIFF + slideshow support
- Per-display volume, playback speed (0.25×–4×), loop modes, and crossfade

### Visual Controls
- Real-time brightness, saturation, hue, opacity, and grayscale
- Inline crop editor with live preview and video scrubber
- GPU-accelerated Core Image filters

### Slideshows
- Drag & drop image queue with reordering
- Adjustable interval (3–60s) and transitions (Fade/Cut)
- Optional Ken Burns cinematic pan & zoom effect

### Multi-Display
- Independent settings per monitor
- Visual display picker with physical layout
- Sync playback across all displays

### Library & Persistence
- Auto-saved library with search and favorites
- "Keep on startup" per-monitor pinning
- Security-scoped bookmarks for reliable file access

### Performance & Power
- Auto-pause on Low Power Mode, thermal pressure, or fullscreen apps
- Performance profiles (Battery / Balanced / High Quality)
- Hardware video re-encoding with progress and size estimation

### Audio
- Independent ambient music player (MP3 and common formats)
- Footer transport + collapsible queue
- Floating mini-player when the main window is minimized

---

## Screenshots

> **Note**: Add screenshots here before final release (main window, crop editor, settings, multi-monitor view).

---

## Building & Distribution

```bash
# Standard arm64 release DMG
./scripts/build-dmg.sh

# Universal binary
ARCH=universal ./scripts/build-dmg.sh

# Signed release (requires Developer ID certificate)
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh
```

See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for notarization and Sparkle update instructions.

---

## Architecture

```
Sources/Lumina/
├── main.swift
├── AssignmentStore.swift
├── WallpaperManagerStore.swift
├── Models/
├── WallpaperEngine/          # VideoRenderer, SlideshowEngine, PowerManager, etc.
└── Views/                    # Main UI, preview, crop, settings
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design notes.

---

## Roadmap

- [x] Core live wallpaper engine (video + GIF + image)
- [x] Multi-monitor support with independent settings
- [ ] Signed + notarized DMG + Sparkle auto-updates (v1.0 target)
- [ ] Homebrew Cask
- [ ] iCloud sync
- [ ] Time-based wallpaper scheduling

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full plan.

---

## Contributing

Pull requests are welcome. Please read [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

- Bug reports: [GitHub Issues](https://github.com/Lyfae/Lumina/issues)
- Feature ideas: [GitHub Discussions](https://github.com/Lyfae/Lumina/discussions)

---

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">Made with ♥ for macOS</p>
