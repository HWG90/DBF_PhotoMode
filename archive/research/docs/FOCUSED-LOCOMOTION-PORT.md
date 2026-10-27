# Focused locomotion port attempt

Status: blocked; no working movement port or runtime deployment.

The requested behavior is Handycam A/D strafing without turning the body and S
backpedaling. The historical GooseGadgets controller at
`Native ADS Camera Test/src/first_person_movement.lua` is S-only. It checks an
authoritative local-avatar descriptor against a private locomotion pool and owns
only a zero-to-one transition of a focused-locomotion byte. It restores the prior
value on release, retains uncertain cleanup, and preserves foreign changes.
It neither sets aiming flags nor establishes that A/D strafing works.

## Current-build evidence

The inspected installed DLL is Steam build 26088801, SHA-256
`6d1d4d3bc6fc84801d9f8f1b310e13a603d07409f3d9495d74b42e1d0bb1c08f`.
All six historical instruction fingerprints have zero exact file matches.
REA/Ghidra also found no match for the masked historical flag predicate across
54,013,008 initialized imported bytes, or for a shorter byte-comparison shape
across the 33,128,448-byte imported text section. These are bounded signature
search results, not proof the behavior or a different native implementation is
absent. No current pool, row layout, flag address, or getter/setter was qualified.

The latest recorded Windows Lua API namespace/component inventory exposes no
locomotion manager. The existing native bridge is rejected with error 577.
The earlier administrator-level read-only process inspection also failed module
enumeration with access denied; this attempt did not retry it or change process
permissions. Existing `move_angle` animation observations do not establish
authority over body facing or gameplay locomotion.

Evidence is retained in `dist/review/focused-locomotion-port/STATIC.json`,
`REA-EVIDENCE.json`, and `analysis-snapshot.json`. The current game, installed
archive, settings, camera, aiming and movement state were not changed by this
attempt. No behavior or performance success is claimed.

## Required next boundary

A supported backend must expose the current local-player locomotion identity,
readable focused state, and a qualified setter before integration can proceed.
An engine/loader provider would avoid requiring the unavailable native bridge.
The historical addresses cannot be deployed as a current-build provider.

Once that boundary exists, a Handycam-only lease can request focused locomotion
on movement transitions and restore on release, ADS handoff, menu/focus loss,
Handycam exit, player/world retirement, and shutdown. Body-facing and backpedal
behavior must be visually tested separately, alongside native aiming and
transition/steady-state timings. An animation-only or camera-rotation substitute
does not establish the requested gameplay behavior.
