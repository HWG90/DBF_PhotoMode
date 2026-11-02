# War Journalist 1.4.0 release protocol

Status: minor release after 1.3.3, for game build 26251122. One package for Boot Mod Loader and Chef Shared Loader, bone posing, and the 1.3.4 changes. 1.3.4 was built and staged but never published: on 2026-11-02 the user chose "Skip to 1.4.0", so 1.4.0 carries its changes and players upgrade from 1.3.3.

## Release boundary

- One ZIP, `War-Journalist-1.4.0.zip`, Arsenal/Nexus GUID `7020a1c8-01ed-4a9d-874f-f778916eb067` (the published entry, so 1.3.3 players get an update). One option, "War Journalist" (was "War Journalist (Lua 5.1)"), holding the `War Journalist` folder and `Assets`.
- One Lua resource, `mods/goose/war_journalist`, that picks its host: Boot Mod Loader 0.13.4 (WJL helper, PNG), Chef Shared Loader 1.4.0 or newer (its own host, DDS screenshots, depth from 1.4.2), or LLL (entry only, no bridges; not promised on the pages).
- Source: `claude/wj-chef-unified` at `d6e7e98`, fast-forwarded onto `origin/main` (`71d5f09`). It contains:
  - 1.3.4's `3dd3a26` (helper renamed `war_journalist_helper.exe`, version info, one file across game updates, no hidden guard files), `af83143` (plain pause message), `823370e` (Center auto-focus at 4K) and its unpublished release commit `82bbfe0`;
  - bone posing (`b59ac13` to `f06a95c`, `70eb156`, `d035e77`): Pose editor and Saved poses in the Subject tab, edits kept across close and reopen;
  - the Chef line `71468fd` merged (`f4e51be`), the one head and builder (`7684c3b` to `3c4375b`), and the 1.3.x key carry-over (`6b12cc0`).
- Assets: the 1.3.0 bytes pinned in `tools/package_head.py`. No native bridges, no depth shaders.
- Not in this release: `claude/wj-1.3.3-discord-fixes` `766db66`; bone-posing work after `d6e7e98` (commit freeze on the branch until 1.4.0 ships); the Proton (LuaJIT/LLL) build.
- Every known 1.3.x limitation stays on every page, plus the Chef differences (keys reach the game, DDS screenshots, Chef 1.5.1 for focus) in the voice of `listing-copy.md`.
- The support statement changes on every page: Boot Mod Loader or Chef's Shared Loader 1.4.0 or newer, instead of "Boot Mod Loader only; a Lite version for Chef is planned".
- Keep all photos, credits and licenses on Nexus, Ayaka and Discord. Replace the NEW IN 1.3.3 block with 1.4.0.
- After it ships: the Chef dev Arsenal entry `7b18fc08` and the GitHub `chefbuild` previews are retired; telling Chefbo about the single package is a message the user approves.

## 1. Lock source and package

- [ ] Release worktree `~/Worktrees/linux-hd2/wj-release-1.4.0` (`release/1.4.0`) from `origin/main`, `--ff-only` to `d6e7e98`. Gitignored inputs copied from `wj-chef-unified`: `dist/chef-src/sandbox/` (Chef 1.2.4 to 1.5.1) and `dist/bml-src/f476df93691895fa.lua` (`7cc69039…`). Never stage the CRLF `freecam/assets/shaders/*.hlsl`.
- [ ] Release edits: `docs/RELEASE-1.4.0.md`, `docs/KNOWN-ISSUES.md`, `README.md`, this file, `tools/build_package.py` (`RELEASE_DESCRIPTION`; INSTALL says one option to switch on; the dev line says reload works once armed).
- [ ] `tools/test_steam_port.py` and `tools/test_package.py --release`.
- [ ] `tools/build_package.py --release`, then `tools/test_package.py --zip … --release`. Release mode: no dev reload, no diagnostics, no probe read; size at most 3,800,000 bytes.

## 2. Verify the distributable

- [ ] Upgrade path as a 1.3.3 player has it: Arsenal entry back on the published 1.3.3 files with its "War Journalist (Lua 5.1)" option enabled, the 1.3.x key file only; then the user imports `War-Journalist-1.4.0.zip` in Arsenal's UI, Deploys with the game closed and cold-starts.
  - Arsenal updates the existing entry, and War Journalist is on after the import.
  - Boot Mod Loader loads `mods/goose/war_journalist`; keys carried over; helper ready; Photo Mode opens; a bone edit, a saved pose and a PNG.
  - No dev reload or diagnostics lines.
- [ ] Chef alone and both loaders: development lineage `1.4.0-dev.3` (`d035e77`, same Lua as the release apart from release mode), runs 2 and 3 of `docs/LIVE-TEST-1.4.0-dev.md`.
- [ ] Native Windows: wait for player reports.

## 3. Update every destination

- [ ] GitHub: `v1.4.0` annotated tag on the release commit, Latest, ZIP + `SHA256SUMS.txt`, notes from `RELEASE-1.4.0.md`; public download hash verified.
- [ ] Nexus 17248: update the 1.3.3 file row to "War Journalist 1.4.0 - Boot Mod Loader and Chef - Complete" with "Archive existing file" and "Update mod version", primary; changelog, short description, description (header, NEW IN 1.4.0 block, support paragraph, pose and install sections); Chef's Shared Loader added beside Boot Mod Loader in the requirements; seven photos kept.
- [ ] Ayaka 4948: 1.4.0 update with the GitHub release link, version 1.4.0, the same description edits, tag line (at most 100 characters). Five inline photos and eleven gallery attachments kept.
- [ ] Discord: thread title and starter for 1.4.0 (under 2,000 characters, starter image kept), no mass mentions.
- [ ] Inspect rendered pages; record URLs, photo counts and the Nexus scan state.

## Publication record

`PUBLICATION-1.4.0.md`: source commit, tag, ZIP hash, helper hash, per-site URLs and state, the Arsenal entry, tests and live scope (exact ZIP on Boot Mod Loader; Chef by development lineage), that 1.3.4 was never published, anything pending.
