# Handycam parallax investigation

The camera-translation candidate was rejected in game: it moved the camera away
from the user's chosen FPS POV. It and the Align FPS aim toggle were removed.
Generation `e4f7e8a2a6d04d2787697cd8a109f9cc` restored the original mount; the
user confirmed "POV restored". All 100 fixture groups passed and all 87 reload
modules matched source. No archive or shader installation was changed.

The correct proposed correction preserves the eye mount and projects the game's
actual aim point into that POV to locate a corrected reticle. Translation-only
parallax depends on target depth: direction alone cannot determine the screen
position for both near and far surfaces. Spread/drop/obstruction remain separate.

The native camera's non-echo numeric aim ray is retained from already-required
camera reads. The ADS handoff leaves the first native near frame untouched and
ignores obsolete own-output comparisons while yielded; its fixtures pass.
These changes do not expose the native weapon hit point.

A one-time read-only animation inventory tested 12 aim-distance candidate names
and found zero. The existing CPU depth path saves the full render surface and
has a bounded automatic capture budget; it is not an established per-frame aim
point provider. No guessed focus distance is presented as a native aim distance.

Crosshair parallax correction remains unimplemented pending a qualified aim
point/depth path. The rejected projection's 120-call live arithmetic sample
rounded to 0 ms at the clock resolution; that is not a zero-cost or accuracy
claim. Evidence is in `dist/review/handycam-parallax`.

ADS exit guard (2026-10-26): the first clearly far native camera sample now
requests Handycam reacquisition in the same render callback. Removed the 50 ms
return cadence and two-sample exit delay; entry still requires two near samples
and ignores our own output. The guard reuses existing camera/head values,
performs no engine calls, and stays idle outside native ADS. Camera ownership
validation and bounded publication retries remain mandatory; an unavailable or
foreign camera can still delay recovery. No absolute no-third-person guarantee
is established. Isolated Lua fixtures and exact offline payload comparison
passed. Deployed through private BML Lua reload ac809b0b256744428dfeab49bbbd9ce2;
runtime loaded and Photo Mode resumed at 2026-10-26 23:15:03. ADS transitions
and steady-state performance await in-game testing. Reload peak was 53 ms.

The user's subsequent ADS test showed persistent weapon/body clipping after
leaving ADS, including slow swaps. The initial log slice contained 66 exit
requests and 66 first-attempt reacquisitions, without recovery timeouts. These
messages establish accepted camera handoffs, not visually correct composition.
The logged recent-publication fallback does not verify the final rendered view.

A fixture reproduced a separate queued-transition race: clearing the event
window on the first handoff could miss a later native ADS transition from the
same input batch. Handoffs now retain the original bounded window (0.5 s / 128
samples), resetting only confirmation history. No handoff extends that budget.
Private diagnostics sample published/native/mount positions at 50/150/350 ms,
limited to 16 handoffs; they cancel on focus/menu suspension, fail closed on
invalid world/API, and stop on a 2 ms sample overrun. Stable state adds no
native reads. Fixture coverage includes rapid re-entry, echo rejection, expiry,
no idle diagnostic work and suspension. The complete isolated fixture runner
passed. This is not established as a fix for the user's clipping.

Scoped BML reload e81cba5c7e4d4d31a514bd0c6056838a loaded and resumed Photo Mode
at 2026-10-26 23:24:38 (41 ms peak reload step). Only steam_runtime.lua (trace
constructor argument) and windows_handycam_ads.lua changed from the previously
loaded generation; all 87 packaged modules compiled and the installed payload
matched exact verified bytes. Slow-swap clipping reproduction with this trace
remains pending. No game archives, shaders, settings or LLL module inventories
were installed or changed.

At the user's 23:27 reproduction, the bounded trace showed first-attempt
reacquisition and published_mount_error=0.0000 for the exit samples through
approximately 350 ms. Published view and requested eye mount were both about
0.14 m from the current head. Thus the sampled position was reclaimed; this
does not establish angular alignment or the weapon/body presentation state.
Diagnostics rounded sample timing to 0 ms; this is not a zero-cost claim.

Single-module scoped reload 015e69024d1f4a2298b0f0d502095bf5 added a published
forward-angle comparison using the same already-sampled matrix (no additional
engine query), retaining the same bounded trace budget. It loaded and resumed
at 2026-10-26 23:29:04 with 60 ms peak reload step. ADS and Handycam fixtures and
all 87 packaged Lua compilations passed, with exact installed payload bytes.
This is diagnostic only; clipping is still unresolved.

The user subsequently could not reproduce clipping on generation
015e69024d1f4a2298b0f0d502095bf5. Through 23:30:25, its log recorded 104 yields,
104 exit decisions and 104 successful reacquisitions, with no recovery timeout.
All 16 sampled exit views logged 0.0000 m position error and 0.0000 degree aim
error relative to the submitted mount. Diagnostic samples peaked at 1 ms at
available clock resolution; steady-state diagnostic reads stop at their budget.
This is a successful current test, not proof that intermittent clipping is
permanently resolved. The current generation was left loaded for normal play.

Persistence cleanup (2026-10-26): removed the temporary Handycam view/angle
trace and its engine/clock reads from source and startup. Immediate first-far
reclaim, retained bounded event windows, output-echo checks and camera ownership
safeguards are unchanged. The isolated Lua fixture runner passed. The existing
startup package was older (79 chunks); it now embeds the tested live graph's
87 chunks, with only the ADS trace and its constructor argument removed.
Fresh-VM packed startup without a development request, exact source/library
readback, reload lifecycle, archive roundtrip and ZIP-byte checks passed.

Installed private build 1.3.0-bml.1-portable.22.15-handycam.1 in the existing
Arsenal War Journalist store and game data/9ba626afa44a3aa3.patch_0. Updated the
package checksums/provenance and deployment snapshot, retained rollback copies,
and verified all other deployed archives unchanged. The actual installed
archive's 87-module graph exactly matches the trace-free session payload.
Clean reload 8c5fff3ab9f44f46b3cffc38b37456a4 loaded and Photo Mode resumed.
No scoped LLL folder modules were installed. An actual game restart was not
performed; persistence is verified in the startup archive and fresh-VM fixture,
not by claiming another live game launch. Receipts/package/rollback are under
dist/releases/handycam-ads-persistent/.
