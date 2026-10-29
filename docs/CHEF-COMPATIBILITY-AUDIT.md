# War Journalist 1.3.3 and Chef Shared Loader 1.3.1 / 1.4.0

Compatibility audit, 2026-10-29. Nothing in this document has been run in the
game. "Implemented" means source plus isolated Lua 5.1 fixtures inside Chef's
real `sandbox.lua`, with the loader's helpers modelled from its published docs
and source. Boot Mod Loader remains War Journalist's only supported loader.

## Sources

| What | Revision |
| --- | --- |
| War Journalist 1.3.3 (Boot Mod Loader build, 86 modules, no Chef files) | `a7f3bb1` on `release/1.3.3` (not yet on GitHub; `main` there is 1.3.2) |
| WJ Chef track | preview 5 `0.5.0` (`47a4647`, GitHub pre-release `v0.5.0-chef-preview.5`); `main` and 1.3.3 still carry the older `0.4.0` copy |
| Chef Shared Loader 1.3.1 | tag `v1.3.1`, `4fe1aa0`, `sandbox.lua` blob `78769389` (same as 1.3.0) |
| Chef Shared Loader 1.4.0 | tag `v1.4.0`, `4188152`, published 2026-10-29 08:43 UTC, `sandbox.lua` blob `ebdcfafc` |
| Chef 1.2.3/1.2.4 (preview 5's pin) | `sandbox.lua` blob `737728a5` |
| Chefbo, Nexus conversation "Compatibility" | 2026-10-27 06:21 (input findings, offer of a shared mouse hold and a players event); 2026-10-28 23:18 (1.4.0 close, both added, will review the source for the trusted list) |

Chef 1.4.0 is no longer upcoming: it was published this morning. Its README now
says 1.4.0. Its trusted list (`TRUSTED` in `src/loader.lua`) already has
`['mods/goose/war_journalist'] = { title = 'War Journalist', capture = true }`.
That is the resource name WJ's Chef addon uses. The entry grants screenshots
only: no lobby, files or patches. Chef's MODDING.md says an entry names the mod,
not a version, and that each new version is checked again. That is source
evidence of the grant, not proof that a capture works in game.

## What changed in Chef between 1.3.1 and 1.4.0 that matters to WJ

New, each with a capability flag:

- `chef.hold_mouse(on)`, `chef.mouse_held()` and `chef.mouse_delta()` (`mouse_hold`). The loader puts a dead zone on the mouse delta axis so the game camera stops turning. It gives the mouse back when the last holder lets go, when a mod stops and when the game closes. While the mouse is held, `mouse_delta` is the cursor's movement, scaled to the delta axis (x right, y down).
- `players` event (`players_event`) and `chef.joining()` (`joining`). It fires when someone starts joining, is in, or leaves. The loader looks once a second, and only while a mod listens.
- `menu` event and `chef.menu_open()` (`menu_state`), and the `mod_stopped` event.
- Button and color rows, headings, hints and folds; key combos and pad buttons for `chef.bind`.
- `chef.ray_box`, and `chef.capture()` for a trusted mod granted capture.

Tightened:

- `Application.save_render_target` is now blocked. So is every Application call whose name contains save, write, dump, export, capture, screenshot, url or browser.
- `Console`, `CommandWindow`, `SaveSystem` and `Cloud` are gone.
- Mods can't read other mods' `chef_data_*`.
- Chunk names are checked.
- Key reads are quiet while the F9 menu is open.
- A hang watchdog stops any mod call that runs over 3 s (10 s at start).

Up to 1.3.1, `save_render_target` was reachable through the sandbox; preview 5
never used it. Unchanged in every version: `os.execute`, `os.rename`,
`os.remove`, `io.popen` and `package.loadlib` are refused, and file writes are
limited to `.log .txt .json .csv .dat .ini .marker .fatal` in the loader's
folder.

## Feature map

Key: **A** runs through documented Lua 5.1 interfaces (already in the Chef
track). **B** became possible with 1.4.0 and is implemented here, behind its
capability check. **C** needs a trust grant or a loader change. **D** can't
currently be supported. **E** might be portable through documented engine reads
but hasn't been attempted, so treat it as unknown.

| WJ 1.3.3 feature (BML build) | Chef ≤1.3.1 | Chef 1.4.0 | Class |
| --- | --- | --- | --- |
| Free camera, speed, roll, zoom, smoothing, lock, level/portrait, lens shortcuts | Chef track (Chef menu + clutch) | same | A |
| Mouse look without the game camera turning | camera and character turn too | `hold_mouse` + `mouse_delta` while the clutch is held | **B, implemented** |
| Keyboard isolation (WASD doesn't move the diver) | WJL helper needs `io.popen`; Lua can't block keys (Chefbo) | same | D, unless the loader adds input capture |
| Cursor confinement | WJL `ClipCursor` | not needed for held mouse look; otherwise same | D |
| Freeze, slow motion, Resume | `set_time_step_policy`, solo check polls peers at 4 Hz | same | A |
| Solo guard reacting to joins | joining peers invisible until they are in `GameSession.peers` | `players` event + `joining()` end time at once and refuse new time while anyone joins | **B, implemented** |
| Cinema, camera paths, scene bookmarks | Chef track | same | A |
| Saved camera presets | opening-camera relative | same | A (adapted) |
| Saved Shots on the selected Helldiver's bones, return to last camera, Follow player Pivot/Pin (new in 1.3.3) | need BML's subject selection; its reads (Unit/Mesh, GameSession) are allowed reads, but `chef.call` refuses some unit calls on runtime-built units | same | E |
| Photo lights, rigs, setups, markers, dragging | Chef track (own light unit) | same | A |
| Poses (213) | Chef track, explicit selection, experimental | same | A |
| 1.3.3 pose fixes (reset-first Apply, Freeze takeback while running) | BML modules only | same | E |
| Hide helmet/torso/cape/weapons | `Mesh`/`Unit` visibility; unguarded direct calls only | same | E |
| Handycam, ADS handoff, aim lock (`look_at_position` field read) | `GameSession.game_object_field` is an allowed read; rest unported | same | E |
| Native bloom on/off, native DoF on/off | Chef track | same | A |
| Numeric DoF (focus, aperture) | BML entity reader; Chef's engine copy not probed | same | E |
| Composition overlays, logos, legend | Chef track | same | A |
| WJ's own photo panel (virtual cursor, blur backdrop) | Chef F9 rows instead | buttons, colors, headings and folds would bring the rows closer | A (adapted), not done |
| Screenshot | `save_render_target` reachable, DDS only; WJL PNG conversion impossible | `chef.capture()` (DDS in the loader's folder, 1 a second, 50 rotating); WJ is on the 1.4.0 list | **B/C, implemented behind the call's own answer** |
| PNG output | WJL converts DDS | the loader writes DDS; mods can't write `.png` | C (loader-side conversion) |
| Scene effects (grade, exposure, shaders) | shipped shaders plus WJL's renderer check | same | D under the current design (excluded from the Chef scope) |
| Automatic game-HUD hiding | none | none | D (the game's own Toggle HUD key still works) |
| Chat detection | none | menu-only quiet keys | D |
| Atomic preset files (`os.rename`) | blocked; Chef track uses `chef.save_table` | same | A (adapted) |
| AI controls | none | none | D (excluded) |
| Running the BML ZIP itself under Chef's BML look-alikes | it would start without WJL (no isolation, PNG or scene effects), and file swaps fail | also no `save_render_target` | not supported, untested |

## What this branch adds (`claude/wj-chef-lite`, Chef runtime 0.6.0)

Base: 1.3.3 release commit `a7f3bb1` plus preview 5's Chef sources. The addon
still declares `chef-shared-loader >= 1.2.3`, and the BML build is unchanged:
its package carries no Chef files, and its port suite still passes.

- `freecam/chef/loader_features.lua` checks each 1.4.0 service once, by its
  capability flag and by its helper being a function. A flag without its helper
  is not used. The start-up log line names what was found.
- **Mouse hold** (`controls.lua`): mouse look asks `chef.hold_mouse(true)` while
  the clutch is held and lets go when the clutch is released, mouse look is
  switched off, the F9 menu opens, the camera closes, or the addon stops. Deltas
  come from `chef.mouse_delta()` and get the same finite/2000 bounds as before.
  The first held frame is discarded. A refused or throwing hold falls back to the
  old shared axis (so the game camera may turn too), logs the reason once, and
  asks again after 2 s, matching the loader's axis retry.
- **Time guard** (`simulation.lua`): the `players` listener exists only while WJ
  owns time, so an idle Photo Mode costs the loader nothing. A count above one,
  or anyone joining, ends Freeze/slow motion on the next update, through the
  existing 1x restore with its pending retry. `chef.joining()` is part of the
  bounded 4 Hz solo check, so time is never taken while someone joins. A
  `chef.on` that fails leaves polling as before.
- **Screenshot** (`runtime.lua`): a "Save screenshot after menu closes" row
  appears only when the loader has `chef.capture`. The request waits for the F9
  menu to close, then 0.25 s more, so the photo isn't of the menu. The loader's
  answer is reported as is ("not available to this mod" on a loader without the
  grant) and never retried on its own. Stopping the addon cancels a waiting
  request. The result is a DDS, not a PNG.

Tests: `tools/test_chef_port.py --sandbox <sandbox.lua>` (repeatable) accepts the
1.2.3/1.2.4, 1.3.0/1.3.1 and 1.4.0 sandbox blobs. The new
`freecam/chef/loader_features_tests.lua` covers both profiles. Removing the hold
release, the players check, the joining check, or the capture's menu check each
fails it. The other 18 fixtures run unchanged against all three sandboxes.

## Not verified, and the next steps

- None of it has been run in the game: not the hold's effect on the camera, not
  `mouse_delta`'s scale against the old axis, not the event's timing in a real
  join, not the capture's file or format.
- Live checks, in order: the `Chef 1.4 services:` log line; held mouse look
  turning only the photo camera; a friend joining while frozen (time returns to
  1x within about a second); one capture after closing F9
  (`goose_war_journalist_capture_01.dds` in `%APPDATA%\Arrowhead\Helldivers2`).
- To ask Chefbo: a DDS-to-PNG step for `chef.capture`, a way to hide the loader's
  notices during a capture, and whether a loader-side keyboard capture (an
  external helper, as WJL does) is something he would carry.
- Rows marked E are the next porting candidates, Saved Shots and Follow cameras
  first. Each needs a live probe under Chef before any claim.
