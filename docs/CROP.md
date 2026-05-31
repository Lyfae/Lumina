# Crop Implementation Decision Record

## Context
Lumina needs high-quality, low-cost per-monitor cropping (and zoom/pan) to match Wallpaper Engine capabilities for video, GIF, and static image wallpapers.

Crop is stored in `MonitorAssignment` as a normalized `CGRect` (0-1, top-left origin).

## Options Evaluated (May 2026)

### Option A: AVVideoComposition + CIFilter (Video)
- Pros: Highest fidelity, proper letterboxing, works with hardware decode in many cases, easy to animate.
- Cons: More complex, can force software decode on some formats, slightly higher CPU on 4K.

### Option B: CALayer contentsRect + affineTransform + mask (simpler)
- Pros: Very cheap, easy for both video (playerLayer) and images.
- Cons: Can look slightly softer on some content; zoom/pan interaction requires more math.

### Option C: Hybrid
- Use B for images/GIFs (easy) + A for video when quality matters.

## Decision
**Start with Option B (layer geometry) for v1.0 speed of delivery and power characteristics.**

Rationale:
- The #1 promise is "ultra low power 24/7".
- Most users will use moderate crop/zoom.
- We can always upgrade the video path to AVVideoComposition later without changing the model or UI.
- Unified implementation across MediaRenderer types is simpler.

## Implementation Plan
1. Add `applyCropRect(_:)` to both `AVVideoRenderer` and `ImageRenderer`.
2. For AVPlayerLayer: Adjust `playerLayer.contentsRect` + small transform on a parent layer or the playerLayer itself.
3. For image layers: Use `contentsRect` + mask.
4. In the CropRectangle editor (SwiftUI), live-update a small preview + push normalized rect to the real renderer.
5. Persist + restore exactly as other settings.

## Open Items
- Interaction model for "zoom" vs pure crop (the rect can represent both).
- Performance testing on 4K + heavy crop.
- Sub-pixel accuracy / retina considerations.

This document will be updated once the spike code lands.
