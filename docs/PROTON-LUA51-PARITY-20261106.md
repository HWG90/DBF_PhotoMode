# Lua 5.1 changes in the Proton candidate, 2026-11-06

This is an offline-verified candidate, not a published or live-game-accepted release. The scoped deployment follow-up below records installation after the initial review.

## Source boundary

- Proton base: `c13d6d5`, `claude/wj-proton-bone-posing` (including the build-26251122 adapters and Proton dev.6 bone-posing fixes).
- Latest Lua 5.1 source merged: `9684b7a`, `claude/wj-discord-review`.
- Integration branch: `codex/wj-proton-lua51-parity-20261106`.

The merge includes the source line's 1.4.0 package/helper maintenance and smaller pose bank, new Photo Mode refusal messages, clearer subject failure reasons, ownership-aware pose recovery, camera targets that follow moving subjects, bounded nearest-camera-pin selection and shared-key guidance. Chef-specific services remain host-specific. The rejected UI restyle was not imported; the existing Photo Mode appearance stays.

Proton retains LLL input and capture services, MCM settings, optional FFI enemy controls, native bridge/build checks, HUD font routing, Handycam aim lock, explicit picked-unit priority, native local-cape handling and existing cleanup gates. Native bridge source is unchanged from the Proton base.

## Integration fixes

- Retained both source's subject reset/camera-target state and Proton's preferred clicked-unit discovery argument.
- Used the source's ownership-aware `abandon` implementation: never overwrite a foreign bone mode, and do not forget an owned mode before a refused restore can be retried.
- Retained Proton's MCM/AI/visibility paths while adopting the source's depth-host options and follow-target flow.
- Kept all left/right modifier key names and Proton's extended key set. Hosted name-to-code lookup now selects the historic lowest code deterministically instead of dropping left-hand names.
- Fixed the optional, explicitly allowed shared-key fallback so its already-owned pointer lease can change between menu and camera. Captured-keyboard capability loss and pending cleanup still fail closed; strict LLL policy is unchanged.
- Updated Proton builders to use maintained `package_head`/`build_package` helpers after the source retired `build_steam_archive.py`.
- Proton folder builds now run the maintained fixtures under both actual Lua 5.1 and LuaJIT 2.1. Explicit test-only VM admission leaves LuaJIT enabled. Pose-bank corruption tests flush traces after deliberate debug-upvalue replacement; heap checks now reject positive retained growth, not memory reclaimed by LuaJIT, and additionally prove pose objects are collectible with weak references.
- Folder packaging verifies content-addressed DLL hashes. Archive packaging verifies all six pinned 1.3.0 asset hashes and rejects unexpected asset files.

## Offline validation

- Maintained suite: 119 checks passed under Lua 5.1 and 119 under LuaJIT 2.1, including 13 shared feature fixtures. The pinned R35 LLL-submodule byte comparison is skipped because that submodule is not checked out here.
- System LuaJIT: all 104 primary fixture files passed independently in fresh CLI processes.
- Ten additional menu/layout/numeric-input fixture groups passed under each system Lua 5.1 and LuaJIT library.
- Both VMs compiled every packaged Lua chunk; 79 declared private modules were checked against the require closure.
- Folder package was unpacked and audited for exact source bytes, checksums and manifest declarations.
- Archive package passed exact embedded Lua/DLL readback, no-LLL refusal, duplicate-folder refusal, isolated entry startup, settings-path routing, first-load-only bridge extraction and truncated-bridge refusal. These tests use synthetic hosts and temporary directories, not the game.
- `git diff --check` passed.

The native DLLs are reused unchanged, with full SHA-256 verified against their content-addressed names:

- `hd2_nativeinfo_c1578203689e39b9.dll`: `c1578203689e39b96db2a846cdfd6bd2a49c9dd13d80da1fedc85a7f9562be7d`
- `hd2_nativeinfo_8db3d96f8c3cbb24.dll`: `8db3d96f8c3cbb24634a6bfcfc18e80b6de2f3d0c7f3bee69e8b0f7c45446f0e`

## Reproduce

Use a Python environment with `lupa.lua51` and `lupa.luajit21` available:

```sh
python tools/test_steam_port.py --runtime lua51 --receipt dist/validation/lua51.json
python tools/test_steam_port.py --runtime luajit21 --receipt dist/validation/luajit21.json
python tools/build_proton_candidate.py
python tools/build_proton_archive.py
```

Provide the unchanged, hash-matching DLLs under `freecam/native/port51/`. The archive tool's `--assets` selects the verified six-file 1.3.0 set. These tools write only development artifacts under `dist/review`; they do not install. Use the Proton builders on this branch. The unmodified Lua 5.1 source branch remains the BML/Chef package build source.

## Remaining live acceptance

Offline checks cannot certify game ABI, render output or live input cleanup. Before calling this candidate stable in game:

1. Preserve the active mod/profile and settings, and test only one War Journalist runtime at a time on build 26251122.
2. Open/close Photo Mode repeatedly; test a refused open, focus loss, mode switches and MCM settings. Confirm keyboard/mouse control returns every time and the HUD font renders.
3. In a mission, double-click nearby and distant Helldivers in a crowded scene. Confirm nearest pin selection, moving-target Pin/Pivot tracking, stale/dead target rejection and no unintended posing of unsupported targets.
4. Apply and replace poses, close/reopen with bone edits, let the game take a pose back, then Stop/Recover. Confirm time resumes, cape release, no foreign mode overwrite and no stuck discovery.
5. Test Handycam aim lock and ADS handoff, held left/right modifiers, numeric fields, screenshot capture and settings persistence.
6. Measure closed idle and open menu behavior. Keep existing scene-effect/numeric-DoF and decorative-overlay qualification gates; this port does not visually qualify them.

At initial candidate completion, no game launch, live deployment, Git push, tag or release had been performed. The subsequent scoped installation is recorded below.


## Scoped installation follow-up

At 2026-11-06 03:59:30 UTC, candidate source commit `71eec8a`, build `20261106.0355-71eec8a`, was installed into the active WORMHOLE Proton prefix's `LLL/Helldivers2/Mods/dbf_freecam` folder. The initial process check reported no game, but later review found that check was PID-namespaced and could not independently prove host closure. The selected and deployed Arsenal profile was `LuaJIT Proton`; LLL explicitly enabled this folder. Its prior 86 files matched the known Proton dev.6 candidate byte-for-byte before replacement.

The old folder was moved intact to `Port-Candidate-Backups/war-journalist-before-parity-71eec8a-20261106T035929Z/dbf_freecam`. That backup also contains a verified copy of the separate WJ settings and `LLL.cfg`. Settings, Arsenal metadata, `LLL.cfg`, shared boot files, native bridges outside this mod and all other mods were left unchanged. DBF and MCM deployment owners confirmed no overlapping work.

The installed folder matches all candidate hashes. `verify_installed_modules.py` passed against the actual installed directory with 79 declared/actual modules, and all 80 installed Lua chunks compile under both Lua 5.1 and LuaJIT 2.1. The disabled Proton archive remains disabled. The existing Chef asset/core row refuses under LLL before creating its runtime, as its source and current loader log confirm; it was not changed.

Installation receipt: `dist/validation/INSTALL-RECEIPT-71eec8a.json`. Actual installed audit: `dist/validation/installed-71eec8a-audit.json`. Roll back with the game closed by moving the installed folder aside and restoring the backed-up `dbf_freecam` folder to its original `Mods` location. No settings rollback is needed because settings were unchanged.

The installation task did not launch the game. Live acceptance remains the checklist above, not a completed claim. No Git push, tag or release was performed.


## Post-install session and obsolete Chef cleanup

The next recorded session ran 2026-11-06 04:12:23–05:00:21 UTC and ended with normal engine shutdown. `LiveLuaLoader.log` recorded the obsolete Chef archive refusing at line 51, then the installed `live/dbf_freecam` loading at lines 161–165 and reporting `Photo Mode ready on LuaJIT 2.1.ROLLING; settings in MCM` at line 271. Its normal shutdown appears at line 886. The Chef host assertion occurs before constructing its runtime, so it did not create a second camera owner. This proves Proton startup, not Photo Mode/pose/screenshot acceptance.

A separate native subject backend probe refused at line 270 (`host_native.lua:56`, CClosure ABI/closure check). Its guard was not changed, relaxed or bypassed. The runtime remained available through its existing fallback paths; native subject behavior still needs live acceptance.

At 07:29:39 UTC the obsolete Chef dev.16 row `7b18fc08-a506-4cd3-a506-dbed18445576` was disabled only in the `LuaJIT Proton` profile. Its exact script-only `9ba626afa44a3aa3.patch_48` and empty sidecars were moved out of `data` to a same-disk rollback folder. Source package, other profiles, every other deployment file, Proton WJ folder, settings, LLL configuration and dedicated WJ assets stayed unchanged. The separate assets were verified by deployed hashes. No full Arsenal deployment or game launch was performed, and the Chef/source host gate remains intact.

This cleanup used a reviewed host-level process check with more than 700 host processes visible and no Helldivers process before or after. The first attempt only created metadata backups: cross-device rename failed before moving anything; the successful attempt used a same-disk backup. Corrected lesson: ordinary sandbox `/proc`/`pgrep` is not a valid host-game-closure check. The initial installation's historical process-check assertion should not be treated as independently verified.

Cleanup receipt: `dist/validation/RETIRE-CHEF-PROTON-RECEIPT.json`. Metadata backup: `~/.config/hd2arsenal/repair-backups/wj-chef-proton-only-20261106T072939Z`. Patch backup: game root `War-Journalist-Backups/chef-proton-only-20261106T072939Z`. The cleanup is verified on disk, not yet on a subsequent launch; Arsenal's existing UI may need its normal page change to refresh the cached row.
