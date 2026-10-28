# War Journalist 1.3.2 publication record

Published 28 October 2026 from Linux. Boot Mod Loader only.

## Source and package

- Release commit `8cb53fd` on `main`, annotated tag `v1.3.2`. It sits on `5a86a59`, the merge of PR #2 (`claude/wj-1.3.1-windows`), whose 1.3.2 commits on top of 1.3.1 are:
  - `305a3cf`: the game never waits for WJL; PNG screenshots on Windows.
  - `9c5ddf9`: PNGs from the engine's DDS, converted by WJL; Toggle HUD in a second Steam library.
  - `333f294`: any armour, one WJL file, hiding in one place, modded installs keep scene effects.
  - `8c028cc`: version and build on screen; Handycam helmet retries an unsettled outfit.
  - `87e6f2b`: the owned shader archive found at any patch number.
  - `ab02f2b`: default movement keys follow the keyboard layout.
- `War-Journalist-1.3.2-BML.zip`, SHA-256 `079f1870d96b8064602ed9d34f7d8dee9a2f67ad1e434b102eec067217a2edbf`, 3,148,847 bytes. Built from a clean worktree of `8cb53fd` with `dist/review/release-1.3.2/build_package.py` and packaged with `package_release.py`. Normal-user build (`RELEASE_MODE=true`); the on-screen build label is `20261028.0421-8cb53fd`.
- Assets and native bridges are byte-identical to 1.3.0/1.3.1. WJL helper `wjl_steam_service.exe`, SHA-256 `28c3bc50d8f6433b3d406ea4ca2345033503ddcd4f583e07781ba8458ca939dc`, built with Visual Studio 2022 MSVC 14.44 and Windows SDK 10.0.26100 under Wine.

## Tests

- Isolated Lua 5.1 fixtures: 102 groups passed, none failed, 1 skipped (LLL reference fixture: submodule not checked out).
- WJL under Wine against the real game executable: readiness, game root, renderer check (stock install and a 600-patch mod setup), refusal of another game build, SDR and HDR10 DDS-to-PNG jobs (every pixel matched the 0.9.x converter), keyboard layout (US: W/A/S/D/Q/E), helper removed after writing.
- Live, development builds of this release, Linux/Proton with Boot Mod Loader: non-blocking start; SDR and 4K HDR10 PNGs; Toggle HUD from a second Steam library; Full Hide, POV hiding and Handycam after an armour change; exposure, contrast and saturation; version label.
- Native Windows: exposure with a development build of this release. Startup fix, PNGs and keyboard layout on Windows wait for player reports.
- The exact final ZIP was not cold-started in game before publication. Every page says so.

## Destinations

| Site | State |
|---|---|
| GitHub | https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.2, Latest. Assets: the ZIP and `SHA256SUMS.txt`. API digests and a fresh download match the local files. Notes: `docs/RELEASE-1.3.2.md`. |
| Nexus 17248 | "War Journalist 1.3.2 - Boot Mod Loader - Complete", version 1.3.2, primary, uploaded as an update of the 1.3.1 file with "Archive existing file". Virus scan: Safe to use; Manual download available. Mod version 1.3.2; short description starts "1.3.2:"; description header "1.3.2 LUA REWRITE", NEW IN 1.3.2 block (with the tester thanks) in place of the 1.3.1 block, "War Journalist 1.3.2 for Boot Mod Loader". 7 description photos before and after. |
| Ayaka 4948 | Version 1.3.2 with update https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/8450/ ("1.3.2 — Startup, PNGs and any armour"); download URL is the GitHub v1.3.2 release page. Overview: same edits as Nexus. Short description: "1.3.2: startup fix, Windows PNGs, any armour. BML only; Native DoF works. Cape/selection/hide bugs." 8 images in the description and 11 gallery attachments before and after. |
| Discord | Thread title "🪿War Journalist 1.3.2 — Lua Rewrite & Handycam". Starter message replaced with the 1.3.2 text; its cover image kept. No separate announcement. |

Thanks to Muchacho, JuanHalodiver, Scarpheon and jager of the Helldivers Modding Discord for bug testing appear in the GitHub notes and on every page.

Proof screenshots are in `dist/releases/1.3.2/` (not committed).

## Local Arsenal

`~/.config/hd2arsenal/mods/War-Journalist-1.3.2-BML_AR139969` (GUID `7020a1c8-01ed-4a9d-874f-f778916eb067`) matches the published ZIP, 17 of 17 files; label "War Journalist (Lua 5.1) 1.3.2" and the 1.3.2 description. Rollback: `~/.config/hd2arsenal/repair-backups/War-Journalist-1.3.2-BML-before-release-1.3.2-20261028-002247`.

## Pending

A cold start of the exact ZIP, and reports from native Windows and AZERTY players.
