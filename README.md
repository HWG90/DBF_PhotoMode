![War Journalist](docs/artwork/war-journalist-0.9.7-cover.png)

# War Journalist 0.9.8

A Photo Mode for Helldivers 2: free camera, a compact movable studio menu,
Native and shader depth of field, autofocus, color grading, scene effects,
photo lighting, Director camera presets and enemy behavior controls,
213 fixed subject pose frames, subject visibility and PNG capture.

[Download on Nexus](https://www.nexusmods.com/helldivers2/mods/17248?tab=files) ·
[GitHub downloads](https://github.com/HWG90/DBF_PhotoMode/releases) ·
[0.9.8 hotfix notes](docs/RELEASE-0.9.8.md) ·
[0.9.7 feature notes](docs/RELEASE-0.9.7.md)

## What's new

- **Steady Native DoF:** temporary or older render packets no longer reset a valid owned lens. The blur was confirmed steady with the camera still and while moving.
- **Held inputs preserved:** entering and leaving Photo Mode no longer forces all keys and mouse buttons to release. Held ADS now stays correct while posing, confirmed in-game. The data-only hoverpack pause guard remains and still requires neutral hover controls.

The complete 0.9.7 feature set, UI and artwork are retained:

- **213 fixed pose frames:** select a pose while the scene stays paused. Gestures, cooperative variants, kneeling poses and both push-ups are included. Reset restores the original pose before play resumes. These are sampled emote/action frames, not 213 store items; see the [pose catalogue](docs/SUBJECT-POSE-CATALOGUE.md).
- **Cape correction:** supported capes follow the posed shoulders and restore across pose changes. The integrated fix was confirmed in-game; it preserves the frozen cloth shape without advancing physics. Wider cape coverage remains open.
- **Menu opacity:** a compact bottom-right slider controls the background from 10% to 100%, saves across restarts, and resets to 38% with right-click.
- **Solo Director enemy behavior:** Normal, Passive, and Dummy, plus Reset to Normal. The chosen mode continues after Photo Mode closes and applies to newly discovered enemies; game restart returns to Normal. Joining players cancel the mode and restore owned changes. Persistence and Reset were confirmed live.
- **Light placement tools:** numbered scene indicators, draggable lights with Shift precision, subject-focused portrait/three-point/side rigs, and five lighting setups saved across restarts.
- **Retained lighting setup:** reopening Photo Mode restores your lights at their previous placements within the same scene. Explicit saved setup slots can also be recalled after restarting.
- **Stronger shader DoF:** 1x–8x blur strength, 4x by default, with more samples and the accepted color conversion retained.
- **Color editing:** explicit Apply, with a live color swatch and HEX value visible while adjusting RGB.
- **Subject hiding:** nested equipment is included, fixing the reported floating parts.
- **Readiness and recovery:** poses unlock independently of paused game time; temporary scene/respawn reads no longer clear the selected enemy behavior.
- **Cleanup guards:** menu-close failures still allow other cleanup, and GUI teardown checks world lifetime. HDR/SDR and other display-setting crashes remain unresolved.

Native/shader DoF, autofocus, the combined compositor, three photo lights,
five Director camera presets, saved menu geometry, fine Shift scrubbing,
screenshots, and curated logos remain included. See the
[0.9.5 notes](docs/RELEASE-0.9.5.md) for those features and their test scope.

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

Camera foundation: [ActionCam](https://www.nexusmods.com/helldivers2/mods/16752)
by HuedPurple. Native UI/font reader: CowboyBingus (0BSD). Selected reader
work: Link (MIT). Bundled licenses and vendor provenance identify their scope.
Helldivers 2/Arrowhead artwork belongs to its respective owners; individual
logo sources and authors are recorded under `freecam/assets/logos`.
