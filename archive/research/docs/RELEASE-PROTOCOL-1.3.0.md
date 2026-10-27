# War Journalist 1.3.0 release protocol

Status: release preparation, 27 October 2026. Page updates describe the rewrite and its limits; they do not make an earlier testing ZIP the final release.

## Release boundary

- One complete Boot Mod Loader package. No BSL/MDL/LLL or Chef compatibility promise.
- Chef Lite is planned; whitelist approval may permit fuller compatibility. Neither is already available.
- Preserve the accepted skeleton Freeze. Remove failed smooth-freeze/body/cape experiments from enabled production paths.
- Native camera DoF is supported. Keep shader DoF and public scene effects disabled until visually verified in the exact package.
- AI control is unavailable. Remove Passive, Dummy and no-aggro current-feature claims.
- Preserve all existing inline/attached/gallery photos, credits and licenses. Older screenshots illustrate the tools, not complete 1.3 parity.

## 1. Lock source and package

- [ ] Reconcile the accepted Lua generation with current source, including independently completed menu/Handycam work. Record chosen commit/module hashes.
- [ ] Review only War Journalist source, fixtures, builders and release docs. Exclude settings, logs, diagnostics, game binaries, activation markers and unrelated dirty work from Git.
- [ ] Build the final versioned ZIP under `dist/releases`; do not rename an older testing package and claim newer contents.
- [ ] Run isolated Lua 5.1 fixtures with the verified Python/Lupa interpreter; record passes/skips and reasons.
- [ ] Verify embedded Lua bytes, assets/registry, helper provenance/hash, archive CRC, manifests/checksums and packaged startup/shutdown.
- [ ] Bundle assets and automatic WJL startup; exclude private development paths and manual helper dependencies.

Offline reference: portable.22.18, SHA-256 `717857d147abbae5bcdb3619633952030f27dbe719362a64f95da3df5032c469`. Its audit recorded 101 passing fixture groups, one missing-LLL-reference skip, 87 embedded modules and 15 checksum rows. It uses an accepted snapshot plus one cleanup admission fix. It is not a fresh-start-accepted final package and excludes later source changes.

## 2. Verify the exact distributable

- [ ] Closed-game deployment with rollback, ownership receipt and actual installed-byte hashes.
- [ ] Normal startup without a manually launched helper or development reload activation; fresh loader/helper logs and exact package identity.
- [ ] Menu open/close/reopen, font, input capture, Alt-Tab and normal-control restoration.
- [ ] Visibly different native focus/aperture, Bloom, light spawn/remove and camera-follow transitions.
- [ ] Solo Freeze/Resume, slow-motion restoration, standing/ragdoll/cape behavior and hover fallback; record exceptions.
- [ ] Subject selection after session changes, independent POV switches and full hide with held/holstered equipment.
- [ ] F11 Handycam, persistent menu return, offsets/drag/lag, ADS exits while holding aim and during dives.
- [ ] Game-window capture and frametimes during transitions/steady state. Investigate new periodic spikes; distinguish HDR/SDR qualification.

## 3. Update every destination

Use `RELEASE-1.3.0.md` as the full changelog. GitHub, Nexus, Ayaka and Discord all need the same support/limits:

1. First pass of a total Lua rewrite; incomplete parity.
2. Boot Mod Loader only; Chef Lite planned unless whitelist approval permits fuller compatibility.
3. AI control no longer possible in this implementation.
4. Occasional cape detachment, intermittent subject selection failure and incomplete Hide options.
5. Rare ragdoll spinning, hover/collision Resume limits, native HUD hiding and shader-depth restrictions.

- [ ] Preserve current descriptions/photo references before replacing prose. Remove old change-note blocks from main descriptions; retain historical changelogs/releases separately.
- [ ] Verify every existing inline photo and attached/gallery image remains.
- [ ] Commit/push reviewed release docs and agreed production source; verify remote revision. Preserve unrelated dirty work.
- [ ] After final-ZIP acceptance, tag its actual source, publish ZIP/SHA256SUMS and verify public download hashes.
- [ ] GitHub: accurate README, full notes and known issues. Clearly label historical test downloads.
- [ ] Nexus: description/summary plus dedicated 1.3.0 changelog; do not advertise old-loader files as current-compatible.
- [ ] Ayaka: description/summary plus separate update; point to final downloads only after publication.
- [ ] Discord: update existing starter/title, preserve attachments, post one changelog/status update without mass mentions.
- [ ] Inspect rendered pages; record URLs, photo preservation and pending upload/scan/test gates.

## Publication record

Record page-only updates separately from binaries in `PUBLICATION-1.3.0.md`. Include URLs, source commit, tag, hashes and outstanding gates. Historical assets are not final-release evidence.
