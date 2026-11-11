# War Journalist 1.4.1 publication record

Published 11 November 2026 from Linux, the day Steam game build 26568081 arrived. One package for Boot Mod Loader and Chef Shared Loader 1.4.0 or newer. The user asked: "Push updates for WJ to all locations, git, ayaka, nexus. Update proton/LuaJIT WJ on git. Create new release notes and publish."

## Source and package

- Release commit `5cee5cf` on `main`, annotated tag `v1.4.1`. `main` moved by fast-forward from `95c1a4a` over `indev/wj-cape-all-bones` `4aa4c12` (the staged dev.14):
  - `9ca29a9` helper sources committed (shipped helper unchanged, `a6f5f3f6…`);
  - `1566114` refusal banner and Subject-tab reasons; `68eb654` pose recovery through Ctrl+Shift+F10, moving camera targets, shared-key guidance, unused modules archived; `9684b7a` nearest camera pin;
  - `772223d` posing under the hover-pack Freeze; `96348b0` name-mapped modded skeletons; `1eb0044` weapon swap during a held pose;
  - `ea4f622` renderer contract and Chef build identity for 26568081;
  - `e69ec8d` smoothed mouse look; `6dfaa1a` All-Bones mode; `4aa4c12` Natural limits;
  - the smaller package and build tidy merged on `main` after 1.4.0 (`c7400e7`).
- Not included: `claude/wj-ui-style` (the HD2-UI-Style restyle is for HellForge mods only, per `~/AGENTS.md`); `claude/wj-1.3.3-discord-fixes` `766db66`.
- `War-Journalist-1.4.1.zip`, SHA-256 `7df91f1193d4dec42fe6dc2e5e1fd604d20604c460adc0f4f4c2b18760c5846f`, 2,028,078 bytes. Built from the clean release worktree with `tools/build_package.py --release`, checked with `tools/test_package.py --zip … --release`.
  - Add-on `mods/goose/war_journalist`: 2,732,491 bytes, SHA-256 `5a439dcc…`, 94 modules, build label `20261111.2025-5cee5cf`, release mode (no dev reload, no diagnostics). Assets: the 1.3.0 bytes.

## Tests

- Isolated Lua 5.1 fixtures with the Windows drive mounted (DBF-MCM fixtures ran): 113 groups passed, none failed, 1 skipped (LLL reference fixture: submodule not checked out).
- Package proofs: Chef sandboxes 1.4.0, 1.4.1, 1.4.2-test1, 1.5.0 and 1.5.1 plus the 1.10.0 version-gate case; Boot Mod Loader 0.13.4's start-up checks ("starts"); LLL does not take it for a Chef addon; dev reload absent.
- `tools/test_wjl_helper_launch.py` headless against the installed 26568081 game: passed (`war_journalist_helper.exe`, no PowerShell).
- Live, development lineage on 26568081, Boot Mod Loader 0.13.4, Lua5.1 profile (Proton):
  - dev.12 `ea4f622`, 13:15: Boot Mod Loader warned "NOT THIS GAME VERSION" and started it; helper verified the game hashes and the renderer contract; scene effects, Freeze, a pose and a PNG in the logs.
  - dev.13 `6dfaa1a`, 14:24: All-Bones mode, user: "Works". Smoothed-look fix live since 13:30, not confirmed separately.
  - Natural limits `4aa4c12` by dev reload into the dev.13 session, user: "Works".
- Not run in game before publishing: the exact release ZIP (same code as dev.14 apart from release mode and the build label), Chef on 26568081, native Windows.

## Destinations

| Site | State |
|---|---|
| GitHub | https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.4.1, Latest. Assets: the ZIP and `SHA256SUMS.txt`; API digests and a fresh download match. Notes: `docs/RELEASE-1.4.1.md`. |
| GitHub, Proton line | Branch `WJ-LuaJIT` fast-forwarded `c13d6d5` → `bfbaca9` (`indev/wj-proton-26568081`, 35 commits: the Lua 5.1 parity merge and the 26568081 address and bridge port). That build is installed in `LLL/Mods/dbf_freecam` and loaded on the 26568081 launch at 12:46 (Photo Mode opened and closed, subject backend ready; user: "All good so far"). It does not have the hover-pack, holster-mod, weapon-swap, smoothed-look, All-Bones or Natural limits commits. |
| Nexus 17248 | File 73696, "War Journalist 1.4.1 - Boot Mod Loader and Chef", version 1.4.1, primary, uploaded as an update of 72378 (1.4.0) with "Archive existing file" and "Update mod version". Virus scan: Safe to use. Requirements carried over (Boot Mod Loader, or Chef Shared Loader). Mod version 1.4.1, changelog and short description. Description: header, NEW IN 1.4.1 block, version line, Bone Poser text and install line changed; 8 photos before and after. |
| Ayaka 4948 | Version 1.4.1, update https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/9117/ ("1.4.1 — Game update, All-Bones mode and Natural limits"), download URL the GitHub v1.4.1 release. Overview: same text as Nexus with Ayaka's two attached photos kept in place; 6 inline images and 11 gallery attachments before and after. Tag line: "1.4.1: works with the 11 Nov game update. All-Bones mode and Natural limits for bone posing." |
| Discord | Thread title "🪿War Journalist 1.4.1 — All-Bones & Natural Limits" (was "… 1.4.0 — Bone Posing & Chef Support"). Starter replaced (1,865 characters), its image kept. No announcement, no mentions. |

Copy follows the user's rules: one download for both loaders first, a bold Chef section, "Developed on Linux via Proton.", no "not tested" lines. Thanks to aharen_1, Devist8er and oldtr (the Discord reports behind the hover-pack, holster-mod and weapon-swap fixes) on every page. Proof screenshots: `dist/releases/1.4.1/NEXUS-PUBLISHED.jpg`, `AYAKA-PUBLISHED.jpg`, `DISCORD-PUBLISHED.jpg` (not committed). Page copy: `dist/releases/1.4.1/copy/`.

Browser: Claude in Chrome 1.0.106 (updated 2026-11-10) no longer works in Vivaldi 8.3. It confines every call to its own tab group and Vivaldi dissolves a one-tab group at once, so every tab was refused. The built-in browser pane would not keep the sign-ins. Nexus, Ayaka and Discord were published from Chromium with the extension installed there.

## Local Arsenal

Entry `7020a1c8-01ed-4a9d-874f-f778916eb067` points at `~/.config/hd2arsenal/mods/War-Journalist-1.4.1`: the release ZIP's files, 18 checksums verified, label "War Journalist 1.4.1", the release description. Written while Arsenal and the game ran, as a targeted text edit of the library record (the data file no longer round-trips through Python's JSON writer). Backup: `repair-backups/hd2a_data-before-wj-1.4.1-release-20261111-152642.json`. The dev.14 folder is untouched. It reaches the game on the next Deploy.

## Pending

- The Proton line on `WJ-LuaJIT` lacks the BML-line pose and look fixes since 1.4.0; porting them needs a Proton build and a live check.
- Chef Shared Loader on 26568081, and reports from native Windows players.
- Claude in Chrome in Vivaldi until the extension or Vivaldi changes.
