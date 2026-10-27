# Explicit Windows unit physics off/on trial

The mode-only trial did not stop root rotation. The earlier paired cape capture
also shows that the cape root and cape1/2/3 world matrices matched the body's
corresponding matrices both before and after root correction. There was no
matrix mismatch in those eight comparisons. This narrows the problem beyond a
missing scene-graph refresh, but it does not measure cloth vertices or prove
which subsystem writes the root. See `CAPE-TRANSFORM-EVIDENCE.json` in
`dist/review/windows-freeze-physics-trial`.

Offline inspection found no literal disable_physics/enable_physics names in
the current executable, game.dll or runtime.dll. The executable text section
has entropy approximately 8.0 and runtime.dll uses packer sections. These files
do not provide an immediately readable call chain. No unpacking, process hook,
debug attachment, executable modification, or retry of denied process reads
was performed. REA's inventory was read; no binary analysis session was opened.

The running Lua namespace does expose Unit.disable_physics and
Unit.enable_physics. The [upstream Unit reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Unit.html)
documents those as unit-wide disable and enable calls. There is no observed
physics-enabled getter in this Lua environment. Consequently this candidate
does **not** claim to restore arbitrary prior per-actor flags. It is an explicit
off/on experiment, with the requested final state being physics enabled on the
same surviving unit. It is not wired into ordinary Freeze.

The private `freeze-physics-v1` marker enables a Subject test button for at most
two trials. The button requires a selected Helldiver, true-zero time, no held
pose, and Handycam ended. Before issuing the disable call, it waits 0.25 seconds
and requires at least five degrees of observed root rotation. That check expires
after one second. It then samples root rotation at 0.5, 2 and 4 seconds, and
calls enable after six seconds. Closing, unfreezing, losing focus or changing
subject also ends the trial. No root, bone, cloth or velocity setter is used.

Session, main world, Unit lifetime, resource and 107-node rig guard each native
operation. Dead or retired identities are not written. Partially applied
disable calls retain enable responsibility. Failed enable calls retain a
cleanup barrier before time can resume; unchanged pending ticks do not retry
native calls. Only scalar quaternions and generation-checked handles survive
callbacks; resource IDs are reconstructed within each operation.

All 92 fixture groups pass, including actual UI-button admission, cleanup
before nonzero time, partial native failures, expired checks, retired identities
and zero native work between scheduled samples. All 83 payload modules match
source. Generation `2310cbdeee2346148690ce89a8c7576d` loaded at 19:12:21 without
restarting the game. Visual results and live operation timings are pending.
No portable archive containing this physics test has been installed or staged.

## Observed result

The first trial started at 19:21:52. After observing 28.253 degrees of rotation,
the disable call completed at 19:21:53. Its first half-second sample still
measured 94.673 degrees of root rotation. Closing Photo Mode ended the trial
early and the enable call completed in the same second; maximum measured step
was 1 ms. This is evidence that this call alone did not stop the selected root,
not proof of which subsystem continued writing it or that physics stayed
disabled (there is no getter).

The second precheck at 19:22:00 observed less than five degrees and made no
physics write. The original attempt counter nevertheless consumed that test,
so subsequent clicks were exhausted. The source now counts only actual
disable attempts. User feedback: "nothing". Evidence is saved in
`dist/review/windows-freeze-physics-trial/OBSERVED.json` and `observed.log`.

## Cleanup retry correction (offline)

The first live generation guarded pending `tick` calls, but ordinary close and
reload cleanup could call `release` repeatedly after an enable failure. The
follow-up candidate also makes those lifecycle calls idle once cleanup fails.
An explicit recovery/subject action may retry; disposal gets one retry for its
entire retirement attempt, rather than one per cleanup poll. Pending cleanup
continues to prevent nonzero time.

The regression fixture exercises 100 automatic closes and 100 disposal calls
after a failed enable, verifies no repeated native attempts, and then verifies
explicit recovery. All 92 fixture groups pass. The offline candidate is in
`dist/review/windows-freeze-physics-cleanup`; it has not replaced the live
physics trial while that visual test remains pending.
