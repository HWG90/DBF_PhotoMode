# Independent camera development candidate

War Journalist owns camera discovery, movement, rendering and teardown in this
candidate. Its runtime is generated from maintained Photo Mode modules; it does
not patch or execute the vendored ActionCam gameplay controller.

This is a development candidate, not a new public release. The accepted 1.0.1
packages and tag remain the recovery point. Installing a ZIP and passing the
offline fixtures do not establish in-game camera or ActionCam compatibility.

## Ownership and lifecycle

- `camera_scene.lua` identifies the verified local avatar and a unique rendered
  camera in the main world. Engine Unit calls use handles from a fresh world
  inventory. Confirmed retirement invalidates the scene epoch; an unreadable
  inventory suspends writes rather than guessing that a handle is safe.
- `camera_motion.lua` applies input once per input sample, redraws the held view
  on every render, and retains the existing lens/compositor pipeline. Menu input,
  camera lock and Cinema use the same ownership transaction.
- `camera_lens.lua` validates a saved lens against the current camera inventory
  before restoration. A replaced camera is discarded without reading its old
  handle; a temporarily unreadable inventory keeps cleanup pending.
- `independent_runtime.lua` chains the game's callbacks, coordinates the existing
  photo tools and releases effects, position and compatibility ownership before
  returning the camera. Pending cleanup is retried before a replacement camera
  can be adopted. Shutdown leaves callbacks inert without removing another mod's
  wrapper.
  A persistent scene-read refusal enters cleanup after eight render attempts.
  MDL disable continues only queued pose/AI/subject restoration until teardown
  is acknowledged; it cannot resume input sampling or camera writes.
- `camera_ownership.lua` prefers a public cooperative provider. Existing supported
  unmodified ActionCam versions use the exact-signature compatibility adapter.
  The adapter is constructed only when needed. Unknown or changed providers deny
  entry rather than allowing two camera writers.

The working menu, saved settings, input policy, DoF, scene compositor, screenshots,
lights, poses, AI, time controls, camera paths and Cinema modules are reused. No
new hook DLL, MCM requirement or LinksLinkToMemory dependency is introduced.

## Optional ActionCam public contract

An ActionCam author can expose the following API to remove private callback
signature matching from the handoff:

```lua
ActionCamCamera = {
    api = 1,
    available = true,
    acquire = function(owner)
        -- Stop all ActionCam camera writes, retaining its current settings.
        -- Return a table/userdata token only after this has completed.
        return token
    end,
    release = function(token)
        -- Resume only after the caller restores its camera and input state.
        return true
    end,
    -- Optional, for hotkey/input coordination outside a held lease:
    set_priority = function(reader) end,
    set_input_blocked = function(reader) end,
}
```

Failed acquisition returns `false, reason` without retaining ownership. Failed
release returns `false, reason` and keeps the token valid for a retry. A token
must remain releasable through the original provider after reload or scene
change. Calls use plain functions, not colon-method syntax. Readiness must be a
boolean if supplied. The two optional readers return booleans and must be checked
before ActionCam changes the camera or processes conflicting hotkeys.

The rewrite cannot make an unknown, uncooperative camera mod yield. Current
unmodified ActionCam still needs the tested version adapter; the public contract
is the route to compatibility independent of its private implementation.

## Build and validation

Run from the owning checkout, using a separate review output:

```powershell
py -3 tools/run_tests.py --receipt dist/review/independent-camera-20261015/fixtures.json
py -3 tools/build_release.py --camera-engine independent --output dist/review/independent-camera-20261015/artifacts
```

The default release engine remains `legacy`. Independent builds are refused in
`dist/releases`, identify their engine and candidate status in provenance, and
include a candidate warning in every loader package. The five new camera modules
are inlined, so they do not add installed LLL module declarations.

`tools/verify_independent_camera.py` checks pre-refactor legacy byte equivalence,
compiles the complete independent runtime and MDL teardown, and refuses any read
of the vendored camera controller during independent generation. Its optional
`--packages <BSL.zip> <MDL.zip> <LLL.zip> --standalone` checks immutable package
contents, candidate provenance, unchanged accepted resources/native binaries and
source-independent mocked startup. `--checkpoint-root` points to the preserved
pre-refactor generator checkpoint when validating a clean source export.

The dedicated Lua fixtures cover scene replacement and transient reads, pending
cleanup, input sample consumption, frozen redraw, menu/Cinema ownership, both mod
load orders, provider replacement, exact callback returns and error propagation.
They run in an isolated LuaJIT host and never attach to a game process.

## In-game acceptance still required

Use one matching loader package at a time. BSL requires a full game restart.
Keep saved settings, screenshots and presets when replacing runtime files.

Verify entry/exit and normal gameplay look; Tab/menu/Escape/Alt-Tab cursor handoff;
freeze/slow motion; camera lock; Native and Shader DoF; Cinema and camera paths;
death/ragdoll/respawn/world transitions; and repeated handoffs with the installed
ActionCam enabled. Test both startup orders on a restart-capable loader. Check
that ActionCam resumes with its settings intact and that clicking in menus does
not move either camera. GPU appearance and real input must be confirmed in game.

The local `dist/review/independent-camera-20261015` checkpoint includes the original
tracked working source, its patch and hashes. Review packages are built from a
clean source export with only this camera change overlaid; unrelated editor and
native experiments are excluded.
