# Releases

## 0.4.0 (current)

Music widget + Studio polish release — waveform timeline, playback health, restrained surfaces.

- Floating music widget redesigned as a compact bar: art, title/artist, waveform scrubber with hover thumb, hover transport (shuffle / skip / loop / volume / queue)
- Menu bar: **Music Widget** (`⌘⇧M`) opens the mini-player without Studio
- Ambient audio: shuffle with Previous history; live meter levels drive the waveform
- Shared `AudioProgressScrubber` in the Studio footer (preview-on-drag, seek-on-release)
- Playback health monitor warns when heavy wallpapers stall or the Mac is thermally warm
- Studio: library rail collapse/expand fix, larger hit targets, solid branded surfaces (no stacked glass)

Full in-app notes: `LuminaChangelog` in `Sources/Lumina/Changelog.swift`.

## 0.3.0

Studio UX release — clearer mental models, music widget, and Settings accordion.

- **Adjust** replaces per-display Config; action bar is Apply → Clear → Reset Adjustments → Adjust
- **Keep on startup** pins for relaunch only (no longer blanks the live desktop)
- Launch: splash → Studio; Choose Display is no longer auto-stacked
- Library filters wrap; empty states offer recovery actions
- Ambient music: metadata/favorites, floating widget with Up Next + horizontal volume
- Settings: accordion sections (one open at a time); About → Version & Status

## Earlier

- **0.2.0** — splash/branding, stability audit, performance polish, crop editor fix
- **0.1.0** — music player, resizable Studio, preview-then-Apply, settings & battery profiles
