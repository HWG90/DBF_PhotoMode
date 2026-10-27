# Windows hoverpack pause investigation

User reproduction: any Freeze during active hovering crashes. The user identifies
the divide-by-zero behavior previously investigated; melee is not required for
the current report. Near-zero time was initially rejected because it advances
simulation and can hyper-accelerate collisions. The user subsequently authorized
`0.00000000000001` (1e-14) as a hoverpack fallback; validation remains required.

Preferred fix: adjust and restore the pack's thrust; do not add
keyboard blocking to solve hover pause. Existing Photo Mode input ownership is
separate. The legacy backend's input-neutrality assumption must not be silently
removed and reported as a working thrust-only Windows guard.

The old `hover_pause.lua` / `steam_hover_backend.lua` solution is data-only. It
neutralizes the instance-owned hover definition field at +0x9C, waits for a
completed positive engine update with neutral controls, and only then admits
exact zero. Resume keeps the override until a positive engine update completes
before restoring the owned value. Its native memory/bridge reader is not loaded
on the Windows engine-only route in `steam51.lua`. Keyboard input capture by
itself does not reproduce that automatic-thrust neutralization.

Current live API inventory includes no Jumppack/Hoverpack component provider.
`components` exposes only ReflectionProbe. The legacy character Unit also had
no UnitComponent-to-entity association in the bounded captured entity inventory;
that does not establish that every other engine route is unavailable.

Generic script data is not automatically the native hover manager's state:
[Unit.get_data](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Unit.html)
reads stored script data, and flow variables require an actual external flow
node. No current property path or flow variable controlling native hover thrust
has been qualified. Inventing a key or reusing old native addresses is not a fix.

The two newest existing dumps inspected on 2026-10-26 report access violations
at helldivers2.exe +0x6f337d and +0xca07a, not an exception directly at a divide.
Their relationship to this hover reproduction is unproven; downstream failure
after invalid arithmetic remains possible. Summaries are retained under
`dist/review/windows-hoverpack`. Do not attribute these dumps to hoverpack
without matching run/action evidence.

Release status: active-hover zero-time pause is unresolved. The old backend's
fixtures do not establish Windows hover safety. No native hook, executable patch,
page-protection change or new DLL has been introduced by this investigation.

## Development-build follow-up

The user reconfirmed active-hover Freeze as the trigger in the new development
WJ build. The active source is the separate `DBF_PhotoMode-BML-fix` worktree,
not the older `steam-lua51-port` checkout. In `steam51.lua`, the engine host
sets `engine_time_only=true` and omits `load_hover`. In `steam_runtime.lua`,
that flag bypasses the hover preparation callback before the exact-zero write.
This establishes a missing guard, not the native crash instruction or a new fix.

A bounded ordinary Windows API check against running PID 78084 opened
`PROCESS_QUERY_LIMITED_INFORMATION`, but both `VM_READ` and the combined
`VM_READ | VM_WRITE | VM_OPERATION` request returned error 5 (access denied).
No memory read, write, privilege change or helper modification was performed.
The enforcing component was not identified. Evidence:
`dist/review/windows-hoverpack/EXTERNAL-ACCESS-CHECK.json`.
Consequently, extending the existing external input helper with the old
memory-based guard is not currently a demonstrated route either.

No runtime change, deployment or hover crash-resolution claim follows from
this check. The remaining dependency is a qualified current-build interface
for owned pack thrust, including restoration and completed-update ordering.

## Tiny-positive development fallback

The user authorized a 1e-14 time multiplier for hoverpack Freeze after the
DLL-free native-field investigation. `windows_hover_freeze.lua` makes one
resource-filtered query per explicit Freeze. Any live hoverpack in the solo
world, including a dropped one, conservatively selects 1e-14; absence selects
exact zero. It does not claim equipped-player ownership or modify thrust.
Unknown or oversized inventories refuse Freeze rather than submit zero.
The selected rate stays fixed through the hold and foreign-write reassertion.
Resume uses the selected Slow Motion rate or 1x; full cleanup uses 1x.

Positive time never satisfies `owns_zero()`, so exact-zero subject/physics
writers cannot activate under this fallback. The separate manual near-zero
button requested in the cape chat switches to 1e-11 and returns to the captured
base rate when disabled. Positive transitions release existing holds first.
Three world-delta samples after a tiny-rate write then stop; there is no added
steady-state equipment polling. Fixtures cover idle reads/writes, restoration,
manual and automatic rates, foreign takeover and actual runtime wiring.

This is a development candidate until actual positive world dt, active-hover
Freeze/Resume, collision behavior and transitions are verified in the game.
It is not a native thrust fix or a public release.

The user's proposed local dt=1 substitution is distinct from global timescale=1.
Historical disassembly saved in the main checkout's
`JUMPPACK-ZERO-DT-STATIC.json` identifies the divisor as the movement function's
float dt argument, saved in XMM14 and a stack slot. That evidence is build-specific,
not a current mutable component property. A denominator-only substitution needs
qualification of the current calculation and its access path; substituting a
whole one-second movement step would also change other integration terms.

## Live fallback result and outstanding fall report

Development generation `1b28f4c697c84a618f4b0f677752c9b4` loaded with all
98 fixture rows passing and 87 payload modules verified against source.
The user confirmed that the scene stops and active-hover Freeze/Resume works.
They then reported being launched **from a fall, not from hovering**. The timing
and checkbox state of that fall report need clarification. Collision safety is
therefore not established; this is not ready for publication. No automatic
withdrawal or further reload followed that ambiguous report.

`World.delta_time` returned ordinary-sized values during tiny-positive holds,
although the user confirmed the scene stopped. It is not a qualified effective
simulation-rate readback for this case. Do not infer that the multiplier was
ignored from those samples alone. Resource query and sample read measurements
rounded to 0 ms at the clock's resolution; no zero-cost claim follows.
Evidence: `TINY-RATE-LIVE.json`, `tiny-rate-live.log`, `TINY-RATE-VERIFIED.json`.

## User acceptance: retain hover fallback

The user clarified that the launch happened immediately after Resume **on a
ragdoll**, and explicitly requested keeping the hover fallback: "no keep it",
"its working", "it only launched me on the ragdoll". Automatic 1e-14 remains
active in generation `1b28f4c697c84a618f4b0f677752c9b4`; no withdrawal reload
was sent. Local hover source was restored to match that verified live payload.
The separate cape chat has a later `photo_menu.lua` source change; it does not
change the active hover backend or time policy.

Acceptance scope: the reported active-hover Freeze/Resume crash is resolved by
the user-confirmed near-zero fallback. The native thrust field is not modified,
exact-zero hover safety is not established, and ragdoll Resume launching remains
a separate known issue. Retaining this development build is an explicit user
choice; it is not a claim of general collision safety or publication approval.
