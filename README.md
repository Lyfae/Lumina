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

## Building & Running the Prototype (Working Now!)

```bash
swift build
.build/debug/Lumina
```

A menu bar icon (🌊) will appear with **no Dock icon**. This is intentional.

### How to see a real live wallpaper right now

1. Run the binary above.
2. Click the 🌊 icon in the menu bar → **Load Video…**
3. Choose any `.mp4`, `.mov`, or `.m4v` file on your Mac (best results: 1080p or 4K, smooth looping footage, preferably muted).
4. The video instantly becomes your desktop wallpaper on **every monitor**, behind all windows and icons.

**Power intelligence is already active:**
- Enable **Low Power Mode** in System Settings → Battery → the wallpaper pauses automatically.
- Do something CPU/thermal heavy → it throttles or pauses.
- Go into a **fullscreen app** (YouTube, games, full-screen Xcode, Zoom, etc.) → wallpaper **automatically pauses**.
- The last video you chose is now **remembered** and will automatically reload the next time you launch Lumina (or after login).
- Click the menu bar icon → "Pause / Resume" for manual control. You can also "Reload Last Video" or "Clear Saved Wallpaper".

This is the core promise of Lumina already working in prototype form.

### Important Prototype Notes

- The windows are created at the correct desktop level using the same techniques as the best existing Mac wallpaper apps.
- Looping uses `AVPlayerLooper` (seamless, hardware-accelerated on Apple Silicon).
- Currently one video is shared across all displays. Per-display wallpapers come later.
- Close the app (Quit from the menu) to stop the wallpaper.

**Testing note:**  
`swift test` may fail on minimal Command Line Tools installs because XCTest / Swift Testing modules are provided by a full Xcode installation. Open the package in Xcode (File → Open Package) for the best development experience.

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
