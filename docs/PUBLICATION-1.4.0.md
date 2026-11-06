# War Journalist 1.4.0 publication record

Published 2 November 2026 from Linux. One package for Boot Mod Loader and Chef Shared Loader 1.4.0 or newer, for game build 26251122.

## Source and package

- Release commit `ae5c4d0` on `main`, annotated tag `v1.4.0`. `main` moved by fast-forward from `71d5f09` (the 1.3.3 page-edit record) over `claude/wj-chef-unified` `d6e7e98`.
  - The 1.3.4 changes: `3dd3a26` (helper renamed `war_journalist_helper.exe`, version info, one file across game updates, no hidden guard files), `af83143`, `823370e` (Center auto-focus when the depth read is too slow), and their release commit `82bbfe0`.
  - Bone posing: `b59ac13` to `f06a95c`, then `70eb156` (edits kept across close and reopen) and `d035e77` (a pose the game takes back no longer blocks subject discovery).
  - The Chef line `71468fd`, merged in `f4e51be`; the one head and builder `7684c3b` to `3c4375b`; the 1.3.x key carry-over `6b12cc0`.
- 1.3.4 was never published. Its ZIP (`ebb96437…`) was built and staged on 2026-10-31. On 2026-11-02 the user chose "Skip to 1.4.0", so 1.4.0 carries its changes and players upgrade from 1.3.3.
- Not included: `claude/wj-1.3.3-discord-fixes` `766db66`; bone-posing work after `d6e7e98`; `claude/wj-one-package-tidy` `6963589` and `claude/wj-package-shrink` `d8ce2c3` (tooling and the smaller package, which passed its own live check on Boot Mod Loader at 13:27–13:32; they merge into `main` only on the user's word).
- `War-Journalist-1.4.0.zip`, SHA-256 `41db843bcd05866b132c745346ae5c679e9ea786962369e196a41a6d101d0af3`, 2,196,650 bytes, 19 files. Built from the clean release worktree with `tools/build_package.py --release` and checked with `tools/test_package.py --zip … --release`.
  - Add-on `mods/goose/war_journalist`: 3,440,523 bytes, SHA-256 `4d1ebf4b…`, 91 modules, build label `20261102.1848-ae5c4d0`, release mode (no dev reload, no diagnostics).
  - Helper payload `a6f5f3f6…` (the 1.3.4 helper). Assets are the 1.3.0 bytes (`9ba626afa44a3aa3.patch_0` `de5e7ace…`, `ee6b1ba7e22d71ed.patch_0` `adc22971…`, its `.gpu_resources` `feed3eb1…`). No native bridges, no depth shaders.
- The first release build, `3c669e42…` from `e33aca4`, is in `dist/review/superseded-e33aca4/` (not committed). The user then asked for copy changes. The rebuilt ZIP's Lua differs from it only in the build label line; assets are identical; the notes, `INSTALL.txt`, `KNOWN-ISSUES.md` and the Arsenal description changed.

## Tests

- Isolated Lua 5.1 fixtures: 110 groups passed, none failed, 1 skipped (LLL reference fixture: submodule not checked out).
- Package proofs on the built text: Chef sandboxes 1.4.0, 1.4.1, 1.4.2-test1, 1.5.0 and 1.5.1 (start, 15 keys, render hook, no refused calls) plus a 1.10.0 version-gate case; Boot Mod Loader 0.13.4's own start-up checks ("starts"); LLL does not take it for a Chef addon; 1.3.x key carry-over.
- Live, the first release build `e33aca4` (same code as the final ZIP apart from the build label), Linux/Proton, 2026-11-02:
  - 13:19: the published 1.3.3 on Boot Mod Loader. The user then imported the 1.4.0 ZIP in HD2 Arsenal's UI: Arsenal updated entry `7020a1c8` in place (new folder `War-Journalist-1.4.0_AR603033`), and the renamed option "War Journalist" stayed on.
  - 13:22, Boot Mod Loader 0.13.4: keys carried over from `mbm_war_journalist_lua51_settings.txt`, helper ready in 0.3 s, renderer contract verified, keyboard lock taken and restored, a PNG saved, a catalogue pose with its cape, double-click focus, and Center auto-focus on its settled path (depth read 18 ms against the 8 ms budget). No errors, no dev reload or diagnostics lines.
  - 13:23, Chef Shared Loader 1.5.1: trusted and started 1.4.0 (`updated … 1.4.0-dev.3 -> 1.4.0`), panel drawn through the render hook, mouse held, a DDS screenshot saved.
  - Logs: `dist/releases/1.4.0/LIVE-TEST-20261102-*` (not committed).
- Development lineage `1.4.0-dev.3` (`d035e77`, identical code): bone edits kept across 94 opens, Chef 1.5.1 alone, both loaders deployed (`docs/LIVE-TEST-1.4.0-dev.md`).
- Not exercised on a release build: bone edits and saved poses, double-click and Center focus under Chef, LLL, native Windows. The final ZIP `ae5c4d0` itself was not started.

## Copy rules from the user (2026-11-02)

After the first approval message the user asked to: say Center auto-focus "works as intended now" instead of "works at 4K"; not mention "not tested on Windows" and say "Developed on Linux via Proton." instead; stress Chef's limits; stress that one download covers both loaders; add their bone posing photo under the bone posing section and keep the other photos. Every page follows that.

## Destinations

| Site | State |
|---|---|
| GitHub | https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.4.0, Latest. Assets: the ZIP and `SHA256SUMS.txt`; API digests and a fresh download match. Notes: `docs/RELEASE-1.4.0.md`, with the photo from `docs/artwork/war-journalist-1.4.0-bone-posing.jpg` at the tag. |
| Nexus 17248 | File 72378, "War Journalist 1.4.0 - Boot Mod Loader and Chef", version 1.4.0, primary, uploaded as an update of 71752 (1.3.3) with "Archive existing file" and "Update mod version". Nexus allows 50 characters, so the approved "… - Complete" name was shortened. Virus scan: Safe to use (scan link carries the ZIP SHA-256). Mod version 1.4.0, changelog and short description. Description: 8 photos (the 7 kept plus the new photo, uploaded to the mod's gallery as `17248-1793645519-1128387612.jpg`), new Chef and Bone Poser sections. Requirements for 72378: Boot Mod Loader, or alternatively Chef Shared Loader 1.5.1 or newer. |
| Ayaka 4948 | Version 1.4.0, update https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/8680/ ("1.4.0 — Bone posing and Chef's Shared Loader"). Download URL: the GitHub v1.4.0 release page. Overview: same text as Nexus, Ayaka's own two attached photos kept in place, the new photo from Nexus; 6 inline images (5 kept plus 1) and 11 gallery attachments before and after. Tag line: "1.4.0: one ZIP for Boot Mod Loader and Chef's Shared Loader. New bone posing and saved poses." |
| Discord | Thread title "🪿War Journalist 1.4.0 — Bone Posing & Chef Support" (was "… 1.3.3 — Lua Rewrite & Handycam"). Starter message replaced (1,866 characters); its cover image kept. Discord cannot add an attachment to an existing message, so the new photo is not in the starter. No announcement, no mentions. |

Thanks to JuanHalodiver (Defender report) and Chefbo (Chef Shared Loader features) appear on every page. Proof screenshots: `dist/releases/1.4.0/NEXUS-PUBLISHED.jpg`, `AYAKA-PUBLISHED.jpg`, `DISCORD-PUBLISHED.jpg` (not committed).

## Local Arsenal

`~/.config/hd2arsenal/mods/War-Journalist-1.4.0_AR603033` (GUID `7020a1c8-01ed-4a9d-874f-f778916eb067`) holds the published ZIP: 18 checksums verified, label "War Journalist 1.4.0", the release description, option "War Journalist". It needs a Deploy to reach the game. Rollbacks in `~/.config/hd2arsenal/repair-backups/`: `hd2a_data-before-wj-1.4.0-release-*` and `War-Journalist-1.4.0_AR603033-e33aca4-before-release-*`. The smaller-package build stays in `mods/War-Journalist-1.4.0-dev.5`. The old store folder `War-Journalist-1.3.2-BML_AR139969` holds 1.3.3's files and is no longer referenced.

## Page-only edits, 2 November 2026 (later the same day)

- The user reported bone posing checked in game on Chef and asked to remove the "Not checked in game on Chef yet" line. It is gone from `docs/RELEASE-1.4.0.md` (and the v1.4.0 release body), `docs/KNOWN-ISSUES.md`, and the Chef section of the Nexus and Ayaka descriptions. Discord and the update texts never had it. No binaries, tags or files changed; the ZIP's own `RELEASE-NOTES.md` and `KNOWN-ISSUES.md` keep the line, since published bytes don't change. The pages as first published are in `dist/releases/1.4.0/copy/as-published/` (not committed).
- The same day, at the user's word, `claude/wj-package-shrink` `d8ce2c3` (with `claude/wj-one-package-tidy` `6963589`) was merged into `main` (`c7400e7`): 111 fixture groups passed, 1 skipped; `test_package` dev and release passed. It is for the next release, not in the 1.4.0 ZIP.

## Pending

- Reports from native Windows players, including Defender's view of the new helper.
- In game under Chef with 1.4.0: double-click and Center focus (bone posing was checked by the user).
- A message to Chefbo about the single package, on the user's word.
- The Chef dev Arsenal entry `7b18fc08` is switched off; the GitHub Chef preview 5 pre-release stays as a historical build.
