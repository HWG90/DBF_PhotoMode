# Windows ESC input investigation — 2026-10-25

Status: input-only Escape context is not established. No native routine was called, patched or injected; no Escape UI state was written.

## Current-build observations

- Steam build 26088801; canonical game module `Helldivers 2_steam/data/game/game.dll`, SHA-256 `6d1d4d3bc6fc84801d9f8f1b310e13a603d07409f3d9495d74b42e1d0bb1c08f`.
- Boot Mod Loader 0.11.0 embeds the original boot. Decoding its Lua 5.1 bytecode shows four callbacks (`init`, `shutdown`, `update`, `render`), each containing only RETURN. The boot does not implement the gameplay menu or its input routing. Decoder evidence: `dist/review/esc-input-trace/boot-evidence.json`.
- The deployed Windows API inventory exposes only `Input.event_queue`; no named input-context getter/setter appears. Window exposes mouse focus/cursor setters and system-shortcut controls, but no gameplay-keyboard capture API. This inventory does not rule out an undocumented engine route.
- The threshold candidate was accepted/read back but the user observed WASD and other input reaching gameplay. It is rejected; the archive builder no longer activates it. The already-running test build retains its own cleanup obligations until closed.

## Historical Escape integration

`DBF-MCM/src/integrations/native_entry.lua` (older pinned binary hash `2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e`) observes the UI manager stack and invokes native tab/close operations through FFI. It does not provide a Lua input-context interface. Photo Mode's older `chat_context.lua` yields its own capture and hands off Window cursor flags while native menus are open; that is not evidence that Window flags suppress gameplay keyboard input.

## Static trace boundary

REA/Ghidra opened the canonical current module after rejecting the junction path. Defined-string searches did not identify an Escape/input-context entry. Raw ASCII searches likewise did not identify those names; their absence does not establish absence of the feature. The old menu addresses fail the old signatures in both the current file and the existing October 22 dump. The dump manifest ties its disk source to the same current hash and reports identical .text bytes. Neither source establishes the current Escape call chain.

REA search evidence: `ev_c56ce10def754bb1760b50159adc465932896b95084f94902ad36fb7e9f86a6a`; retained provider snapshot: `dist/review/windows-input-v1/game-esc-static.snapshot.json`.

## Conclusion and remaining work

The suggestion is plausible, but opening Escape, hiding its UI, or copying old UI-manager flags would not establish an independently owned input lease. A usable replacement needs a current-build entry and matching release operation, proof that it blocks gameplay without consuming Photo input, and transition validation for held keys, focus loss, Escape, close/reopen and camera/action-shot handoff. No working input-only replacement or pure-Lua reachability has been demonstrated. Further progress needs current executable-call-chain evidence or an exposed supported engine interface; the old offsets are not a valid shortcut.

## Live ETW follow-up

A user-performed ESC-open/closed comparison was captured with WPR at 20:35 local time. It contains 419,733 target CPU samples and reports zero lost events, but incomplete stack unwinding, missing mappings for key game addresses, no exact menu-state markers and no setter arguments prevent identification of a reusable input-only routine. Full evidence and limitations: `dist/review/esc-live-trace/FINDINGS.md`. No speculative native call or Photo Mode integration was made.
