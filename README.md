![War Journalist](docs/artwork/war-journalist-0.9.7-cover.png)

# War Journalist 1.2.1

A Helldivers 2 Photo Mode: free camera, a movable photo studio menu,
Native and shader depth of field, autofocus, color grading, scene effects,
photo lighting, Cinema action shots, camera paths, solo enemy behavior,
213 fixed subject pose frames, subject visibility and PNG capture.

[Download on Nexus](https://www.nexusmods.com/helldivers2/mods/17248?tab=files) ·
[GitHub downloads](https://github.com/HWG90/DBF_PhotoMode/releases) ·
[1.2.1 release notes](docs/RELEASE-1.2.1.md)

**A huge thank-you to everyone sharing their photos, testing builds, and reporting bugs.**
Seeing the shots you are making with War Journalist has been the best part of building it.
Keep them coming!

## New in 1.2.1

Fixed the regular Photo Mode panel/control-legend hitches confirmed during live testing.
Unchanged panel layout and legend commands are retained, equivalent choice lists no longer
force rebuilds, and renderer/lens validation uses reusable buffers. Camera discovery no
longer enumerates every world Unit repeatedly while active. Existing font binding is preserved.
All 1.2.0 handycam, smooth zoom and lighting features remain included.
See the release notes for testing limits and upgrade instructions.

## What's included

- **Cinema action shots:** place the camera, begin an action shot, and control your Helldiver while the camera holds its position, angle and lens. Returning to Photo Mode restores your previous Freeze Action state. Your selected slow-motion speed is retained, and the Cinema hint fades away after three seconds.
- **Camera paths:** record up to 32 scene-local points with per-segment durations, smooth travel or timed cuts. Five separate player-relative Director camera presets remain saved across restarts.
- **Reachable global controls:** Freeze/Resume Action, solo AI behavior, Slow Motion with a speed slider, and Lock Camera stay available above the settings. The AI indicator uses the current mission's faction emblem when verified.
- **Photo studio:** move and resize the menu, adjust opacity, navigate with W/S and A/D, and use Shift for fine slider scrubbing. Menu geometry and controls-drawer visibility/layout survive restarts. The contextual controls drawer docks at the left edge.
- **Native and shader lenses:** focus distance, aperture, double-click subject focus, center autofocus, focal-length presets and portrait roll. The combined shader compositor layers depth effects, grading and preview bokeh without the former color rectangle or dim/cool tint.
- **Fixed subject poses:** 213 sampled frames and variants apply while paused; Reset restores the original pose. Supported cape variants follow the posed shoulders. See the [pose catalogue](docs/SUBJECT-POSE-CATALOGUE.md).
- **Photo lighting:** up to three point/spot lights, draggable position indicators, a color editor with Apply and a live swatch, subject-directed rigs, and five saved lighting setups. Wider lighting coverage remains **Not tested fully**.
- **Solo AI direction:** Normal, Passive and Dummy persist after closing Photo Mode and apply to newly discovered enemies. Reset returns normal combat. Multiplayer/joining players disable suppression; game restart begins at Normal.
- **Correct frozen ragdolls:** an observed ragdoll pose stays still at exact zero time, resumes normally and yields to Subject poses. This reproduction and handoff were verified in game.
- **Input and recovery fixes:** gameplay look returns after menu handoffs, native settings suspend the Photo camera, chat ignores the Photo shortcut, held ADS remains intact, and double-click focus uses buffered click timing. Camera cursor confinement is retained.
- **Complete subject hiding:** owned equipment attachments, including the Maxigun feed belt, hide and restore with the subject. Curated Helldivers logos and Super Earth insignia remain included.
- **Owned camera controller:** Photo Mode uses its own scene discovery, motion and cleanup. Starting it does not inspect or wrap another camera mod's private functions.
- **Radeon compatibility repair:** the package contains the game's 77 native shader registrations and its 44 shipped Photo Mode shaders. Radeon testers reported stable Alt-Tab, fullscreen, bloom and DoF changes with this repair.

## Install

Choose one loader: **BSL v15+** (recommended), **MDL API 2**, or **LLL**.
Nexus hosts BSL and MDL; GitHub hosts all three. Every ZIP includes the complete
runtime and its required assets. No separate asset download is needed.
MCM, DBF-HUD, ActionCam and Link's addon are not prerequisites.

BSL: import the complete ZIP in Arsenal, enable with BSL, deploy and restart.
MDL: copy `dbf_freecam` into MDL's Mods folder, then import the complete MDL ZIP
into Arsenal to enable and deploy its `GameData` assets. Restart normally.
Arsenal installs assets only; the runtime folder must also be installed.
The MDL package contains no nested archives.
LLL: install `dbf_freecam` in LLL's Mods folder, deploy the asset ZIP bundled
inside that same download, and restart.
Use one Photo Mode runtime at a time. Preserve settings, presets and screenshots.
Photo Mode uses its own camera controller. Other camera mods are not inspected, reconfigured or paused by a private adapter.
See [installation and controls](freecam/README.md) for manual installation.

## Controls

P opens Photo Mode; Tab switches camera/menu focus; Pause takes a screenshot.
W/S navigates rows and A/D changes values in menu focus; Q/E changes tabs.
Double-click a subject outside the menu to focus. Hold Shift while dragging
sliders for finer adjustment. Typed values commit when clicking away.
All key bindings are configurable; existing bindings are retained.

Native DoF is the quality baseline. Shader DoF offers round/hex bokeh and
64/128-sample quality above 1x strength (32/64 at 1x). Scene effects and grading
can layer with shader DoF. The stronger shader still needs live acceptance.
The compositor's HDR tint/exposure correction was visually accepted;
SDR compositor parity and all effect combinations are not fully validated.
Pause/slow motion are solo-only. See [known issues](docs/KNOWN-ISSUES.md).

## Build and verification

Use `py -3 tools/build_release.py --output dist/releases/<new-folder>`.
The builder uses maintained source and hash-checked compiled asset snapshots;
no installed-game assets or developer capture folders are needed. Lua syntax
validation requires a Lua 5.1/LuaJIT DLL (`HD2_LUA51_DLL` can select it).
Run `py -3 tools/run_tests.py` for isolated fixtures and
`py -3 tools/test_packaged_standalone.py <BSL.zip> <MDL.zip> <LLL.zip>` for
source-independent package startup checks. Tests do not establish live GPU behavior.

## Credits

Earlier releases used [ActionCam](https://www.nexusmods.com/helldivers2/mods/16752)
by HuedPurple as a camera foundation. The current controller is maintained here.
Native UI/font reader: CowboyBingus (0BSD). Selected reader
work: Link (MIT). Bundled licenses and vendor provenance identify their scope.
Helldivers 2/Arrowhead artwork belongs to its respective owners; individual
logo sources and authors are recorded under `freecam/assets/logos`.
