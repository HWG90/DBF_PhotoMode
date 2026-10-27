# Handycam world-marker drift

The user supplied third-person and Handycam screenshots showing ship interaction
diamonds displaced from the armory terminals in Handycam. This is consistent
with different viewpoints being used for native HUD projection and scene
rendering; the exact native projection source is not yet established.

War Journalist writes the camera component's position, rotation and FOV just
before calling the original game render callback. That does not establish that
native HUD coordinates, possibly calculated during the earlier game update,
are recalculated from the modified camera.

A temporary passive wrapper observed the exposed Lua `Camera.world_to_screen`
function during the user's reproduction. It recorded zero calls over 240 active
Handycam updates, then restored the function automatically. Thus that Lua
function was not a correction seam in this test. This does not prove that every
possible engine or loader API is unavailable, nor does it locate the native HUD
camera or establish native update ordering.

The probe preserved arguments and exact return tuples, used no camera/marker
setters or native reads, and stopped after three seconds or 240 updates. Its
fixtures cover forwarding, nil returns, idle behavior, bounded removal and
preserving later function replacements. Only the runtime module in the live
generation was temporarily instrumented; the installed archive was unchanged.
Evidence and baseline/diagnostic payloads are retained under
`dist/review/handycam-hud-projection/`.

No icon-position fix was implemented or visually accepted. A supported native
HUD-viewpoint update or a qualified marker projection provider is still needed.
Moving the camera back to third person would remove the requested viewpoint;
a constant two-dimensional offset cannot generally correct a camera translation
for markers at different depths.
