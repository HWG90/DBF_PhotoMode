# Steam Lua 5.1 feature restoration

This is a development port, not feature parity or a public release candidate.
The legacy FFI bundle is excluded from its module graph. Do not enable an old
native backend simply because its controller passes a fixture.

| Feature | Current evidence | Remaining work |
| --- | --- | --- |
| Free camera transform, lens, roll, smoothing | Parent-Unit ABI and render-time application verified in game; ownership fixtures pass | Suppress gameplay movement without changing focus or locking the avatar pose |
| Menu, shared mouse, Tab, close/reopen | User verified; input trace ends with no owner or pending restoration | Verify each added feature's transitions |
| Composition and preferences | Current 21-module candidate; user verified grain/vignette/logo export plus CRT rendering, animation and lifecycle transitions | Full decorative catalog coverage; preview remains session opt-in |
| Cinema, paths and Director | User verified camera points, placed action shots, path action shots, following light and return refreeze; deployed shot callbacks measured | Player-relative Director and Handycam require native avatar context |
| Saved camera | Model passes actual Lua 5.1 fixtures | Authoritative player identity and retention context |
| Photo lights and saved rigs | User verified illumination, camera-follow, reopen restoration, preset/aim, saved-slot recall, marker drag and transitions | Player-follow and range API |
| Subject visibility, cape, poses | Pose model passes Lua 5.1 | Current native avatar identity, visibility and animation APIs |
| Freeze, slow motion and ragdoll guard | User verified true-zero toolbar Freeze/Resume, selected slow-motion rate, slider changes, ordinary exit preserving slow motion and gameplay Backslash toggle | Hover safety and captured-ragdoll adapters |
| Passive AI (Normal / Passive only) | Prior runtime's bit-25 no-aggro behavior was user-confirmed; current runtime adapter not restored | Current-build avatar identity and guarded character-flag access; Dummy deferred by user |
| Handycam, HUD and focus | Not restored | Native visibility, player basis, HUD and focus adapters |
| Screenshot | Repaired shared helper and 20-module Photo candidate installed/audited; four valid 4K SDR PNGs in one surviving game/helper session; button/Pause, reopen and controls verified | Native HUD hiding remains unported; HDR input remains unsupported |
| Bloom and scene color | Native Bloom OFF/ON, persistence and gameplay restoration verified; post-deployment callback sample recorded | Exposure, contrast and saturation; bounded component-baseline investigation ongoing |
| Scene effects and numeric DoF | Publicly disabled | Current shaders/backend plus visual validation |

The Lens correction is packaged, reviewed and installed. Focal
and tilt presets now expand into the same atomic settings transaction as their
numeric values; manual edits include Custom in that transaction. A failed save
publishes neither half. Pending keyboard roll and path lens values cannot
overwrite explicit changes during close callbacks. A successful lens edit
stops path preview at its current frame; a refused edit preserves playback.
Historically inconsistent saved shortcut labels display as Custom through a
cached projection, without writing files or preventing camera entry when the
settings directory is read-only. The focal-length text targets the registered
row and changes only when visible, applied FOV/gameplay status changes.

All 18 fixture groups pass for this candidate, including injected save failures,
mixed close/edit batches, stale settings, invalid explicit lens values and
unchanged-readout idle work. Independent read-only review found no remaining
material issues. Candidate/byte audit is under `package-lens-atomic`. After the
LLL dump call finished, a single-module update installed exact source bytes and
all 17 installed declarations/checksums passed. LLL acknowledged the complete
disable/load/ready sequence; saved settings were unchanged and the rollback
archive/hash are recorded in `LENS-DEPLOYMENT.json`. Live UI acceptance and
active callback measurement were subsequently completed. The user confirmed
the Lens controls and close/reopen test. A 15-second deployed menu sample
recorded 1740 render callbacks averaging 0.51149 ms / 3 ms worst and 1740 updates
averaging 0.25862 ms / 2 ms worst. The os.clock clock has millisecond resolution
and includes child work/instrumentation; this is not a game frame-time
percentile or a controlled comparison with the earlier Camera-tab sample. The
temporary timing probe was hash-removed. No new native player/input probe or
overlapping Photo reload was introduced.

`tools/test_steam_port.py` runs ten boundary/controller/view fixture groups
and eleven shared feature groups in actual Lua 5.1. Shared feature groups use
mock native adapters. They do not establish native behavior or performance.

Freeze Action now uses `Application.set_time_step_policy('external_multiplier',0)`
at the user's explicit request for true zero. The user qualified a solo,
normal-speed, grounded trial; the finite probe logged world dt exactly 0 and
restored multiplier 1 after ten wall seconds. The user confirmed the scene
stopped, camera remained responsive and resume avoided acceleration. A prior
0.0001 trial is not the installed freeze policy. Both probes were removed.

The installed controller exposes Freeze Action / Resume Action in the toolbar,
honors the saved entry preference and restores normal 1x on close, disable or
focus-loss cleanup. This 1x resume policy is explicit, not an exact native
snapshot of another time modifier. A scoped Lua setter wrapper observes foreign
multiplier changes, yields without overwriting them and is removed with compare
ownership. Unfrozen/closed state makes no native time reads or writes. Because
the API has no peer-join notification, active freeze checks the small peer list
at most once per wall second and thaws on session/world replacement or a joined
player. Refused pause never prevents Photo Mode from opening. Fixtures cover
these transitions and restoration refusal; native readback beyond world dt,
native writers bypassing Lua, hoverpack/ragdoll guards and slow-motion ownership
are not established. The user explicitly deferred hoverpack work.

Freeze installation: `dist/review/steam-lua51/hot-freeze-zero-v3` contains the
rollback and deployment receipt; all 17 installed modules pass the actual audit.
LLL acknowledged the normal reload. The user confirmed Freeze works exactly as
before after the Freeze-only control moved to the top toolbar. Subsequent cleanup
review added sparse/keyed-peer counting, joining-peer rejection, preservation of
ownership on refused foreign writes, one-second restoration retry backoff and
deduplicated notices. Isolated fixtures reproduce the refusal and 100-tick retry
cases. Those changes are installed under `hot-freeze-cleanup`; 17/17 installed
module checks pass and the normal loader reload is acknowledged.

Slow Motion shares that single time-policy owner. Freeze overlays exactly zero;
changing the selected rate or toggling Slow Motion while frozen performs no
native write. Resume and ordinary Photo exit use the latest selected rate, or
1x when Slow Motion is off. Disable, disposal, recovery and session/world loss
restore 1x only while still owned. Successful foreign Lua multiplier writes
revoke both features; refused writes retain cleanup ownership. Active modifier
validity checks remain bounded to once per wall second, with immediate checks
before explicit native rate changes. Pending light/camera cleanup cannot starve
those checks. Unchanged modifiers do not repeat native time writes.

The gameplay Backslash shortcut works while Photo Mode is closed. Key/text
editing suppresses activation, held keys toggle once and newly captured keys
remain suppressed until released. Fixtures cover these transitions, frozen-rate
edits, positive-rate foreign ownership, immediate solo revalidation and failed
full-cleanup retries. The user confirmed the menu/slider, Freeze/Resume, exit and
gameplay shortcut in the deployed session. The package and rollback are under
`package-slowmo` and `hot-slowmo`; the actual installed directory passed all 17
module declarations/checksums and the loader acknowledged the normal reload.

A subsequent bounded deployed CPU sample covered closed Photo Mode only:
2,269 update callbacks, 19 ms total, 0.00837 ms average and 1 ms worst at
`os.clock`'s millisecond resolution. This includes instrumentation and does not
establish active-camera cost, frame percentiles or the cost of active slow
motion. The completed observer was hash-checked and removed; its source and log
are retained as `slowmo-cpu-timing.lua` and `slowmo-cpu-timing.log`.

The retained view now accepts an explicit immutable command token from the
panel. Matching static submissions reuse their plane partition and native
primitives without rescanning geometry or rebuilding signatures/ID arrays.
Per-frame font/material binding and drawable/world/lifetime checks remain
active. Default mutable callers still use the full scalar diff; preview material
planes still refresh uniforms. Clear, font/world replacement, mutable draws and
failed allocations invalidate fast-path eligibility. The new view fixture and
menu fixture cover those boundaries; all 18 Lua 5.1 groups pass.

Both compatible one-module updates were installed through normal LLL reloads,
with rollback receipts under `hot-ui-token` and `hot-retained-view`; the final
installed directory passes all 17 module declarations/checksums. Vendored view
provenance matches source bytes. The user confirmed readable text, changing tabs,
camera motion and close/reopen behavior. A subsequent active-camera CPU sample
measured 1,559 calls per callback: render 0.28736 ms average / 2 ms worst; update
0.38165 ms average / 6 ms worst. The earlier camera/follow-light sample measured
render 1.11211 / 5 ms and update 0.34763 / 5 ms. These are bounded instrumented
samples at millisecond clock resolution, not a controlled FPS/frametime test.
Only draw code changed in the optimization; update behavior was unchanged.
Completed observers were hash-checked and removed. Logs and sources remain in
the ignored review directory; the failed extra diagnostic logger is not a valid
CPU sample.

Native bridge investigation remains separate: the exact SDK name-only plugin
was installed by MCM with a matching hash, but startup and the exact installed
relative-path load both left its expected name absent. Only the three stock
plugin names were returned. The candidate is unsigned and a stock plugin is
signed, but the bounded CodeIntegrity query had no recent events; signing alone
does not establish why the engine refused it. LLL owns further loader diagnosis;
no current player-flag or keyboard-suppression capability has been established.

Passive restoration is now scoped to Normal / Passive only, with Dummy deferred.
The legacy backend's game build is 6AB3B43F. The current on-disk game DLL is
SHA256 A457433F0EB766FBE15A6DE5A16F0FBBB1FD3C840C5607A5F0B2EBF53B112949,
PE timestamp 6AD02348. Its bytes at legacy RVAs 8873A0 and 885975 do not match
the old detector guards. This is on-disk evidence, not a decoded current native
layout or a claim that bit-25 semantics changed. No old address was used live.

Required Passive adapter contract: resolve an authoritative current local-avatar
identity and scene/session generation; verify solo authority; read current
character flags; set/restore bit 25 through a fresh identity check, preserving
every unrelated bit and preserving preexisting bit 25. Return an ownership token
only after readback, retain partial-write/restoration state on errors, and retire
tokens on confirmed avatar/session replacement. Prefer native lifecycle events
for respawn/mission changes; no repeated enemy scans or writes on unchanged state.
No installed Lua bridge currently provides this contract. `AI` exposes only
`find_intersecting_units`; generic Unit data/properties have not established
access to this game-specific character-manager row. The current Steam Lua VM
has no FFI. This is an unresolved backend requirement, not an enabled toggle.

The path-preview candidate adds a seventeenth declared module, `steam_path.lua`.
It copies at most 32 numeric points, previews smoothstep motion or timed cuts,
uses shortest yaw/roll arcs and interpolates FOV. It does no native discovery,
file writes or clock reads while idle. The active controller cancels on Tab,
revocation, close and edits; close clears points so no scene identity is guessed.
Lens values persist once when preview stops, never every playback frame.
This is explicitly labeled Preview camera path, not a completed action-shot
handoff. Package and controller tests passed. The cold installation receipt is
`dist/review/steam-lua51/deployment-path-preview-v3/DEPLOYMENT.json`; the actual
installed directory passed 17/17 module declarations and checksums. Saved settings
were unchanged during installation. The first report of no movement found persisted Lock camera ON;
the owning runtime accepted an explicit unlock, verified false afterward. Its
temporary recovery probe was removed. The user subsequently confirmed that
freecam movement and look respond again, then reported that camera points work.
That confirms basic point playback; the reply did not separately establish each
Smooth/Cut/Tab transition or deployed frametime cost.

The coordinated held-threshold trial did not suppress native movement: the user
still moved while the input service held 1.0 and recorded WASD. Exact restoration
to 0.5 was acknowledged by its owner. No keyboard-gate capability is consumed.
A finite read-only Network.object_info query resolved none of eight common type
names; its loose probe was removed. This excludes those names, not all schemas.

Lighting asset review: `tools/photo_light_assets.py --steam-review --output
<new-review-directory>` writes a single owned unit to `patch_1`, preserving
LLL's `patch_0`. It does not install it. Check existing archive ownership before
deployment; a compatible header is not startup or rendering proof.

An isolated native stock-light copy passed point/spot type, intensity, cone and
parented-transform checks, then was destroyed with its private world. Range
readback remained zero after setting 8 m, including after scene update. The
Steam bridge masks the falloff setters and keeps range controls disabled;
the compiled owned light range is retained. The isolated check itself was not
visual proof; the subsequent main-scene light test was user-confirmed.

The first lighting trial exposed persisted Clean View trapping the hidden
panel and a rolled camera frame with an unrolled right axis. H now clears both
hidden-panel flags when explicitly showing controls, and the light frame
computes both rolled axes. Both regressions have fixture coverage. The user
subsequently confirmed the panel, visible light, follow, removal and camera
transitions. Final allocation-only changes loaded through normal LLL reload;
all 14 installed module declarations/checksums pass the installed audit.

Light reopen restoration now uses the existing model's numeric retained setup.
The Steam bridge compares the actual world's level handles on explicit entry;
unchanged level sets preserve the light scene generation across camera sessions.
Missing/empty/oversized level metadata, changed worlds or replaced levels retire
the generation. No level reads occur while closed or on unchanged frames. The
user confirmed restoration across two reopens and the corrected Q/E direction;
fixtures assert Q decreases roll and E increases it.

A bounded deployed CPU sample (`lighting-cpu-timing.log`) measured the complete
Photo callbacks, including child work: camera render 0.968 ms average / 3 ms
worst; camera update 0.271 ms average / 2 ms worst; menu render 1.027 ms average /
3 ms worst; menu update 0.299 ms average / 6 ms worst. These use millisecond
`os.clock` resolution and include instrumentation. They do not isolate lighting
cost or establish frametime percentiles. An earlier wall-clock sample was
discarded because Application time is fixed within a frame.

A bounded, read-only script-data inspection found no local-player/owner/peer
metadata on the inspected head-bearing units or Application data. This does
not prove such metadata cannot exist elsewhere. No nearest-unit or skeletal
match was accepted as local-player ownership; the subject backend is pending.

The 15-module lighting-tools candidate adds preset replacement, aiming and five
persistent lighting slots. Without native focus, these use the explicit
Lighting subject distance point ahead of the camera, matching the old center
distance fallback rather than inventing a player identity. Existing preset
files are preserved; settings-backed storage lives under the owning mod's
config directory. Installation and package checks pass; live acceptance is
pending the next launch.

The next launch acknowledged the 15-module entry successfully. Preset/aim and
saved-slot gameplay acceptance remains pending the user's test.
The user subsequently confirmed preset, aim and saved-slot save/remove/recall.

Menu retention now reads only stored-value control types. Text and section IDs
are not settings in core; the old loop caused caught lookup errors every frame.
The cache fixture now refuses informational-value reads and checks that their
count stays zero. This change is installed but has not yet been timed live.
Lighting pages without a scene-gizmo controller now retain their unchanged draw
commands as well; previously the page name alone forced full recomposition.
The fixture checks command identity across unchanged Lighting frames. LLL
acknowledged the scoped menu update; deployed timing of this change is pending.

The marker candidate declares a sixteenth module (`photo_light_gizmos.lua`). It
projects the owned numeric light definitions, queues selection/moves for update,
honors panel/modal ownership, suppresses held clicks on activation and supports
Shift precision. Projection state has an explicit revision: unchanged markers
retain panel commands, changed positions/colors/selection invalidate them.
Both the projection/drag fixture and menu-retention fixture cover this boundary.
It is installed with all 16 module declarations/checksums verified; the game
was closed during installation. The user subsequently confirmed marker drag,
Shift precision, Tab to camera and close/reopen transitions. The existing placement distinction is unchanged:
Aim rotates the selected light; presets reposition the rig around the explicit
distance point ahead of the camera.

The shared API inventory contains no Player/Game/Hud/Stratagem table in either
the engine namespace or globals. A separate bounded read-only entity query
found 357 entities, but none tagged local_player, player, helldiver, character
or avatar. This rules out those inspected tags, not all possible metadata.
No ownership is inferred from an arbitrary entity, node name or proximity.

The later supplied executable-section dump did not establish that bridge.
The AI registration's captured reference leads to `find_intersecting_units`,
whose associated body is missing from the supplied code pages. The separate
game-specific character manager remains unresolved; absent strings in sparse
executable pages do not prove it is absent from the game.

Screenshot investigation found `Application.save_render_target` and
`Renderer.save_captured_frame` in the current Lua API inventory. The existing
back-buffer adapter uses two strings and performs native target/format guards
before capture because a missing render-target lookup can modify its registry.
Its guard depends on the prior build and FFI, so it was not reused or removed.
The supplied sparse dump did not establish the current wrapper or argument
checks. No unqualified capture call was made and Screenshot remains disabled.

Resumed investigation: UnitComponent enumeration over the live main world's
entities mapped zero units, so it did not establish a local-avatar identity.
An isolated owned light confirmed the documented lights/light/intensity path
returns 3. Both direct and property falloff-end setters still read back zero,
including while enabled. Each temporary unit/world was destroyed. Range stays
disabled; successful calls alone do not establish correct range behavior.
Evidence is retained under dist/review/steam-lua51/Photo*Properties*.log and
PhotoEntityUnits.log. The completed loose probe was removed, releasing the
shared probe path; no command mailbox or another mod's probe was modified.

Evidence and rollback receipts remain under `dist/review/steam-lua51`.
Installed module changes require matching declarations/checksums and an audit
against the actual installed directory. Never substitute package validation
for installed-byte verification or loader acknowledgement.

The time controller now owns true-zero Freeze and optional slow motion through
one engine-policy wrapper. Frozen speed edits change only the cached resume
rate; ordinary close thaws to that rate, while disable/recovery/focus/session
cleanup restores 1x. Successful foreign policy writes revoke our ownership.
The user confirmed Freeze, speed changes, Resume, exit and gameplay Backslash.

The retained view accepts an explicit immutable command token. It skips geometry
partition/signature work only for that contract; font atlas/material binding is
still performed every frame. Mutable callers and dynamic material previews keep
their existing updates. The user confirmed readable text, tabs and reopen.
The final 15-second active-camera sample (`active-camera-sample1456.log`) measured
1,742 calls: render 0.29793 ms average / 1 ms worst; update 0.20092 ms average /
3 ms worst. Millisecond-resolution os.clock includes child work and probe cost;
these values do not establish game frametime percentiles or isolate light cost.

The next action-shot candidate keeps the placed camera and lights alive while
releasing only Photo Mode's input lease. Its Photo Mode key returns to menu
placement and restores the actual pre-shot Freeze state; an already unfrozen
shot stays unfrozen. Slow motion is retained. Gameplay Tab does not recapture
input. A separate path action button plays the numeric camera path with gameplay
input released; the existing in-menu preview remains available. Foreign input
ownership is refused, and foreign time ownership cancels automatic refreezing.

Current-build read-only calibration confirmed row-vector matrix composition.
The camera's world pose is converted through its fresh parent transform before
the existing qualified Unit-parent local setters. An action shot rejects a
rendered pose matching neither the last submitted view nor the held component's
fresh world pose. No native matrices are retained across frames. Fixtures cover
translated/rotated/moving parents, publication order, foreign camera rejection
and local ownership cleanup. Live action-shot acceptance remains pending.

This does not establish Handycam, local-avatar identity, native menu/chat
notifications, player-follow lights, Subject, Passive AI, hover/ragdoll guards,
numeric DoF or screenshot parity. Those backends remain gated. The action-shot
session guard has no lifecycle notification in this API, so it performs one
constant-size identity check per second only while performing; it never scans
world units or samples the gameplay pointer during a shot.

The action-shot candidate is installed and LLL acknowledged its reload. All 17
actual module declarations/checksums pass. The first UI trial exposed inherited
disabled Director buttons and status references pointing to pre-registration
copies. Both were corrected in source and installed. The fixtures now activate
the registered Begin, Reposition, path action and gameplay-return buttons and
exercise the Photo-key return. All 18 fixture groups pass. Live action-shot
acceptance is pending: the game closed during a separate LLL logging trial
before that check completed. Photo's bounded timing probe was hash-removed.

The fresh session subsequently passed both user checks: placed action shots
hold the camera with gameplay input released and refreeze on Photo-key return;
path action shots play correctly with a following light and refreeze on return.
A bounded deployed sample recorded 576 shot callbacks: render 0.07639 ms average
/ 1 ms worst; update 0.10069 ms average / 2 ms worst. These millisecond-resolution
os.clock measurements include children/instrumentation and are not frame-time
percentiles. The one-shot timing probe was hash-removed after observation.

A separate external screenshot proof now uses Windows Graphics Capture for the
explicit game PID's unique visible HWND. It waits for a fresh FrameArrived event,
encodes PNG outside the game, and publishes through delete-on-close staging and
a non-replacing atomic rename. It neither loads code into the game nor changes
input/focus ownership. The actual output class passed success, collision,
exception and forced-termination cleanup checks; the build verifies source and
builder hashes before and after compilation.

The first live capture from PID 115600 produced a valid 3842x2162 RGBA PNG, with
the ship interior, Helldiver and gameplay HUD visibly present. The game remained
responsive. PNG chunk CRCs and decompressed scanline sizes pass; the image also
contains sRGB and gAMA chunks. This proves window acquisition, not accurate HDR
conversion, client-area cropping, clean Photo frames or a working Screenshot
button. Highlights appear clipped/posterized in the preview without a paired
reference, so color fidelity remains unqualified. The tool stays separate from
the installed mod and Screenshot remains gated. A future LLL-owned asynchronous
image service must keep frame wait/encoding off its synchronous exchange thread,
bind each job to the validated game/window, and perform no work without a job.
Proof source is `freecam/native/window_capture.cpp`, with the pinned build/run
wrapper `tools/capture_game_window.py`; receipts and the image are private under
`dist/review/window-capture-proof`.

The user subsequently confirmed that the captured ship image matches the game
view. This is visual acceptance of that frame, not measured HDR fidelity. A
separate client-crop revision now queries physical window/client/DWM bounds
under its own thread's restored DPI-awareness scope. It rejects ambiguous
origins, size changes, or an out-of-frame client region. An explicit metadata
inspection starts no WGC session. The matched display reports PQ/Rec2020 10-bit;
the prototype remains BGRA8 and does not claim HDR preservation.

The client revision passed 20 synthetic crop/DPI cases, eight malformed-CLI
checks, and success/collision/exception/forced-termination output contracts. An
independent source review found no blockers. Its one live capture from the same
PID/HWND is a valid 3840x2160 RGBA PNG cropped at (1,1) from the 3842x2162 window
frame. Root inspected the image, verified all PNG chunk CRCs and decoded row
sizes, and confirmed the same game process remained responsive. The original
proof binary and frozen sources are preserved separately. A labeled framing
comparison and receipts are under `dist/review/window-capture-client`.

Neither external proof is installed as a Photo module. Screenshot remains
disabled while the shared LLL helper's asynchronous capture API is coordinated;
no independent in-game pipe, synchronous PNG encode, or idle capture poll was
introduced.

Preparatory `steam_capture.lua` now coordinates an injected asynchronous job
adapter without any loader, GUI, filesystem or encoder calls. Its standalone
Lua 5.1 fixture passes: 12 consecutive distinct clean frames, copied request
identity, exact returned output identity, at most 10 status checks/second only
while a job is pending, application-clock timeout, scene/focus cancellation,
stale-result rejection and explicit failed-cancellation recovery. Idle and
blocked cleanup perform zero clock/backend calls. Fresh job tokens come from
the facade's pure session-qualified issuer, without coordinator token history
or a fixed job-count cap. Every accepted pending/terminal record must echo the
exact immutable job, output token and path. Cancellation restores the UI
immediately; pending retirement checks run for a bounded two-second grace,
then block new work with zero idle reads until an explicit cleanup retry.
The actual terminal outcome is retained if publication completed before
cancellation. This source is excluded from the installed 17-module graph.
Fixture evidence is `window-capture-client/COORDINATOR-TESTS.json`, not live
acceptance.

The source-only runtime integration now accepts an injected capture facade.
Its Screenshot button and existing Pause binding wait for 12 distinct successful
completed renders with the panel, legend, markers, Cinema notification and
composition grid hidden. Frame/logo preferences are retained without changing
saved settings or time policy. A completed-render baseline avoids an extra
frame for keyboard-triggered capture. Varargs and nil return values survive
the render wrapper; failed rendering never advances readiness. Cleanup remains
bounded after Photo Mode closes, and disable refuses unconfirmed retirement.
The capture coordinator, runtime and entry fixture groups bring the runner to
21 groups, using mock services only. A private candidate now declares 18
modules and gates capture on the documented shared service v1 capabilities
and dot-call methods; older loaders keep the camera working with Screenshot
disabled. The read-only capabilities proxy is covered by an entry fixture.
Actual installed entry/module declarations remain at the accepted 17-module
Lens build. This is not an installed Screenshot feature or proof of clean
captured pixels.

Independent review subsequently caught nonthrowing empty-draw refusals that
could leave retained UI visible. Capture now requires a positive cached owned
UI-plane release acknowledgement plus a non-refused composition draw before
counting a clean frame. Ordinary draw/suspend invalidates the acknowledgement;
unchanged hidden frames do not re-release planes. Refused/throwing release and
overlay draws are covered by the real menu and runtime fixtures. Explicit
cleanup retry also works while Photo Mode is closed/disabled; repeated ordinary
dispose retries never resend cancellation. The targeted independent re-review
found no remaining material issues.

The shared helper is SDR-only and refuses HDR/unknown outputs. A fresh elevated
metadata-only inspection of PID 141776 at 20:57:49 UTC confirms the current
3840x2160 client still maps to a PQ/Rec2020 10-bit output. No WGC session, pixel
capture, focus/input change or display-setting write occurred. The attested
diagnostic exited and the game remained responsive. Receipt is
`window-capture-client/LIVE-INSPECT-141776.json`. Supporting the current output
and the helper's final native qualification remain deployment gates; the
earlier accepted BGRA8 proof does not establish HDR correctness.

LLL's final SDR screenshot dependency is independently recorded in
`screenshot-final-v2/qualification.json` under its current-Steam review folder:
941 native checks and focused lifecycle/API/runtime suites pass, source hashes
are unchanged across qualification, and the portable package hashes to
`f78cc72d008db4fe450e32f5a6e95e17a36e183f2e4b69934a7c02ef24e4bf6d`.
This qualifies the candidate dependency, not installation or current-output
capture. The user then offered SDR and confirmed "SDR selected; game closed."
The coordinated cold-install window installs LLL first through its owner, then
Photo's 18-module candidate. Both installed boundaries, settings preservation,
postlaunch display metadata, clean capture and callback timing still require
their own evidence. HDR support remains unfinished; the isolated external HDR
investigation plan is retained without compiled or installed code.

Both cold installations subsequently completed while the game was closed.
LLL's final startup/helper hashes were independently read back. Photo's scoped
installer completed before the final actual-files audit: 18 declared modules,
18 actual modules, no errors. All three saved Photo settings files match their
immediate preinstall hashes. Photo rollback is
`capture-deployment/rollback-20261020-170815-bc6757f8.zip`, SHA256
`f2f299bcc6571057a36eca4961959fcf8069f3d7e4845756c131f9d390d4b84c`.
Detailed receipts are `capture-deployment/DEPLOYMENT.json` and
`CAPTURE-DEPLOYMENT.json`. Loader acknowledgement, fresh SDR inspection,
actual clean PNG, interaction recovery and deployed timing are still pending.

The restarted game PID 100128 and new shared helper PID 90172 were observed
responding; Photo's fresh log records loading/ready/loaded and its enabled
"Take screenshot (SDR)" control. The elevated metadata-only inspection still
reports Windows output as PQ/Rec2020 10-bit, despite the generic SDR selection
confirmation. No capture was started. The Windows display requirement was
clarified with the user; current-output support, PNG/recovery and deployed
timing gates remain open. Receipt is `window-capture-client/LIVE-INSPECT-100128.json`.

The user then confirmed Windows HDR off. A fresh metadata-only query on the
same game PID reports SDR/sRGB (color space 0, output precision 10-bit), which
passes the helper's SDR input gate. The first requested PNG was published at
17:13:41 local time: 3840x2160, valid chunk CRCs and decoded row sizes, SHA256
`36b2ada73b2b66237d31f844b13c4096fc500b5ecdbf750447af5a93f8a1bb3f`.
Visual inspection confirms the Photo panel/legend/markers are absent, while
native gameplay HUD remains visible through its still-unported backend.
No independent color-fidelity claim is made.

This live trial is **not accepted**. A dump for external helper PID 90172 was
created at 17:13:52, after publication. Photo subsequently logged
`LLL-Steam:227: Invalid argument`; that exact attested runtime line writes and
flushes the filesystem pipe, consistent with the exited helper. The helper
owner is investigating its dump and WGC cleanup. All further capture/timing
requests were stopped. The restarted game/helper (170408/111924) are responding;
the old game exit's cause/intent is not established by that observation. Native
player access remains independently unresolved. Failure and PNG evidence are
recorded in `CAPTURE-DEPLOYMENT.json` and `capture-first-png.json`.

The later native-access trials did not recover a player bridge. The temporary
Lua image-capture log records `loadlib_failed`, system error 577, before its
native entry point/worker ran. The elevated Windows dump receipt records one
MiniDumpWriteDump call with 0x410 rights, HRESULT 0x80070005 and zero output
bytes; the helper exited and the same game process remained responsive.
Read-only ProcessSignaturePolicy flags were zero, so that policy read does not
identify the origin of the earlier image rejection. No native capability was
enabled from these failed attempts.

A separate API review found no supported cross-Unit parent getter in the saved
current inventory. `Unit.scene_graph_parent` returns a node inside that Unit;
`World.link_unit`/`unlink_unit` mutate attachments. The exposed `Unit.is_child`
has no qualified signature here and was not called. A camera's containing Unit
therefore remains insufficient evidence for local-avatar identity. Subject,
Passive, Handycam and gameplay-input suppression still require a verified
current-build route. The existing Screenshot feature can use the separately
proven external WGC route; LLL owns the new shared-helper protocol work.

## Screenshot helper recovery candidate

The second live capture failed because the external helper retained a Windows
Graphics Capture factory after its worker COM apartment unloaded the provider
DLL. LLL owns that lifetime fix and transport-loss containment. The current
Photo instance refuses new capture admission through a reversible owned hold;
it has not been live-reloaded during this repair.

Photo's source candidate admits the exact development loader revisions
`R33-steam-screenshots-factoryfix-candidate` and `R34-steam-lua51-preview.1`, in addition to the v1
capture API capabilities. The old, missing and unknown revisions leave
Screenshot disabled while preserving the camera/menu fallback. This temporary
development gate is covered with read-only capability proxies. The R34 native
screenshot worker/job sources are unchanged from the prior repaired baseline
(`ad6ad6d`); final rebuilt helper checks and deployed acceptance remain required.

Exit lens persistence and diagnostic logging are now best effort. Save errors
cannot starve camera, time or input restoration. Genuine native and GUI
retirement failures still leave cleanup pending, block reopening and support
an explicit retry. The same pending sequence does not repeat failed save IO.
Fixtures cover refused/throwing stores, logging, native restores and both UI
finalizers; these are isolated contracts, not a live recovery claim.

The candidate also loads the existing curated logo assets once at entry with
their legacy picker indices and enables the portable static vignette controls.
Unchanged overlay commands use the retained immutable geometry path, including
after native GUI invalidation. Animated grain and decorative shader materials
remain pending. No additional periodic polling or idle asset work was added.

The frozen candidate and its source hashes are recorded in
`dist/review/steam-lua51/package-capture-factory-recovery/QUALIFICATION.json`.
All 22 actual Lua 5.1 fixture groups pass and the reconstructed package audits
20 declared modules. It is **not installed or live-accepted**. The shared
helper's full qualification must complete before a coordinated game-closed
install, actual installed-byte audit, owned hold removal and repeated capture
acceptance. Deployed performance remains unmeasured for these additions.

## Animated grain restoration

The subsequent `package-composition-grain` candidate preserves the frozen
recovery archive and adds animated grain without full-overlay regeneration.
Static framing, filters and vignette use depth 100, grain uses 101, and guides
and logos use 102. The legacy composition entry point retains its previous
geometry, ordering and fields; 450 comparisons against its prior source agree.

Only the 96 grain rectangles regenerate at the integer 12 Hz phase. Their
clock is the already-sampled active application time, so Freeze Action does
not stop the effect. Phase changes do not rebuild static geometry or write
settings. Grain is lazy, releases once when disabled, and adds no clock reads
or refresh work when disabled or closed. Clean View retains grain and finishing
effects; capture retains grain while hiding guides and controls. Both overlay
planes must acknowledge a clean frame before capture dispatch.

All 23 Lua 5.1 fixture groups pass, including all 4,096 valid grain phases,
retained static geometry across animation, and capture/cleanup transitions.
The package reconstructs and audits 20 modules. An independent source review
found no material issue. Native rendering, transitions and deployed performance
still require fresh live acceptance. The original recovery package remains available
as a separate frozen artifact.

## Current installed boundary and next shader prototype

The repaired LLL helper/startup and the 20-module grain candidate were installed
with the game closed. The actual installed module CLI audit passed 20/20, all
four immediately recorded user settings hashes were preserved, and the owned
temporary capture hold was hash-checked, archived and removed. Photo's rollback
archive and combined installed-byte receipt are under
`dist/review/steam-lua51/grain-deployment/`. Fresh loader acknowledgment and the
scoped live checks described below subsequently completed.

Subsequent source-only work is excluded from that frozen installed archive:
`steam_overlay.lua` is declared as module 21 in the next development candidate,
with explicit non-persistent activation for each runtime session. Saved shader
preferences cannot activate unqualified assets automatically. It uses private Photo material
names, a retained two-triangle decorative plane, lazy availability discovery,
static uniform caching and supplied application time for animation. Ordinary
view lifetime/material guards remain active. An explicit required material
cannot fall through to a solid rectangle. Partial allocation teardown retains
any survivor and blocks drawing until explicit GUI retirement succeeds.

The review-only asset builder produces 40 private material aliases under
`mods/dbf_photo/materials/mapped_*`, preserving material payloads and the 40
existing shader identities/CPU/GPU bytes. It neither changes frozen vendor
assets nor emits an installable patch or replacement `default_shaders` group.
Eight Python asset contracts and all 25 current Lua 5.1 fixture groups pass.
The integrated adapter accepts only positive draw acknowledgment for capture,
retains ownership after false/throwing whole-GUI retirement, and remembers an
ordinary draw refusal without repeating native work until explicit retry.
Independent review reproduced the earlier failures and verified their fixes.
These checks prove source/payload behavior only.

Bounded archive inspection subsequently resolved the bundled base
`ee6b1ba7e22d71ed` through its unique index mapping. Its native resource table
contains none of the 40 required custom shader libraries. The 77-entry stock
registry also contains none of those IDs and matches the vendored stock registry
SHA256 `f62a82b5fc095c42958a1f30fe6a1f7846107d197960b3e5beb72bda18b86040`.
Both installed native patches contain one resource each and no shader/group
rows. This does not qualify loose archive contents or engine override priority.
A material-only candidate is unsupported by this evidence; a complete registry
union and compiled libraries still require qualification before installation.
The review payload and source receipts are under
`dist/review/steam-lua51/private-overlay-materials/` and are not installable.

## Current SDR capture and portable composition acceptance

The fresh game/helper session (41220/63708) acknowledged
`R33-steam-screenshots-factoryfix-candidate`. Metadata-only output inspection
confirmed SDR/sRGB. Four 3840x2160 RGBA8 PNGs published in this session; all
chunk CRCs and decoded scanline sizes pass. The user verified button/Pause
captures, close/reopen and gameplay look recovery. The third PNG followed the
explicit reopen/effects check; the fourth followed the logo export check.
The fourth visibly contains the Arrowhead logo. The user's reference to the
crest is retained in the receipt without inferring that specific asset from
the saved pixels. Photo controls, legend and markers are absent from the
exports; native gameplay HUD remains visible through its unported backend.

The user confirmed grain/vignette looked correct and smooth and that the saved
image matched the game view. This is visual acceptance, not independent
colorimetry. The fixed helper remained responsive after the repeated captures.
`grain-deployment/REPEAT-CAPTURE.json` records hashes and the publication
chronology, including the initial two-file observation after a three-file
user report. The later third file resolves that gate prospectively.

A return-preserving observer finished after 15 active seconds and was
hash-removed. With grain enabled, 607 render callbacks averaged 1.26853 ms
and peaked at 4 ms; 607 update callbacks averaged 0.41845 ms and peaked at
4 ms, with no callback errors. These are `os.clock` intervals including child
work and instrumentation. Clock CPU semantics were not independently
calibrated, and the changing menu setup is not a controlled grain-on/off
comparison or a frame-time percentile. The helper's separate 120-second
process sample covered only the first two captures. No additional capture
timing is inferred from the later exports.

This accepts the installed SDR screenshot and portable composition scope.
Native player/input/visibility/AI/Handycam, decorative shader assets, scene
effects, numeric DoF and HDR remain separate unfinished work.

## Finite network schema metadata check

Four exact RPC names from the retained `.network_config` were queried through
the documented one-string `Network.message_info` API. All four calls returned
metadata: `rpc_set_player_info` has one argument, `rpc_sync_player_info` eight,
`rpc_from_host_respawn` six and `rpc_from_host_peer_added_to_session` one.
The tables describe positional types, bit widths and ranges, without configured
object field names or an authoritative Unit relationship. No message was sent
or intercepted, and no object/player state or callback was changed. The finite
probe completed, wrote one bounded log and was hash-removed. Evidence is under
`dist/review/steam-lua51/player-rpc-metadata/`. These signatures do not establish
the local-avatar provider required by the still-disabled native features.

## Decorative overlay cold-test candidate

`package-decorative-overlays-v1` contains a frozen 21-module candidate with
25 passing Lua 5.1 fixture groups. Its combined development archive is
SHA256 `d8f04bad9797327b35a7080ecfbb9a2917a46bfbaad992a73a29fe5e02924b65`.
It is not publicly qualified. After the user confirmed the game closed, the
21-module build and six native files were installed with guarded rollback.
The actual installed-module CLI audit passed 21/21; all four immediate settings
hashes were preserved, and the accepted loader/helper/light bytes were unchanged.
`overlay-deployment-v1/INSTALLED-VERIFIED.json` records these installed boundaries.
The fresh session (game 154492, helper 103896) subsequently acknowledged the
21-module Photo runtime on the unchanged qualified capture revision. The user
confirmed CRT scanlines render and animate with readable menu text. A bounded
15-second callback sample completed and was hash-removed: with grain and RGB
phosphor selected, 1,627 render calls averaged 1.27289 ms (worst 9 ms) and
1,627 update calls averaged 0.33067 ms (worst 6 ms), with zero callback errors.
These os.clock intervals include callback children and instrumentation; they
are not isolated overlay cost, frame percentiles or a controlled comparison.
The user subsequently verified animation OFF/ON, close/reopen, selecting None,
and gameplay-look recovery. Other catalog assets have not all been visually
qualified. This development preview remains an explicit session opt-in.

The separate `install_steam_overlay_assets.py` tool builds the complete 117-ID
registry and 40 compiled libraries in a new `ee6b1ba7e22d71ed.patch_0`, with
40 private Photo material aliases in `9ba626afa44a3aa3.patch_2`. It preserves
the accepted loader/light patches, refuses occupied targets or competing
shader providers, and records staged-file identity plus hashes for guarded
rollback. All 15 installer tests pass against temporary filesystems, including
refused publication, incomplete staging, changed ownership and rollback.

A fresh read-only qualification of the actual game data verified the complete
77-stock-library closure and exact base table/registry fingerprints. It read
58 selected compressed chunks (6,471,086 compressed bytes; 14,613,770 inflated),
without GPU payload reads or game-process access. Installation revalidates
this boundary. CRT visual acceptance and the callback sample qualify only
the scope above; full catalog coverage remains separate.

The finite remaining-color audit identified one avatar-independent candidate:
the legacy Bloom mapping uses the currently exposed `Application.render_setting`
and `set_render_setting` functions with `bloom_enabled`. Its legacy setter used
serialized `true`/`false` strings and asynchronous acknowledgement. Current
binding/key/type and ownership restoration remain unqualified. The source-only
`bloom-setting-read.lua` check prepares exactly one getter call, with no setter,
`render_config` or callback replacement; its actual Lua 5.1 protocol selftest
passes. It has not run in game or changed the frozen 21-module package.
Exposure/contrast/saturation still need the scene-color backend; numeric focus
and aperture need the native lens/depth backend. Captured API names alone do
not qualify either route, and no current shading-environment getter has been
established.

The finite Bloom getter subsequently ran once in the current game and returned
a successful boolean `false` baseline. The loader acknowledged the isolated
probe; it finished and was hash-removed. This qualifies the current getter/key
and return type only. No setter, rendering change or preference write occurred.
Evidence is `dist/review/steam-lua51/bloom-setting-read/DEPLOYMENT.json` and its
archived log. Setter acknowledgement, ownership-safe restoration and visible
Bloom behavior are still unqualified.

The subsequent finite Bloom setter trial acknowledged the opposite boolean
value and the original false baseline after one serialized submission each.
It observed no foreign Lua writes, restored its Lua observer, and was
hash-removed. The game remained responsive. This qualifies native toggle and
restore acknowledgement; the visible Bloom effect and real control integration
are still pending. Evidence is `bloom-setting-trial/DEPLOYMENT.json`.

## Native Bloom control restored

The next 21-module candidate passed all 27 Lua 5.1 fixture groups and independent
ownership/disposal/recovery/slow-motion regressions. Its package SHA256 is
`ccb6edc726701752fb9c7e2e6b41aecbe3a2e8064e9b6129628acda146de1534`. The scoped hot update changed
only `steam_runtime.lua` plus provenance/checksums; entry and module graph are
unchanged. The actual installed-module CLI audit passed 21/21, and LLL
acknowledged disable/load in game 154492. Existing native overlay/light/loader
assets and capture helper hashes were preserved. Receipts and rollback are
under `dist/review/steam-lua51/bloom-deployment-v1/`.

The user verified Bloom visibly changes the glow, the saved selection returns
on reopen, and gameplay look works after exit. Bloom applies on explicit
entry/change, coalesces pending choices, and polls acknowledgement at most
10 Hz for two seconds; settled/blocked state does no native/clock work.
Camera/input/UI retirement precedes pending Bloom cleanup, and the recovery
shortcut can make an explicit guarded cleanup retry. The Lua writer observer
preserves successor bindings and foreign writes; native ABA cannot be detected.
Exposure, contrast, saturation and numeric DoF remain unported/gated.

The post-deployment 15.005334-second sample covered 1,713 callbacks each with
Bloom ON reported by the user, the visible menu and grain. Render averaged
0.47169 ms (worst 3 ms); update averaged 0.34676 ms (worst 10 ms), zero errors.
The observer restored callbacks and was hash-removed. These os.clock totals
include child work and instrumentation, not isolated Bloom cost or frame-time
percentiles; different menu/preview state prevents an overlay-on/off comparison.

## Further read-only API qualification

The first bounded exposure-component pass preflighted all required exports and
validated 353 entities. It safely refused a signed component identifier before
any object write: 16 native calls, at most five in one update. A second
diagnostic pass preserved the same calls and observed the exact finite integer
`-140308449` from `RenderDataComponent.instances`. The original nonnegative
component guard was stricter than the documented integer API. Both probes
completed and were hash-removed; no exposure provider was qualified. A reviewed
clone accepts signed-32 component IDs unchanged, while entity array indices
remain positive. Its finite live pass scanned ten entities and sixteen
instances in 91 native calls, with at most five per update. It stopped when an
integer component ID repeated across entities; no exposure mapping matched in
that prefix. The reader was hash-removed. Repeated IDs do not qualify their
scope or establish the current fork's property-call signature. Further live
property reads wait for exact binding evidence; no object setter ran.

A separate pure-Lua namespace inventory called no engine functions and was
hash-removed. Current Input exports only `event_queue`; Window exports focus,
foreground, mouse-focus and OS keystroke functions. Keyboard/Mouse expose
state reads and deadzone/rumble controls, with no keyboard ownership setter in
these direct member tables. Names do not establish call semantics. The exact
report is `input-namespace-read/PhotoInputNamespaceRead.log` and was shared with
LLL. No focus takeover or input write was performed. The user's requirement
that a deployed route keep the game focused is preserved.

A separate selected-subject rig reader is source-only and passes actual Lua
5.1 fixtures plus independent review. It queries the exact stock avatar
resource and validates its 107-node topology and original bone mode in bounded
batches. It retains only the resource hex string across frames, recreating
temporary IdString64 values inside each batch. It neither claims local-player
identity nor changes poses, visibility or cape state. Installation was refused
when the expected game process had already closed; no probe was armed. Numeric
local-transform qualification is a separate next step.

The separate source-only P/Q/S reader passes 9,696 Lua 5.1 assertions and root
review. It validates the complete rig before reading one body bone per update,
rechecks current lifetime/resource/topology in the same callback, and retains
only finite scalar summaries. Its four-subject fixture peaks at 21 native
calls per update with a hard ceiling of 24 and a 20-second deadline. It is not
installed, and its sequential samples are not a coherent pose snapshot or a
qualified restoration backend. Evidence is under `selected-subject-pqs-read/`.

Offline exact-build checks of the current EXE and both DLLs did not recover the
RenderDataComponent property argument decoder. The EXE contains its namespace
name and a C++ source path; those are not a Lua function signature. No new
process acquisition or target execution was used. The exact three-versus-four
argument property ABI remains unresolved, and no guard was relaxed.

## Shared view allocation reduction

The next 21-module candidate changes only `vendor/view.lua` plus package
provenance/checksums. It hoists the per-draw GUI-routing closure and vector-field
keys into instance scope and allocates diagnostic arrays only when reporting.
Font binding, material acquisition, native call order and owned cleanup are
unchanged. Across 10,000 unchanged animated draws in actual Lua 5.1 with
allocation-free native doubles, bookkeeping falls from 632.0066 to 328.0066
Lua bytes per draw (48.1%). Native counts and the two retained triangles match.
This measures Lua allocation, not deployed frame-time improvement.

All 27 fixture groups and independent focused review pass. Package SHA256 is
`87d5a710527a62ae0fa7d6f9dff7d7314875db89b906fdb85de4c4d1bf7e3bf6`.
With the game closed, the scoped update installed the single Lua change;
the mandatory actual installed audit passed 21/21 and sixteen other recorded
boundaries matched, including runtime, entry, manifest, native assets and helper.
The rollback and receipt are under `view-allocation-deployment-v1/`. The fresh
game 79424 launch acknowledged Photo Mode with these installed bytes. Visual
transitions and deployed timing of this allocation change remain pending.
No subject/exposure diagnostic probe is installed or armed.

## Selected-subject pose port qualification

In game 79424, the finite rig reader found one exact stock avatar and validated
all 107 authored parent/name mappings. Its original bone mode was
`position_and_rotation`. The stricter numeric reader stopped before sampling
because the root-parent getter returned zero Lua values. A shape-only pass
confirmed exactly zero values at node 1; the corrected reader normalizes that
case only for authored root 1 with expected parent 0. Other return-count and
topology guards remain unchanged.

The corrected pass validated all 107 nodes and read all 85 body nodes' local
P/Q/S through the current engine bindings. It made 2,302 native calls, at most
21 per update; maximum quaternion norm-squared error was 1.63680917e-7 and
unit-scale error was 5.96046448e-8. All readers completed and were hash-removed.
Receipts are under `selected-subject-rig-read/`, `selected-subject-pqs-read/`,
`selected-subject-pqs-shape-read/` and `selected-subject-pqs-root-read/`.
These sequential reads establish getter feasibility, not a coherent baseline,
setter roundtrip, local-player authority, cape ownership or pose restoration.

The source-only lazy bank retains every one of the 213 catalog entries and
181,050 authored P/Q/S scalars exactly, including signed zero. It interns 7,491
of 18,105 bone rows and decodes one fresh selected frame without retaining a
decoded-pose cache. Actual Lua 5.1 observations show 1,546.7 KiB retained load
heap versus 14,211.1 KiB for the original nested asset, and about 12 ms versus
219 ms load CPU. One selected frame is approximately 50 KiB and 1 ms. These
are offline observations, not deployed frame-time claims. Deterministic
regeneration, corruption refusal and full numeric/metadata parity passed
independent review. Bank SHA256 is
`0834160c75f2c496d1780ea2c5fe45524995de832c7e33da24863c1363eb801f`.

The separate source-only controller uses explicit photographic-subject
selection and an injected adapter. It captures one coherent numeric baseline,
applies only changed requested bones, preserves scene anchors and the original
root8 for upper-body poses, and retains exact owned state for cleanup. It has
no tick method or automatic discovery/reapply loop. The native adapter now has
a separate unqualified preview factory with per-mutation authorization,
constructor-canonical numeric comparisons and guarded partial-write recovery.
Its finite writer trial is being prepared in review artifacts; no pose writer
has been installed or armed. Live setter/commit/restoration qualification,
runtime UI, module declarations and live pose behavior remain unfinished; the
current installed graph is still 21 modules.

The isolated Lua 5.1 runner now includes the bank, selected-subject controller
and native-adapter fixtures (30 groups total). The menu also accepts an explicit
`choices_revision` publisher promise: fixed catalogs observe only revision,
array identity and count each frame. Existing mutable/recreated lists retain
content-based observation. Instrumented real-menu tests cover all 213 labels,
zero label enumeration on unchanged draws and revision/replacement/removal
transitions. These menu changes are source-only.

## R34 shared keyboard capture candidate

The 21-module Photo candidate opts into LLL's owner-aware keyboard capture when
the service advertises it. It consumes the published immutable 32-byte mask and
one combined pointer/physical-key snapshot per frame. ARMING keeps a neutral
lease, ACTIVE requires a fixed positive u32 generation, and revoked/malformed
input never falls back to gameplay key reads. Optional `set_mode` retains the
same lease between menu and freecam. False, nil and throwing cleanup responses
retain ownership for explicit retry. Older mouse-only brokers retain their
existing path.

All 30 isolated Lua 5.1 fixture groups and the packaged byte/module audit pass.
The package hash is
`348959e7e7b5c3996da658e6f219a95fe4f537c19474a300abfcdce7632c6551`.
During the joint closed-game window, installation and the mandatory actual
installed CLI audit passed 21/21. Exactly five expected package files changed;
external settings and nine recorded native Photo asset boundaries matched.
The rollback archive and receipts are under `r34-keyboard-deployment-v1/`.
The installed input hash is
`c33a42d239966e1636aeb09c09196019068b939afeeb7c6aab000550950d0393`.
The menu revision cache is now installed too. Fresh game 9440, started at
21:08:55 local on October 20, acknowledged Photo loaded in the R34 startup at
21:09:16. Movement isolation and deployed transition/performance acceptance
remain pending with the shared-input test owner.
No subject pose writer or diagnostic probe was installed.

### October 20 follow-up

The human R34 input test confirmed freecam movement isolation, menu/freecam
switching, normal gameplay input after close, and Alt-Tab typing. The installed
graph remains 21 modules. The 24-module Subject integration is source-only;
its R34 development admission requires explicit session preview and selection.
The integration includes cleanup before leaving owned true-zero time.

The finite selected-hand diagnostic reached position apply/reset, then stopped
at the rotation-stage all-P/Q/S exact readback comparison after about 67 ms.
This explains why its pause and tiny motion were not visible. It did not
qualify a pose. Its automatic mode/time cleanup and later explicit recovery
were attempted, but the terminal observation still reports a pending body
lease. The existing log does not separately acknowledge mode/time cleanup.
The retained diagnostic is inert; its owner must remain until successful
cleanup or definitive unit/world/session retirement. A loader `loaded` line
does not establish successful recovery. The next investigation uses an owned
disposable camera unit in a private world to inspect transform representation
without another live-character write.

Both private-camera checks completed in game 9440 and acknowledged destruction
of their owned Unit and World. The rotation check reproduced the constructor
versus matrix-decomposition discrepancy, including further drift on repeated
conversion. The replacement check observed the current 12-scalar affine ABI,
rehydrated a rotated/translated/nonunit-scaled target exactly, and verified
exact target and original matrix storage immediately and after `update_unit`.
Its report is retained under `private-transform-check/matrix-roundtrip/`;
SHA256 is `eafd7228e5bc84cb59efc42a609faf155e0b8a8f0ef4f4f55b39f0dadf9a4bb2`.
Both private diagnostic source files were hash-removed after cleanup. Their
terminal callbacks can remain in the running loader until lifecycle retirement
or restart. These checks prove the shared Unit matrix boundary, not the visual
result of a selected Helldiver pose. The source pose path now carries original
numeric matrices through Apply/Reset instead of rebuilding getter quaternions.
