# Decisions — ambient sound fork (2026-11-11)

- **Sound engine: AVAudioEngine, streamed loops + random one-shots.** Rejected: AVAudioPlayer per file (no shared mixer, no sample-exact looping), bundling long raw recordings (≈1 GB).
- **Layers per mode, no per-layer mixer UI.** A menu-bar app gains little from 9 sliders; volumes are tuned in `Ambience.swift`. Custom per-mode folders cover "I want different sounds".
- **Sound off by default.** An app that starts making noise unasked gets quit.
- **Silent while the snow is not seen** (screens asleep/locked, session inactive, every display covered by a full-screen app) and at intensity 0; volume follows intensity.
- **Licenses: CC0 and CC BY only, from Freesound.** Rejected: Pixabay/Mixkit (raw-file redistribution forbidden, repo is public).
- **Own music = a folder, shuffled under the ambience.** Rejected: Apple Music/Spotify control (needs entitlements and Automation prompts; not "your own music").
- **Removed "Support Snowhush" and "Check for Updates…".** Sparkle points at the upstream appcast and would replace this fork with upstream; automatic checks are off in Info.plist. About/license (PolyForm Noncommercial) untouched.
- **Added: presets (5 built-in + save your own), sleep timer (15 min–2 h, 30 s fade).** Rejected: Pomodoro (not ambience), time-of-day automation (presets cover it with one click; automation would fight manual choices), global hotkeys (needs a key-capture UI; menu is one click away), notifications (nothing worth interrupting for).

## 2026-11-11 — bug-fix pass
- Fade ticker and sleep timer run in `.common` run-loop modes: in the default mode they froze while the status menu was open.
- Music player passes over unreadable files instead of stalling on them.
- Turning sound off by hand cancels the sleep timer.
- Added: current track + Next Track in the Sound menu; an alert when the chosen folder has no playable music.
- Rejected: a per-layer mixer (too much for a menu-bar menu), global hotkeys (not asked for).
