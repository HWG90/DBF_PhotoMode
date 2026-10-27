# War Journalist 1.1.0

A Helldivers 2 Photo Mode.

**A HUGE THANK YOU to everyone sharing photos, testing builds and reporting bugs.** Your shots and feedback keep making this better. Keep them coming!

- **Passive now uses player-side no aggro.** Enemies continue their simulation while ignoring the player in the verified solo test. This replaces Passive's repeated enemy scans and target suppression. A once-per-second player/session ownership check handles replacement and cleanup; Normal restores our owned flag. No Link addon required. **So uh... don't get too comfy.** Damage, objectives and the integrated respawn path still need wider testing; this is not invulnerability.
- **Lower AI overhead:** Passive no longer scales its maintenance work with the enemy population. Dummy keeps bounded discovery and a measured per-frame work budget, rather than an unrestricted population sweep. No promise of a fixed FPS gain.
- **Independent photo camera:** War Journalist now owns its camera discovery, movement, lens and cleanup. Removed the ActionCam adapter and dependency. Other camera mods can remain installed; coexistence still depends on respecting input/camera ownership. Check that Restart ActionCam is not bound to M1.
- **Input recovery:** corrected stale camera handoffs, opening while moving, gameplay-look restoration, and coordinated editor/menu input. Ctrl+Shift+F10 is the recovery shortcut; close other editors before testing if input gets stuck.
- **Follow Player follows the complete light rig.** Existing and newly added lights share the switch. Moving lights update transforms instead of resending every color/intensity/shadow property. Following translates with the player; it does not rotate the rig with their facing.
- **Hoverpack:** pause-entry fallback and pending restoration now use a fresh world-update clock even after the camera target is retired. Native hover hooks remain removed. The integrated latest package needs further equipment-combination testing.

The photo tools, poses, cape/ragdoll fixes, compositor, logos and gallery remain included. Native DoF, shader preview, camera paths, Freeze/Slow Motion, lighting presets and saved Director cameras are retained.

Choose one complete package: BSL, MDL or LLL. GitHub has all three; Nexus has BSL and MDL. Preserve settings, presets and screenshots, replace the old runtime, deploy the matching bundled assets and restart. Each package includes its assets and helpers. Do not mix runtime versions.

The new player flag was observed live through LLtM; the integrated mode passed isolated ownership/lifecycle tests. Offline package checks are not full live acceptance across all loaders or missions.
