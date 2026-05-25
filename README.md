# Lumina

**Native, ultra-low-power live wallpaper engine for macOS.**

Lumina brings the beloved experience of Wallpaper Engine (Windows/Steam) to the Mac — but fully native, completely free, open source, and obsessively engineered for minimal battery/CPU impact so it can run 24/7 without affecting your real work.

## Current Status (Early Development)

This project is in active bootstrapping / MVP phase.

**What works today:**
- Pure menu-bar accessory app (no Dock icon, `LSUIElement` / `.accessory` policy)
- Clean Swift 6 + SPM structure targeting latest macOS (Tahoe+)
- Placeholder status item with basic menu

**Next immediate goals (see the approved implementation plan):**
- PowerManager (smart pause on Low Power Mode, thermal, fullscreen, battery)
- DesktopWallpaperWindow at the proper window level behind icons
- Hardware-accelerated video renderer (AVFoundation + AVPlayerLooper) as the first content type

See the detailed plan here (internal):
`/Users/lyfae/.grok/sessions/%2FUsers%2Flyfae%2FDocuments%2Fgithub%2Fwallpaper/019e5d9d-f1bf-7d01-940d-20d1e9703497/plan.md`

## Why Another Wallpaper App?

Most Mac "live wallpaper" solutions are either:
- Paid one-time purchases with high OTP ($30+)
- Electron-based (higher baseline cost)
- Video-only with no intelligence around power/thermal/fullscreen

Lumina is different: **the power & performance manager is a first-class citizen**. The app will aggressively (but respectfully) pause or throttle when it would otherwise interfere with foreground work, video calls, gaming, or battery life.

## Building & Running (Development)

```bash
swift build
.build/debug/Lumina
```

The binary will appear as a menu bar icon (🌊 placeholder) with no Dock presence.

**Testing note:**  
`swift test` may fail on minimal Command Line Tools installs because XCTest / Swift Testing modules are provided by a full Xcode installation. Open the package in Xcode (File → Open Package) for the best development experience — tests, SwiftUI previews, and signing all work there.

For pure CLI validation of the engine logic you can still build the main product at any time with `swift build`.

For a more app-like experience during development you can later wrap it or simply `open` a generated .app (future release scripts will handle proper bundling + notarization).

## Roadmap (High Level)

See the full phased plan for details.

1. MVP: Video wallpapers + excellent PowerManager + basic library
2. v1: Images + Web (WKWebView) + hotkeys + per-wallpaper settings
3. v1.5+: Lightweight custom scenes (SpriteKit / Metal) + creator docs
4. Polish, community sharing format, Homebrew cask, etc.

## Contributing

This is currently a solo/greenfield effort. Once the core engine is solid and the first public release ships, contributions (especially efficient renderers, power heuristics, and beautiful low-cost wallpaper examples) will be very welcome.

## License

MIT (once we ship the first real code).

---

Built with ❤️ for people who love beautiful desktops but hate killing their MacBook battery.
