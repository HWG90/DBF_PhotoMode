# HD2 WinVerifyTrust hypothesis

Date: 2026-10-25

## Goal

Determine whether stubbing `WinVerifyTrust` could explain or intercept the
current DLL signature rejection path, without modifying trust behavior.

## Decision

The hypothesis is unsupported by the static import evidence. None of the four
examined retail binaries imports `WinVerifyTrust`, directly or through the PE
delay-import table. A `WinVerifyTrust` stub is therefore not an evidence-based
interception point for the observed error 577.

## Steps

Parsed normal and delay-import directories for:

- `bin/helldivers2.exe`
- `bin/preloader.dll`
- `bin/runtime.dll`
- `start_protected_game.exe`

The pass matched `WinVerifyTrust`, certificate, crypto, `wintrust.dll`, and
`crypt32.dll` imports.

## Evidence

- `helldivers2.exe` has delayed BCrypt hashing imports but no
  `WinVerifyTrust`/WinTrust import.
- `preloader.dll` exposes no matching import.
- `runtime.dll` exposes no matching import.
- `start_protected_game.exe` imports certificate-chain and object-processing
  routines directly from `CRYPT32.dll`, including `CertGetCertificateChain`,
  `CertFindCertificateInStore`, `CryptQueryObject`, and related functions.
- The protected launcher also imports legacy CryptoAPI hashing functions from
  `ADVAPI32.dll`.

## Validation

Read-only PE inspection completed successfully. No binary, import table,
configuration, return value, or runtime process was modified.

## Unresolved items

- Imports do not exclude dynamically resolved WinTrust functions, although no
  present evidence supports that path.
- Existing ETW evidence still does not attribute the exact DLL rejection to the
  launcher, game, EAC, Theia, or Windows Code Integrity.
- The next defensible static step is cross-referencing the launcher's existing
  `CRYPT32` imports, not stubbing a function absent from its import table.
