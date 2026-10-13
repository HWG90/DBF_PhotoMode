# Changelog

## 0.9.5 — 2026-10-13

- Added native focus/aperture, double-click focus, center autofocus, lens presets, and tilt shortcuts.
- Combined shader DoF, scene effects, and color grading in the full-resolution compositor; corrected the demonstrated HDR tint/exposure issue.
- Added three configurable photo lights and a dedicated mission-light asset. **Mission-light fix: Not tested fully.**
- Added five persistent player-relative Director camera shots and local subject visibility controls.
- Added a compact movable/resizable menu with saved geometry, dockable controls legend, fine Shift scrubbing, updated logos, and a rebindable screenshot shortcut.
- Fixed the reported hoverpack + melee pause/resume reproduction with a data-only guard; the user confirmed the original case. Connected or unidentified controllers cannot use guarded active-hover pause.
- Guarded all seven animation-state reads against dead Units or missing graphs, and repaired native camera/profile-instance ownership.
- Improved held-input release, focus/capture handoff, menu reopening, chat activation checks, and scene-resource warmup.
- Corrected HDR PNG conversion brightness and the verified SDR capture profile's red/blue channel ordering.
- Packaged complete BSL, MDL, and LLL downloads. AI behavior controls remain unintegrated. Broader stability, full cold-start coverage, SDR compositor parity, and all effect combinations are not claimed.

Full details and installation: [0.9.5 release notes](docs/RELEASE-0.9.5.md).
