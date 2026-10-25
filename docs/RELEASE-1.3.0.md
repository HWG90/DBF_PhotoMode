# War Journalist 1.3.0 — Steam Lua 5.1

War Journalist is back on the current Steam build through Live Lua Loader's
Lua 5.1 runtime. Requires LLL Steam preview `R34-steam-lua51-preview.1`.

## Working

- Free camera: movement, look, lens/focal presets, roll, smoothing, lock.
- Menu, shared mouse, Tab between menu and camera, close/reopen.
- Cinema: camera points, path preview, placed and path action shots with
  gameplay input released and refreeze on return.
- Photo lights: presets, aim, five saved rigs, marker drag (Shift for
  precision), camera-follow and reopen restoration.
- Freeze Action / Resume, slow motion, gameplay Backslash toggle.
- Screenshot button and Pause key: clean SDR PNG without the Photo UI.
- Composition: frames, filters, vignette, animated grain, logos, guides.
- Native Bloom on/off.

## Not yet restored on Steam

Passive AI, Subject poses/visibility/cape, Handycam, HUD hiding (the native
gameplay HUD stays in screenshots), numeric depth of field,
exposure/contrast/saturation, HDR screenshots and decorative shader overlays.
Passive AI has no current-build route without native access.

## Notes

- Screenshot needs Windows HDR off for the game display.
- Light range is fixed; the current runtime ignores falloff changes.
- Copy `GameData` only if no other mod already provides
  `9ba626afa44a3aa3.patch_1`.

## Build

`py -3.14 tools/build_steam_release.py` packages the 21 modules accepted in
game on October 20 (`r34-keyboard-deployment-v1`), pinned by SHA256, and the
owned light unit rebuilt from source. The ongoing Subject work in
`freecam/steam_runtime.lua` is excluded; the accepted runtime is kept in
`freecam/steam_release/`. All 31 Lua 5.1 fixture groups pass for the current
source tree.
