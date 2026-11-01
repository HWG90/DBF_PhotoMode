# War Journalist 1.3.4 release protocol

Status: patch release of the 1.3.x Boot Mod Loader line for game build 26251122, after a Windows Defender false positive on 1.3.3's helper (30 October 2026), with the Center auto-focus fix for 4K (31 October).

## Release boundary

- One complete Boot Mod Loader package, `War-Journalist-1.3.4-BML.zip`. No BSL/MDL/LLL or Chef compatibility promise.
- Scope: `3dd3a26` from `claude/wj-helper-hardening`:
  - the game build comes from `engine_render_contract.lua` (`--exe-sha`/`--game-sha`), so the helper's bytes no longer change with game updates;
  - version information (War Journalist, HWG90, 1.3.4.0) and the asInvoker manifest, `/Brepro`;
  - screenshot guard files no longer hidden;
  - helper renamed `war_journalist_helper.exe`; `wjl_steam_service.exe` retired and deleted at startup.
- `af83143` on top: the Center auto-focus pause message in plain words ("Center auto-focus paused to avoid stutter. Use Manual or Double-click to focus."), added at the user's request after the first live test of the 1.3.4 package showed the old technical text. Behaviour unchanged.
- `823370e`: Center auto-focus keeps working when the depth read is too slow to repeat (15–16 ms at 4K against the 8 ms budget). A centred Helldiver is focused from its skeleton; scenery is read once each time the camera stops. The user chose to hold 1.3.4 for it ("Hold 1.3.4"), and it was confirmed in game at 4K on DEV `08c377b` ("Works, no stutter", 2026-10-31 00:15).
- The committed helper payload ships as is (`a6f5f3f6aede55b2…`); it is not rebuilt for the release.
- Everything else is 1.3.3.
- Not in this release unless the user includes it: `claude/wj-1.3.3-discord-fixes` `766db66` (Ctrl+Shift+F10 soft-lock escape). `171bc40` on that branch is superseded by 1.3.3's Page Down change.
- No code signing (the user's call).
- Every 1.3.0 limitation still open stays on every page, in the plain voice of `listing-copy.md`.
- Keep all existing photos, credits and licenses on Nexus, Ayaka and Discord. Replace the NEW IN 1.3.3 block with 1.3.4; do not stack old change notes.

## 1. Lock source and package

- [ ] Release commit on top of `origin/main` (`71d5f09`) fast-forwarded to `3dd3a26`, then `af83143` and `823370e`. Never stage `freecam/assets/shaders` CRLF noise, settings, logs or diagnostics.
- [ ] Bridge DLLs copied from `wj-26251122`, SHA-256 equal to 1.3.3's `BUILD-RECEIPT.json`.
- [ ] Isolated Lua 5.1 fixtures with the Windows drive mounted; `test_wjl_helper_launch.py` against the 26251122 install.
- [ ] Build with `dist/review/release-1.3.4/build_package.py`: assets and bridges are 1.3.3's bytes, helper payload `a6f5f3f6…`, `windows_dev_reload.lua` stripped, `RELEASE_MODE=true`.
- [ ] The add-on names `war_journalist_helper.exe` and passes `--exe-sha`/`--game-sha` with the 26251122 hashes.
- [ ] `package_release.py` rules: `FILES-SHA256.txt`, CRC, `SHA256SUMS.txt`.

## 2. Verify the distributable

- [ ] Local Arsenal entry (GUID `7020a1c8-…`) updated in place with a rollback copy, every checksum verified in the store, label, description and version updated.
- [ ] Exact final ZIP cold start under Boot Mod Loader on Linux/Proton:
  - `war_journalist_helper.exe` written and started, `wjl_steam_service.exe` gone;
  - WJL ready, game hashes and renderer contract verified, keyboard lock;
  - one PNG screenshot;
  - Photo Mode open/close.
  If not performed, every page says so.
- [ ] Native Windows and Defender behaviour: wait for player reports.

## 3. Update every destination

- [ ] GitHub: `v1.3.4` annotated tag on the release commit, Latest, ZIP + `SHA256SUMS.txt`, notes from `RELEASE-1.3.4.md`; public download hash verified.
- [ ] Nexus: update the 1.3.3 file row to 1.3.4 with "Archive existing file", keep it primary; changelog, mod version, short description, NEW IN 1.3.4 block; seven photos kept.
- [ ] Ayaka: 1.3.4 update with the new version and the GitHub release link, then the overview NEW IN block and tag line (at most 100 characters). Five inline photos and eleven gallery attachments kept.
- [ ] Discord: thread title and starter updated for 1.3.4 (under 2,000 characters, starter image kept), no mass mentions.
- [ ] Inspect rendered pages and record URLs, photo counts and the Nexus scan state.

## Publication record

`PUBLICATION-1.3.4.md`: source commit, tag, ZIP hash, helper hash, per-site URLs and state, Arsenal entry, tests and live scope, anything pending.
