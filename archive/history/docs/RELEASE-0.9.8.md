# War Journalist 0.9.8

A Helldivers 2 Photo Mode. This hotfix keeps the complete 0.9.7 feature set,
UI and artwork, and corrects Native DoF flicker and held ADS while posing.

## Fixed

- **Native DoF stays steady.** Temporary, expired or stock render packets no longer reset a valid owned lens. When several views are queued, the matching lens packet is preferred. A real camera/profile ownership change still triggers guarded recovery. Blur was confirmed steady with the camera still and while moving.
- **Held inputs stay intact.** Photo Mode no longer sends blanket key or mouse-button releases on entry or exit. You can hold ADS as you enter and pose; that behavior was confirmed in-game.

The data-only hoverpack pause guard remains. Active-hover pause still requires
neutral hover controls and may refuse entry while movement/jump is held. This
hotfix does not claim a new live hoverpack regression test.

## Everything from 0.9.7 remains included

213 sampled fixed pose frames, the supported-cape correction, persistent solo
Normal/Passive/Dummy AI, draggable photo lights and saved lighting setups,
Native and shader DoF, autofocus, color grading and scene effects, Director
camera presets, subject hiding, screenshots, curated logos, and the movable
menu with saved position and opacity.

See the [0.9.7 feature notes](RELEASE-0.9.7.md) and
[pose catalogue](../../../docs/SUBJECT-POSE-CATALOGUE.md).

## Complete downloads

Choose one **BSL v15+**, **MDL API 2**, or **LLL** package. Every ZIP includes
its runtime and required assets. GitHub offers all three; Nexus offers BSL
and MDL. MDL stays flat, without nested archives. No separate mod asset download
or Link addon is required.

Follow the package's `INSTALL.txt`, deploy its included assets, and restart
normally. Keep one Photo Mode runtime active. Preserve settings, key bindings,
camera and lighting presets, and screenshots.

## Verification and limits

All **54 isolated fixture groups** and all **three source-independent package
startup checks** passed. Native DoF stability and preserved ADS were separately
confirmed in the running game. Package checks do not establish every scene or
loader's live behavior.

**Lighting: Not tested fully.** Wider mission/cape coverage, stronger shader
blur, SDR compositor parity and all effect combinations still need more testing.
HDR/SDR switching and other display-setting crashes remain unresolved. Fixed
poses require solo pause; AI modes leave brains and physics running. See
[known issues](../../../docs/KNOWN-ISSUES.md) for the full limits.
