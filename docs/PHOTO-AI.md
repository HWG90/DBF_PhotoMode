# Director enemy behavior — 0.9.7

The runtime embeds `freecam/ai_backend.lua` and
`freecam/ai_control.lua` and adds **Enemy behavior** at the top of Director. Its stable
setting ID is `ai_behavior` (1 Normal, 2 Passive, 3 Dummy); `ai_reset` explicitly
resets it to Normal. `ai_status` reports the affected count, pending cleanup,
or the reason it is unavailable. This feature was developed in 0.9.6 and is
included in 0.9.7; the earlier public 0.9.5 ZIPs do not contain it.

The menu exposes **Normal**, **Passive**, and **Dummy**. The selected behavior
continues after the menu and Photo Mode close, including bounded discovery of
new enemies. Normal or **Reset AI to Normal** restores ordinary detection and
movement. The process starts at Normal after a game restart. Frozen is not
exposed: Link's stun-based mode needs separate implementation and testing.
These controls are **solo-only**. A connected or joining remote player resets
the selection to Normal and restores owned detection/movement changes. The
previous mode does not resume automatically if that player leaves.
Their intended behavior does not stop the AI brain or pause physics. Enemies still animate,
take damage, stagger, and die. A committed attack can finish, and a temporarily
shared target may be cleared only at the next bounded refresh.

- Normal restores detector enablement and the stationary bit changed by this
  Photo Mode session, when the same live component still has the applied value.
- Passive disables detection and clears hostile counts, behavior targets, and
  alert levels. Enemies can wander.
- Dummy applies Passive and the enemy movement flag `0x80`. Physics impulses
  and damage reactions can still move it.

No stun requests, spawning, removal, world clocks, velocities, poses, actor
physics flags, or native game-function calls are involved. This route avoids
the unsafe world-pause/tiny-delta experiment.

## Integration and lifecycle

The builder constructs `backend = ai_backend.new(stingray)` in a protected call, then
`control = ai_control.new(backend, log)`, exposed internally as `H.dbf_ai`.
Unsupported builds expose an honest
unavailable state; there is no dependency on the Link addon or its command
driver. The backend supports exactly game.dll timestamp `0x6AB3B43F` and engine
timestamp `0x6AB382E4`, with the verified Unit-registry code fingerprint and
fixed component layouts for that build.

`ready()` returns `ready, reason, capabilities`. Controls require a mission,
a known local peer, verified authority, exactly one connected player including
the local peer, no synchronizing peers, a main world, and an enemy director.
The existing `GameSession.other_peers`/`synchronizing_peers` reader counts map
entries, including sparse peer tables. Without a game session it uses the
existing `Network.connections` reader. Missing, malformed, or failing readers
are unavailable. Multiplayer hosts and clients are both denied.

`queue('normal' | 'passive' | 'dummy')` records menu intent without writing.
The generated runtime calls `flush(photo_active)` from the real update callback.
Menu callbacks only queue intent. Startup resets `ai_behavior` to Normal;
Photo Mode exit does not change it. Shutdown explicitly queues Normal, retains
the registration and returns false while restoration is pending; an update
must finish cleanup before teardown succeeds. Behavior choices are disabled
outside verified solo play; Reset remains available while cleanup is owed.
Joining or unknown network/session state cancels the selected mode. Temporary
world/scene reads during respawn or loading suspend writes while preserving
the selection; discovery resumes when the scene is verified again. A separate
`restore_context`/`restore` path restores only the owned detector state and
stationary bit while the same authoritative host remains valid; it cannot
discover enemies or clear targets/alerts. Unknown authority retains the leases
for retry. Ordinary writes recheck solo state even if a stale UI queues one.
A retired world
invalidates old records; the chosen mode resumes only in a new validated
authoritative mission context.

Movement, target and alert fields resolve independently of any borrowed
detector owner. If that owner is retired or cannot be validated, the backend
uses this enemy's own independently validated detector when available; it
never writes the stale owner's surviving row. Missing components leave the
other validated controls usable and are reported as partial application,
rather than claiming the enemy is fully affected. Dummy-to-Passive movement
restoration keeps its lease for retry without blocking target suppression.

The controller polls availability at most twice per second. The backend uses a monotonic
wall clock independent of world time, discovers at most 256 map buckets every
50ms, processes at most 16 known enemies per owning update, and tracks at most
1,024. The known-enemy hold no longer waits for the discovery timer. Larger
groups are revisited over multiple updates; this is not a claim that every
enemy is processed every frame. A discovery failure delays new arrivals but
keeps validating and holding known enemies; the status reports the pending
discovery retry. Context or authority failure still stops ordinary writes.
Unusable records without owned changes are discarded for later discovery;
they cannot permanently consume the tracking slots. A full registry is shown
in the status. Detector cleanup has its own bounded 16-owner sweep at the
discovery cadence; its owner list is not rebuilt between sweeps.
Discovery and processing therefore span multiple refreshes in large scenes.
Writes happen only when a field differs; there is no global frame hook,
background task, or every-frame whole-world enumeration in these modules.

`mode`, `status`, `available`, `pending`, and `affected` provide UI readback;
`count()` returns tracked records plus outstanding detector cleanup leases.
`release(reason)` / `clear(reason)` /
`close(reason)` stop suppression and perform conditional restoration. A failed
restore or lost authority retains cleanup ownership and returns false, so the
caller must retry before retiring the manager. Actual world retirement drops
old records without dereferencing their fields.

Each read/write resolves the current world entity row, full entity ID, Unit
reference/generation, native Unit world, live AI component descriptor, and
fresh manager row. Components can move without leaving cached write addresses.
The detector owner must also be a live enemy when it differs from the entity.
Field writes verify component tokens, expected values, and post-write readback.
An acknowledged write followed by failed readback retains its restoration lease.
Shared detector leases follow the validated actual owner, so a borrower dying
does not discard the original detection state. Reset attempts all remaining
owners even if another owner temporarily cannot be restored.

Only the detector enable byte and this module's stationary-bit change retain
baselines. Restoration preserves unrelated flag bits and preexisting disabled
or stationary state. Hostile arrays/targets/alerts are transient history: their
old values are deliberately not restored, because referenced entities and list
storage can change. Detection repopulates them naturally after Normal.

## Verification status

`freecam/ai_control_tests.lua` passes offline with mocked behavior and a
byte-addressed backend fixture. It covers changed-only/bounded refreshes,
Normal/Passive/Dummy transitions, preexisting states and high flag bits,
another writer, component replacement, generation reuse, authority loss,
restoration retry, partial-write acknowledgement, world retirement, exact
build/registry rejection, descriptor liveness, relocated manager rows, host
and joining gates, and no writes from menu callbacks. Solo-policy fixtures
cover sparse remote-peer maps, unknown counts and reader errors, stale-context
write rejection, join-triggered restoration, restricted cleanup writes, and
no automatic reactivation when returning to solo.

`freecam/ai_controls_integration_tests.lua` exercises the real MCM Core,
controller and options with the real AI manager and a mock backend: the Director
row, saved behavior reset, update-only writes, authority loss and Normal/Reset
access, affected count, inactive-backend state, Photo exit persistence, new enemy
discovery, Passive movement, Reset, failed restoration and shutdown retry.
The AI manager, UI integration, close cleanup, and GUI lifecycle fixtures passed
4/4 after the persistence change; receipt:
`dist/validation/ai-behavior-persistence-fixtures.json`.

David accepted the initial live Dummy behavior and subsequently confirmed
that the selected behavior persists after leaving Photo Mode and that Reset
restores normal behavior. The live selector exposes Normal, Passive, and Dummy.
New-enemy discovery has bounded-refresh fixture coverage; the live acceptance
does not establish every enemy type, mission, or transition.

On October 13, the mission trace identified live enemies whose Behavior row
still named a retired detector owner despite having a valid detector of their
own. After the fallback and independent-field correction, David confirmed
**"Dummy and Passive both work"** (live handoff batch 359). Fixtures cover the
stale borrowed row remaining untouched, own-detector fallback, missing or
unreadable optional components, independent failed writes, and restoration.
The subsequent discovery-failure continuation and sweep-allocation change
have offline fixture coverage; they were not part of that live confirmation.

The earlier combined development candidate was
`dist/releases/War-Journalist-0.9.5-persistent-ai-dev`; BSL, MDL and LLL each
include their required assets and pass standalone package verification.
All 47 fixture groups pass, including provider replacement without losing the
selected behavior. The next-launch LLL runtime was installed with a verified
backup; SHA-256:
`e2f31545269d344051b70a56bc54a6ddb283247f41b7b9fdc012280ff34e3833`.
The current process also received the persistent AI selector and a same-panel
color editor refresh with Apply, a live swatch and HEX. Camera hooks were not
reloaded. Public 0.9.5 release archives remain separate from this candidate.

The package includes narrow GUI lifetime and close-error cleanup guards.
They pass isolated lifecycle fixtures, but do not establish that HDR/SDR or
other display-setting crashes are fixed.

## Provenance and license

Component layouts and behavior semantics are adapted from Link's
`hd2_enemy.lua`, `hd2_addresses.lua`, and `hd2_net.lua`, included with Links Link
To Memory 0.5.1. The existing `freecam/vendor/LICENSE-Link.txt` must accompany
packages embedding this code. `hd2_ai.lua` was not present in the local kit;
`hd2_enemy.lua` supplies the validated behavior route.

MIT License

Copyright (c) 2026 Link

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
