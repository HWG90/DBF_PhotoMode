# War Journalist 1.3.0 — The Lua rewrite

Stop the action. Find your angle. Build the shot.

**A HUGE THANK YOU to everyone sharing photos, testing builds and reporting bugs.** Getting this working again has taken a lot of testing. Your shots make it worth it. Keep them coming!

**1.3.0 is the first pass of a total rewrite for the game's Lua 5.1 runtime.** Much of the old native/FFI implementation has been replaced with game-Lua implementations. Those replacements have limitations; this release does not have complete feature parity with 1.2.1.

**Boot Mod Loader is the only supported loader at the moment.** A **Lite version for Chef's Shared Loader is planned**. Whitelist approval may allow fuller compatibility; neither approval nor full compatibility is guaranteed. Old BSL, MDL and LLL downloads are historical builds for the previous runtime.

**Release preparation:** the final 1.3.0 bundle is not published yet. The existing `1.3.0-bml.1` download is an earlier testing build and does not contain all the changes below. These notes cover current development; final-package acceptance is tracked in the [release protocol](../archive/research/docs/RELEASE-PROTOCOL-1.3.0.md).

## Known issues and removed features

- **Cape detachment still occasionally happens**, especially around Freeze, ragdolls and pose transitions. The new hold improves tested cases; it is not a universal cape fix.
- **The new subject selection sometimes fails.** Automatic player selection and click selection can miss the intended subject or find none. Session recovery has improved; reliability is still being worked on.
- **Some Hide options do not work fully.** Helmet, torso and cape controls work on tested outfits; Hide entire player can leave holstered weapons, scopes, magazines, backpack/support-weapon parts or other accessories floating.
- **AI control is no longer possible with the current implementation.** Passive, Dummy and no-aggro are unavailable. World Freeze is separate from AI control.
- **Depth shaders currently do not work.** Inverted depth, Thermal depth, Depth contours, Depth fog and Shader DoF/bokeh are removed from the 1.3.0 menu. **Native camera DoF is working**, including focus distance and aperture. Public scene effects stay disabled until visually verified.
- **Rare frozen-ragdoll spinning can still occur.** Cape attachment and hold/resume were accepted in live tests, with this remaining exception.
- **Hoverpack Freeze uses a near-zero-time workaround.** Active-hover pause/resume worked in the reported test, but this is not a thrust-only fix. Detection can also include dropped packs; ragdoll/collision Resume launching has been reported. Exact-zero hover safety is not established.
- **Handycam transitions need wider coverage.** ADS handoff/recovery is improved, but intermittent return/clipping problems and normal-aim parallax remain possible. Moving the POV camera changes its relationship to the weapon's point of impact. Stock backward/strafe body turning is not corrected.
- **Automatic native HUD hiding is not restored on Windows.** Use the game's Toggle HUD binding; the tester used `/`. Your binding may differ.
- **Lighting, equipment variants, respawns and scene transitions need broader testing.** SDR capture is the qualified path; HDR capture is not promised by this rewrite.

## Full 1.3.0 changelog

### Loader, input and recovery

- Ported Photo Mode to Boot Mod Loader and Lua 5.1, replacing Windows features that depended on unavailable native DLL access.
- Added the bundled **WJL helper** and automatic startup, removing the need to manually launch it for each session. Helper names now use WJL.
- Restored Windows gameplay-input blocking while Photo Mode owns input, with release/restoration on close and focus/menu handoffs. Displaying a cursor alone was insufficient; the Windows helper supplies the working path.
- Fixed menu-open crashes encountered during the port; made cleanup/recovery more resilient when operations are refused or resources change.
- Added opt-in development Lua reload for supported Lua changes. Archive/native/asset changes still require deployment and restart; this is not a promise that every mod change hot-reloads.

### Native lens and presentation

- Restored **Native camera DoF**, manual focus distance and aperture through current renderer profiles. Focus/aperture changes were visually confirmed on Windows.
- Retained lens presets, focal length, roll, camera lock and center-focus sampling. Improved depth-assisted picking; a focus depth sample does not mean shader access to the depth buffer works.
- Restored the game font and corrected material/atlas initialization after the port.
- Retained the movable/resizable panel, saved opacity and controls drawer. Added HUD-style frame details and native background blur within the panel/footer bounds.
- Reduced repeated UI/discovery work with retained state, explicit invalidation and bounded discovery. No universal FPS claim.
- Restored native Bloom toggling. Removed the crashing color CPU-readback path. Experimental depth bindings are not presented as a working shader feature.

- The HUD toolbar displays the game's assigned Toggle HUD key and warns when unbound. The key passes through Photo Mode input capture.

### Freeze, poses and lighting

- Restored Freeze/Resume and Slow Motion through engine time controls, preserving the selected slow-motion rate across relevant transitions.
- Reworked frozen-body holding: capture a coherent skeleton before exact zero, hold the body after the saved render callback, and restore animation transfer before positive time. Cape bones/separate cape units are not forcibly moved by this hold.
- Removed failed smooth-freeze and forced body/cape transform experiments after live regressions. Rare spin and cape problems remain listed above.
- Retained the user-tested hoverpack near-zero fallback, with its collision/ragdoll and detection limitations disclosed above.
- Apply Pose resets the previous pose before applying. Changing a held pose resets and applies the new selection in one action; failed restoration blocks the next pose.
- Restored Lua subject poses and Reset on tested Helldivers. The catalogue contains sampled action frames/variants; every outfit, cape and ragdoll transition is not verified.
- Fixed the reported photo-light spawn crash; retained point/spot lights, presets, draggable markers, saved rigs and camera-follow support. Lighting remains **Not tested fully** across scenes.

### Handycam / POV

- Added **F11** to start/end Handycam, automatic player discovery and selected-subject fallback.
- Handycam stays attached when Photo Mode is reopened or settings change, until explicitly ended.
- Added configurable **Movement lag** next to Intensity for a tighter camera or intentional trailing movement.
- Added forward/up/left-right offsets and yaw/pitch adjustment. Updated defaults from the tested framing.
- Added **Drag camera position**: M1 drag for position, mouse wheel for forward/back, held MMB drag for yaw/pitch. Framing persists after release.
- Split POV visibility into independent helmet, torso and cape switches. Handycam always hides the helmet.
- Added first-person ADS yielding/reacquisition while retaining POV visibility. ADS means the first-person sight view entered with MMB while aiming; normal aim is a separate state.
- Improved camera return after ADS, including while aim stays held and around dives. Remaining transition limitations are disclosed above.

### Subjects and visibility

- Added automatic nearby-Helldiver discovery, bounded inventories and recovery when the game session changes.
- Added reversible mesh visibility so supported helmet, torso, cape, body and equipment meshes restore their prior state instead of forcing every mesh visible.
- Added a separate Hide carried weapons control and full-skeleton attachment discovery beyond the original outfit list. Expanded recognized weapon/accessory relationships, including tested pistol parts. Full equipment hiding remains incomplete: the latest test still leaves a holstered rifle and accessories visible; restoration succeeds.
- Preserved Cinema action shots, scene-local camera paths, saved Director positions, composition guides, frames, logos, vignette and grain where supported by the new runtime.

## Install and upgrade

When the final bundle is published, import the complete **BML ZIP** into HD2 Arsenal, enable with [Boot Mod Loader](https://github.com/pat-pat-patrick/boot-mod-loader), Deploy, then restart. Disable previous War Journalist runtimes; run one copy at a time. Keep settings, presets and screenshots. WJL is bundled and starts automatically on Windows.

Use the controls shown in the panel; saved bindings take priority. F11 toggles Handycam. Tab changes camera/menu focus. Use the game's Toggle HUD binding when a clean native HUD is needed.

## Testing scope

Windows development has live acceptance for the menu, font, native focus/aperture, poses, Handycam offsets/drag/persistence and tested POV visibility. The accepted Freeze improved ragdolls and cape attachment, with rare spinning explicitly reported. Fixtures, package audits, fresh startup and live acceptance are separate. The final ZIP needs its own checks; a live reload does not validate a different archive.

For reports include loader/version, scene, equipment and reproduction steps. The Lua log is `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log`. Remove private information before sharing it.
