# Owned camera runtime

War Journalist uses maintained Photo Mode modules for scene discovery, camera
movement, lens handling, input and teardown. There is one camera build path.
The former external-camera adapter, signature catalogue and vendored camera
controller have been removed from maintained source and generated packages.

`camera_ownership.lua` is a local lifetime lease. It reads no external globals,
inspects no callbacks, changes no third-party bindings and performs no version
checks. The controller restores its scene, position, lens, effects, input and
simulation leases before releasing this local lease. Pending cleanup is retried.

`camera_scene.lua` selects a verified rendered camera belonging to the current
world and avatar. `camera_motion.lua` consumes each input sample once and
restores only its own still-current writes. `camera_lens.lua` validates camera
identity before restoring lens state. Confirmed retirement clears old handles;
transient read failures suspend writes rather than treating stale data as safe.

The existing menu, screenshots, lighting, poses, AI, time controls, Cinema,
camera paths, input recovery and shader compositor remain in the owned runtime.
No third-party camera code is used to generate or start it. Other mods' callback
chains remain intact; this does not itself establish coexistence with every
other writer to the same game camera.

Build into a named candidate directory:

```powershell
py -3 tools/run_tests.py --receipt dist/review/owned-camera/fixtures.json
py -3 tools/build_release.py --input-recovery-candidate --output dist/review/owned-camera/artifacts
```

Runtime files are `src/camera_runtime.lua` and `src/camera_ownership.lua`.
All three loader packages share the same generated camera. Preserve settings,
screenshots and presets on install. Restart normally when replacing the camera
controller so old callback wrappers do not remain resident.

Offline fixtures and package checks establish source/package behavior only.
Live entry, movement, menu/input handoff, Cinema, lens effects and scene changes
must be checked in game after a normal restart.
