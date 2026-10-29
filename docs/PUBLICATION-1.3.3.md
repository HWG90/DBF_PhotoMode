# War Journalist 1.3.3 publication record

Published 29 October 2026 from Linux. Boot Mod Loader only, for game build 26251122.

## Source and package

- Release commit `a7f3bb1` on `main`, annotated tag `v1.3.3`. It sits on the 27 commits of `claude/wj-26251122` (`f290f08` to `2c32a05`) on top of the 1.3.2 record `dec5f77`. Main changes:
  - `f290f08`: WJL and the renderer contract for game build 26251122.
  - `b19db31`: Pose Stop (cape resource compared by text); `9708ed0` logs which check refused.
  - `47e86c8`, `5816a69`: F11 left to the game (Steam Ctrl+F11); Handycam defaults to Page Down, a saved F11 moves once.
  - `3b3df72`: menu blur kept with scene options.
  - `db3887c`, `4d94835`: Saved Shots under Boot Mod Loader, bone-anchored; the camera returns on reopen.
  - `2eda1e3`, `c170899`, `5d9d0c4`: Freeze holds a running Helldiver (take-back only; pause and pin experiments off).
  - `d84d409`, `22f104c`: the first pose resets, then applies after settling.
  - `a3c9d01`: Follow player - Pivot and Pin.
  - `500de6d`: carry sockets left to the game while frozen.
  - `ed44582`, `ae0e9e6`, `1d2991e`, `c7ba34d`, `2c32a05`: armour pieces sorted by region markers, then height (rigid and skinned bounds), then bones.
- Not included: `claude/wj-1.3.3-discord-fixes` `766db66` (Ctrl+Shift+F10 soft-lock escape). It was never run in game, and its trigger was fixed by `b19db31`.
- `War-Journalist-1.3.3-BML.zip`, SHA-256 `4d8d8bb8e73fdb00a490fffc243c59b5dde1e118e35e57a6c4c355bea97442b8`, 3,165,468 bytes. Built from a clean worktree of `a7f3bb1` with `dist/review/release-1.3.3/build_package.py` and packaged with `package_release.py`. Normal-user build (`RELEASE_MODE=true`, 86 modules, `windows_dev_reload.lua` stripped); on-screen build label `20261029.1552-a7f3bb1`.
- Assets and native bridges are byte-identical to 1.3.2. WJL helper `wjl_steam_service_763e527c…` for game build 26251122, shipped as `wjl_steam_service.exe`.

## Tests

- Isolated Lua 5.1 fixtures: 103 groups passed, none failed, 1 skipped (LLL reference fixture: submodule not checked out). DBF-MCM fixtures ran with the Windows drive mounted.
- Live, development builds of this release, Linux/Proton with Boot Mod Loader on 26251122 (user confirmations):
  - WJL and the renderer check;
  - Pose Stop;
  - Ctrl+F11 and Handycam on Page Down;
  - menu blur with Exposure, with a fully graded screenshot;
  - Saved Shots following the face, and the camera returning on reopen;
  - Freeze while running (one-frame flicker accepted);
  - the first pose's cape;
  - Hide carried weapons with the slung primary;
  - Hide Torso on several armours, and Hide Helmet.
- Exact final package, cold start 2026-10-29 11:57 under Proton, deployed from HD2 Arsenal:
  - Boot Mod Loader 0.11.0 loaded the 5,297,219-byte add-on;
  - WJL ready in 0.3 s, game hashes and the renderer contract verified, keyboard lease acquired and restored;
  - Photo Mode opened, Freeze held (93 nodes, carry sockets excluded), a pose played with its cape placed;
  - Hide Helmet (5 meshes), Hide Torso (4 pieces, 21 meshes) and Hide Cape;
  - no errors, developer reload or diagnostics lines.
  The run did not exercise Page Down Handycam, Saved Shots and reopen, the Follow player cameras, an armour change or a screenshot. Logs: `dist/releases/1.3.3/LIVE-TEST-20261029-1157*.log` (not committed).
- Not confirmed in game: the Follow player cameras and the cape after an armour change. The notes say so.
- Native Windows: not tested in game for this release.

## Destinations

| Site | State |
|---|---|
| GitHub | https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.3, Latest. Assets: the ZIP and `SHA256SUMS.txt`. API digests and a fresh download match the local files. Notes: `docs/RELEASE-1.3.3.md`. |
| Nexus 17248 | File 71752, "War Journalist 1.3.3 - Boot Mod Loader - Complete", version 1.3.3, primary. Uploaded as an update of the 1.3.2 file, with "Archive existing file" and "Update mod version". Virus scan: Safe to use. Mod version 1.3.3; short description starts "1.3.3:". Description: header "1.3.3 LUA REWRITE", NEW IN 1.3.3 block in place of the 1.3.2 block, "War Journalist 1.3.3 for Boot Mod Loader". 7 description photos before and after. Non-essential cookies rejected on the consent dialog. |
| Ayaka 4948 | Version 1.3.3, with update https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/8504/ ("1.3.3 — Game update, Saved Shots and Follow cameras"). Download URL: the GitHub v1.3.3 release page. Overview: same edits as Nexus. Short description: "1.3.3: game update fix, Pose Stop, Saved Shots, Follow cameras. BML only; Native DoF works." 8 images in the description and 11 gallery attachments before and after. |
| Discord | Thread title "🪿War Journalist 1.3.3 — Lua Rewrite & Handycam". Starter message replaced with the 1.3.3 text (1,858 characters); its cover image kept. No separate announcement. |

Special thanks to Scarpheon, Muchacho, JuanHalodiver and jager of the Helldivers Modding Discord appear in the GitHub notes and on every page.

Proof screenshots are in `dist/releases/1.3.3/` (not committed).

## Local Arsenal

`~/.config/hd2arsenal/mods/War-Journalist-1.3.2-BML_AR139969` (GUID `7020a1c8-01ed-4a9d-874f-f778916eb067`) matches the published ZIP: 18 files, 17 checksums. Label "War Journalist (Lua 5.1) 1.3.3" with the 1.3.3 description. Rollback (the previous DEV `c7ba34d` staging): `~/.config/hd2arsenal/repair-backups/War-Journalist-1.3.2-BML_AR139969-before-release-1.3.3-20261029-114648`.

## Pending

Reports from native Windows players, and an in-game check of the Follow player cameras and of the cape after an armour change.
