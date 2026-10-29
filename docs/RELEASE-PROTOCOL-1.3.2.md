# War Journalist 1.3.2 release protocol

Status: patch release of the 1.3.x Boot Mod Loader line, 28 October 2026.

## Release boundary

- One complete Boot Mod Loader package, `War-Journalist-1.3.2-BML.zip`. No BSL/MDL/LLL or Chef compatibility promise.
- Scope: the game never waits for WJL at startup; no hidden `start` dialogs; PNG screenshots on Windows (the engine's DDS converted by WJL, SDR and HDR10); Toggle HUD binding found in a second Steam library and under Proton; POV hiding, Handycam and Full Hide with any armour; renderer check raised for large mod setups and the owned shader archive found at any patch number; all hiding in Subject > Visibility, Handycam always hides the helmet; version and build on screen; one WJL file; default movement keys follow the keyboard layout. Everything else is 1.3.1.
- Every 1.3.0 limitation still open stays on every page: first pass of the Lua rewrite, BML only, Chef Lite planned without a whitelist guarantee, no AI control, no depth shaders (Native DoF works), occasional cape detachment, intermittent subject selection, incomplete Hide options.
- Keep all existing photos, credits and licenses on Nexus, Ayaka and Discord. Replace the NEW IN 1.3.1 block with 1.3.2; do not stack old change notes.

## 1. Lock source and package

- [ ] Release commit on top of `origin/main` (`5a86a59`, the merge of `claude/wj-1.3.1-windows`). Never stage `freecam/assets/shaders` CRLF noise, settings, logs or diagnostics.
- [ ] Build from the clean release worktree with `dist/review/release-1.3.2/build_package.py` (1.3.0 Assets and bridges reused byte for byte; WJL helper `28c3bc50…` from the committed payload).
- [ ] Run the isolated Lua 5.1 fixtures; record passes and skips.
- [ ] Confirm the ZIP is a normal-user build and its build label names the release commit without `+`.
- [ ] Check with `package_release.py` rules: `FILES-SHA256.txt`, CRC, `SHA256SUMS.txt`.

## 2. Verify the distributable

- [ ] Linux/Proton development builds: non-blocking start, PNG (SDR and HDR10), Toggle HUD from a second library, Full Hide/POV/Handycam after an armour change, exposure/contrast/saturation, version label. Done during development; recorded in the notes as development-lineage acceptance.
- [ ] Native Windows: exposure with a development build. Startup fix, PNG and keyboard layout on Windows wait for player reports.
- [ ] Keyboard layout: Wine with a US layout only.
- [ ] Exact final ZIP cold start: not performed unless recorded here; every page says so.
- [ ] Local Arsenal entry updated in place (GUID `7020a1c8-…`) with a rollback copy, every package checksum verified in the store, label and description updated.

## 3. Update every destination

- [ ] GitHub: `v1.3.2` annotated tag on the release commit, Latest, ZIP + `SHA256SUMS.txt`, notes from `RELEASE-1.3.2.md`; public download hash verified.
- [ ] Nexus: update the "War Journalist 1.3.1 - Boot Mod Loader - Complete" row to 1.3.2 with "Archive existing file", keep it primary; 1.3.2 changelog; mod version and short description; NEW IN 1.3.2 block; seven photos kept.
- [ ] Ayaka: post a 1.3.2 update with the new version and the GitHub release link, then the overview block; five inline photos and eleven gallery attachments kept.
- [ ] Discord: thread title and starter updated for 1.3.2 (under 2,000 characters, starter image kept), no mass mentions.
- [ ] Inspect rendered pages and record URLs, photo counts and the Nexus scan state.

## Publication record

`PUBLICATION-1.3.2.md`: source commit, tag, ZIP hash, per-site URLs and state, Arsenal entry, tests and live scope, anything pending.
