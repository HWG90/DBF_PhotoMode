![War Journalist](docs/artwork/war-journalist-cover.png)

# War Journalist 0.9.6

A Photo Mode for Helldivers 2: free camera, a compact movable studio menu,
Native and shader depth of field, autofocus, color grading, scene effects,
photo lighting, Director camera presets and enemy behavior controls,
subject visibility and PNG capture.

[Download on Nexus](https://www.nexusmods.com/helldivers2/mods/17248?tab=files) ·
[Published GitHub downloads (0.9.5)](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v0.9.5) ·
[Full 0.9.6 changelog](docs/RELEASE-0.9.6.md)

This source is 0.9.6; the published download above is still 0.9.5.

## What's new

- **Solo Director enemy behavior:** Normal, Passive, and Dummy, plus Reset to Normal. The chosen mode continues after Photo Mode closes and applies to newly discovered enemies; game restart returns to Normal. Joining players cancel the mode and restore owned changes. Persistence and Reset were confirmed live.
- **Light placement tools:** numbered scene indicators, draggable lights with Shift precision, subject-focused portrait/three-point/side rigs, and five lighting setups saved across restarts.
- **Retained lighting setup:** reopening Photo Mode restores your lights at their previous placements within the same scene. Explicit saved setup slots can also be recalled after restarting.
- **Stronger shader DoF:** 1x–8x blur strength, 4x by default, with more samples and the accepted color conversion retained.
- **Subject poses:** Salute, Wave, and Taunt, with guarded play/stop controls. Victory poses still need verified event mappings.
- **Color editing:** explicit Apply, with a live color swatch and HEX value visible while adjusting RGB.
- **Subject hiding:** nested equipment is included, fixing the reported floating parts.
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
