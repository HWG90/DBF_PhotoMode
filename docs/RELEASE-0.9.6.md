# War Journalist 0.9.6

This development update adds movable scene lights, subject-focused lighting
setups, stronger shader depth of field, fixed subject poses, and persistent
solo-only enemy behavior.

## Changes since 0.9.5

- **Solo enemy behavior in Director:** choose Normal, Passive, or Dummy, or use **Reset AI to Normal**. The chosen mode continues after closing the menu or exiting Photo Mode, with bounded discovery of new enemies. A game restart starts at Normal. Joining players cancel the mode and restore owned changes. The user confirmed live persistence and Reset.
- **Enemy behavior recovery:** transient scene/respawn read failures suspend writes without clearing the selected mode. Dummy renews its owned movement flag even when a borrowed detector is unavailable, and cleanup restores movement independently of that detector. Unknown network authority still cancels suppression safely. These recovery cases have fixture coverage; live verification is pending.
- **Photo light placements are retained:** reopening Photo Mode restores the previous setup in the same scene, without adding lights again. Explicit saved lighting slots also survive restarts.
- **Clearer light colors:** the RGB editor has an **Apply** button and keeps a live color swatch and HEX value visible while adjusting channels.
- **Drag lights in the scene:** numbered, color-coded indicators show placed lights while the menu is open. Drag an indicator across the camera plane; hold Shift for ten-times finer movement. Indicators disappear with hidden controls and clean screenshots.
- **Subject-focused lighting:** Key / Fill / Rim, Portrait, and Dramatic side presets aim at the selected subject. Without a selected subject, the current center focus plane supplies the target. Applying a preset replaces the current light setup, with rollback on a failed replacement.
- **Five saved lighting setups:** save, recall, and clear subject-relative placements and settings. Slots persist across restarts in `lighting-presets.ini`; no game handles are stored.
- **Stronger shader DoF:** blur strength defaults to 4x and ranges from 1x to 8x. Stronger blur uses 64 samples in Standard and 128 in Smoother. Native DoF is unchanged. The accepted compositor color conversion and scene-effect code are retained exactly; the new shader still needs live visual acceptance.
- **Fixed subject poses:** choose Salute, Wave, or Taunt while **Pause entire action** remains ON. Selection applies a sampled skeleton pose immediately, without an emote event or simulation step. **Reset pose** restores the original pose; exiting or resuming time waits for restoration. Placement anchors remain unchanged. The user confirmed a held Salute with world rate and delta both zero, then confirmed immediate pose switching and Reset. Broader mission/transition coverage remains in progress. Victory poses are not exposed.
- **More complete subject hiding:** nested equipment is included, fixing the reported floating parts left behind by visibility controls. The user accepted the live result.
- **Cleanup guards:** menu-close errors no longer prevent the remaining effect, time, and input cleanup. Retired-world GUI resources are guarded during teardown.

## Scope and remaining limits

Passive and Dummy suppress enemy detection; Dummy also restricts ordinary
movement. They do not stop AI processing, physics, damage, or an attack already
in progress. Controls require a supported, verified solo mission context;
multiplayer hosts and clients are unavailable. Link's addon is not a prerequisite.

The cleanup changes have isolated fixture coverage. **HDR/SDR and other
display-setting crashes remain unresolved**; this update does not claim to
fix them. Broader mission-light combinations, all camera transitions, and
every compositor/effect combination still need coverage. New draggable lights,
lighting presets, and fixed poses have isolated fixture coverage; their
full in-game acceptance is pending. Lighting: **Not tested fully**.

This remains a single-pass bokeh gather. Large foreground blur and highlight
clipping at the existing GUI carrier's white level remain limitations. A full
[OtisFX Cinematic DOF](https://github.com/FransBouma/OtisFX/blob/master/Shaders/CinematicDOF.fx)
port would require additional render targets and passes; it is not bundled as
an implemented feature in this build.

Install one complete BSL, MDL, or LLL package, preserving settings, camera
presets, and screenshots. See [installation and controls](../freecam/README.md),
[AI behavior details](PHOTO-AI.md), and [known issues](KNOWN-ISSUES.md).
