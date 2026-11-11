# War Journalist 1.4.1 release protocol

Status: patch release of the one-package line (Boot Mod Loader and Chef Shared Loader) for Steam game build 26568081, which arrived 2026-11-11. The user asked on 2026-11-11: "Push updates for WJ to all locations, git, ayaka, nexus. Update proton/LuaJIT WJ on git. Create new release notes and publish."

## Release boundary

- One ZIP, `War-Journalist-1.4.1.zip`, Arsenal/Nexus GUID `7020a1c8-01ed-4a9d-874f-f778916eb067`, option "War Journalist". Players upgrade from 1.4.0.
- Source: `indev/wj-cape-all-bones` at `4aa4c12` (the staged dev.14), fast-forwarded onto `origin/main` `95c1a4a`:
  - `9ca29a9` helper sources committed (no change to the shipped helper);
  - `1566114` refusal banner and Subject-tab reasons; `68eb654` pose recovery through Ctrl+Shift+F10, moving camera targets, shared-key guidance, unused modules archived; `9684b7a` nearest camera pin;
  - `772223d` posing under the hover-pack Freeze; `96348b0` name-mapped modded skeletons; `1eb0044` weapon swap during a held pose;
  - `ea4f622` renderer contract and Chef build identity for 26568081;
  - `e69ec8d` smoothed mouse look; `6dfaa1a` All-Bones mode; `4aa4c12` Natural limits;
  - the smaller package and build tidy already on `main` (`c7400e7`).
- Not in this release: `claude/wj-ui-style` (the HD2-UI-Style restyle is for HellForge mods only, per `~/AGENTS.md`); `claude/wj-1.3.3-discord-fixes` `766db66`.
- Every page keeps the one-download statement, the Chef "read this first" section and the 1.4.0 known bugs, in the voice of `listing-copy.md` ("Developed on Linux via Proton.", no "not tested" lines).
- Keep all photos: Nexus 8 in the description, Ayaka 6 inline and 11 gallery attachments, the Discord starter image.

## 1. Lock source and package

- [ ] Release worktree `~/Worktrees/linux-hd2/wj-release-1.4.1` (`release/1.4.1`), `--ff-only` to `4aa4c12`; gitignored inputs copied (`dist/chef-src/sandbox/`, `dist/bml-src/f476df93691895fa.lua`).
- [ ] `test_steam_port` with the Windows drive mounted (DBF-MCM fixtures), `test_package --release`.
- [ ] `build_package.py --release`, `test_package --zip … --release`; headless `test_wjl_helper_launch.py` against the installed 26568081 game.

## 2. Verify the distributable

- [ ] Arsenal entry `7020a1c8` updated to the release with a rollback, checksums verified, label and description updated.
- [ ] Live acceptance by development lineage on 26568081 (Boot Mod Loader 0.13.4, Lua5.1 profile): dev.12 `ea4f622` (helper, contract, scene effects, Freeze, pose, PNG), dev.13 `6dfaa1a` (All-Bones: user "Works"), Natural limits `4aa4c12` by dev reload (user "Works"). The exact release ZIP and Chef on 26568081 are not run before publishing; the publication record says so.

## 3. Update every destination

- [ ] GitHub `v1.4.1`, Latest, ZIP + `SHA256SUMS.txt`, notes `docs/RELEASE-1.4.1.md`, digests and download verified.
- [ ] Nexus 17248: update file 72378 (1.4.0) to "War Journalist 1.4.1 - Boot Mod Loader and Chef" with "Archive existing file" and "Update mod version"; changelog, short description, NEW IN 1.4.1 block and version strings; requirements kept.
- [ ] Ayaka 4948: 1.4.1 update linking the GitHub release, version 1.4.1, overview NEW IN block, tag line.
- [ ] Discord: thread title and starter for 1.4.1, image kept.
- [ ] Proton line: push `indev/wj-proton-26568081` `bfbaca9` (installed and running on 26568081) to `WJ-LuaJIT` as a fast-forward from `c13d6d5`.

## Publication record

`PUBLICATION-1.4.1.md`: source, tag, ZIP hash, per-site state, Proton branch, Arsenal entry, tests and live scope.
