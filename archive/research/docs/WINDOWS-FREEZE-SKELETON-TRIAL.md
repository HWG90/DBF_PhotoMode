# Selected full-skeleton hold trial

**Current candidate: body skeleton hold, no cape corrections.** At the user's
latest request, automatic skeleton replay is restored with cape1..cape8 excluded
from capture, replay and readback. All eight names must match the known rig's
nodes 35..42 before capture succeeds. The other 99 nodes are held until Resume.
Native bone-transfer mode is preserved. The separate nearby-root hold, explicit
cape refresh, paired observer and body-flip activation are removed from startup.
Engine propagation from body nodes can still affect linked garment rendering;
the mod makes no direct cape correction. Visual acceptance is pending.

Earlier full-skeleton integration visibly rotated the character about 180
degrees and was withdrawn, then the root-only correction was restored. That
history is retained below. Do not ship a claim that ragdoll/cape Freeze is fixed.

The user suspects the body is misplaced relative to a correctly placed cape.
Historical paired samples include a body-root correction of approximately 152
degrees with determinant +1, while three corresponding cape/body bone world
poses match both before and after correction. This is not evidence of a fixed
mirror/180-degree error; exposed graph poses do not establish cloth vertex or
skinning state. The existing four-pair read-only cape observer is re-enabled on
the root-only candidate to collect a current comparison. No flip, negative
scale, attachment relink, or full-skeleton replay has been added.

The fresh comparison generation `c572c9d3b4d04902a5041664e41477be` recorded
approximately 167 degrees of body-root correction; the three exposed cape/body
bone world poses again matched before and after. The user reports a final shift
as Freeze settles. Pre-zero root capture was proposed but has NOT been deployed.

At the user's explicit request to rotate the body only, a private one-use
`wj-freeze-body-flip.request` marker (`body-flip-v1` plus newline) now exposes
Subject -> Flip body 180 degrees / undo. It requires an explicitly selected,
held 107-node Helldiver and owned exact-zero time, outside Handycam/authored pose
ownership. It toggles the held body's root target through a proper half-turn
about its right axis around the chest pivot. No separate cape transform, bone,
negative scale, or link is written; the usual explicit cape scene refresh is
skipped for the flipped body. The engine can still propagate body changes to
linked attachments, so this does not promise a world-stationary rendered cape.
Resume/disposal discard the override without rewinding the live pose. This is
an explicit visual test, not a permanent correction or release acceptance.

The flip fired once at 21:05:02 in generation
`570da47434514df4a9baada60c700f15`. Its post-scene-update exact matrix readback
failed and disabled the root hold; the user reported resumed spinning. The
failure did not establish that rotation itself caused ongoing spinning, nor
whether the mismatch was float rounding or a material engine rewrite. The test
is now inactive under the user's subsequent request above.

## Integrated Freeze candidate

The six-second trial stopped spinning, confirmed by the user, but the cape looked
inverted. Live generation `165c194515af4751a2d7e3becd06edda` completed 560 render
passes over six seconds, with 3928 changed-node writes, zero scheduled readback
mismatches and a 2 ms maximum pass. Bone mode restoration was acknowledged. This
does not pass cape acceptance or establish a release-ready Freeze fix.

The next candidate captures the selected skeleton in the existing `before_zero`
pause-entry path, after any available hover preparation succeeds and before the
time-policy zero write. It then holds until Resume instead of using a test
button/timer. Capturing after a body has already spun may disagree with cached
cloth orientation; this is a hypothesis to test, not an established cause.
Focus loss retains the continuous hold while Freeze remains owned. Authored pose
actions, subject changes, Resume, close and reload release it. The continuous
mode uses the same bounded replay/readback/cleanup code as the trial. A missing
selected character is logged without inventing ownership; this candidate does
not yet cover arbitrary enemies or every nearby corpse.

The explicit probe marker still selects the finite diagnostic instead of the
continuous owner, so the two never write the same skeleton simultaneously.
Fresh Freeze/cape visual acceptance remains pending. No hoverpack fix is implied.

The first integrated generation `5cf01356e62f44c88fa18bb425644b37` stopped after
seven render passes because the engine returned bone transfer to its original
mode during pause entry. It preserved that native change; the measured maximum
was 1 ms. The revised continuous path therefore does not override bone-transfer
mode at all. It replays changed local poses while the captured native mode is
unchanged, and ends if a different mode takes ownership. The finite diagnostic
retains its original explicit mode test. Only four scheduled samples enumerate
the changed indices; this introduces no per-frame log stream.

The old `ragdoll_pause.lua` held all 107 local bone poses on one character and
returned bone-transfer ownership on release. The withdrawn Windows root hold
instead captured up to 32 separate nearby roots over a bounded inventory scan,
including cape/accessory units, and did not hold the full skeleton. The latter
stopped the visible spin but detached the cape. Bone-transfer mode alone and
physics off/on did not stop rotation. Near-zero time is withdrawn because it
continues simulation and the user reports collision acceleration.

This private trial captures one selected, qualified 107-node Helldiver's complete
local skeleton synchronously while the runtime owns exact-zero time. A separate
one-use `wj-freeze-pose-probe.request` marker (`freeze-pose-v1` plus newline)
exposes Subject -> Test full skeleton hold (6 seconds). It does not identify the
character as the local player or claim to detect ragdoll state. The user chooses
the subject and starts the test. At most two trials are admitted per generation.

The render lifecycle changes bone transfer from `position_and_rotation` to
`ignore` and replays only changed nodes from the same coherent capture. Separate
cape/accessory units, physics flags, root-transfer mode and time policy are not
written. No world inventory is scanned. Node matrices are retained as copied
scalars, never frame-scratch values. Lifetime, exact resource, selected identity,
session, world and binding ownership are checked. Scheduled all-node readback
checks stop the trial on a mismatch; they are not visual proof of frozen cloth.

The existing render callback is required because observed roots change every
frame even at exact zero; no engine notification for those changes is available
in this implementation. Work is limited to one 107-node skeleton for six seconds.
Capture or a replay pass exceeding 8 ms stops the trial. Unchanged nodes cause
no pose writes, unchanged skeletons cause no scene refresh, and inactive trials
perform no native work. Timing is logged for live evaluation.

Release restores only the bone-transfer mode while it still equals the owned
`ignore` value. It never replays the original pose during resume. Subject changes,
lost Freeze ownership, focus loss, close, timeout and reload end the trial.
Uncertain cleanup remains idle and prevents normal nonzero-time restoration;
explicit recovery can retry. Foreign modes and retired identities are not
overwritten. Reload has one explicit cleanup retry across its cleanup polls.

Fixtures cover full-skeleton coverage, scalar lifetime, unchanged-state behavior,
exact-zero admission, partial writes, mode ownership, target retirement, timeout,
budget failure and the actual runtime menu/release paths. Visual acceptance of
spinning, cape attachment and normal resume remains pending.

### Transfer ownership parity after timing test
User confirmed post-render world-space boss hold still spins/flips. Comparison found continuous=true explicitly retained original bone mode while the original DLL-assisted ragdoll controller and successful six-second skeleton trial acquire ignore. Added explicit claim_transfer option for continuous lifetime, preserving defaults and foreign-owner/partial-failure cleanup. Entry replaces failed root holder with continuous body-only coherent replay, excluding cape1..cape8 and separate cape units, captures before zero, acquires ignore only on owned post-render and restores original mode before time resumes. Full source fixtures passed (including the concurrent ADS fixture after its correction). Rebased onto e81cba5c7e4d4d31a514bd0c6056838a; its only runtime difference from e037 was diagnostics injection for Handycam ADS, and retained our post-render correction. Candidate 07c2c9cd9b744860a3bbf406836e13d7 changes main and windows_freeze_pose_probe only; other 85 modules identical, including hoverpack and camera/ADS. Public/installed archive unchanged; visual acceptance pending.

Integration follow-up: added continuous-transfer runtime fixture proving pre-zero capture, post-native render acquisition, focus-loss retention, single mode lease, no running/closed replay, restore-before-positive-time and explicit failure recovery. It exposed that the before_nonzero gate included load_subject/root/ragdoll but omitted freeze_pose_hold alone. Added that explicit dependency. The deployed Windows configuration already supplies load_subject, so left the live visual trial unchanged; verified scoped cleanup payload saved offline under windows-freeze-transfer-cleanup. Full fixture suite passes. Runtime at 23:29:14 captured 99 nodes excluding cape, sample readback mismatches=0, then restored bone mode after 30 renders/232 node writes, max 1 ms; visual result still pending. This confirms acquisition/cleanup execution, not successful body/cape appearance.

## User-accepted Freeze baseline
After the post-render coherent body skeleton hold acquired ignore transfer ownership (cape1..cape8 excluded), the user explicitly reported THAT WORKS and PERFECT. This supersedes earlier pending/failed root-only, pelvis-only, world-boss and mode-preserving skeleton candidates. Preserve this policy and callback order; do not reintroduce cape corrections, teleport or Smooth Freeze. The exact current acknowledged payload and acceptance receipt are retained under dist/review/windows-freeze-accepted. This is visual user acceptance of the current Freeze behavior, not public release approval or a claim that every mod feature is finished. No further Freeze experiment or restart was issued.

Acceptance clarification: user explicitly confirmed the cape attaches correctly, then reported rare remaining spinning while accepting that it works fine otherwise. Keep the exact accepted baseline; cape attachment is visually confirmed, but Freeze reliability is incomplete. Earlier PERFECT confirmation must not be interpreted as zero remaining intermittent cases. No new Freeze policy, reload or restart was issued.
