# War Journalist 1.3.3 release protocol

Status: patch release of the 1.3.x Boot Mod Loader line for game build 26251122, 29 October 2026.

## Release boundary

- One complete Boot Mod Loader package, `War-Journalist-1.3.3-BML.zip`. No BSL/MDL/LLL or Chef compatibility promise.
- Scope:
  - WJL and the stock renderer check for game build 26251122;
  - Pose Stop (cape resource check);
  - Handycam on Page Down and F11 left to the game (Steam's Ctrl+F11);
  - menu blur kept with scene options;
  - Saved Shots under Boot Mod Loader, bone-anchored, and the camera returning on reopen;
  - Follow player - Pivot and Pin;
  - Freeze holding a running Helldiver;
  - carry sockets left to the game while frozen;
  - first-pose apply after a reset;
  - armour pieces sorted by region markers, height, then bones (Hide Torso, Hide Helmet).
- Everything else is 1.3.2.
- Not in this release: `claude/wj-1.3.3-discord-fixes` `766db66` (soft-lock escape on Ctrl+Shift+F10), unless the user includes it.
- Every 1.3.0 limitation still open stays on every page:
  - first pass of the Lua rewrite;
  - BML only, with Chef Lite planned without a whitelist guarantee;
  - no AI control;
  - no depth shaders (Native DoF works);
  - occasional cape detachment;
  - intermittent subject selection;
  - incomplete Hide options.
- Keep all existing photos, credits and licenses on Nexus, Ayaka and Discord. Replace the NEW IN 1.3.2 block with 1.3.3; do not stack old change notes.

## 1. Lock source and package

- [ ] Release commit on top of `origin/main` (`dec5f77`) fast-forwarded to `claude/wj-26251122` (`2c32a05`). Never stage `freecam/assets/shaders` CRLF noise, settings, logs or diagnostics.
- [ ] Build from the clean release worktree with `dist/review/release-1.3.3/build_package.py`:
  - Assets and bridges are 1.3.0's bytes;
  - WJL helper `wjl_steam_service_763e527c…` from the committed payload;
  - `windows_dev_reload.lua` stripped.
- [ ] Run the isolated Lua 5.1 fixtures; record passes and skips.
- [ ] Confirm the ZIP is a normal-user build and its build label names the release commit.
- [ ] Check with `package_release.py` rules: `FILES-SHA256.txt`, CRC, `SHA256SUMS.txt`.

## 2. Verify the distributable

- [ ] Linux/Proton development builds on 26251122: each change above, as recorded in the notes (development-lineage acceptance).
- [ ] Exact final ZIP cold start under Boot Mod Loader:
  - WJL ready and keyboard lease;
  - Pose play/Stop;
  - Page Down Handycam;
  - menu blur with Exposure;
  - Saved Shot and return on reopen;
  - Follow player - Pivot and Pin;
  - Hide Helmet/Torso;
  - one screenshot.
  If not performed, every page says so.
- [ ] Native Windows: waits for player reports.
- [ ] Local Arsenal entry updated in place (GUID `7020a1c8-…`) with a rollback copy, every package checksum verified in the store, label and description updated.

## 3. Update every destination

- [ ] GitHub: `v1.3.3` annotated tag on the release commit, Latest, ZIP + `SHA256SUMS.txt`, notes from `RELEASE-1.3.3.md`; public download hash verified.
- [ ] Nexus: update the "War Journalist 1.3.2 - Boot Mod Loader - Complete" row to 1.3.3 with "Archive existing file", keep it primary. Also:
  - 1.3.3 changelog;
  - mod version and short description;
  - NEW IN 1.3.3 block;
  - seven photos kept.
- [ ] Ayaka: post a 1.3.3 update with the new version and the GitHub release link, then the overview block (short description at most 100 characters). Five inline photos and eleven gallery attachments are kept.
- [ ] Discord: thread title and starter updated for 1.3.3 (under 2,000 characters, starter image kept), no mass mentions.
- [ ] Inspect rendered pages and record URLs, photo counts and the Nexus scan state.

## Publication record

`PUBLICATION-1.3.3.md`: source commit, tag, ZIP hash, per-site URLs and state, Arsenal entry, tests and live scope, anything pending.
