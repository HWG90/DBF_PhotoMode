# Changelog

## 0.9.6 — 2026-10-13

- Added numbered scene light indicators, click/drag positioning, Shift fine control, three subject-focused lighting rigs, and five persistent lighting setup slots.
- Added shader blur strength from 1x to 8x (4x default), with 64/128 samples above 1x and the accepted compositor color math preserved. New visual acceptance is pending.
- Added fixed Salute, Wave, and Taunt poses under Subject. Selecting a pose applies it immediately while world time stays at zero; Reset, exit, pause-off and slow motion restore the original skeleton before simulation resumes. No gameplay emote is triggered. Victory poses are not yet included.
- Added solo-only Director Normal, Passive, and Dummy enemy behavior with Reset to Normal. The selected behavior continues after Photo Mode closes and covers newly discovered enemies; game restart returns to Normal. Joining players cancel the mode and restore owned changes. Live persistence and Reset were user-confirmed.
- Fixed temporary scene/respawn read loss clearing the selected enemy behavior. Dummy now retains and renews its owned movement flag when a borrowed detector becomes unavailable; restoration no longer depends on that detector's lifetime. These edge cases have fixture coverage.
- Retained photo-light placements across Photo Mode exit within the same scene; five explicit saved setup slots also survive restarts.
- Added an explicit color Apply action and a live RGB swatch/HEX readout while editing.
- Fixed nested equipment remaining visible when its subject was hidden; the live result was accepted.
- Added menu-close cleanup and retired-world GUI lifetime guards. Display-setting and HDR/SDR crashes remain unresolved.

Full details: [0.9.6 release notes](docs/RELEASE-0.9.6.md).

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
