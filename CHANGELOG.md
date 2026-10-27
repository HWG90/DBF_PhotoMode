# Changelog

## 1.1.0 — 2026-10-16

- **Passive now uses player-side no aggro.** Enemies continue their simulation while ignoring the player in the verified solo test. This replaces Passive's repeated enemy scans and target suppression. A once-per-second player/session ownership check handles replacement and cleanup; Normal restores our owned flag. No Link addon required. **So uh... don't get too comfy.** Damage, objectives and the integrated respawn path still need wider testing; this is not invulnerability.
- **Lower AI overhead:** Passive no longer scales its maintenance work with the enemy population. Dummy keeps bounded discovery and a measured per-frame work budget, rather than an unrestricted population sweep. No promise of a fixed FPS gain.
- **Independent photo camera:** War Journalist now owns its camera discovery, movement, lens and cleanup. Removed the ActionCam adapter and dependency. Other camera mods can remain installed; coexistence still depends on respecting input/camera ownership. Check that Restart ActionCam is not bound to M1.
- **Input recovery:** corrected stale camera handoffs, opening while moving, gameplay-look restoration, and coordinated editor/menu input. Ctrl+Shift+F10 is the recovery shortcut; close other editors before testing if input gets stuck.
- **Follow Player follows the complete light rig.** Existing and newly added lights share the switch. Moving lights update transforms instead of resending every color/intensity/shadow property. Following translates with the player; it does not rotate the rig with their facing.
- **Hoverpack:** pause-entry fallback and pending restoration now use a fresh world-update clock even after the camera target is retired. Native hover hooks remain removed. The integrated latest package needs further equipment-combination testing.

The photo tools, poses, cape/ragdoll fixes, compositor, logos and gallery remain included. Native DoF, shader preview, camera paths, Freeze/Slow Motion, lighting presets and saved Director cameras are retained.

Choose one complete package: BSL, MDL or LLL. GitHub has all three; Nexus has BSL and MDL. Preserve settings, presets and screenshots, replace the old runtime, deploy the matching bundled assets and restart. Each package includes its assets and helpers. Do not mix runtime versions.

The new player flag was observed live through LLtM; the integrated mode passed isolated ownership/lifecycle tests. Offline package checks are not full live acceptance across all loaders or missions.

## 0.9.11 development candidate — 2026-10-14

- Added Director action shots: place the camera, return input to the Helldiver and retain the static camera position, rotation, roll and FOV. The Photo Mode shortcut returns to placement.
- Restore fixed poses, paused world time and hover overrides before returning gameplay input. Camera ownership remains exclusive through performance; scene and player changes retire the shot.
- Retain the screenshot shortcut without recapturing gameplay input, and hide the Cinema indicator in mod screenshots. Native menus, chat and focus loss block camera shortcuts.
- Includes the completed 0.9.10 ActionCam startup and disposal guards. Offline lifecycle/render fixtures and complete package validation cover the candidate; live aiming, combat and coexistence remain unverified.

Full details: [Cinema camera notes](archive/history/docs/RELEASE-0.9.11.md).

## 0.9.10 development candidate — 2026-10-14

- Added scoped camera ownership for the supported standalone ActionCam 2.3.1 / runtime 10.31. Gameplay profiles and First Person remain ActionCam's; its camera update/draw work yields while War Journalist owns Photo Mode.
- Restore original FOV/First Person leases before takeover and clear transient camera state before resume. Failed photo cleanup retains exclusivity; failed startup cancels after restoring War Journalist's resources.
- Separate original Photo bindings from War Journalist controls, retain gameplay restart/profile shortcuts and drain held shortcuts during handoff. Both startup orders are tested; unsupported hooks are refused without replacing them.
- Retain the 0.9.9 closed shader registry and complete assets. 55 isolated fixture groups and all three package-only startup checks passed. Live ActionCam coexistence is still pending.

Full details: [0.9.10 release notes](archive/history/docs/RELEASE-0.9.10.md).

## 0.9.9 — 2026-10-14

- Removed 198 inherited shader registrations that were absent from a clean War Journalist package. The registry now contains exactly 77 native registrations plus all 44 bundled shader libraries.
- AMD testers reported Alt-Tab, fullscreen, bloom and DoF changes stable with the registry-only fix, before and after opening Photo Mode. HDR/SDR switching and unrelated crashes are not separately validated.
- Retained 0.9.8 runtime behavior, all shader programs, materials, lights, logos and features. This hotfix does not include deferred startup.
- Added strict build/package checks against unbundled, missing, duplicate or reordered native shader registrations. Complete BSL, flat MDL and LLL bundles remain available.

Full details: [0.9.9 release notes](archive/history/docs/RELEASE-0.9.9.md).

## 0.9.8 — 2026-10-13

- Fixed Native DoF flickering when temporary render packets disappeared, expired or carried stock lens values. A validated owned lens is retained until the actual camera/profile owner changes; matching packets are preferred when multiple views are queued. Blur was confirmed steady while still and moving.
- Removed blanket synthetic key and mouse-button releases on Photo Mode entry and exit. Held gameplay inputs, including ADS, remain intact for posing. Held ADS behavior was confirmed in-game.
- Retained the data-only hoverpack pause guard and its neutral-control requirement. This hotfix does not claim a new hoverpack regression test.
- Retained the complete 0.9.7 UI, fixed poses/cape correction, solo AI controls, photo lights, shader compositor, curated logos and bundled assets.
- Complete BSL, MDL and LLL bundles; MDL remains flat without nested archives. All 54 fixture groups and all three package-only startup checks passed. Lighting is **Not tested fully**; HDR/SDR and other display-setting crashes remain unresolved.

Full details: [0.9.8 release notes](archive/history/docs/RELEASE-0.9.8.md).

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

Full details: [0.9.7 release notes](archive/history/docs/RELEASE-0.9.7.md).

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

Full details: [0.9.6 release notes](archive/history/docs/RELEASE-0.9.6.md).

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

Full details and installation: [0.9.5 release notes](archive/history/docs/RELEASE-0.9.5.md).
