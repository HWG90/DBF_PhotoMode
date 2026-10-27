# Windows ragdoll bone-transfer trial

The root correction in portable.22.8.1 stopped the reported spinning but
separated cloth from the body. It remains withdrawn. The saved read-only
capture at 17:16:49 shows the Helldiver root rotating 109.166 degrees and
local bones changing by up to 133.061 degrees while world time is zero.
Its root animation mode stayed `ignore`; bone mode stayed
`position_and_rotation`. The old DLL-assisted ragdoll implementation in
`ragdoll_pause.lua` instead captured all bones and set bone transfer to ignore
before repeatedly applying that pose. Those are materially different paths.

The upstream [Unit API](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Unit.html)
describes bone mode as controlling animation transfer, with root mode separate.
This does not establish that it stops HD2 physics. Test that distinction before
adding another root or cloth correction.

`windows_freeze_bone_probe.lua` is disabled unless a private one-shot marker
contains `freeze-bone-v1` followed by a newline. Once consumed, Subject exposes
an explicit six-second test button, limited to three trials per generation.
It requires a selected subject and confirmed true-zero time. The existing
selected-subject controller owns the mode write and restoration ledger,
including partially applied setters and foreign-mode preservation. No body,
root, or cape transform is written. Existing selection/world/rig validation
remains mandatory.

The probe copies root position/yaw and head position, then observes them at
0.5, 2, and 4 seconds. It restores the original mode at six seconds, or through
normal subject cleanup before unfreezing/closing. A replacement user pose or
subject cancels the probe without resetting that new owner. Failed restoration
stays visible as pending subject cleanup. No native observation occurs between
the scheduled samples or after a completed test. This is a diagnostic, not a
claimed ragdoll fix or an automatic Freeze feature.

All 91 fixture groups pass; 82 payload modules match source. Tests cover native
mode-only writes across scratch-frame rollover, partial mode-write recovery,
foreign changes, timeout, pose replacement, closure, and restoration before
nonzero time. Generation `27f64965665240c2a4790e3673c5b895` loaded at 18:50:37
without a game restart. Actual ragdoll/cape behavior and trial timings remain
pending in that first generation. Evidence: `dist/review/windows-freeze-bone-trial`.

The first UI button was accidentally omitted from the supported-control list
and therefore disabled. Generation `aed9af16ad614d06b8a9831ddc9bf5e3` corrects
that admission and reports refused preconditions in the menu. The integration
fixture now asserts the button is enabled and activates it through the real
service handle, rather than only calling its callback. It also releases any
other pose owner before starting, using the same path as authored poses.

Two completed live trials started at 18:55:57 and 18:56:07. Each mode change
was acknowledged, took about 3 ms, and restored successfully after six seconds.
The first samples still measured root yaw changes of 125.325 and 120.320
degrees respectively, with head movement of 0.604 and 0.590 m. The user reported
no change in spin. This candidate is not a fix. Per-sample native bone mode was
not recorded, so the captures do not distinguish an independent root writer
from a subsequent engine override of the mode. The next investigation must
address the root writer and attachment synchronization. Evidence:
`dist/review/windows-freeze-bone-button/OBSERVED.json`.

The current Lua inventory exposes Unit.disable_physics and Unit.enable_physics,
but no corresponding physics-enabled getter or Actor namespace was observed.
The upstream API describes a unit-wide physics toggle, not a root-specific
rotation gate. No physics toggle was called by this experiment; current-build
semantics and restoration requirements need inspection before using it.
