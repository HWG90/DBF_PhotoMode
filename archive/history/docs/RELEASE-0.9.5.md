# War Journalist 0.9.5

Native focus and aperture, autofocus, a more flexible studio menu, photo lights,
saved camera shots, and fixes for the reported hoverpack/melee pause crash.
This release brings the work since 0.7 into complete **BSL, MDL, and LLL** packages.

## New and improved

- **Native depth of field:** adjustable focus distance and aperture, with current-camera discovery and recovery when camera/profile instances change. Native DoF remains the blur-quality baseline.
- **Focus tools:** double-click a subject outside the menu to focus, or use center autofocus. Manual focus remains available, including fine adjustment. Choose 24, 35, 50, 85, or 135 mm lens presets, plus level and portrait tilt shortcuts.
- **Combined full-resolution compositor:** shader bokeh, scene effects, and color grading can work together. Shader DoF retains round/hexagonal bokeh and 32/64-sample quality choices. The HDR tint and exposure correction was visually accepted during development.
- **Photo lights:** place up to three owned point or spot lights. Adjust color, intensity, range, cone, and camera-relative offsets; follow the camera or leave a light in place. Position indicators help locate them. The dedicated mission-light asset fix is **Not tested fully**.
- **Director camera shots:** save five camera positions and angles relative to the player, recall them in later sessions, and clear individual slots.
- **Subject controls:** hide the entire local player, armour and helmet, or carried weapons. Photo Mode restores the visibility changes it owns when closing.
- **Studio controls:** a compact, movable, resizable menu with saved position and size; a dockable controls legend that follows camera/menu focus; and finer Shift-drag slider adjustment. Camera and Lens controls have separate pages.
- **Composition and capture:** updated Helldiver crest and curated logos, plus a rebindable screenshot shortcut using Pause by default. Existing camera movement, solo pause/slow motion, composition guides, and 40 decorative overlays remain included.

## Fixes

- **Hoverpack + melee pause/resume:** the original reported crash reproduction passed with the data-only hover guard, confirmed by the user. Four earlier basic pause/resume cycles also completed separately. Hover input is neutralized before zero-time pause, and the owned setting is restored after gameplay resumes.
- **Animation reads during ragdoll/death/respawn:** all seven Photo Mode animation-state reads now check that the Unit is alive and has an animation graph before calling the native getter. The development ragdoll/respawn test reported no crash.
- **Native lens ownership:** follows the active camera/profile instance, tolerates bounded observation delay, and preserves changes made by another writer during restoration.
- **Held input:** keyboard/mouse release waits for later engine readback before capture. Exit releases follow input restoration. Guarded hover pause resumes gameplay before deliberately giving up input capture.
- **Screenshot colors:** corrected HDR-to-SDR conversion brightness and the verified engine SDR capture profile's swapped red/blue channels.
- **Menu behavior:** saved geometry survives restarts; focus switching retains the menu view; reopening, hidden controls, disabled standalone recovery, typed-value commits, and fine slider scrubbing have dedicated regression coverage. Game chat prevents accidental Photo Mode activation.
- **Scene transitions:** focus sampling and effects wait for valid, stable resources after launch or display changes instead of consuming stale camera/depth data.

## Install and controls

Choose one runtime loader: **BSL v15+**, **MDL API 2**, or **LLL**. Nexus offers
BSL and MDL; GitHub offers all three. Each download includes its runtime and
required assets. MCM is optional; DBF-HUD, ActionCam, and Link's addon are not
required.

For BSL, import the complete ZIP into Arsenal, enable, deploy, and restart.
For MDL, copy `dbf_freecam` into MDL's Mods folder, then import the complete
MDL ZIP into Arsenal, enable and deploy its `GameData` assets, and restart.
Arsenal installs assets only; the runtime folder must also be installed.
The MDL package contains no nested archives. Manual GameData installation
is an alternative to Arsenal deployment; use one asset installation method.
For LLL, install `dbf_freecam` in LLL's Mods folder, deploy the asset ZIP
included in that download, and restart.
Use one Photo Mode runtime at a time and preserve settings, camera presets,
and screenshots. Follow the included `INSTALL.txt` for the selected package.

**P** opens Photo Mode, **Tab** switches camera/menu focus, and **Pause** takes
a screenshot. W/S selects menu rows, A/D changes values, and Q/E changes tabs.
Hold Shift while dragging a slider for finer adjustment. Existing bindings
are retained and can be changed.

## Remaining limits

- **Mission photo-light asset fix: Not tested fully.** The earlier ship light was demonstrated live. The newly bundled dedicated asset has offline validation; mission spawning and every point/spot/follow combination still need live coverage.
- Pause and slow motion require a verified solo session. Connected or unidentified controllers refuse active-hover guarded pause. The confirmed hoverpack/melee result covers the reported reproduction, not every loadout, scene, transition, or game update.
- HDR compositor acceptance covered neutral grading, no scene effect, and active Shader DoF. SDR parity and every effect combination remain unverified; blurred HDR energy above GUI white is still limited by the GUI carrier.
- Native focus/aperture were user-tested during development. Complete release-package cold startup and all camera transitions have not received fresh live acceptance.
- Screenshots may still contain ship UI. The new shortcut is fixture-tested; a separate live keyboard-trigger test is not claimed.
- AI Passive/Dummy controls are unintegrated and excluded from the release's features. Director provides camera presets.
- Other shader packs replacing the default registry require a registration merge. General alt-tab crashes and HDR/SDR switching crashes are outside the fixes established here.

See [known issues](../../../docs/KNOWN-ISSUES.md) for the current limits and
[hover pause verification](HOVER-PAUSE-VERIFICATION.json) for the recorded test scope.
