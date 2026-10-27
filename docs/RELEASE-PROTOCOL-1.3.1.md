# War Journalist 1.3.1 release protocol

Status: patch release of the 1.3.0 Boot Mod Loader line, 27 October 2026.

## Release boundary

- One complete Boot Mod Loader package, `War-Journalist-1.3.1-BML.zip`. No BSL/MDL/LLL or Chef compatibility promise.
- Scope: WJL keyboard reservation when another program owns a Ctrl/Shift/Alt shortcut (Windows error 1409), Handycam refusal notices, PowerShell-free WJL startup through `cmd.exe`, and the Proton in-game keyboard fallback. Everything else is 1.3.0.
- Every 1.3.0 limitation stays on every page: first pass of the Lua rewrite, BML only, Chef Lite planned without a whitelist guarantee, no AI control, no depth shaders (Native DoF works), occasional cape detachment, intermittent subject selection, incomplete Hide options.
- Keep all existing photos, credits and licenses on Nexus, Ayaka and Discord. Add a 1.3.1 block; do not stack old change notes.

## 1. Lock source and package

- [ ] Commit the 1.3.1 source on top of `origin/main` (`15b3fb2`). Never stage `freecam/assets/shaders` CRLF noise, settings, logs or diagnostics.
- [ ] Build from a clean checkout of the release commit with `dist/review/release-1.3.1/build_package.py` (1.3.0 Assets and bridges reused byte for byte).
- [ ] Run the isolated Lua 5.1 fixtures; record passes and skips.
- [ ] Confirm the release build's addon and archive bytes match the build tested live, and that the ZIP is a normal-user build.
- [ ] Package and check `FILES-SHA256.txt`, CRC and `SHA256SUMS.txt`.

## 2. Verify the distributable

- [ ] Linux/Proton: WJL starts via `cmd.exe`, the renderer contract verifies, Photo Mode opens and closes with keyboard capture acknowledged.
- [ ] Native Windows: Photo Mode stays open with a GPU overlay installed; F11 Handycam and panel buttons respond. Not tested before publication unless recorded here.
- [ ] Local Arsenal entry updated in place (GUID `7020a1c8-…`) with a rollback copy and every package checksum verified in the store.

## 3. Update every destination

- [ ] GitHub: `v1.3.1` annotated tag on the release commit, Latest, ZIP + `SHA256SUMS.txt`, notes from `RELEASE-1.3.1.md`; public download hash verified.
- [ ] Nexus: update the "War Journalist 1.3.0 - Boot Mod Loader - Complete" row to 1.3.1, archive the 1.3.0 file, keep it primary; 1.3.1 changelog; mod version and short description; NEW IN 1.3.1 block; seven photos kept.
- [ ] Ayaka: post a 1.3.1 update with the new version and the GitHub release link, then the overview block; five inline photos and eleven gallery attachments kept.
- [ ] Discord: thread title and starter updated for 1.3.1 (under 2,000 characters, starter image kept), one announcement, no mass mentions.
- [ ] Inspect rendered pages and record URLs, photo counts and the Nexus scan state.

## Publication record

`PUBLICATION-1.3.1.md`: source commit, tag, ZIP hash, per-site URLs and state, Arsenal entry, tests and live scope, anything pending.
