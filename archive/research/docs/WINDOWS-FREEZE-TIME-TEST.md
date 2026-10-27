# Private zero-time boundary experiment

**Withdrawn after the live comparison.** The positive-time interval reduced
the violent spin and kept the cape attached, but the user observed continuing
simulation and reports that near-zero rates can hyper-accelerate collisions.
It is unsuitable as a Freeze replacement. Its entry marker, time-policy branch
and runtime wiring have been removed from current source. The isolated fixture
is retained with the review evidence rather than the active fixture suite.

The reset test ran from 19:47:17 to 19:47:23, measured positive world deltas near
1.09e-8 seconds, then acknowledged exact zero on the same frozen pose. Rotation
resumed immediately at exact zero. The experiment therefore isolates a strong
dependence on the zero-time path but does not identify the responsible writer.
`OBSERVED.json` and `reset-live.log` preserve the result and user feedback.

The following describes the withdrawn experiment for reproducibility.

The consecutive-frame capture found a nearly constant 132-degree rotation per
update while world delta was zero. Physics off/on and bone-transfer ignore did
not stop the spinning. This experiment tests whether the behavior specifically
depends on exact zero time; it does not yet identify the writer.

The one-use `wj-freeze-time-probe.request` marker with `freeze-time-v1` enables
one six-second interval on the next admitted Freeze. The existing time-policy
owner requests multiplier 0.000001 and then returns to its normal exact-zero
Freeze path. It preserves the normal solo/world/binding admission, ownership,
cleanup, foreign-write handling and Slow Motion preferences. No root, bone,
cape or physics setter is called by this test. Ordinary builds and later Freeze
requests remain exact zero.

During the positive interval `owns_zero()` is false. Existing pose and root
writers therefore remain unavailable; the read-only observer is separately
allowed to record that diagnostic phase. Returning to zero starts a fresh
capture so both phases can be compared. Actual world delta is recorded rather
than inferred from a successful multiplier setter.

Resume, close, foreign time changes or world/session changes cancel the
interval. A clock failure requests normal cleanup. The zero return repeats the
ordinary gate and admission; refused writes retain normal cleanup behavior.
The positive-time clock is read only while the six-second test is active.
There are no repeated multiplier writes during unchanged state.

Fixtures cover the interval, exact-zero ownership distinction, one-use limit,
Slow Motion preservation, early close/resume, foreign ownership, session/world
replacement, clock/gate failures, refused setters and actual runtime wiring.
Live results are recorded above. This withdrawn diagnostic is not a replacement
for true-zero Freeze and has not been published or installed in an archive.
