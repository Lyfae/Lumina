# Lumina

**Native, ultra-low-power live wallpaper engine for macOS.**

Lumina brings the beloved experience of Wallpaper Engine (Windows/Steam) to the Mac — but fully native, completely free, open source, and obsessively engineered for minimal battery/CPU impact so it can run 24/7 without affecting your real work.

## Current Status (Early Development)

This project is in active bootstrapping / MVP phase.

**What works today (prototype improved with UX + debug support):**
- Pure menu-bar accessory app (no Dock icon, `LSUIElement` / `.accessory` policy)
- Clean Swift 6 + SPM structure targeting latest macOS (Tahoe+)
- Full working engine: `AVVideoRenderer` (seamless `AVPlayerLooper`), `PowerManager` (LPM + thermal + fullscreen intelligence), `DesktopWallpaperWindow` (correct desktop layering on all screens), `FullscreenDetector`, bookmark-based persistence with fallback.
- **Improved UX (B)**: Dynamic menu showing current video filename, "Clear Current Wallpaper" (stop playback, keep persistence), helpful "no video loaded" state, "About / Status…" dialog with live policy + instructions, simple power toggles in menu, highly informative status bar icon (🌊 / 🌊○ / 🌊⏱ / 🌊⏸ + rich tooltips), "Debug: Print Status" (⌘D).
- **Hardware verification support (C)**: In-app debug menu + status, plus comprehensive `docs/PROTOTYPE_TESTING.md` with Instruments guidance and checklist.

The core low-power promise is already demonstrable on real hardware.

See the detailed plan (internal) for full phased roadmap.

## Why Another Wallpaper App?

Most Mac "live wallpaper" solutions are either:
- Paid one-time purchases with high OTP ($30+)
- Electron-based (higher baseline cost)
- Video-only with no intelligence around power/thermal/fullscreen

Lumina is different: **the power & performance manager is a first-class citizen**. The app will aggressively (but respectfully) pause or throttle when it would otherwise interfere with foreground work, video calls, gaming, or battery life.

## Building & Running the Prototype (Working Now!)

**Recommended way:**
```bash
./scripts/setup.sh
```

This script now does much more:
- Checks your macOS and Swift versions
- Detects missing Command Line Tools and offers to install them
- Uses safe color output (auto-detects terminal support)
- Builds the project + prepares everything for testing

You can also run with `./scripts/setup.sh --no-color` if needed.

Manual alternative:
```bash
swift build
.build/debug/Lumina
```

A menu bar icon (🌊 or 🌊○) will appear with **no Dock icon**. This is intentional.

### How to see a real live wallpaper right now

1. Run the binary above.
2. Click the menu bar icon → **Load Video…** (⌘O).
3. Choose any local `.mp4`, `.mov`, or `.m4v` (best: 1080p/4K smooth looping footage, preferably muted or silent audio).
4. The video instantly becomes your desktop wallpaper on **every monitor**, behind all windows and icons.

**Power intelligence is already active:**
- Enable **Low Power Mode** → wallpaper pauses automatically.
- CPU/thermal heavy work → throttles or pauses.
- **Fullscreen app** (YouTube fullscreen, games, full-screen Xcode, Zoom, etc.) → wallpaper **automatically pauses**.
- Last video is **remembered** via security-scoped bookmarks + fallback and auto-restores on next launch.
- Manual controls: Pause/Resume (⌘P), Reload Last (⌘R), etc.

### New in This Prototype Update (Improved UX + Debug)

The menu is now much more useful:
- Always shows current wallpaper filename (or clear "No video loaded" guidance).
- **Clear Current Wallpaper**: instantly stops playback **without** clearing your saved bookmark.
- **About / Status…**: shows live loaded video, exact power policy, current settings, and quick instructions.
- Simple toggles for Low Power Mode and thermal pause behavior.
- **Debug: Print Status to Console** (⌘D): detailed dump of policy, per-renderer rates (for verifying throttling/FPS), flags, etc.
- Status bar icon + tooltip are highly informative and change with state (including no-video case).

See the full user-friendly changes in the menu when you run it.

**For real hardware testing and Instruments guidance, read:**
`docs/PROTOTYPE_TESTING.md`

It includes:
- Step-by-step MacBook verification instructions
- How to use Energy Diagnostics + CPU Profiler
- Detailed scenarios (LPM, thermal load, fullscreen, sleep/wake, multi-monitor)
- A ready-to-use **Verification Checklist**

### Important Prototype Notes

- Windows use the correct desktop window level (same techniques as top Mac wallpaper apps).
- Seamless looping via `AVPlayerLooper` (hardware accelerated on Apple Silicon).
- One video shared across displays for now (per-display support planned).
- Close via "Quit Lumina" (⌘Q) to stop everything cleanly.

**Testing note:**  
`swift test` may fail on minimal Command Line Tools installs (XCTest/Swift Testing require full Xcode). Open the package in Xcode for the best dev experience. Pure CLI builds always work with `swift build`.

---

## Demo Assets — Ready-to-Test Royalty-Free Videos

For immediate testing, run the setup script:

```bash
./scripts/setup.sh
```

This will build the project, create the samples folder, open recommended demo videos, and the testing guide.

**Top recommendations (subtle, calm, perfect for wallpapers, muted, excellent loops):**

- **Mixkit – Clouds and Blue Sky Background** (highly recommended)  
  https://mixkit.co/free-stock-video/clouds-and-blue-sky-background-2408/  
  Slow natural clouds. 4K available. **License**: Mixkit Free License — royalty-free for personal/commercial, **no attribution required**.

- **Mixkit – Multicolor Ink Swirls in Water**  
  https://mixkit.co/free-stock-video/multicolor-ink-swirls-in-water-286/  
  Calm abstract. Beautiful for desktops.

- **Pixabay** (search "looping 4k", "ocean loop", "abstract seamless"):  
  https://pixabay.com/videos/search/looping/  
  Many free 4K options. License: free personal + commercial, **no attribution** for most.

- **Pexels Videos**: https://www.pexels.com/search/videos/loop%20nature/ or "slow motion waves".

**One-command setup + browser helper (macOS):**

```bash
mkdir -p "$HOME/Movies/Lumina Samples" && \
cd "$HOME/Movies/Lumina Samples" && \
open "https://mixkit.co/free-stock-video/clouds-and-blue-sky-background-2408/" && \
open "https://mixkit.co/free-stock-video/multicolor-ink-swirls-in-water-286/" && \
open "https://pixabay.com/videos/search/looping%204k/" && \
echo "✅ Ready: ~/Movies/Lumina Samples/. Download MP4s from the pages and load via Lumina menu."
```

**Tips for best wallpaper results:**
- H.264 or H.265 (HEVC) for maximum efficiency on Apple Silicon.
- 1080p or 4K, 24–60 fps, short seamless loops (5–30s ideal).
- Lumina forces mute for wallpapers (audio support is future optional).

See full guidance + fallback options (GIFs etc.) in `docs/PROTOTYPE_TESTING.md`.

---

## Hardware Verification & Testing

See the complete guide:

**`docs/PROTOTYPE_TESTING.md`**

It covers everything needed to validate the low-power claims on real Mac hardware using Instruments and the built-in debug tools. Includes a printable Verification Checklist.

**Quick build verification:**
```bash
swift build
```

The prototype must build cleanly after every change.

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
