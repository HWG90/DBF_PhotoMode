# Selected-subject Handycam on BML

The Windows camera can use a selected Helldiver's genuine engine Unit and named
head node without loading the native avatar DLL. This is photographic tracking,
not authority over a local player. A teammate can be selected in the same way.
Framing continues to use the existing gameplay-camera look basis and Handycam
smoothing; it is not the teammate's screen feed or their exact aim.

An automatic candidate runs only at Photo Mode entry, after bounded subject
discovery. It compares the rendered camera's containing Unit root transform with
the authored `attach_cam_1` node of each discovered Helldiver. A unique complete
matrix match selects that photographic target. Without that match, a head within
6 m of the initial gameplay camera may be selected if it is at least 0.75 m closer
than the runner-up. This is a photographic proximity heuristic, not proof of local
player ownership. Ambiguous candidates leave explicit Subject selection available.
Runtime logs confirm proximity selection. On portable.22.14 the user confirmed
automatic selection worked in the current test; crowded and replacement cases
remain separate acceptance tests.

Movement lag is configurable immediately after Intensity: 0 ms follows the copied
head position directly; 1-500 ms applies exponential position smoothing independently
of aim smoothing. The default is 150 ms.

During a shot the selected Unit's session, world, alive state, resource and graph
size are checked before reading its head. Replacement or retirement closes the
shot through the existing cleanup. It does not silently switch to another body.
There are no world scans in the tracking loop and no head reads while closed.

Handycam now retains its subject, smoothing history and any native visibility
lease while Photo Mode settings are open. The Photo key, Return to camera and
ESC from settings resume the same attached shot. Explicit exit still restores
the gameplay camera; target/session retirement still performs cleanup. Subject
replacement and camera-type changes are disabled during the attached session.
The existing refreeze preference applies while editing. Lua fixtures cover
these transitions. The user confirmed all requested menu/return/end transitions
with "Works" after the live reload on October 26; the receipt is under
`dist/review/windows-handycam-persistence`.

Visibility is a separate unfinished Windows port. The native visibility reader
still provides exact equipment ownership and shader-pass masks under LLL, but
its DLL cannot load here. The Windows tracking fallback therefore does not hide
the character. Native visibility, where available, keeps the existing hide and
restore behavior. Do not describe this candidate as a completed Hide Player fix.

The saved engine inventory is expanded to Mesh/MeshComponent and network mapping
APIs; the bounded cape observer records Mesh.visibility when available. These
are read-only probes. Autodesk documents that getter as visibility in the current
render context, not the full shader-pass mask used by the old restoration lease:
https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Mesh.html
Do not translate that Boolean into an invented original 255 mask or infer
equipment ownership from proximity alone.

Requested Handycam visibility modes are separate: POV hides only the helmet and
torso, retaining arms, hands and weapons; Full Hide covers the body, outfit,
carried weapons, backpack, cape and attached accessories. Full Hide's existing
native ownership graph includes nested attachments and independent ammunition
feeds. Windows does not yet have an equivalent qualified graph or mask reader.
No POV grouping is inferred from a shared skeleton or a whole-armour group.

The next private probe inventories at most 64 meshes on the selected root, once
per distinct target and at most four targets per runtime. It reads documented
mesh node, material-count and current-context visibility getters only. It never
scans the world, calls visibility setters or refreshes unchanged targets. This
is diagnostic preparation, not a completed POV/full-hide implementation.

Live portable.22.14 capture at 15:06:23 on October 26: selected root has one mesh,
scene node 103, one material, current-context visibility false. The Handycam
entry completed without a runtime error. This root inventory does not identify
the visible outfit or its attachments. Evidence and user confirmation are in
`dist/review/windows-hud-pov-probe/HANDYCAM-ACCEPTANCE.json`.

The next private diagnostic is a read-only outfit inventory, triggered once by
an active subject-selection event. It snapshots at most 16,384 world units, then
examines at most 24 per update with a 2 ms scheduling target and an 8 ms stop
threshold. The snapshot is timed separately. It compares live world matrices
for known body bones in the same callback and logs at most 32 matching units
and 16 mesh rows per candidate. It cancels on selection/world retirement or
Photo Mode close, and stays idle after completion. Matching bones are evidence
for investigation, not attachment ownership or permission to hide those units.
No visibility or transform setters are present. Source fixtures and exact
reload payload checks are in `dist/review/windows-outfit-discovery`.

Live result, October 26 at 15:28:41: all 2,292 world units were examined,
17 render units matched selected-body bone matrices, and the maximum measured
update cost was 4 ms. Matching units contain visible meshes; the candidates
include three head/chest/spine rigs, several torso/arm/leg rigs and one broader
rig including cape1. These are topology observations, not confirmed visual
helmet/torso groupings. No gameplay visibility was changed. Resource IDs and
mesh indices are preserved in that review directory's `runtime.log`/`LIVE.json`.

Next qualification: test the documented explicit `default` visibility context
on an owned disposable unit in an isolated world, including whether shadow
context changes remain independent and whether the Boolean getter reads the
default context. Do not reuse the old full-mask lease by converting that getter
to 0/255. Full Hide still needs weapons, cape and attached accessories; POV
still needs visually verified grouping that preserves arms and hands.

Private visibility qualification passed live at 15:37:24 on October 26.
An isolated world spawned its own copy of resident outfit resource
`3bae7995707e30fb`. On that copy, the explicit `default` context round-tripped
true/false/true. Changing `shadow_caster` and `occluder` did not change the
Boolean getter, demonstrating that the context argument is honored and the
getter observes default visibility in this update callback. This does not read
or reconstruct a complete pass mask. The private world was released; no player
mesh was written. Maximum phase cost was 2 ms. Evidence:
`dist/review/windows-visibility-private/LIVE.json` and `runtime.log`.

This also demonstrates standalone outfit-resource instantiation. A complete
character clone, attachment assembly, skinning, posing and visual appearance
have not been tested and must not be reported as working.

The default-context visibility lease now passes live hide/restore on copies of
all 17 discovered outfit resources (87 meshes), with every private world
released and a 4 ms maximum test phase. The catalog records numeric mesh-name
IDs and bounds. A separate cross-frame test passed at 15:55:45, preserving
original visibility and releasing the private world; maximum phase was 3 ms.
The implementation retains original mesh identity, preserves pre-hidden and
foreign states, retries failed restoration and performs no periodic scans.

Director exposes a default-off POV visibility toggle on Windows. The user
visually confirmed the helmet/torso grouping preserves arms and weapons and
restores appearance when switched Off. Repeated live transitions owned 16
meshes when On and zero when Off, costing 0-1 ms at the runtime timer resolution.
Evidence: `dist/review/windows-pov-candidate/LIVE.json`.

The next Lua generation extends the same toggle to `Hide helmet, torso and
cape (POV)`. It adds the observed cape resource `ea846ef460cc5ba0` (four meshes)
to the three accepted resources `98ef4e039e963bdb`, `d2a2e2bc4fa5be21` and
`544ed679357b6cb7`. All four exact mesh-name/layout fingerprints and unique
named-bone world-matrix matches must validate before writes. Each explicit
transition performs four bounded resource lookups and otherwise stays idle
until an option/selection/lifecycle change. Menu reopening retains the lease;
Off and Photo Mode exit restore it. Other outfits are refused and the toggle
returns Off. The user confirmed the cape hides and restores with YES on October 26. The 87 executable fixture
groups pass (one optional reference skipped), and all 78 payload modules match
source. Evidence: `dist/review/windows-pov-cape`.

Full-player hiding including weapons and all attachments remains unfinished.
These are live Lua development generations, not new published archives.

A bounded read-only attachment-anchor diagnostic now extends the one-shot outfit
inventory. For unmatched render units whose first scene node is within 3 m of
the selected body's first node, it compares at most eight leading node world
matrices with twelve authored weapon/hand/backpack/accessory anchors. It logs
only full matrix matches, at most sixteen candidate units. Proximity alone is
not a match, and these observations never grant a visibility lease. Existing
24-unit/2-ms scheduling, 8-ms stop, lifetime cancellation and idle completion
limits remain. Source fixtures cover exact transforms, orientation mismatch,
far-unit early exit and graph bounds. Live at 16:05:05 on October 26, the scan completed all 2,292 units with a
4 ms maximum update. It found exact attachment-anchor candidates for sample
pouch `a9936cbe561e8180` (six meshes), intel pad `1c8764d62e12925a` (ten meshes),
and holstered pistol `416d053372c4e433` (nine meshes). These remain read-only
candidate associations; held weapon, backpack and nested accessory coverage
is incomplete. Evidence: `dist/review/windows-attachment-anchors`.
The cape-inclusive POV toggle separately owned twenty meshes at 16:05:08 and
restored to zero at 16:05:45, both measured 0 ms at timer resolution. User
visual acceptance and transition evidence are in `dist/review/windows-pov-cape`.

POV controls now expose independent helmet, torso and cape toggles. Each group
owns its own mesh visibility lease: toggling cape does not restore/re-hide the
helmet or torso. Only changed groups perform bounded resource lookups; unchanged
state stays idle. All selected dirty groups validate before new writes, and
selection loss, failure or exit releases every owned group. These remain limited
to the currently verified outfit.

Handycam adds view-local forward/up offsets in centimetres, independently
adjustable from -30 to +30. The starting position is 8 cm forward and 4 cm up
from the head bone; both zero reproduce the old mount. The clean camera yaw and
pitch orient the offset; angular shake does not move this anchor. The offset is
applied after head-position lag and is never stored in position/speed history.
Changing offsets while editing Handycam settings preserves the attached shot.
Fixtures cover separate group leases, untouched-group writes, idle behavior,
restoration, axes, defaults, negative/zero offsets, nonaccumulation and attached
menu edits. The user confirmed independent toggles and framing with yes in `dist/review/windows-pov-controls`.

Start / end Handycam is unbound by default, editable in Controls and shared
with the loader binding menu. It was F11 through 1.3.2; Steam records with
Ctrl+F11, so a saved F11 is cleared at load and WJL no longer reserves F11
while Photo Mode holds the keyboard. From gameplay the key opens Photo Mode, performs the
existing automatic subject selection, and starts Handycam. From an attached
shot or its settings it explicitly ends the shot and restores gameplay. The
Photo Mode key still opens/resumes Handycam settings. Editing, input handoff,
capture and foreground guards prevent accidental activation; a held key produces
one action. If no subject is available, selection remains open for the user,
without a per-frame retry. Source tests exercise closed/shot/menu states,
repeated presses, holding, editing, focus, remapping and missing targets.

At the user's request, defaults now match their saved settings read on October
26: 4 cm forward, 13 cm up and zero milliseconds of movement lag. Saved settings
are not overwritten. The camera arithmetic fallback and reset defaults agree.
Evidence and live acceptance status: `dist/review/windows-handycam-f11`.

The attachment diagnostic now resumes deeper graphs eight nodes at a time,
rechecking world, resource and graph size across callbacks, including the final
world unit. It retains the 2-ms scheduling target and 8-ms stop threshold and
adds a 4,096-node total limit. Read-only hits are capped at 32 per candidate;
no transform or visibility setter is used. Deep-node continuation, completion,
resource replacement and idle behavior pass fixtures. Its source is included
with the F11 development generation; fresh attachment observations remain pending.

The F11 live-reload attempt halted on the old generation's DoF restoration:
`dispose()` was called without the regular update that processes render-flag
acknowledgements. Portable.22.15 explicitly advances only those in-flight flag
transactions during disposal; a regression fixture verifies retirement without
normal gameplay updates. The old halted adapter needs one restart to receive
this fix. The installed package now includes the accepted POV controls,
user-requested defaults, F11, deeper attachment diagnostic and passive camera/HUD
signal qualification. Actual first-person ADS detection/handoff and HUD hiding
remain unimplemented; right-mouse third-person aiming must not be treated as ADS.
The user enters first-person ADS using middle mouse while aiming, and requests
that POV visibility remain enforced through ADS. `windows_camera_signals.lua`
observes documented mouse input events during Handycam and three existing-camera
samples per relevant event; `Gui.set_visible` calls are observed passively up to
32 changed states. There are no camera/visibility writes in this observer.


## Live acceptance: Handycam controls and ADS (October 26)

The current development generation changes defaults to 14 cm forward, 7 cm up,
0 cm right, zero yaw/pitch offsets and zero movement lag. Saved settings remain
owned by the user. Director exposes left/right, forward/up and yaw/pitch sliders,
plus a camera handle: M1 drag translates laterally/vertically, wheel changes depth,
and MMB drag changes yaw/pitch; Shift gives fine adjustment. Pointer movement
previews in memory, with one settings batch on release. Focus loss cancels an
unfinished preview. The user confirmed smooth directions and retained framing.
Evidence: `dist/review/windows-handycam-drag/LIVE.json` (79 exact modules,
88 passing fixture groups, live reload at 16:47:24).

Handycam now forces the verified helmet lease for the attached session without
changing the stored helmet preference. The user confirmed the ADS handoff at
16:56: the native sight view takes over, the prior Handycam framing returns, and
the helmet stays hidden. First-person observations were approximately 0.12 m
from the selected head; normal aim approximately 1.16 m, and released aim 2.65 m.
This is an event-triggered camera-evidence classifier, not an authoritative ADS
bit. Middle-button presses and right-button aim transitions open a maximum
0.5-second / 128-frame observation window; the mod's own output is excluded and
two consistent near/far samples are required. Between events, classification is
idle. Other scopes, collisions near the head and alternate control layouts still
need qualification.

Yield clears prior camera write ownership without restoring a stale pose over
the game camera. Resume requires the held component to match the rendered camera
and captures a fresh cleanup baseline. The shot, settings and POV leases remain
active; camera writes stop while yielded. POV reassertion occurs only at ADS
transitions against already owned, revalidated meshes. Live transition checks
reported 0 ms at timer resolution for five helmet meshes. Evidence:
`dist/review/windows-handycam-ads/LIVE.json` (80 exact modules, 89 passing fixture
groups, live reload at 16:55:31; no restart).

The HUD hotkey is `/`. The Lua `Gui.set_visible` observer recorded no corresponding
calls; global/update-environment inventories found no HUD bindings. The on-disk
game image has the expected build identity, but its bytes at the old native HUD
setter do not match the qualified runtime signature, so it cannot substantiate
that code path's current disassembly. External module enumeration previously
returned access denied. At 17:01:47 the bounded native-function environment inventory ran live:
Gui.set_visible, Application.main_world and Unit.camera all share the already
scanned globals. Fourteen tables and 328 keys yielded no HUD candidates. This
specific environment route adds no HUD binding; no function environment or HUD
state was changed. Evidence: `dist/review/windows-hud-binding/LIVE.json`.

## Aim alignment and facing during movement (October 26)

The user requests aim correction for the relocated Handycam view and forward-facing
A/D strafing and S backpedaling. Neither behavior is implemented by the current
diagnostics. The camera copies native view direction to the displaced head mount;
angular smoothing and user offsets remain independent potential contributors.
A fixed angle correction cannot establish convergence at arbitrary distances.

The user-completed trace in `dist/review/windows-handycam-aim-trace2` recorded
33 selected-unit matrices and 11 animation snapshots, with no pose-trace errors
and a maximum measured sample of 1 ms. Ordinary S movement ended with the unit's
forward axis 177.52 degrees from camera forward; an aimed S release measured
2.451 degrees. These are samples, not a universal locomotion-state classifier.
ADS yield/resume occurred at approximately 0.157 and 1.097 m from the head.
The rig's `weapon_aim` and `aim_weapon` matrices are observable, but neither is
yet qualified as the actual weapon ray or a world-space aiming destination.

The initial diagnostic incorrectly limited animation state tuples to 16 values.
The game returns 31 in this capture. The corrected diagnostic accepts up to 64
values and skips an oversized or failed optional state snapshot without disabling
independent bone reads. Fixtures cover 31 values, oversize, failed reads, retired
subjects and inactive state. This was a diagnostic error, not a movement fix.

The A/D/S probe in `dist/review/windows-handycam-parameters` checked 20 candidate
parameter names, one existence query per event-triggered sample. It found only
`move_angle` and `move_speed`; sampled angles included about +90 and -90 degrees.
No constraint-target name in that list matched. The search is not exhaustive and
does not prove that no other Lua route exists. The probe stopped additional pose
reads after one sample took 3 ms, exceeding its 2-ms guard; ADS event delivery
continued, and later yield/resume entries were logged. No parameter setter was
called. These animation variables are not qualified to control native body facing.

The prior implementation was located in the separate GooseGadgets checkout at
`Native ADS Camera Test/src/first_person_movement.lua`. It owns only a 0-to-1
transition on a focused-locomotion byte, preserves foreign values, and restores
on release. It uses native memory access, exact binary anchors and local-avatar
descriptor ownership; it does not set aim or animation flags. Its historical
address/layout is not qualified for the present BML runtime. The Lua inventory
does not expose a locomotion component manager. A/D behavior remains unverified.
Source provenance is recorded in `windows-handycam-aim-trace2/FOCUSED-MOVEMENT.json`.

Upstream parameter getter semantics were checked against the Autodesk Unit
reference: https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Unit.html .
These document existence checks and indexed reads; they do not establish the
meaning or write ownership of HD2's animation variables.

## ADS handoff and nested equipment follow-up (October 26)

The user reported misaligned native ADS sights and a missed exit until aim was
released. The 17:59:15 live generation in `windows-ads-native-yield/LIVE.json`
deduplicates only identical mouse events at the same engine timestamp, allowing
a new middle press even when a release was lost. Camera yield now restores fresh
pre-write native position, rotation and FOV only where the current value still
matches Handycam's last write. Native changes are preserved. The existing bounded
camera-reacquisition window remains. All 89 fixture groups passed; live ADS visual
acceptance is pending. The distance-based classifier is still not an authoritative
ADS state signal.

Full-player hide still leaves scopes and magazines visible according to the user.
The direct equipment catalog covers the current primary, pistol, backpack, support
weapon, sample pouch and intel pad. This does not establish ownership of their
separate accessory units. `windows-nested-attachments` adds a read-only second
pass over the same world snapshot: at most 128 nearby candidates and 16 direct
parents, eight parent nodes per chunk, at most four chunks per update, a 2-ms work
target, an 8-ms stop guard and an 8192-node total budget. A parent's root must
still match a named selected-body anchor in the current callback. Child-root to
parent-node matches compare all 12 matrix elements; proximity alone is insufficient.
Handles and scalar identity survive callbacks, while scratch matrices do not.
The observer stops after completion, subject retirement, cancellation or a budget
failure. It makes no visibility writes and does not grant an ownership lease.

At 18:04:33 the user-triggered capture completed over 2292 units, 47 nearby
candidates and three directly attached parents. It found accessory resource
`e53e4b0c20563d21` (one mesh, five nodes) at pistol `416d053372c4e433`
node 24, and `78829731a0563576` (four meshes, 13 nodes) at pistol node 15.
The pistol has 32 nodes. The second pass compared 2992 nodes; maximum complete
observer step was 4 ms. Evidence: `windows-nested-attachments/OBSERVED.json`.
The candidate in `windows-pistol-accessories` adds these two optional equipment
models with a qualified body-to-pistol link, exact parent graph, exact child
graph/mesh counts, unique full-matrix matching and existing reversible mesh
leases. No new steady-state scans or writes are added. Fixtures cover restoration,
foreign parents, unmatched children, layout changes and ambiguous matches. Live
visibility acceptance is pending; larger weapon/support/backpack accessory trees
still need observation with that equipment present in a mission.

The user subsequently confirmed pistol hiding, but reported the holstered primary
visible. A mission capture at 18:11:56 matched three primary accessories to
`968211c0033dce64` (43 nodes): `f9df21c8e52cac95` (4 meshes/13 nodes) at node 12,
`7be1e04a7738e673` (4/18) at node 14, and `5c1e075cba68340b` (4/12) at node 15.
These use the same reversible nested association candidate. A further read-only
fallback compares unmatched known primary/pistol/backpack/support roots against
the qualified 107-node Helldiver graph to find missing holster anchors. It does
not apply a guessed numeric anchor or move any equipment. The existing total
node/time budgets still apply; the body may add one parent to the 16 direct limit.

The user clarified that the consistent point-of-aim/impact offset occurs during
normal aiming, outside ADS; ADS itself intermittently occupies the wrong position.
At 18:12:04 the native camera was already 1.1153 m from the head, but Lua received
only a middle-button release, which the classifier ignored. It resumed only on
right-button release at 18:12:05. `windows-ads-release-holster` reconciles camera
evidence on either middle edge, with the same two-sample/one-handoff window.
Release-only entry and exit have fixture coverage. Live acceptance is pending.

`windows_movement_probe.lua` is an opt-in experiment, not a movement fix. Only an
explicit `wj-movement-probe.request` containing `move-angle-once-v1\n` arms it at
startup/reload. In unfrozen Handycam it permits one trial each for A/D/S. It waits
up to 0.6 seconds for an existing move_angle magnitude of at least 30 degrees,
writes zero once, observes at 50-ms intervals for at most 0.16 seconds, and restores
only its still-owned value. Native overwrites are preserved without reapplication.
Menu entry, ADS, focus loss, close and selection changes cancel the trial. Invalid
subjects/graphs/indices refuse before writing. Restoration failure remains a
cleanup barrier. The experiment remains unarmed for the current ADS/visibility test.

The release-edge fix produced several live `middle released` resumptions at
18:18:14-16, with camera acquisition succeeding on its first attempt. The user
still reported occasional third-person returns and requested persistent Handycam
intent. `windows-handycam-return-guard` adds a return-only fallback while yielded:
it reuses the frame/head already sampled by the render path at no more than 20 Hz,
requires two far-camera confirmations, and cannot enter ADS on its own. No engine
getter, input poll, world scan or camera setter is added by this classifier.
It avoids relying on an event that may be missing or whose half-second window
has expired. Existing camera identity/ownership checks remain; a brief transition
can still be visible, and this is not a native return-state override. Fixtures
cover late/missing edges, frequency limits, invalid samples, inactive state and
returning the same shot without settings commits. Visual acceptance is pending.

The read-only equipment observer can now rearm on explicit full-hide On actions,
up to four total captures per generation. Routine subject sync and unchanged
settings never rearm it. This lets a holstered capture follow an earlier equipped
capture without a restart or reload; only the explicit menu action starts work.

The earlier 18:19:40-43 trace also recorded a two-second camera-reacquisition
timeout before succeeding after further input (12 attempts in the next window).
This establishes a render/component-match delay, not its precise cause.
`windows-camera-publication` tests the publication-lag hypothesis: the existing
Handycam frame read copies four recent poses of the same validated component
into reusable scalar slots, using the caller's existing timestamp. Resume may
accept an exact pose match within the existing tolerances if it was observed in
those four slots no more than 100 ms ago. Unmatched, expired and evicted poses
remain refused; component/world lifetime checks remain in force. No additional
native read or discovery call is needed to maintain the history. Runtime logs
identify acceptance via `recent held-camera publication` so the hypothesis can
be checked live. Tests cover delayed publication, expiration, bounded storage,
caller mutation and foreign-camera refusal. Visual/performance acceptance remains
pending. The normal-aim convergence problem is not changed by this candidate.
# Mission subject inventory recovery (October 26)

At 18:37:45 the live adapter reported `Subject inventory is not a bounded dense
array`. Discovery incorrectly treated the four menu slots as the maximum world
inventory, so extra bodies or sparse entries disabled every subject and F11
fell back to the menu. The adapter now inspects at most 128 exact-resource
entries on explicit discovery, skips dead/duplicate handles, and retains the
four nearest valid 107-node bodies. Complete rig and lifetime validation still
precedes publication. Opening uses the gameplay camera position; Refresh uses
the photo camera position; click selection uses the hit centre. No discovery
work runs while unchanged.

The source tests cover sparse inventories, more than four bodies, distance
ranking, duplicates, retired handles, scratch-frame rollover, the 128-entry
bound, and retaining previous private records after a failed discovery.
All 90 fixture groups pass and 81 payload modules match source. Generation
`58cec372b34e48d9b3ce79f9d42bee3f` loaded at 18:41:13 without restarting the game.
At 18:42:39 discovery listed one subject in 1 ms (runtime clock resolution),
and camera association found its head at 1.40 m. The user confirmed F11 now
finds the Helldiver and works. The larger inventory path is fixture-verified;
this successful live sample contains only one entry. This is a development
reload, not a new installed portable archive.
Evidence: `dist/review/windows-subject-inventory`.

The visibility catalog also used `ipairs` on native resource inventories,
which could omit later equipment or miss an ambiguous match beyond a hole.
It now enumerates and validates every entry, retaining the sixteen-entry bound
per resource and all existing bone, mesh and ownership checks. Sparse full-hide,
ambiguity, malformed-key, bound and idle/restoration fixtures pass. This change
loaded with the root-source generation at 19:27:49 and remains in the current
root-burst generation. It does not establish a holstered-primary association
or extend the equipment catalog; live acceptance of that remaining issue is
still pending.


### HUD static-route follow-up (23:30 onward)
No live mutation or reload. REA/Ghidra 12.1.4 opened the installed game.dll (SHA256 6d1d4d3bc6fc84801d9f8f1b310e13a603d07409f3d9495d74b42e1d0bb1c08f). Provider-defined string search for toggle/HUD and hide_hud returned no matches; an independent ASCII sequence scan also had no matches. Incoming-reference query for historical UI-root slot RVA 0x2e28788 (PE imagebase 0x180000000) returned none. This does not prove no HUD handler exists: the prior qualified runtime setter bytes differ from on-disk data, and packed/undefined/indirect paths are outside this evidence. Therefore no currently qualified Lua or static native path can be claimed from these queries. Retained exact evidence and provider snapshot under dist/review/windows-hud-static; target closed, game unchanged. Native hotkey remains the supported manual route while a callable boundary is unqualified.

### Observed 40-node weapon variant and multiple accessory slots
Repeated read-only captures at 23:04, 23:15, 23:21 and 23:27 identified direct weapon 27ee1ed8f6fb6356 (10 meshes, 40 graph nodes) matching the selected body attach_hand_r. Nested resources 309f7e645a8d2b56 (4 meshes/14 nodes) matched weapon node 19; cebd25f8778bfdee (5/14) node 17; b1bc2b7252ccbc03 (5/12) nodes 28 or 29. These resources were missing from the visibility catalog. Added optional exact-layout associations and multiple child instances with a unique owner per parent slot. Duplicate inventory entries and two units at one matching slot refuse before writes. Foreign parents/unmatched children stay visible. Reuses existing reversible default-context mesh leases and explicit invalidation; no steady-state queries added. Fixtures cover both slots, foreign parent, unmatched child, duplicate/ambiguous slot, graph change, pre-hidden restoration and idle. Full fixture runner passed. Candidate 33431eacc86d4bc194db143609279e92 changes windows_pov_visibility only from base 8c5fff3ab9f44f46b3cffc38b37456a4, preserving all 86 other modules, including accepted Freeze. Visual acceptance and transition cost pending; this does not establish all outfit or holstered-weapon coverage. Review evidence is in windows-weapon-variant-hide.

Association performance follow-up: the fixture's 13-part body plan performed 52 world-pose getter calls, including 26 repeated reads of the selected body. A scalar-only cache local to a single rows() call reduces this to 31 total / 5 selected-body reads; each subsequent plan starts fresh. The test rejects moved/stale correspondences and proves idle flush performs no getters or writes. Full fixtures pass. Optimized single-module payload is verified offline under windows-visibility-plan-cache but deliberately not requested live while the original accessory candidate awaits visual feedback. No deployed transition-time improvement is claimed before measurement; Freeze and the portable.22.18 artifact are unchanged.

### Subject recovery across game-session transitions
User could not select any subject. Runtime logged Qualified session changed at 2026-10-27 00:01:29; repeated Refresh reused a native adapter bound to the prior session. Added a read-only session_current predicate and controller proxy. Runtime checks it only on explicit Photo Mode open/subject refresh, releases prior leases and tracking/POV ownership before factory requalification, then reapplies current visibility preferences. Pending or failed cleanup prevents replacement. No per-frame session polling added. Full fixtures pass, including new session predicate, idle-check count, explicit refresh after session replacement and fresh-entry auto-selection tests. Scoped generation 62ad0d305dfd4eae8a1d63bd06a9b124 changes runtime/subject/native only from 9bdf3c421f864a539ec5096be6a911aa; preserves all 84 other modules and deliberately excludes another chat's pending HUD callback from runtime payload. The accepted Freeze transfer/post-render policy remains. Visibility screenshot confirms full weapon and smaller parts remain; variant holster observer source/test change is prepared but not reloaded while restoring selection. No archive install/restart performed.

### Read-only local-bind parent hypothesis
Session-recovery generation subsequently logged scanned=1/listed=1 and automatic nearest-head selection at 00:09:31. Full visibility on the ship acquired/restored 101 meshes with 0-1 ms logged transition cost; this is not acceptance of mission holstered-rifle coverage. To distinguish authored root offset from missing association, added root_parent_pose: copy known weapon local/world root matrices, require finite non-singular local basis, derive inverse(local)*world and verify recomposition. attachment_matches evaluates it only for four known weapon resources on the first node chunk and returns/logs derived anchor matches separately; they never enter direct matches, nested ownership or visibility leases. Added current variant 27ee1ed8f6fb6356 to the existing bounded body-node holster fallback. Fixtures cover noncommuting rotation/translation, reused scratch getter storage, no transform/visibility writes, no extra derivation on later chunks/unknown props, dead roots and singular transforms. Full fixtures passed. Scoped read-only observer generation 73cc2f9dc8f447bdb1a8a27f30cdb607 changes only windows_subject_tracking from e200aa6316f54fcfb55041cabdcadaf9; all 86 other modules unchanged. Live parent relationship and cost remain unqualified pending capture; no new hide policy is inferred from the math alone.


### Holstered rifle accepted (27 October, 01:20 onward)
The reported floating gold rifle was render resource b80951732a5f58f4, 10 meshes/40 nodes, absent from the catalog. A read-only complete-world inventory sorted by distance identified it; the earlier output cap had been consumed by static ship displays before reaching dynamic player equipment. All 40 node world/local matrices were compared with the selected 107-node body. Inverse(local root) * world root exactly matched body node 28 (sling); world root alone did not. Added this exact resource/layout with hand/sling/weapon anchors and local-bind matching, plus nested matching for observed nearby scope/accessory variants. Acquisition retries only four after-game frames after explicit visibility invalidation. New generic matches apply immediately through appendable reversible leases rather than waiting for the entire inventory. Acquired equipment flags are checked at the existing after-game callback because stock equipment work may restore them; only changed, owned flags receive setters. No world discovery occurs in that maintenance callback, and Off is idle. Transition and maximum maintenance costs are logged. Game time, body/cape transforms and input modules are unchanged by the final single-module reload.

Generation 1e334946afc9479c8d18bc6bed738eec changed only windows_pov_visibility from 0b82ce0d03f04513a17cb9858cd0a0b2. Focused fixture covers offset sling binding, nested offset scope, after-game visibility and restoration. The user answered YES to the exact in-game holstered-rifle hide/Off restoration test. This accepts that reported reproduction, not every weapon/equipment/other Hide option. No archive replacement, restart or public binary publication was performed. One-shot diagnostic code remains only in the private live pack; it must be removed from the final distributable.
