# Lumina

**A native, ultra-low-power live wallpaper engine for macOS.**

Lumina aims to bring the beloved experience of Wallpaper Engine (Windows) to the Mac — fully native, free, open source, and obsessively engineered to run 24/7 with minimal impact on battery and performance.

## Vision

- Truly native (Swift + AppKit/SwiftUI + AVFoundation/Metal/SpriteKit)
- Extremely battery and CPU friendly
- Per-monitor wallpaper support with independent settings
- Rich media support (videos, images, GIFs, future procedural content)
- Smart power management (auto-pauses on fullscreen, Low Power Mode, thermal load, etc.)
- Beautiful, accessible UI for users of all technical levels

## Current Status

**Phase:** Active redesign of the Wallpaper Manager (per-monitor support)

The core engine is functional:
- Menu-bar-only accessory app
- Hardware-accelerated video playback with seamless looping
- Smart `PowerManager` (Low Power Mode, thermal, fullscreen detection)
- Per-screen `DesktopWallpaperWindow` at the correct desktop window level
- Basic per-monitor assignment system (in development)
- Persistence via security-scoped bookmarks + file paths

The new **Wallpaper Manager** (SwiftUI) is being rebuilt with:
- Visual physical monitor layout
- Per-monitor video/image assignment
- Scaling + crop controls
- "Keep on startup" per monitor
- Live preview in the detail panel (in progress)

See the [Roadmap](#roadmap) for upcoming milestones.

## Getting Started

### Prerequisites

- macOS 15+ (best on macOS 26 Tahoe+)
- Swift 6.3+ (Xcode Command Line Tools or full Xcode recommended)
- Git

### Quick Start

```bash
git clone https://github.com/Lyfae/Lumina.git
cd Lumina
./scripts/setup.sh
```

Or manually:

```bash
swift build
.build/debug/Lumina
```

A menu bar icon will appear. Use **Wallpaper Manager… (⌘M)** to configure per-monitor wallpapers.

## Documentation

- **[Architecture](docs/ARCHITECTURE.md)** — High-level design and component overview
- **[Roadmap](docs/ROADMAP.md)** — Current phase and future plans
- **[Prototype Testing Guide](docs/PROTOTYPE_TESTING.md)** — How to validate performance with Instruments
- **[Contributing](docs/CONTRIBUTING.md)** — How to help

## Building

The project uses Swift Package Manager.

```bash
swift build
```

For development with Xcode:

```bash
open Package.swift
```

## Running

```bash
.build/debug/Lumina
```

Lumina runs as a menu-bar-only accessory app (no Dock icon).

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for the detailed phased plan.

High-level milestones:

- **Phase 1 (Current):** Functional per-monitor Wallpaper Manager with spatial layout, basic settings, and persistence.
- **Phase 2:** Live preview + crop editor in the manager, unified media renderer (images + video).
- **Phase 3:** Rich media support, transitions, playlists, better power heuristics.
- **Phase 4:** Polish, distribution (Homebrew, GitHub Releases), community features.

## Contributing

This project is currently in active solo development. Contributions are welcome once the core architecture stabilizes.

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) (coming soon).

## License

MIT License

---

Built with care for people who want beautiful desktops without sacrificing battery life.