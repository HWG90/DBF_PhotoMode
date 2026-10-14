# Registry compatibility test

Reports include Radeon 9070 and 6950 XT crashes on Alt-Tab, fullscreen changes,
and the game's bloom/DoF settings, including before Photo Mode's first use.
There is no AMD crash dump yet, so the driver-specific cause is unconfirmed.

The published 0.9.8 registry contains 319 IDs: the current game's 77 native IDs,
44 shipped Photo Mode libraries, and 198 registrations inherited from a larger
development asset archive. Those 198 libraries are absent from a clean Photo Mode
package. The development machine has them in a separate installed HUD archive,
which masked the missing package closure.

The maintained builder now registers exactly 77 + 44 = 121 IDs. The release
verifier rejects missing, duplicate, reordered-native and unbundled registrations.
`--allow-legacy-registry` is only for auditing immutable historical packages; its
receipt explicitly reports the 198 unbundled registrations.

`tools/build_registry_compatibility.py` creates BSL, MDL and LLL controls from the
hash-verified frozen 0.9.8 release. Runtime Lua, native DLLs, GPU programs, all
materials, logos and the dedicated light are byte-identical. It changes only the
registry resource, checksum/audit metadata and test instructions. It does not
replace the public release or install anything.

Test with War Journalist and its loader alone. Replace the original package,
deploy and restart. Before opening Photo Mode, test Alt-Tab, fullscreen, bloom
and DoF separately. Then open Photo Mode and repeat. Report the GPU and driver,
loader, precise failing action and whether Photo Mode had been opened.

If the registry-only candidate still crashes before first use, the next control
defers camera discovery and native services until the first configured toggle,
while retaining the same corrected assets. This separates boot assets from the
inactive camera/runtime callbacks. It is a diagnostic control, not a release.

An additional source audit found that suspending camera input does not suspend
effect/native-renderer calls after activation. A separate graphics suspension
path is needed; ordinary cleanup restores renderer flags and must not be used
blindly during an uncertain graphics reset. This does not explain crashes before
first activation, so it is not substituted for the registry/startup tests.

Registry/archive tests and mocked standalone loader startup do not prove AMD
crash resolution. The test candidate must be confirmed on the affected hardware.
