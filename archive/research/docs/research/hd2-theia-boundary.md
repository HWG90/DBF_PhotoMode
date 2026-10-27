# Helldivers 2 Theia boundary

Date: 2026-10-25

## Goal

Identify the locally observable Theia component boundary in the current
Helldivers 2 build without modifying or bypassing integrity enforcement.

## Decision basis

The current evidence supports treating Theia as code compiled into the game,
not as a separately installed EAC component. A name or source-path string is
insufficient to attribute DLL rejection to that code.

## Steps performed

1. Enumerated installed files whose names contain `theia`, `eac`, or
   `easyanti`.
2. Searched the protected launcher, game executable, game DLL directory, and
   EAC directory for embedded `theia` references.
3. Preserved the distinction between component presence, observed behavior,
   rejection attribution, and enforcement authority.

## Evidence

- No installed file is named for Theia.
- `bin/helldivers2.exe` contains the embedded source-path string
  `stingray/runtime/theia/theia_core.cpp`.
- Nearby strings include `Hardware Incompatibility detected!` and an `AC`
  marker.
- The separate named anti-cheat installer remains
  `EasyAntiCheat/EasyAntiCheat_EOS_Setup.exe`.
- Existing ETW evidence contains no exact-payload event attributing error 577
  to Theia, EAC, or game code.

## Validation result

Theia code is present inside `helldivers2.exe`. Its precise responsibilities
and callers are not yet resolved. Nothing observed proves that Theia performs
the failed DLL signature check.

## Artifact paths

- `C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/helldivers2.exe`
- `C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/EasyAntiCheat/`
- `<local-investigation-directory>`

## Unresolved items

- Resolve cross-references to the Theia source-path and hardware diagnostic
  strings in the exact executable build.
- Determine whether Theia participates in module policy, hardware checks, or
  only engine compatibility reporting.
- Attribute the exact DLL rejection using an observed load attempt before
  assigning enforcement authority.
