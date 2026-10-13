# Photo lighting development integration

0.9.5 lighting status: **Not tested fully**.

`freecam/photo_lights.lua` manages at most three local light units owned by the
current Photo Mode session. The release uses the bundled dedicated resource
`mods/dbf_photo/units/photo_light_v1` (`e07f49224f0a5759`). Its 976-byte definition
has no external geometry, materials, GPU, or stream dependencies; the existing
shared boot archive includes it. No authored world light is edited or removed.

The original ship prefab and engine functions were inventoried read-only in
the running game. On October 13, David confirmed visible prototype illumination in PID
25996. Native readback also confirmed root node 1, position at the actual camera
plus its forward offset, matching world direction/up, linear RGB, intensity,
point type, disabled shadows, and realtime (unbaked) mode. Spot/follow behavior,
the expanded power/range limits, and the drawn position indicator retain their
own live verification requirements.
That observation used `content/env_ship/shiplight` (`15c7f9cccbb13826`), whose
ship package is not guaranteed to remain loaded on missions. It does not prove
the new dedicated asset loads or illuminates a mission. The lighting status
in the release retains the label “Not tested fully”; failed availability stays
disabled until the bundled startup asset is available.

## Engine route

The route is `World.spawn_unit`, `Unit.light(unit, 1)`, the public `Light`
setters, `World.update_unit`, and `World.destroy_unit`. Epic LUT already uses
the same resource and basic route for its preview world. [Autodesk's light
creation documentation](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/lighting_rendering/lighting/light_sources/create_light_source.html)
describes spawning a unit containing a light. [The Light API reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Light.html)
documents point lights as `omni`, spot lights as `spot`, linear color, falloff
distances, and cone angles in radians. Helldivers exposes `set_spot_angle_end`
but does not expose the older `set_spot_angle_start`; the latter is optional.

Placement reads `Light.node(light)` before changing transforms. A light
attached to unit root node 1 shares the placed root transform and must not be
zeroed by the light-local setters. A direct child is verified with
`Unit.scene_graph_parent(unit, node) == 1` before its authored local offset is
neutralized on the owned copy. Unknown attachment hierarchies fail with owned
cleanup. This avoids moving a correctly placed root-attached light back to the
world origin. The engine's `Light.world_position` and `Light.world_pose` provide
readback for live placement/direction verification.

## Controller contract

The generated runtime constructs `lights = factory.new(sr, log)` and passes it
to the controller after the focus sampler. Its render hook caches the actual
camera's numeric world position and basis after placement. Lighting requests
from the menu run through `queue(action, values)`; `flush(world, context)` drains
them in the real game update callback. Repeated slider edits merge, and exiting
discards outstanding creates or edits. Shutdown performs final owned cleanup.
An optional third `new` argument refreshes an existing empty, idle manager in
place. This preserves the controller/update callback's shared table identity;
refresh rejects managers with owned units or queued work so no ownership is
abandoned.
An explicit fourth-argument owned handoff can preserve an occupied manager's
exact record table, selected index, world, camera context, and serial sequence.
It validates record IDs against the existing public list and rejects queued
work or malformed state before replacing methods. The review helper reads this
existing state without changing closure upvalues, then queues reapplication in
the update callback; it never destroys/recreates the user's current lights.

- `tick(world, context)` attaches the live main world, copies numeric camera
  context, prunes retired/dead owned units, and moves lights set to follow the
  camera. Context contains `position`, `forward`, `right`, and `up`, each a
  three-element numeric array. Basis vectors must be orthogonal.
  The right/forward/up basis must also have the engine's positive handedness.
- `ready(world)` returns `ready, reason, capabilities`. Point, spot, and range
  controls are separately gated against the available engine API. The light
  resource must be loaded. There is no fallback to a scene light.
- `create(values)` creates one light using the last camera context.
- `selected()` returns a copied values table, selected index, and light count.
- `list()` returns copied values and IDs, never engine unit/light handles.
- `markers()` returns numeric actual world `position` and `forward` arrays for
  live owned units, with `id`, `kind`, picker `color`, requested `enabled`,
  `selected`, `cone`, `range`, and any record `error`. It reads the fresh light
  component under a scoped Script temporary count and copies all coordinates
  before restoring that count, including error paths. Returned marker data
  contains no engine objects. Retired worlds are skipped before unit access.
- `select(index)`, `update(values)`, `place_at_camera()`, and `remove(index)`
  operate on owned records. `remove()` defaults to the selected light.
  Removing an earlier record retains the same selected light. A failed native
  edit attempts to restore the previous settings and anchor; a failed restore
  disables that owned light and retains its handle for cleanup/retry.
- `release(reason)` / `clear(reason)` / `close(reason)` remove all owned lights.
  Call on Photo Mode exit, actual menu/session exit, world change, owner
  retirement, and loader disable. Hiding the controls for a screenshot retains
  lights. Failed destruction keeps its owned record for a later cleanup retry;
  a retired world is never dereferenced. A scene change cannot create new lights
  while old live-world cleanup is pending.
- `revision` identifies completed selection/property/lifecycle changes and
  `pending` identifies queued menu requests. The controller reflects completed
  selected-light values into the fields without causing new queued edits.

Defaults are `kind='omni'`, `enabled=true`, `intensity=3`, `color='#FFFFFF'`,
`range=8`, `cone=45`, `right=0`, `forward=1`, `up=0`, and
`follow_camera=false`. Position offsets are metres in the camera basis saved
when a light is created or moved to the camera. Cone is degrees in the UI.
Picker colors are decoded from sRGB to linear values for the engine.
Intensity accepts 0–10,000 and range accepts 0.1–1,000 metres, including .01
precision. When the verified game API is present, apply turns the owned copy's
`Light.set_auto_falloff_end_and_culling` off before manual falloff settings.
The prefab's automatic mode must not override the chosen distance. The live
`falloff_end` getter reads separate storage from the configured range setter;
its observed zero is not interchangeable with the requested distance.

Suggested Lighting page order: Add light, selected light, enabled, point/spot,
intensity, color, range, cone, right/forward/up offsets, follow camera, move to
camera, remove selected, remove all. This page is separate from lens settings
and capture/navigation actions.

## Verification

`photo_lights_tests.lua` exercises placement, color decoding, point/spot
properties, selection, visibility, fixed/follow-camera positions, the three
light limit, invalid input, missing capabilities/resources, partial spawn
initialization, destruction retry, scene changes, and retirement. It uses
isolated engine mocks and does not prove a rendered game light.

The focused hardening fixtures also simulate both root and child light
attachments (including the root-reset regression), unsupported child parents,
missing node access, partial native edit rollback, selection retention, invalid
request payloads, and reflected camera bases. The review helper at
`dist/review/photo-lighting-20261012/probe.lua` reads the existing manager via
read-only `debug.getupvalue`, queues requested edits through its public API,
and captures only the engine `back_buffer`. It never replaces the manager,
changes closure upvalues, or creates a second render world.
Expanded fixtures cover fractional/high limits, manual auto-falloff selection,
numeric marker copies, temporary-scope restoration on getter failure, and
preservation/cleanup of exact original units across an occupied handoff. UI
integration now also exercises the owning MCM core: point-light readback must
not write its disabled cone field or close Photo Mode, while switching to spot
enables cone editing.
