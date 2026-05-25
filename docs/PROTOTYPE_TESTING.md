# Lumina Prototype — Hardware Verification & Testing Guide

**For early testers and developers verifying the low-power promise on real Mac hardware (especially MacBooks).**

This document accompanies the improved prototype (tasks B + C). It focuses on practical, repeatable testing using built-in macOS tools.

---

## 1. Running the Prototype for Testing

```bash
# From the project root
swift build
.build/debug/Lumina
```

- Menu bar icon appears (🌊 or 🌊○ when no video).
- No Dock icon (by design).
- Run from Terminal so you see rich `print()` logs (policy changes, loads, debug output).
- Recommended: keep Terminal + Activity Monitor + Instruments visible.

**Quick start with a video:**
1. Click menu bar icon → **Load Video…** (or ⌘O)
2. Pick any local `.mp4`/`.mov` (ideally 1080p/4K, 30–60 fps, preferably muted or silent).
3. It should appear instantly behind your desktop icons on all screens.

**New in this update (B + C UX/Debug):**
- Top of menu always shows **"Wallpaper: filename.mp4"** or **"No video loaded…"**.
- **Clear Current Wallpaper**: stops playback immediately but keeps your saved bookmark (use "Reload Last Video" to bring it back).
- **Clear Saved Wallpaper**: removes persistence (old behavior).
- **About / Status…**: live snapshot of loaded video + current policy + power settings + instructions. Buttons to print debug or open this guide.
- **Debug: Print Status to Console** (⌘D): detailed dump including per-renderer playback rate (great for verifying throttling).
- Simple toggles for "Pause on Low Power Mode" and "Pause on High Thermal" (changes take effect on next policy evaluation or via manual pause/resume).
- Status bar icon is now state-aware:
  - `🌊` = normal playback (video loaded)
  - `🌊○` = no video loaded / ready state
  - `🌊⏱` = throttled
  - `🌊⏸` = paused (with reason in tooltip)
- Tooltip on the icon always shows current filename + state when possible.

---

## 2. In-App Logging & Debug for Testers

- Console output is the primary debug channel (run from Terminal).
- Use **Debug → Print Status** frequently during tests.
- Policy transitions are logged by PowerManager: `[PowerManager] Policy changed → ...`
- Load/clear/persistence actions are logged.
- In `About / Status…` you get a human-readable summary without leaving the app.

These tools make verifying power behavior much easier than before.

---

## 3. Measuring Impact with Instruments (Xcode)

You need a full Xcode installation (not just Command Line Tools) for Instruments.

### Recommended Templates & What to Look For

1. **Energy Diagnostics** (or "Energy" / "Power" templates)
   - Excellent for battery impact.
   - Record a trace while:
     - Lumina running with 4K wallpaper in normal state (5–10 min)
     - Then enable Low Power Mode (System Settings → Battery)
     - Perform heavy work (Xcode build, video export, browser with many tabs)
   - Key things to inspect:
     - Overall energy impact / "Energy Use" level
     - CPU/GPU active time attributed to Lumina / AVFoundation / VideoToolbox
     - How quickly power draw drops on pause/throttle or LPM entry
     - "On Battery" vs plugged-in differences

2. **CPU Profiler** / **Time Profiler**
   - Attach to the `Lumina` process (or launch via Instruments).
   - Sample during:
     - Idle desktop with wallpaper playing
     - Throttled state
     - Paused state (should be near-zero)
   - Expect: very low CPU (single-digit % or less on Apple Silicon for hardware-decoded 1080p/4K H.264/H.265). Decoding is mostly on the media engines.
   - Look for hotspots in AVPlayer, AVPlayerLooper, CALayer, etc.

3. **System Trace** or **Metal System Trace** (if you see GPU activity)
   - Useful to see if the video layer is causing unnecessary presents or work.

4. **Core Animation** / **Animation** template
   - Confirm that paused renderers are truly not pushing frames.

**Pro tips for clean measurements:**
- Close other apps or at least pause their background work.
- Use the same video file across runs.
- Record 3–5 minute steady-state segments.
- Compare "wallpaper playing normal" vs "wallpaper paused" vs "Lumina not running at all".
- Note: the desktop-level windows + AVPlayerLayer are designed to be extremely cheap when the player is paused or rate-reduced.
- Run Lumina from the command line so its stdout appears in your terminal alongside Instruments data.

---

## 4. Key Test Scenarios & Guidance

### Low Power Mode (LPM)
- Enable/disable via System Settings → Battery (or Control Center).
- Expected: wallpaper **pauses** within ~1–2 seconds. Icon changes to ⏸, tooltip says reason "lowPowerMode".
- Debug print should show the policy.
- Energy impact should drop dramatically.
- When you disable LPM, it should resume (or respect other conditions).

### Thermal Throttling / High Load
- Induce load:
  - Terminal: `yes > /dev/null &` (multiple instances) or `stress` if installed.
  - Heavy Xcode build / Swift compilation of a large project.
  - Run a graphics demo or 3D app.
  - On Apple Silicon: watch `pmset -g therm` or use `powermetrics`.
- Expected behavior (per current PowerManager):
  - `.serious` / `.critical` → **paused**
  - `.fair` → **throttled** (~15 fps effective via rate reduction)
- Verify with Debug status: rate drops or 0.0 when paused.
- CPU/thermal graphs in Instruments or Activity Monitor should show Lumina backing off.
- Recovery: when load drops, it should return to normal automatically.

### Fullscreen Apps & Obscured Desktop
- Test cases:
  - YouTube / Vimeo in Safari or Chrome fullscreen (⌘F or the full-screen button).
  - Full-screen Xcode (Editor > Enter Full Screen or the toggle).
  - Games, Keynote presentations, Zoom screen share / full screen.
  - Mission Control / full-screen Spaces transitions.
- Expected: wallpaper **pauses** quickly (FullscreenDetector polls ~every 2.5s + reacts to activation).
- Icon → ⏸ with "fullscreenApp".
- When you exit fullscreen or switch away, it should resume (unless other pause conditions active).
- Test edge: menu bar apps, floating panels, etc. (should **not** pause).

### Sleep / Wake
- Put Mac to sleep (Apple menu → Sleep or close lid).
- Wake it.
- Expected: wallpaper should come back in the correct state (respecting current LPM/thermal/fullscreen).
- `wakeFromSleep` handler triggers a fullscreen re-check.
- Check console for any errors; windows should re-order correctly to desktop level.

### Multi-Monitor
- Connect/disconnect external display(s), projector, AirPlay, Sidecar.
- Use "Displays" settings for mirror vs extended.
- Expected:
  - One wallpaper window + renderer per screen.
  - Same video content (synced via shared player logic in prototype).
  - Correct desktop level on every display.
  - Fullscreen detection works across screens.
  - Changing arrangement triggers `screensChanged` → re-check.
- Test: drag full-screen window between monitors.

### Manual Controls & Persistence
- Load video → Quit (⌘Q) → Relaunch → should auto-restore (bookmark + fallback).
- "Clear Current Wallpaper" vs "Clear Saved Wallpaper" distinction.
- Toggle the power settings in the menu and observe policy changes.
- "Pause / Resume" (⌘P) manual override.
- "Reload Last Video" (⌘R).

### Battery & Long-Run
- Run for 30–60+ minutes on battery with a nice looping wallpaper.
- Compare battery drain % with vs without Lumina (or with wallpaper paused).
- Use `pmset -g log` or CoconutBattery / Stats app for discharge rate.

### Other Edges
- Rapid app switching.
- Spaces / Mission Control / Stage Manager.
- Dark mode / resolution changes.
- Very large 4K/5K/6K videos or high-bitrate files (watch thermals).
- No video loaded state (should feel helpful, not broken).

---

## 5. Verification Checklist

Use this as your test log. Check items as you verify.

**Setup**
- [ ] Prototype builds cleanly with `swift build`
- [ ] Runs as pure menu-bar accessory (no Dock icon)
- [ ] Loads a video and displays correctly behind icons on primary screen
- [ ] Status bar icon + tooltip reflect state (including no-video case)
- [ ] Menu shows current filename (or helpful "no video" message)

**Core Power Intelligence**
- [ ] Low Power Mode → pauses reliably (icon, policy, playback)
- [ ] High thermal (serious/critical) → pauses
- [ ] Medium thermal (fair) → throttles (rate visibly reduced or logged)
- [ ] Fullscreen app (multiple types) → pauses
- [ ] Exit fullscreen / switch away → resumes when appropriate
- [ ] Manual Pause/Resume works and overrides
- [ ] Policy recovers automatically when conditions clear

**Hardware & System Events**
- [ ] Sleep/wake cycle preserves correct state
- [ ] Display reconfiguration (add/remove monitor) works without crash or stuck wallpaper
- [ ] Multi-monitor: correct layering + content on all screens
- [ ] Instruments Energy/CPU traces show low impact when playing, near-zero when paused/throttled

**UX & Polish (B)**
- [ ] "About / Status…" shows accurate live info + power flags
- [ ] "Clear Current Wallpaper" stops playback without deleting saved bookmark
- [ ] "Reload Last Video" works after Clear Current
- [ ] Debug print (⌘D) produces useful detailed output
- [ ] Simple power toggles in menu function
- [ ] No-video state is obvious and actionable in menu + icon + tooltip

**Persistence**
- [ ] Last video auto-restores on relaunch
- [ ] Clear Saved removes the auto-load behavior
- [ ] Bookmarks work across file moves (within reason)

**Demo Asset**
- [ ] Successfully used a royalty-free looping video from recommended sources (see section 7)

**Longevity / Real-World**
- [ ] Ran 30+ min on battery with minimal drain
- [ ] No noticeable interference with foreground work, video calls, or productivity apps

---

## 6. Reporting Issues / Feedback

When reporting:
- macOS version + Mac model (especially Apple Silicon vs Intel)
- Exact video file specs (resolution, codec, fps, duration, bitrate — use `ffprobe` or Media Info)
- Console output around the event (especially `[PowerManager]` lines)
- Screenshot of Debug status print + About dialog if relevant
- Instruments trace summary (energy numbers, CPU %)

---

## 7. Recommended Demo Assets (Royalty-Free, Looping, Wallpaper-Friendly)

**Primary recommendation (subtle, perfect for wallpaper):**
- **Mixkit – Clouds and Blue Sky Background**  
  https://mixkit.co/free-stock-video/clouds-and-blue-sky-background-2408/  
  Slow, natural cloud movement. Excellent seamless loop feel. 4K available. Muted.  
  **License**: Mixkit Free License — royalty-free, free for personal & commercial projects, **no attribution required**.

- **Mixkit – Multicolor Ink Swirls in Water**  
  https://mixkit.co/free-stock-video/multicolor-ink-swirls-in-water-286/  
  Beautiful, calm abstract. Very wallpaper-appropriate. Looping.

**Other excellent sources (check each video's page for exact license confirmation):**
- **Pixabay Videos** (search "looping ocean", "abstract loop 4k", "nature seamless"):  
  https://pixabay.com/videos/search/looping/  
  Many high-quality 4K options. License: free for commercial & personal use, **no attribution required** for most.
- **Pexels Videos** (search "slow motion waves", "loop nature 4k", "abstract background loop"):  
  https://www.pexels.com/search/videos/loop/  
  High quality. License generally allows personal + commercial use (attribution appreciated on some older clips but usually not required for the video platform content).

**Bonus: Easy download script / instructions for macOS**

Create the samples folder and open the best pages in one command:

```bash
mkdir -p "$HOME/Movies/Lumina Samples" && \
cd "$HOME/Movies/Lumina Samples" && \
open "https://mixkit.co/free-stock-video/clouds-and-blue-sky-background-2408/" && \
open "https://mixkit.co/free-stock-video/multicolor-ink-swirls-in-water-286/" && \
open "https://pixabay.com/videos/search/looping%204k/" && \
echo "✅ Folder ready at ~/Movies/Lumina Samples/. Download the MP4s (usually 1080p or 4K buttons on the page) directly into it. Then use Lumina → Load Video… to test instantly."
```

You can also use `curl` or `yt-dlp` (if installed) for direct MP4 URLs when sites expose them, but the browser download buttons on Mixkit/Pixabay/Pexels are reliable and give you the highest quality encodes.

**Fallbacks if video download is inconvenient:**
- High-quality animated GIFs converted to MP4 (using `ffmpeg -i input.gif -movflags faststart -pix_fmt yuv420p -vf "scale=1920:-1" output.mp4`).
- Short image sequences rendered as ProRes or H.264 loop.
- Any personal or Creative Commons 0 (CC0) footage you already have.

**Tips for best results:**
- Prefer H.264 or H.265 (HEVC) — hardware decode is extremely efficient on Apple Silicon.
- 1080p or 2160p (4K) at 24–60 fps.
- 5–30 second seamless loops work best.
- Mute audio tracks (Lumina forces mute for wallpapers anyway).

---

## 8. Prototype Limitations (Known)

- Single video shared across all displays (per-display content planned for later).
- No audio support yet (intentional for wallpapers).
- No per-wallpaper settings or library UI (menu-driven only).
- Fullscreen detection uses CGWindowList heuristics (very good but can have rare edge cases with certain apps).
- Persistence uses security-scoped bookmarks + path fallback (robust for non-sandboxed prototype).
- No login item / launch at login yet (manual launch for testing).
- Instruments data can be noisy; always compare against baseline "Lumina not running".

---

**Thank you for testing!** Your real-hardware feedback on power/thermal behavior, multi-monitor, and UX is invaluable for making Lumina the best native low-power solution possible.

— Lumina Team (early prototype phase, May 2026)

---

*This document created as part of prototype improvement tasks B + C.*