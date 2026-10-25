# Linux restoration on the recovered Steam branch

Baseline: local Windows `steam-lua51-port`, commit 60667f4, recovered read-only. Work continues on the same named local branch. The original 31 Lua 5.1 fixture groups are retained.

## Installed and observed

- Shared input explicit ACCESS_DENIED rollback for the two qualified R35 revisions. Unknown replies and accepted generations retain ownership. Engine-key fallback remains a limitation: it does not isolate gameplay keyboard actions.
- Deferred loader cleanup polling.
- Co-located ship cameras use a unique exact published pose to disambiguate; identical poses are still refused.
- Human confirmed menu opening, Tab, camera movement and mouse restoration. A subsequent report exposed stale visibility values and dynamic control references; those fixes are installed and human-confirmed.
- Registered controls now receive dynamic choices/callback/capability changes. Visibility callbacks invalidate cached options after values commit and before Core advances revision. Added path points become selected immediately.
- Independent Bloom/DoF flags, genuine local-player bookmarks, and normal Lua subject visibility adapter are installed.

The latest scoped menu deployment keeps the existing 29-module boundary. It does not activate the newer Director or selected-subject qualification changes.

## Source candidate

The branch also contains the original persistent relative Director model integrated with the verified local player backend. The R35 private-camera matrix roundtrip completed and destroyed its owned Unit/World; selected-subject admission is prepared using the original adapter and 213-pose bank. These changes are not yet deployed or visually accepted.

All 36 fixture groups and the source candidate byte/module audit pass. Model tests are distinct from game acceptance. Installed module audits and receipts are retained in the surrounding task workspace.

## Remaining

Resolve reported menu behavior before expanding the live boundary. Complete gameplay key isolation, remaining HUD/Handycam/player-follow/lens/scene adapters, mission attachment guards, capture acceptance and performance checks. AI stays disabled on non-FFI builds; full parity is not claimed.

Keyboard capture rejection was traced to the Proton game-root binding: canonical S: and Z: paths differ for the same Windows file ID. The helper binding is corrected to the actual S: path, preserving the existing identity guards. Activation and isolation acceptance require a game restart. Player-follow lighting is also restored in the source candidate using the original model and a verified local-player provider; not deployed yet.


## Current continuation — 2026-10-23 21:26

The maintained steam-lua51-port source now includes the installed 35-module boundary: current native font, required native keyboard capture, gameplay HUD ownership, Director/player-follow source, selected 213-pose bank, Proton PNG backend and restored original Handycam tracking. The build tool packages these modules explicitly and includes both license files.

Human acceptance has passed menu/camera/mouse, immediate visibility/list updates, keyboard isolation, pose Apply/Reset, gameplay HUD hide/restore and actual 3840×2160 PNG capture. Photo Mode/input/HUD cleanup was observed after capture. PNG is SDR; ship HUD and external FPS remain visible. Linux capture uses the separate per-user host worker; Windows retains its native backend.

Handycam is installed and fixture-tested but still awaits visual acceptance; the game exited before the requested check. Ragdoll integration and migrated guards remain staged outside this source boundary pending a fresh live qualification. Numeric lens/rendered-profile identification, scene effects, hoverpack and FFI AI remain incomplete. No full-parity or release claim is made. Historical sections above record earlier states and are superseded by this section.

## Current 38-module boundary (2026-10-23)

The maintained source matches the installed 38-module package. Manual native
focus distance/aperture is visually accepted, with exact sixteen-field restore
after Off/Close. The typed lens and gameplay HUD helpers support ordinary Lua
5.1 without FFI. Latest typed HUD and active ragdoll mission checks remain open.
Handycam head tracking, movement, visibility return, level roll and restoration
of placement roll are human accepted. Full parity remains in progress: hover,
FFI AI, scene effects/color, autofocus and remaining visual checks.

## Hover pause gate after airborne crash (2026-10-23)

The user reported the crash occurred with Photo Mode open while hovering.
The installed build now checks exact local backpack ownership before taking
zero-time ownership. With a Hover Pack, the camera/menu opens but Freeze Action
remains Off; a refused click immediately reflects that state. Live open/toggle/
close verified zero native zero-time requests and clean input restoration.
Full hover pause remains under development and is not enabled by this gate.

## Guarded hover preparation installed (2026-10-23 23:56 local)

The 42-module package now contains the recovered hover controller, an ordinary
Lua 5.1 backend, a genuine world-update observer and typed private-copy/height
operations. Preparation retains keyboard capture and waits for a completed
positive update before permitting zero time; release waits for a resumed update
before restoring an owned height and returning gameplay input. Unknown reads,
foreign values and retired entity generations remain guarded.

All 45 source fixture groups pass, including byte-backed ownership, update
ordering, delayed cleanup and native private-copy transaction rollback. Actual
installed module audit passes 42/42. Live batches 592–594 verified the equipped
inactive Hover Pack, advancing world clock, grounded zero-time hold and complete
close/input cleanup. The typed private copy preserved the original height 6.
Airborne pause/resume acceptance is pending; the earlier temporary gate section
records the superseded package. AI, scene/color and autofocus remain unfinished.

Airborne pause/close/re-hover was accepted by the user. Postflight batch 595
confirmed the same pack lifetime, restored private height 6 and advancing world
clock. Hover pause is now accepted; no crash attribution is inferred from this.

## Optional FFI AI restored (2026-10-24)

The 45-module package includes the migrated original AI backend/controller,
loaded only after explicit Passive or Dummy selection on a build providing CFFI
or LuaJIT FFI. Non-FFI builds leave these controls disabled; their other feature
modules remain ordinary Lua. Mode ownership persists after closing Photo Mode,
as in the recovered branch; Normal and addon disable restore owned changes.

All 49 fixture groups pass, including original byte-backed backend/controller,
player bit ownership and the lazy opt-in coordinator. Live batch 599 applied
Passive and returned to Normal with confirmed cleanup. Dummy/Normal lifecycle
batch 600 passed but affected zero entities, so enemy behavior acceptance is
still pending. Installed module audit passes 45/45. Scene effects/color,
autofocus and the remaining visual checks are still unfinished.

## Scene/depth restoration preview (2026-10-24)

Installed package: 49 Lua modules and three declared native libraries; actual
installed audit passes 49/49. The current source build passes 53 fixture groups.
The original scene overlay and DDS focus sampler now accept ordinary Lua guards
and a typed depth binder, so neither requires FFI. The renderer cache moved from
+468/+478 to +480/+490; current shader registration, resource identity, texture
formats, display separation and HDR/UI-white schema were qualified read-only.
Batch 613 bound verified depth to a temporary GUI material and destroyed it
without drawing. Batch 630 sampled a real depth surface at 4.991 metres and
removed its temporary DDS; the cache directory was confirmed empty afterward.

Effects has a session preview button for scene effects and autofocus. Live
menu-driven autofocus, scene color/effects, advanced shader DoF and visual
acceptance remain pending. Manual native DoF remains the previously accepted
mode. No public release or full-feature acceptance is claimed.

## Focus-loss persistence (2026-10-24)

Photo Mode now retains its window, camera mode and owned frozen-time state when
the game loses focus. It releases its input lease in the background and retries
reacquisition on return, waiting for a valid sample and priming key edges before
accepting input. Action shots also remain open. Session/world retirement and
native ownership errors still perform their normal cleanup. Regressions cover
held toggle keys across focus return and preserved paused subject sessions.

The 54-group build passes and the installed 49-module audit passes. The running
runtime/time coordinator received the same logic through a scoped closure patch
without closing the session or restarting the game; human Alt-Tab acceptance is
pending. The optional SDR shader asset candidate remains uninstalled, so the
reported dark advanced blur is not claimed fixed by this update.

## Current acceptance and SDR work (2026-10-24)

The user confirmed scene color/effects, autofocus and manual native DoF, and
clarified that advanced shader blur is correct in HDR. The outstanding blur
problem is SDR only. The additive SDR shader candidate uses the native SDR
compositor transform while preserving the accepted HDR path and blur sampling
source byte for byte. Its assets require startup registration and remain pending
installation and visual acceptance; the older pending sections above are history.

Selected-subject posing now reuses the maintained cape-placement solver. The
user accepted cape alignment, both menu/camera pointer confinement, and Alt-Tab
release/return. Photo Mode remains open across focus loss. The Subject panel no
longer requires a preview opt-in; Refresh discovers up to four subjects, with one
explicitly selected pose lease at a time.

Native Wayland screenshots use the exact game-window KWin handle; XWayland
retains its game-window backend. Neither backend falls back to desktop capture.
The Linux facade ignores stale acknowledgements from previous worker sessions
so the Photo UI stays hidden until the current job finishes. Saved-image UI
exclusion and HDR capture color fidelity still need visual acceptance.

The current Lua port has 50 declared modules and four typed native libraries.
All 56 isolated fixture groups pass, including cape attachment variants, pointer
confinement lifecycle and stale screenshot acknowledgements. AI factories remain
lazy and are admitted on CFFI/LuaJIT FFI builds only; all other feature factories
are retained on non-FFI builds. Enemy-behavior, Director/player-follow, lighting
and decorative-overlay visual acceptance remain outstanding.

### SDR candidate revision 2

The first additive SDR decoder was visually rejected and is superseded. A
matched, opaque scene-copy pass preserves native SDR color (median luminance
ratio 1.0), while the blur gather loses brightness. Revision 2 decodes four PQ
texels before bilinear interpolation instead of interpolating encoded PQ codes.
The isolated regression demonstrates a black/100-nit midpoint: 50 nits after
linear interpolation, versus 5.4542 nits when PQ codes are interpolated first.
The accepted HDR source/math and sampler remain unchanged. The compiled SDR
material ends in `da4d644cfee69b09` with template `49a73b4c`.

Revision 2 assets and runtime are installed and pass resource/module audits and
all 56 Lua fixture groups plus the SDR transfer check. Startup registration,
visual parity and GPU cost are pending the next game launch. Experimental UI
headroom changes were restored to the original 200 and are excluded from the
installed package; they did not fix the issue. General renderer color readback
remains excluded after its earlier crash.

### SDR normalization and decorative controls

Revision 2 registration passed, but its original 200-nit SDR normalization was
still visually rejected. True opaque scene-copy tests then isolated the carrier
normalization: 200 nits produced a median native-view luminance ratio of 0.5185;
48 nits produced 1.0, with a median absolute display-luminance error of 0.000834.
The qualified SDR renderer therefore uses a fixed 48-nit carrier; HDR continues
to use its verified `ui_brightness` setting. This changes only the overlay's
normalization, not the game's UI-brightness setting. It is installed and passes
the fixtures, but final blur appearance/performance acceptance remains pending.
Earlier identity tests using a saved exposure value of 0.001 were invalid because
the control quantized that value to zero; those results did not prove color parity.

All 40 retained decorative materials use the established `mods/dbf_hud` resource
namespace. The port's incorrect `mods/dbf_photo` lookup is fixed and live resource
inventory confirms 40/40 present. The extra preview switch is removed: selecting
an overlay activates it, and None disables it. Saved selections restore on entry.
Negative caches, capture acknowledgements and cleanup guards remain. The build
passes 57 groups, including an independent runtime-path/asset-manifest check.
Actual decorative draw acceptance still remains pending.

Light range remains an outstanding port issue: the Steam adapter still excludes
manual falloff setters after an earlier inconclusive getter roundtrip. It needs
an owned-light validation before restoration; other lighting controls remain
available. This is not covered by the non-FFI AI exception.


## WJ Oct24 12:31 — SDR accepted; light range restored

User confirmed reloaded SDR shader blur is looking good. Live batch761 confirms SDR v2 material da4d644cfee69b09, white48, shader DoF active (strength8), HDR false. HDR path remains unchanged. No separate numerical FPS acceptance claimed.

Director scratch-only native local-frame save/reload/relative recall passed batch762; actual camera and saved user presets untouched. Light range temporary unlit owned-unit probes763/765 cleaned up in same callback. Setter changes +0x34 to8/16/4 while falloff_end getter reads unrelated +0x80 and always returns0. Live code764 corroborates offsets; no raw memory writes. Restored ordinary Lua setters in steam_lighting and light_range routing/control capability in steam_runtime, adjusted bridge fixture. Existing photo_lights auto-falloff override remains required.

Candidate build passed57 groups, installed4files with backup war-journalist-lua51-20261024T163109Z; actual installed audit50/50 pass. Guarded close766 and enable767 succeeded. Light range visual validation pending; screenshots UI exclusion and decorative draw remain pending. Only AI gated by FFI, no extra CFFI binaries.


## WJ Oct24 — decorative material replacements prepared (not installed)
User confirmed light range works. Reported copper/prismatic/other overlays as colored squares. Inspection proves original HLSL deliberately quantizes panel coordinates and hashes square cells; not a missing texture. Added source generator generate_decorative_v2.py and eight continuous replacements under assets/decorative-v2 (copper, prismatic, hammered metal, leather, ceramic, gunmetal, brushed steel, frosted). Original frozen assets unchanged. build_decorative_v2.py compiles separate content-identified shader/material resources, preserves vertex bytes and native binding tail, adds registry entries and roundtrips archives, checks all294 prior nonregistry resources unchanged. Candidate dist/review/decorative-v2-r3 adds16 resources. Runtime composition shader_materials maps exact HLSL hashes; adapter uses these paths. All57 groups and separate SDR filtering check pass. Current installed runtime/assets NOT changed yet; needs game/Arsenal closure before native deployment using native-work/wj-feature-completion/install_decorative_v2_assets.cjs. Then install current-lua51 candidate, audit installed50/50, game restart and verify registration/draw. Visuals not yet live accepted. Failed early build folders preserved, compiler helper uses fixed entrypoint photo_resolved_v2, builder renames entrypoint only.


## WJ Oct24 12:36 — decorative replacements installed, restart pending
User closed game/Arsenal. Native installer install_decorative_v2_assets.cjs succeeded, backup decorative-v2-install-backup-2026-10-24T16-36-13.894Z; receipt DECORATIVE-V2-ASSET-INSTALL.json. New game corepatch3/sharedpatch97 triples. All other mod selections preserved. Deployed audit256core/55shared no mismatches (includes8new shader/material pairs, original resources retained). Lua candidate installed4files with backup war-journalist-lua51-20261024T163617Z, actual50/50 audit pass. Runtime now selects new eight materials. Restart/registration/visual validation pending; do not mark accepted.


Decorative replacement startup validation: live batch770 passed all8 shader-template registry checks, shader_library/material availability and runtime catalog identity checks. Visual draw still pending user test.


## WJ Oct24 12:39 — decorative v2 crashed; selection quarantined
User reports crash after restart/registration770; new dump dump-2026-10-24-12.37.05-91ac7e29-HELIOS-764.dmp. Read-only triage in native-work/wj-decorative-crash-20261024-1238: access violation0xc0000005 EXE+74526e, read0xe4b960080. Raw stack candidates are not an unwind. No proven root cause yet; registration success is NOT first-draw qualification. Do not automatically retry new material draws. Runtime composition.shader_materials cleared, original eight paths restored. Rebuilt57groups pass, installed3files backup war-journalist-lua51-20261024T163930Z, actual50/50 audit pass. New asset resources remain registered but no runtime selection refers to them; do not claim full asset rollback. SDR48 and light range unaffected. Pending user answer precisely which action crashed. Need investigate serialized GPU ABI/first draw before ever re-enabling new catalog paths.


## WJ Oct24 12:49 — opening crash narrowed; aligned candidate offline only
User says crash occurred opening Photo Mode. Saved Settings/dbf_freecam/dbf_freecam.ini shader41 (Prismatic), opacity34, scale1, so replacement attempted automatically on open. Current running restart detected; readonly778 captured fault code,780 confirms R inactive. Fault EXE+74526e dereferences renderer table using mapped resource index0x80000000 (RDX0x180000000); no proven binding-name/root cause. Found first build serialized pixel delta not preserving modulo16 (Prismatic -3444 mod16=12); previous working scene builder explicitly preserves this alignment. Added tools/decorative_shader_compiler.cc supporting DXBC private padding to required remainder and build_decorative_v2.py enforces old modulo16 and uses distinct :aligned-v2 content identities. Built dist/review/decorative-v2-aligned using pre-v2asset backup as base; all8 compiled and independent alignment-check.json proves vertex byte identity, tail length and modulo16. New candidate NOT installed or drawn. New installer install_decorative_aligned_assets.cjs ready, checks serialization_alignment16. Current composition.shader_materials remains EMPTY and installed originalpaths; DO NOT auto-reenable replacement on saved shader41/open. Need game/Arsenal closure then install corrected assets ONLY, restart registration, bounded explicit firstdraw while original runtime catalog remains quarantined. Existing failedv2 asset rows remain in lowerpatches but aligned registry built from original294excludes them. Do not claim alignment proven sole cause, visuals/fps still unverified.


## WJ Oct24 16:35 — decorative crash root cause identified; aligned candidate verified offline
Root cause (data-proven, not a guess): every DXBC payload in a shader library is followed by a native stage record = u32 stage id, then padding to 8 bytes (relative to resource start), then binding words beginning (0, 0x330). All 40 shipped overlays (record at offset%8==4, 0 pad), the scene template and live-qualified SDR v2 (offset%8==0, 4-byte pad) obey it. decorative-v2-r3 copied the pixel record verbatim after a pixel payload whose length changed by 4 mod 8 for oxidized_copper, prismatic, hammered_metal, leather, ceramic: their binding words were read 4 bytes shifted. Fault EXE+74526e consumes a 24-bit resource handle from those bindings (table+0x88 -> 0x80000000 unallocated), matching the crash. Evidence script native-work/wj-decorative-crash-20261024-1238/stage_alignment.py -> stage-alignment.json (r3: 5/8 misparse incl. Prismatic; aligned: 8/8 parse).
New tools/verify_decorative_candidate.py (offline, never deploys) on dist/review/decorative-v2-aligned PASSED: all prior resources byte-identical, only 16 reviewed additions, registry 324 prior + 8; per library payload offsets unchanged, only program/variant/pixel IDs + pixel length differ, vertex/pixel stage records same residue/pad and identical binding words, ISGN/OSGN identical (mask-only usage differs for copper which ignores carrier rgb), declarations identical, material differs only at +128 shader ref. Receipt DECORATIVE-VERIFY.json.
Runtime: composition.shader_materials now maps the eight aligned names (salted ':aligned-v2' content IDs, never r3 names). steam_overlay prefers a replacement only when can_get finds it, else keeps the shipped mapped material; fixture covers undeployed fallback and invalidation re-resolve. test_steam_port identity check updated. Build 57/57 groups, module audit 50/50; NOT installed yet.
Live read-only batch846 (game restarted 16:07): shipped true, r3 true (still in patch_3/97, unregistered after aligned deploy), aligned false, Photo inactive.
Next: game+Arsenal closed -> install_decorative_aligned_assets.cjs -> audit -> install Lua candidate + verify_installed_modules -> restart -> registration check BEFORE opening Photo Mode (saved shader41 Prismatic draws immediately) -> visual test. Note Arsenal per-mod deploy leaves earlier WJ patch versions (core patch_0..3, shared 95..97); a full Arsenal UI deploy would clean them.


## WJ Oct25 — LuaJIT boot fixes (branch claude/wj-luajit-fixes)
User report: DoF/scene shaders needed several open/close cycles; LLL/MCM could not open over Photo Mode; focus loss and player actions unpaused; menu closed without ESC/Photo key.
- DoF: the DoF flag opens before scene readiness, which now retries on DoF acknowledgement, the first frame and a bounded 0.25-2 s backoff; scene controls enable as soon as it is ready. The native lens backend loads at open, observes render packets only until its source is selected, then checks written fields at 1 Hz and reacquires after a foreign writer instead of latching. Live monitor batch1072 showed the game toggling `dof_enabled` itself; Bloom/DoF policies now keep the selection against Lua writers (foreign value becomes the close-time restore value) instead of revoking ownership. No new polling.
- Scene overlay verification is cached per resolution/HDR/material with 1 s revalidation (was bulk registry reads every frame); `rearm()` clears its failure latch.
- Freeze Action is held against a direct foreign `external_multiplier` write while our wrapper is the live binding and we are not resuming; successors and Slow Motion keep the old revoke rule.
- Insert/Delete were inside WJ's native keyboard capture mask, so LLL/MCM never saw their keys. WJ now reads their keys at open, yields input on press, opens them after the key is released, hides its panel and retakes input at 4 Hz once they close. Lease loss, sample failure and focus-mode failures yield instead of closing; optional-feature errors (overlay, grain, visibility, ragdoll, hover hold, time tick) report without closing. Return to player no longer closes/reopens.
- Subject: nearest Helldiver auto-selected on open; Reset runs recovery when refused; double-click picks any animated character (one-shot World.units scan, alive + scene-graph guards before transforms; live 10203 units, ~4.5 ms per pick). Non-Helldivers set focus distance and light subject distance only.
- Screenshot label follows `hdr_enabled`; Lua 5.1 validation placeholders removed; per-open MCM TEXT diagnostics and per-setting commit log lines removed.
Fixtures: 47 core rows pass in Lua 5.1 (new: steam_pick_tests, steam_handoff_runtime_tests, overlay verification caching); 12 DBF-MCM feature fixtures skipped because that checkout is an unmounted link. Candidate compiles in the running game (51 modules).
Review follow-up: an unexplained input-loss handoff still exits on ESC/Photo key and falls back to a full close after 5 s or 5 rapid losses; scene retries stay within one bounded budget and only explicit events (open, DoF acknowledgement) clear the overlay error latch; a scene failure re-requests native DoF; the depth resource is still fetched and identity-checked every frame (only registry/descriptor scans are cached); native lens reacquires at most 3 times per DoF activation; both holds reassert at most once per second; a parked overlay is cleared on open.


## WJ Oct25 — Lua 5.1 without FFI (branch claude/wj-lua51-no-ffi)
Based on claude/wj-luajit-fixes (7b63e7c): the installed 1.3.0-steam51-dev source plus the LuaJIT boot fixes above, which are VM-neutral and still run in Lua 5.1.
- FFI removed from the Lua 5.1 build: the cffi adapter (`cffi.lua`), the optional FFI AI (`steam_ai*.lua`) and the entry's cffi/ffi probe are gone. The Steam runtime passes `without_ai`, so the Enemy behavior rows (and the toolbar AI button) are not built; the original LuaJIT controller still gets them. `ai_behavior` moved from `defaults` to `ai_defaults`, read and reset only when its row exists. The leftover `PORT51={kind=type,number=tonumber}` shims in subject_backend, subject_visibility and vendor/font are plain `type`/`tonumber` again.
- `build_steam_candidate.py` packages 47 modules and refuses packaged Lua that imports cffi/ffi, calls `ffi.`, declares `cdef` or uses `PORT51`; PROVENANCE records `ffi: none`. The hd2_nativeinfo modules stay: they are ordinary Lua C modules, not FFI (they still export a `hd2_cffi_bootstrap_status` name from LLL's shared bootstrap header). Native Windows refuses custom DLLs (error 577), so those features remain Proton-only.
- `lll/` is a submodule of HWG90/LLL pinned at 173a374, R35-26088801-cffi-insert-fix.2: the last Lua 5.1 LLL, matching the installed boot source. `test_steam_port.py` checks `freecam/test_reference/input_service_r35.lua` against `lll/src/steam/input_service.lua` byte for byte.
Fixtures: 42 Lua 5.1 groups plus the asset closure and the LLL reference pass (the four AI groups were removed; steam_entry now fails on any cffi/ffi import and steam_runtime on any AI row); the 12 DBF-MCM feature fixtures are still skipped. Built package: dist/review/steam-lua51-noffi/package, 47 modules, module audit passes. Not installed; no live check yet.
- Own LLL id: the package is `dbf_freecam_lua51` ("War Journalist (Lua 5.1)") so it installs in its own Mods folder beside the FFI build `dbf_freecam`. LLL keys folder mods by folder name (enable flag, Settings folder, log), so it starts with fresh settings. The runtime keeps its internal `dbf_freecam` ids, so the single-owner guard still allows only one to run. Installed 2026-10-25 06:26 (58 files, audit 47/47, tree identical to the package); live check pending, under the LuaJIT boot.
- Arsenal archive build (for the Lua5.1 profile): `tools/build_steam_archive.py` packs the audited `dbf_freecam_lua51` candidate into one LLL archive addon, `mods/goose/war_journalist_lua51` (key 8d1bcdc06004d44b, Arsenal GUID 7020a1c8-…). It gives the modules the same `mod`/`require` scope LLL gives folder projects, keeps settings in `Settings/dbf_freecam_lua51`, and installs any missing bridge DLL into LLL's Native folder (content-addressed; a size mismatch is refused). Bridge paths now go through `host_native.library`, so folder installs still use `port51/`. LLL starts archive entries before folder mods, so in that profile this build owns Photo Mode and a folder War Journalist refuses as a second owner. Verified offline: modules and bridges read back exactly, the addon loads in Lua 5.1 and returns the LLL API 1 entry, installs missing bridges and refuses a differing one.


## WJ Oct25 — bundle for Boot Mod Loader (with assets)
The Arsenal bundle `War-Journalist-Lua51-1.3.0-steam51-dev` (GUID 7020a1c8-…) holds the archive addon and the War Journalist assets under one option, for Boot Mod Loader (Nexus 17754; deployed here as 0.11.0) on the Lua 5.1 game. Chef Shared Loader is not supported: it blocks native code and file renames.
- Under LLL the addon returns its LLL API 1 entry as before. Without LLL it hands the entry an engine host (`mod.host_loader`: `engine_input=true`, revision `boot-mod-loader-host.1`) and drives it from the game's `update`/`shutdown`, starting on the first update.
- `engine_input.lua` serves the shared input service v1 from the engine: while Photo Mode holds input the game's mouse focus is off, the cursor shows in the menu and hides for the camera (clipped), and the saved Window flags are restored on release. Cursor from `Mouse.axis('cursor')` (bottom-left, converted to top-left), motion from `Mouse.axis('mouse')` (y flipped to y-down), wheel ×120, five mouse buttons. No keyboard capture: keys also reach the game. Live check 2334 confirmed every one of these engine calls exists on build 26088801; the motion sign and focus-off motion are not yet seen in game.
- The engine host keeps engine keys (`require_keyboard=false`), admits Subject on the same build, and has no capture service (no screenshots) or LLL manager handoff.
- Folders: LLL's Native and Settings/dbf_freecam_lua51 when they exist, else the game's settings folder (%APPDATA%/Arrowhead/Helldivers2). Log: war_journalist_lua51.log there.
- Offline: the bundle starts, ticks and cleans up on a bare fake engine, passes the game's update results through, and still returns the LLL entry under LLL. Boot Mod Loader's archive reader (src/boot_mod_loader.lua) accepts the archive. Not yet run in game.
