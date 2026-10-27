# Frozen root source capture

The physics off/on trial did not stop root rotation. The earlier bone-mode
trial also failed visually. Neither result proves the responsible writer.

The existing read-only Freeze observer now records three extra matrices for
qualified 107-node Helldivers in the priority lane: actual world root,
animation-requested root and the most recent root delta. It also records world
delta time. These are read only at its existing baseline and two sample points;
finished captures stay idle. The additional getters are used only when the
observed animation root mode is `ignore`, with a fresh resource check. Matrix
components are copied before the callback ends. Missing or refused getters are
reported independently and do not discard the established root/bone trace.

The [upstream Unit reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Unit.html)
documents `animation_wanted_root_pose(unit)` for ignore mode and
`delta_pose(unit, node)` as a frame delta. Current-game equivalence remains to
be checked by this capture; a matching wanted/actual matrix alone would be a
correlation, not proof of a particular writer.

The candidate also includes the pending cleanup retry correction and bounded
sparse outfit inventory fix. No root, bone, physics or visibility state is
changed by the observer. The failed physics experiment is not rearmed.
Live generation and evidence are recorded in
`dist/review/windows-freeze-root-source` after verification and reload.

The first live capture at 19:27:54-55 recorded zero world delta at the two
settled samples, while the reported root delta matrix represented about
152.48 and 152.47 degrees. Wanted and actual matrices matched exactly at those
two points. The baseline was still at nonzero engine delta (0.01015 seconds),
so it must not be described as a settled frozen sample. The capture completed
with zero errors and a maximum step of 2 ms. This suggests repeated root motion
but does not establish it from two separated samples.

The follow-up adds one eight-update burst per episode only when a qualified
root reports a nontrivial rotation delta at world delta zero. Each update reads
one root, logs its time, actual/wanted/delta matrices, then returns without a
bone loop or world scan. Nonzero delta, identity/mode change or an unavailable
getter stops the burst. Existing four-capture/sixteen-attempt limits still
apply; unchanged completed state stays idle. Evidence and receipts are in
`dist/review/windows-freeze-root-burst`.

## Consecutive-frame result

Generation `d67e6b090dc44058ac3c0a1d099869f7` loaded at 19:31:16; all 83
published modules matched the verified source payload. The user's spinning
reproduction produced eight consecutive samples at 19:31:52, with world delta
zero throughout and unchanged root position. Across seven adjacent pairs the
actual orientation advanced 132.0768-132.0855 degrees every 10.297-10.771 ms.
Reported delta orientation agreed to within 0.023 degrees by the relative-matrix
comparison (including float/printed-value error). Wanted and actual poses
matched at these sample points.

That demonstrates repeated, nearly constant rotation during zero-time updates;
it does not prove that the delta getter is the source rather than a result of
the rotation. Subsequent stationary captures had an identity rotation delta.
The full nearby scan was interrupted by unfreezing after the complete root
burst; no whole-capture performance maximum is claimed for that interrupted
episode. The prior completed source capture reported 2 ms maximum work.

The next intervention should isolate the zero-time update path or its rotation
writer. Re-enabling the withdrawn root correction would repeat the cape
problem and would not explain the continued rotation. No freeze fix is claimed
from this read-only capture.
