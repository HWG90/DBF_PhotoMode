# Changelog

## 0.9.8 — 2026-10-13

- Fixed Native DoF flickering when temporary render packets disappeared, expired or carried stock lens values. A validated owned lens is retained until the actual camera/profile owner changes; matching packets are preferred when multiple views are queued. Blur was confirmed steady while still and moving.
- Removed blanket synthetic key and mouse-button releases on Photo Mode entry and exit. Held gameplay inputs, including ADS, remain intact for posing. Held ADS behavior was confirmed in-game.
- Retained the data-only hoverpack pause guard and its neutral-control requirement. This hotfix does not claim a new hoverpack regression test.
- Retained the complete 0.9.7 UI, fixed poses/cape correction, solo AI controls, photo lights, shader compositor, curated logos and bundled assets.
- Complete BSL, MDL and LLL bundles; MDL remains flat without nested archives. All 54 fixture groups and all three package-only startup checks passed. Lighting is **Not tested fully**; HDR/SDR and other display-setting crashes remain unresolved.

Full details: [0.9.8 release notes](docs/RELEASE-0.9.8.md).

## 0.9.7 — 2026-10-13

Public release covering all changes since 0.9.5, including the 0.9.6 development work below.

- Expanded Subject to **213 sampled pose frames**, including full-body and cooperative variants. Selection holds a fixed pose while world time stays at zero; Reset and exit restore the original skeleton before time resumes. These are not 213 released store emotes, and props or partners are not spawned.
- Fixed supported capes floating above the subject during pose changes. The original garment now follows the posed shoulders and restores correctly, retaining its textures and frozen cloth shape without stepping physics. Integrated push-up/Salute switching and reset were confirmed live; broader cape coverage remains open.
- Fixed pose readiness remaining grayed out while simulation time was paused, with immediate pause-state refresh and real-time recovery retries.
- Added a persistent 10%–100% menu-opacity slider in the bottom-right footer; right-click restores 38%.
- Included draggable scene lights, subject-focused rigs, five saved lighting setups, retained same-scene placements, and the color editor's Apply button/live swatch/HEX preview.
- Included persistent solo Normal/Passive/Dummy enemy behavior, explicit Reset, multiplayer exclusion, and recovery from temporary scene/respawn reads.
- Fixed live mission enemies remaining hostile in Passive/Dummy when their detector owner was stale. Controls now use an independently validated own detector and apply movement/target/alert fields independently. Known enemies refresh in bounded batches each owning update, while discovery remains on a 50ms timer. Both modes were confirmed working in-game; discovery-failure continuation and restoration retry also have fixture coverage.
- Included 1x–8x shader blur strength with increased samples, nested-equipment hiding fixes, and menu/world cleanup guards.
- Retained flat MDL packaging with no nested archives. All loader downloads include their required assets.
- All 53 isolated fixture groups passed, including all 213 poses and cape restoration/retirement/retry cases. Lighting is **Not tested fully**; stronger blur and broader scene coverage remain open. Display-setting and HDR/SDR switching crashes remain unresolved.

Full details: [0.9.7 release notes](docs/RELEASE-0.9.7.md).

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
