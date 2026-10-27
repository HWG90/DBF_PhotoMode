# War Journalist 1.3.1 publication record

Published 27 October 2026 from Linux. Boot Mod Loader only.

## Source and package

- Release commit `8262009` on `main`, annotated tag `v1.3.1`. Commits on top of 1.3.0 (`15b3fb2`):
  - `00b13e0`: keep Windows Photo Mode input when another program owns a shortcut (error 1409).
  - `88d307b`: release docs, PowerShell-free WJL startup through `cmd.exe`.
  - `3df3e7d`: cursor kept in the game window; no in-game DLLs under Boot Mod Loader; Proton keyboard fallback removed.
  - `8262009`: notes record the live pass of the final build.
- `War-Journalist-1.3.1-BML.zip`, SHA-256 `cb646ae92a0710aa0174a46088333775df8f5cd7aef256567a218cae199a4027`, 3,093,473 bytes. Built from a clean checkout of `8262009` with `dist/review/release-1.3.1/build_package.py` (1.3.0 Assets and bridges reused byte for byte) and checked with `package_release.py`. Normal-user build (`RELEASE_MODE=true`).
- Two earlier local 1.3.1 builds were never published: `88d307b` (`6440d6bf…`, still had the Proton keyboard fallback) and `3df3e7d` (`844d6523…`, identical runtime to the final ZIP; only `RELEASE-NOTES.md` and its checksum list differ).

## Tests

- Isolated Lua 5.1 fixtures: 102 groups passed, none failed, 1 skipped (LLL reference fixture: submodule not checked out).
- Live on Linux/Proton, Boot Mod Loader, 27 Oct 09:39: the PowerShell-free build started WJL through `cmd.exe`, verified the stock renderer, and opened and closed Photo Mode six times with keyboard capture acknowledged.
- Live on Linux/Proton, Boot Mod Loader, 27 Oct 11:54: the `3df3e7d` package (same runtime as the published ZIP) deployed from HD2 Arsenal and cold-started without a manually started helper. WJL started and verified the renderer; Photo Mode and Handycam opened and closed with keyboard capture and restoration acknowledged; the subject and HUD backends refused in-game DLLs ("In-process native libraries are not used by the Windows build"); no errors, developer reload or diagnostics lines. The cursor staying inside the game window was checked by eye; neither log records it.
- Native Windows: not tested in game. Every page says so.

## Destinations

| Site | State |
|---|---|
| GitHub | https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.1, Latest. Assets: the ZIP and `SHA256SUMS.txt`. API digests and a fresh download match the local files. Notes: `docs/RELEASE-1.3.1.md`. |
| Nexus 17248 | File 71366 "War Journalist 1.3.1 - Boot Mod Loader - Complete", version 1.3.1, primary, uploaded as an update of the 1.3.0 file with "Archive existing file". Virus scan: Safe to use; manual download available. Mod version 1.3.1; short description starts "1.3.1:"; description header "1.3.1 LUA REWRITE", NEW IN 1.3.1 block after the thank-you paragraph, "War Journalist 1.3.1 for Boot Mod Loader". 7 description photos before and after. |
| Ayaka 4948 | Version 1.3.1 with update https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/8425/ ("1.3.1 — Windows and Proton input fix"); download URL is the GitHub v1.3.1 release page. Overview: same three description edits as Nexus. Short description shortened to fit Ayaka's 100-character limit: "1.3.1: Windows/Proton input fix. BML only. Native DoF works; cape, selection, hiding issues remain." Images in the description (8 by `.bbWrapper img`, five of them photos) and 11 gallery attachments before and after. |
| Discord | Thread title "🪿War Journalist 1.3.1 — Lua Rewrite & Handycam". Starter message replaced with the 1.3.1 text (1,883 characters); its cover image kept. The previous starter held the 1.3.0 text twice (a paste artifact); that is gone. No separate announcement. |

Proof screenshots and the live-test logs are in `dist/releases/1.3.1/` (not committed).

## Local Arsenal

`~/.config/hd2arsenal/mods/War-Journalist-1.3.1-BML_AR148731` (GUID `7020a1c8-01ed-4a9d-874f-f778916eb067`) matches the published ZIP, 17 of 17 files. Rollbacks in `~/.config/hd2arsenal/repair-backups/`: `…-before-release-1.3.1-20261027-103435`, `…-before-cursor-windows-only-20261027T110611`.

## Pending

Nothing for this release. Native Windows players' reports are the open test.
