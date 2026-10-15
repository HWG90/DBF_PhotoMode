# War Journalist 1.0 publication

Published October 15, 2026 from `9e8c81545aa0ae42873fbd9a2066fd02994c4687`, tag `v1.0`.

- [GitHub](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.0): latest stable release with complete BSL, MDL and LLL bundles, checksums and release notes. All five public downloads were independently compared with the validated local artifacts; all match.
- [Nexus](https://www.nexusmods.com/helldivers2/mods/17248?tab=files): BSL 68839 is the primary main file and MDL 68840 is the optional complete file with no nested archives. Both are publicly downloadable; the page reports **Safe to use** and links both exact release SHA-256 hashes in its scan results. Older files were archived. LLL was not uploaded to Nexus.
- [Ayaka](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/): public version, overview, complete BSL download URL and [update 7343](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/7343/) verified. The overview links the complete MDL download and all three GitHub packages. All 11 gallery attachments and five original inline images remain.
- [Discord announcement](https://discord.com/channels/1260111500522295377/1559027203315073094/1560154458535501854): posted once and verified as a rendered message; the thread title is now **War Journalist 1.0 — A Helldivers 2 Photo Mode**. The message composer is empty.

Nexus retains all seven original inline images, feature sections and credits. Both main pages remove the historical 0.9.5–0.9.8 release-note blocks and prominently thank everyone contributing photos, tests and bug reports. Historical update posts remain in their dedicated update history.

All 63 clean-source fixture groups, three standalone loader startup/cleanup checks, package structure, checksums and asset-closure checks passed. The exact-zero ragdoll captured-pose hold, resume and Subject-pose handoff were accepted live, as were action-shot unfreeze/refreeze and Cinema hint fading. Existing accepted compositor, materials, lights and logo resources are bundled. Lighting remains **Not tested fully** and Shader DoF remains a preview; HDR/SDR switching is not claimed fixed.

The separate, uncommitted external-editor input-sharing bridge and old diagnostic/hook experiments were excluded by building from a clean archive of the tagged source. Those local changes remain preserved and unstaged. The installed development runtime, public package validation and publication evidence are separate records.

Local LLL and the existing Arsenal source received a backed-up metadata/documentation refresh to 1.0: 21 files updated and hash-verified, with all 134 protected files and 88 screenshots unchanged. Both 12-module inventories pass. Runtime Lua, native libraries, settings, presets and the closed 319-entry merged Photo/HUD shader assets were preserved. Local provenance records the editor-bridge and whitespace differences from the public runtime; it does not claim exact public-package identity. No reload or restart was performed.

Ayaka's current version record is 8391. Its overview edit also relabeled the preceding record 8288 to 1.0 before the new version was posted; the history interface exposes deletion but no edit for that older record. Both records were retained. The previous 0.9.9 update and GitHub release remain available.

Local receipts and browser proof images are under `dist/review/release-1.0`; package validation is under `dist/releases/1.0`. The public package files and `v1.0` tag remain immutable. This documentation follow-up does not replace release assets.
