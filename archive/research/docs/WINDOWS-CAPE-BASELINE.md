# Recovering cape alignment under Freeze

The user identifies the best earlier result as snapping the cape to the body
and then disabling cloth simulation. The user confirmed this happened during an authored pose. The exact run/build
is not identified; do not infer a cloth-disable API from that report.

The maintained `subject_poses.lua` provides a proven historical placement path:
capture the garment placement relative to the body's cape1 shoulder anchor,
then transform supported separate placement nodes to the new shoulder pose.
It excludes mesh nodes already descended from cloth bones, preventing the
shoulder transform from being applied twice. Reset evaluates/restores the body
before restoring the garment. Supported authored-pose transitions were visually
accepted in earlier releases, not necessarily moving/ragdoll Freeze.

That implementation does not contain a separate cloth-simulation disable call.
It relies on stopped world time retaining the cloth shape. Searches of the
maintained Photo Mode native sources and local LLL source also did not identify
such a call. This is a scoped search result, not proof that no switch exists.

The current Windows executable contains Havok cloth inspection strings including
`Cloth Update: ENABLED`, `Cloth Update: DISABLED`, and `Teleport Cloth`. They
are not a qualified callable API. A bounded offline RIP-relative LEA scan found
no references to the selected strings; no commands or native addresses were
invoked. Evidence is in `dist/review/windows-skeleton-no-cape/cloth-static-*`.

The old solver's attachment reader requires verified ownership and mesh lifetime
data. Windows POV hiding already associates the current cape resource through
matching head/chest/cape1 transforms and validates mesh identities. Reusing that
association for placement needs its own restore/retirement qualification; simply
claiming the unavailable native ownership reader succeeded is not valid.

The next candidate retains the 99-node body hold with cape bones excluded and
ports the authored-pose placement calculation into `windows_freeze_cape.lua`.
It reuses the Windows POV outfit association once at Freeze capture, then leases
exact garment meshes/topology and copies all matrix scalars across callbacks.
Only independent placement nodes are changed, after body refresh or one of the
existing four scheduled readbacks. Unchanged placement produces no setter or
scene refresh. Resume restores original placement when still owned; retired
worlds/sessions/meshes and foreign placement are preserved.

95 fixture groups pass (one absent LLL submodule check skipped), including
rotated/translated transforms, scratch expiry, idle writes, partial setter failure,
restoration, replacement meshes, retired sessions, hierarchy changes and the
body-refresh/cleanup ordering. All 86 live-payload modules match source.
Evidence: `dist/review/windows-cape-placement`. Visual acceptance and runtime
performance remain pending. There is no cloth simulation API call, near-zero
world time or keyboard-blocking change. Hoverpack protection remains unresolved.

Live reload acknowledged at 21:32 on 2026-10-26. First observed Freeze acquired
three placement nodes, wrote 21 node transforms total, then stayed at 21 through
the later readbacks while body replay continued. Closing Photo Mode restored
placement and released the hold after 661 renders, max combined step 2 ms.
This is execution/performance/restoration evidence, not visual acceptance.
The installed archive remains unchanged; this is a development reload generation.

## Cape-only half-turn trial

The user rejected the placement-only Freeze candidate: still not reattaching.
They explicitly requested a 180-degree cape rotation test. The next private
Freeze candidate rotates the independent placement bindings around the shoulder's
local right (left-to-right) axis, preserving its pivot and a proper rotation.
No body or cloth-bone flip is added. Resume restores owned original placement.
This is a test, not a release fix; it is deliberately not enabled for authored poses.

The Windows authored-pose adapter is also wired into the same non-flipped
placement solver: capture before body changes, apply after body commit, restore
after body Reset. Steady authored-pose maintenance does not reapply or scan it.
95 fixture groups pass; 86 payload modules match source. Evidence is in
`dist/review/windows-cape-halfturn`. Runtime and visual results remain pending.
Hoverpack investigation is now assigned by the user to the separate chat
`Fix new hoverpack crash` (01a17b02-6d66-74e1-b35b-0fc0a887b732).

## Attachment trace result and root-hold restoration

The user rejected the 180-degree cape-only trial with screenshots: cape across
front/head, still misplaced. The half turn is removed from entry activation.

The shared hover inventory reload cec7f5039a644e11aa12571c5e295236 at 21:46:18
also loaded the trace-only cape code. Read-only phase pairs show body and garment
chest/cape bones matching immediately before body replay, then separating after
it. Later samples: chest/shoulder orientation differs by about 165.3 and 168.0
degrees, cape1 translation by about 0.49 and 0.44 m. Garment matrices remain
unchanged across that replay; Mesh.world_pose agrees with each mesh node pose.
This directly identifies replay-induced scene-graph separation, not the native
physics writer or actual cloth vertex state. TRANSFORM-ANALYSIS.json and live.log
under dist/review/windows-cape-attachment-trace preserve the evidence.

At 21:47:48 the trace added enough work to exceed the eight-millisecond skeleton
budget. The skeleton hold stopped, consistent with the user's renewed spinning.
This diagnostic is withdrawn with automatic skeleton activation.

User explicitly requested root hold instead, plus a manual near-zero time toggle
at 1e-11 to try letting cape simulation update. Entry now activates root hold,
with no automatic skeleton or cape-transform replay. The hoverpack chat owns the
shared time-policy implementation and is adding set_near_zero(enabled); its
separate user-authorized hover fallback is 1e-14 for a live pack in a solo world.
Positive time must release root/pose leases and report owns_zero=false. This is
not yet a visually verified cape fix or a live-validated hoverpack crash fix.

The manual near-zero control is a transient checkbox immediately beside the
fixed Freeze/Resume Action toolbar button on every tab. It is enabled while
Freeze is active. Checked selects 1e-11; unchecked returns to the captured base
Freeze rate (0 normally, 1e-14 under the hover fallback). It shares the existing
time ownership and cleanup path. Closing Photo Mode restores normal time.
No setting file, scan, repeated setter or new keyboard blocker is added.
Toolbar pointer/layout tests pass from 640x480 through 4K; runtime fixtures verify
root release before positive time, no root rendering while near-zero runs,
reacquisition after toggling back to zero, and restoration on Photo Mode close.
Combined publication is coordinated by Fix new hoverpack crash after its fixtures.

The user separately confirmed hover Freeze/Resume works and explicitly requested
keeping automatic 1e-14. The launch was clarified as ragdoll Resume. No withdrawal
was loaded. Current generation is 2b2b5a3c39dd4cb895278eede6e65875 (22:02:14),
including the outlined toolbar checkbox; its 87 modules match current source
after the hover chat restored its source. The hover fallback stays; ragdoll
Resume launching and cape separation remain unresolved. Root-hold setters remain
gated to exact zero, so the positive-rate hover fallback does not acquire them.

## User video: remove cape writes and refresh from root hold

Reviewed the supplied 12.992-second HEVC clip
<temporary-video-directory>/3C8596CE4965DB20.mp4 at two frames per
second. The character is on the ship without an active hoverpack. The cape
collar/shape visibly changes after the body stops during Photo Mode. The toolbar
checkbox is unchecked in the visible menu. The running root hold still included
cape rigs and refreshed them after corrected body roots: fresh log counters show
51 cape updates in 80 renders, and 346 in 348 renders. This identifies an unwanted
forced cape path, but removal still requires visual confirmation.

At the user's request, root candidate acquisition now excludes non-Helldiver
rigs with cape1/cape2/cape3 before capturing a transform. The forced garment
World.update_unit loop is removed. Root fixtures assert that even a changed cape
root remains untouched while the body is corrected, and only the body is refreshed.

Published a scoped generation from the acknowledged 7c97029730fb46c8a6eb29ee3daf90f7
payload, replacing only src/windows_freeze_root_hold.lua. All 86 other modules
are byte-identical to that live generation, preserving concurrent Handycam work.
Evidence and guarded publication recipe: dist/review/windows-cape-no-refresh.
Video frames and overview: dist/review/windows-cape-video. Public archive unchanged.

## Cape removal accepted; investigate body snap at zero

User confirmed the delayed cape movement no longer happens after removing
forced cape refresh/root capture. They then reported a separate whole-body snap
when Smooth Freeze reaches zero. Fresh ramp receipts show 600.3-605.6 ms and
12 steps, so the requested descent is occurring; that does not prove endpoint
pose continuity.

The root baseline was previously acquired by the first update after exact zero.
A new candidate captures at most 32 qualified Helldiver roots immediately before
the zero setter, with a 128-entry/2-ms read budget. Only copied pose/scalar values
survive callbacks. The next root scan consumes that baseline only in the same
world and within one second. Resume/dispose clear it. Capes remain excluded.
Root acquisition logs initial drift from this pre-zero target. If the body still
snaps with an unchanged root, the remaining problem is in another pose layer;
this change must not be described as a confirmed native animation/ragdoll fix.

Fixtures simulate a first-zero displacement and prove that it cannot become
the saved target, plus retirement/expiry and the pre-zero ordering for immediate
and 600-ms Freeze. The combined isolated suite passes. A scoped payload replaces
only steam_runtime.lua and windows_freeze_root_hold.lua from the acknowledged
e4f7e8a2a6d04d2787697cd8a109f9cc generation; the other 85 modules are unchanged.
Evidence: dist/review/windows-root-before-zero. Visual result remains pending.

The user rejected the pre-zero-root candidate: still snapping/flipping. Fresh
root differences at acquisition were generally small, so late root acquisition
alone does not explain the large visible inversion.

Next isolation removes forced World.update_unit for qualified Helldivers after
root setters. Root compare/write and local readback remain; other eligible roots
keep their prior scene update. Cape roots/refresh remain excluded. The upstream
World reference documents this call as a forced scene-graph update after the main
world update, and notes that linked child units are not updated automatically:
https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_World.html
This is a hypothesis about the current pose discontinuity, not a proven native
writer attribution. Focused fixtures pass; the shared reload logs root corrections
with forced_scene_update=false. Visual result is pending in
`dist/review/windows-root-no-scene-update/LIVE.json`.

### 2026-10-26: rejected teleport and Smooth Freeze; pelvis-only trial
User reported outside-map teleport and crash on the teleport generation. Removed Smooth Freeze runtime/toolbar and disabled teleport even for legacy options; live generation 601c8b88c7bb44b3abf6e0b41016b724 acknowledged. Hoverpack module retained byte-for-byte. User authorized hips-only experiment. Generation 58f2451c35d64a3da2589b050d90607a changes only entry/root holder: known 107-node Helldiver hips node 10, parent 8; captured before zero, changed-only local-pose writes, no root/cape/teleport/forced scene refresh, no resume rewind. Full fixture receipt passes and all 87 payload modules compile; visual outcome pending. Installed archive unchanged.

Pelvis trial follow-up: parsed ten released episodes after ACK 58f2451c35d64a3da2589b050d90607a. All reported cape_updates=0; maximum recorded hold pass was 1 ms at the runtime timer resolution. One episode wrote on all 1780 renders, indicating continuing native overwrite, not proof of visual success. The known rig places hips (10) and spine1 (22) on separate branches under boss (8); hips-only cannot be assumed to control the entire skeleton. No Helldivers process was present during follow-up. Removed rejected teleport API branch entirely from source; cleanup fixtures pass and scoped offline 87-module payload is verified in windows-pelvis-hold/CLEANUP-VERIFIED.json. Cleanup is not requested live and installed archive is unchanged. Hoverpack bytes are preserved.

### World-space body anchor trial
User confirmed pelvis-only still spins. Generation 3e2710447a47493ebb564fa4ad7c35d0 replaces it with boss node 8 (parent 5), shared ancestor of hips and spine1. Capture world transform before zero; derive local from saved world * inverse(current parent world) each changed render. Root/cape setters, forced scene update and teleport remain absent. Qualified exact rig and parent identity; finite/invertible parent checks; changed-only comparison; no resume rewind. Fixtures include noncommuting rotations/translations, 50 rotating-parent corrections, steady idle, topology retirement and singular-parent refusal. All fixtures pass; all 87 modules compile; 85 unchanged modules including hover and cameras match the preceding pack. Runtime ACK at 23:13:52; visual acceptance pending. Earlier absence claim from sandbox Get-Process was wrong; fresh reload proves game running, CIM explicitly denies access.

### Post-render timing correction
User confirmed world-space boss hold still spins. Source comparison found steam_runtime held before saved game render while independent_runtime's original ragdoll hold runs after the saved callback. Moved root/optional skeleton hold to observed(), after a successful game callback; no new transform policy or cape correction. Focused fixtures cover native-overwrite ordering, failed-render skip, capture returns/cleanup, root/anchor/skeleton and startup. Whole suite encountered concurrent ADS fixture failures independent of this change, so no full-suite-green claim. Generation e037efa521e5413d806fbbffb886dd1d changes only steam_runtime; 86 modules including hover, camera and body-anchor code byte-identical to ac809b0b256744428dfeab49bbbd9ce2. Visual result pending. Continuous skeleton source also preserves transfer mode while original native ragdoll claims ignore; that separate difference is not changed by this timing experiment.

## Accepted result
User confirmed the latest body-skeleton transfer-ownership implementation works perfectly. It captures the body coherently before zero, claims ignore in the post-game-render hold, excludes cape1..cape8 and separate cape units, and restores original bone mode before Resume. Exact accepted generation retained in dist/review/windows-freeze-accepted/ACCEPTED.json. Earlier speculative root/hips/boss/flip/cape-placement corrections remain rejected. Preserve the accepted implementation and the hoverpack fallback; Smooth Freeze stays removed.

Acceptance clarification: user explicitly confirmed the cape attaches correctly, then reported rare remaining spinning while accepting that it works fine otherwise. Keep the exact accepted baseline; cape attachment is visually confirmed, but Freeze reliability is incomplete. Earlier PERFECT confirmation must not be interpreted as zero remaining intermittent cases. No new Freeze policy, reload or restart was issued.
