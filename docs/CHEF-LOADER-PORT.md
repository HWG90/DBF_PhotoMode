# Chef Shared Loader port

Development **preview 4**, 2026-10-26, targets Chef **1.2.3 / API 3** at
[`429516a243392bc724ce7b41ef2712cf4e5a0157`](https://github.com/Th3chef/Chef-Shared-Loader/tree/429516a243392bc724ce7b41ef2712cf4e5a0157).
The LLL/BSL/MDL graphs remain separate. Shader effects and AI controls are excluded.
See the [feature matrix](CHEF-FEATURE-MATRIX.md) and [candidate instructions](CHEF-PREVIEW.txt).
Nothing has been installed, published or validated in game.

## Loader contract

References: [modding guide](https://github.com/Th3chef/Chef-Shared-Loader/blob/429516a243392bc724ce7b41ef2712cf4e5a0157/docs/MODDING.md),
[sandbox](https://github.com/Th3chef/Chef-Shared-Loader/blob/429516a243392bc724ce7b41ef2712cf4e5a0157/src/chef_loader/sandbox.lua),
[services](https://github.com/Th3chef/Chef-Shared-Loader/blob/429516a243392bc724ce7b41ef2712cf4e5a0157/src/chef_loader/services.lua),
[utilities](https://github.com/Th3chef/Chef-Shared-Loader/blob/429516a243392bc724ce7b41ef2712cf4e5a0157/src/chef_loader/utilities.lua).

- Resource `mods/goose/war_journalist` declares the addon and minimum loader in
  its headers. Source Lua 5.1 and sandbox-local preload modules are embedded.
  No boot replacement, FFI, DLL, process hook, detour, network bridge, subprocess,
  executable patch or global engine hook is added.
- Engine calls use `chef.call`; refused nil/reason or false setters never count
  as success. Chef always returns four values. Adapters truncate single results
  before nested calls. Quaternion decomposition preserves four. Subject snapshots
  obtain twelve scalars through the four stored matrix axes, preserving raw affine
  storage instead of rebuilding it from position/rotation/scale.
- Menu changes drive edits. Fixtures model Chef's 2-32 choice limit, slider
  validation/rounding and unchanged-value callback suppression. Actions reset their
  toggles. **Retry photo cleanup** handles already-off camera toggles reliably.
- Shared leases coordinate cooperating WJ Chef instances, not unrelated camera/time
  mods or an old LLL runtime. Use one WJ runtime. Failed restoration stays pending.

## Implemented workflows

Freecam has rebindable clutch/movement/look/roll/zoom, optional mouse look,
smoothing, movement lock, FOV/focal shortcuts, horizon/portrait tilt and opening
view recall. Menu/clutch handoffs reset smoothing and pending mouse deltas.
Chef reads shared input; the game, native menus and chat can still react.

Freeze requests exact zero, slow motion selects 0.05-1x, and rate changes while
frozen preserve freeze. Motion/paths use `Application.time_since_launch` because
Chef's own clock advances with game dt. Cinema resumes gameplay while holding a
placed/path camera, resets owned poses before thaw, and remembers pre-take freeze
unless explicitly overridden. End/close/focus/world/session/stop request 1x.

Time and pose edits require one visible peer. Time ownership checks at most 4 Hz;
Chef exposes no peer-join event or synchronizing-peer inventory. Earlier join
stages remain undetectable. No time-policy getter or cross-addon write observation
exists, so cleanup is explicitly 1x, not a measured previous multiplier. Use solo
testing without other time modifiers. Refused time cleanup retries at most 1 Hz.

Paths have up to 32 numeric frames with editable outgoing duration/Smooth/Cut
segments. Recall/remove points and manual takeover are explicit. Paths and five
bookmarks clear on close. Five persistent camera presets use the opening camera
as their relative anchor. Namespaced numeric saves reject invalid schema/basis,
nonfinite data and failed reads; failed writes preserve the previous cache.

Composition includes frames, guides, tint overlays, vignette/width, opt-in grain,
clean view, all 13 logo picker entries (including None), RGB and size/opacity/
position. An optional movable legend refers to the bindings menu so it does not
show stale keys after rebinding. Clean view hides guides/logo, not the game's HUD.

## Lighting and native switches

Three local lights use the exact dependency-free unit
`mods/dbf_photo/units/photo_light_v1` (`e07f49224f0a5759`). Explicit Apply updates
RGB/preset color, intensity, enabled state, point/spot, cone and offsets. A swatch
previews the next color. Shadows stay off. Range defaults to the compiled 8 m;
alternate values require a positive native getter and successful readback. A
failed range edit cleans up that copy. Visible cone/range behavior is unverified.

Static lights stay idle. Opt-in following compares numeric camera frames before
writing. Numbered markers and clutch + middle-button dragging use at most three
owned points and a captured camera plane; no raycast/scene scan. Shift gives 0.1x
precision. Spot aiming and Key/Fill/Rim, Portrait and Dramatic side rigs use a
numeric target ahead of the camera, not inferred actor identity. Five setups
save/recall relative to the current camera. Partial replacement attempts rollback.

Helpers reacquire light components for writes. WJ confirms destruction before
releasing Chef's spawn ledger, because `chef.despawn` drops bookkeeping before
native destruction is confirmed. Retired-world units are never dereferenced.
Failed cleanup retains the record until explicit retry or loader stop.

Bloom and native DoF are independent boolean Game setting/Off/On controls. Each
captures a baseline, preserves observable foreign edits, and polls acknowledgement
at most 10 Hz for two seconds. Settled flags stay idle. Game setting/world/stop
request restoration. Late cleanup needs explicit retry; identical foreign writes
cannot be observed. Both start at Game setting. DoF retains the game's own focus;
numeric lens controls and autofocus remain unavailable. No shader assets ship.

## Experimental selected subjects

Subject model/native adapter and the 213-frame bank load on explicit enable/
refresh. The existing `unit-pose-preview-v1` contract is used, never a fabricated
qualified receipt. Only resource `4d1c334d294dfa97`, its 107-node hierarchy and
named body nodes qualify. At most four candidates are offered for explicit
selection. This is not authoritative local-player identity.

Freeze is required to apply. Seven pages reach all 213 frames; empty final-page
slots refuse. Exact twelve-scalar body snapshots, mode/topology/identity checks,
85-node ownership and partial-write recovery reuse the existing subject owner.
Explicit thaw/Cinema reset first and stop if reset fails. Unexpected time
invalidation attempts cleanup once. There is no frame tick or reapply loop.
Cape/attachment adaptation, subject hiding and frozen-ragdoll controls are absent.
Visible pose acceptance is unverified; this feature stays experimental/default-off.

## Cost and validation

- Closed camera, unmodified time, settled flags, empty actions and hidden overlays
  remove both callbacks. No background camera-open hotkey or subject polling.
- Camera acquisition takes one world inventory (32,768 handles maximum), examines
  at most 64 units/frame with a five-second unscaled deadline, and compares at most
  64 cameras. Inventory can still spike and needs deployed measurement.
- Active ownership requires bounded world/view reads because there is no camera
  change event. Native reads fill retained arrays; unchanged values are not
  reapplied. Input checks the clutch before other bindings/cursor. Motion reuses
  buffers; explicit actions are bounded to eight per update.
- Subject operations are explicit synchronous batches with matrix/topology/owner
  checks. They can spike. Lazy bank decode/mock timings are not deployed metrics.
- Static lights stay idle; following compares at most three numeric frames.
  Marker lists rebuild on revision and project at most three points per render.
- Overlay layout rebuilds on relevant edits/resolution changes. Immediate drawing
  submits visible primitives each frame. Grain uses 96 rectangles, changing at most
  12 Hz. Extra logos use at most 512 prebaked spans each; crest uses 451 native
  triangles or at most 256 fallback spans after one probe. Edge detail is reduced.

Use Python with `lupa.lua51` (`py -3.14` here). The game is never the fixture VM.
The pinned sandbox Git blob is `737728a5911189c3f02b13b21487ab8dbac97310`.

```powershell
py -3.14 tools/test_chef_port.py --sandbox dist/review/chef-upstream-current/src/chef_loader/sandbox.lua
py -3.14 tools/build_chef_candidate.py --sandbox dist/review/chef-upstream-current/src/chef_loader/sandbox.lua
```

Output: `dist/releases/chef-preview.4/War-Journalist-0.4.0-chef-preview.4.zip` and
`BUILD-RECEIPT.json`. Seventeen source suites run: ten Chef and seven shared
camera/view/composition/path/subject/native/bank suites. All ten Chef suites run
again from decoded packaged Lua. They use the real pinned sandbox with mocked
engine/input/services, checking contracts, ownership, partial/refused writes,
idle behavior, transitions, persistence and exact restoration for all 213 poses.

The package permits exactly one source addon and the byte-exact light unit, with
empty GPU/stream payloads. Checksums cover every ZIP member. Provenance includes
source, generated-art inputs and build hashes. Independent archive/corruption
review is recorded beside the ZIP. Older candidates are retained. See
[artwork credits](CHEF-ARTWORK-CREDITS.txt) for retained source attribution.

Release acceptance still needs installed-byte/loader verification, direct camera
and input observation, freeze/slow/Cinema transitions, saved-anchor behavior,
lighting and pose visibility/restoration, native flag acknowledgement, focus/world/
stop cleanup, native/below-native render scale, and deployed steady-state timing
plus transition spikes. No source/package result establishes those outcomes.
