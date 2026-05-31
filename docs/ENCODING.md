# Recommended Video Encoding Settings for Lumina

Lumina is designed to deliver beautiful wallpapers while using as little energy as possible. The single biggest factor in battery impact is **how your video files are encoded**.

Follow these guidelines for excellent results with minimal power draw on Apple Silicon.

## 1. Codec (Most Important)

| Codec       | Recommendation     | Notes |
|-------------|--------------------|-------|
| **HEVC (H.265)** | **Best choice**    | Excellent quality at low bitrates. Hardware decode on all Apple Silicon Macs. |
| H.264       | Good               | Widely compatible, slightly higher power than HEVC. |
| AV1 / VP9   | Avoid for now      | Usually software decoded → much higher CPU/GPU usage. |
| ProRes      | Only for very short clips | Extremely high bitrate. Not suitable for always-on use. |

**Strongly prefer HEVC.**

## 2. Resolution & Frame Rate

- **Resolution**: Match your display or go slightly lower.
  - 1080p or 1440p is ideal for most users.
  - 4K only if you have a 4K/5K/6K display **and** are on AC power.
- **Frame Rate**: 24 fps or 30 fps is perfect. 60 fps is rarely worth the extra power cost for ambient wallpaper content.

## 3. Bitrate

| Resolution | Recommended Bitrate (HEVC) | Notes |
|------------|----------------------------|-------|
| 1080p      | 4 – 8 Mbps                 | Excellent quality |
| 1440p      | 8 – 14 Mbps                | Very good |
| 4K         | 15 – 30 Mbps               | Use only when necessary |

Use **Constant Quality (CRF)** mode when possible (HandBrake, Compressor) rather than targeting a specific bitrate.

## 4. Audio

**Remove the audio track entirely.**

```bash
ffmpeg -i input.mov -c:v libx265 -crf 23 -an output.mov
```

No audio = zero audio decoding, mixing, and session overhead.

## 5. Looping

- Keep loops relatively short (8–60 seconds) for smaller file sizes.
- Make sure the first and last frames match perfectly for seamless looping.
- Lumina uses `AVPlayerLooper`, which handles this very efficiently.

## 6. Recommended Tools

- **HandBrake** (free) — Excellent presets, Apple Silicon optimized.
- **Apple Compressor** — Best quality and control.
- **FFmpeg** — For automation and scripting.

### HandBrake Recommended Preset (HEVC)

- Format: MP4
- Video Encoder: H.265 (x265)
- Constant Quality: RF 20–24
- Framerate: 24 or 30 (Peak Framerate)
- Audio: None

## 7. Low-Power Variants (Advanced)

Lumina supports automatic low-power variant swapping.

If you have a file called `sunset.mov`, you can also place a lower-quality version next to it:

- `sunset-low.mov`
- `sunset-battery.mov`

When the user is on battery or Low Power Mode, Lumina will automatically switch to the `-low` / `-battery` version if it exists. When power improves, it can switch back.

This technique gives you maximum visual quality on AC power while protecting battery life.

## 8. Quick FFmpeg One-Liner

```bash
ffmpeg -i input.mov \
  -c:v libx265 -crf 22 -preset medium \
  -vf "fps=24,scale=1920:-2" \
  -an \
  -movflags +faststart \
  output.mov
```

---

Following these guidelines will give you beautiful, smooth wallpapers that use dramatically less energy than typical video content.

If you have specific content (nature loops, abstract, 4K, etc.), feel free to share examples and we can help refine the settings.
