# War Journalist 0.9.9

A Helldivers 2 Photo Mode. This compatibility hotfix corrects the bundled shader
registry while retaining the tested 0.9.8 runtime, UI, features and artwork.

## Fixed

- Removed 198 inherited shader registrations whose libraries were not included
  in a clean Photo Mode install. The registry now contains the game's 77 native
  registrations plus the 44 shader libraries actually shipped: 121 in total.
- Added package checks that reject missing, duplicate or unbundled registrations
  and preserve the native registration order.

Affected Radeon testers reported that the registry-only candidate remained
stable through Alt-Tab, fullscreen, bloom and DoF changes, both before and after
opening Photo Mode. No AMD crash dump was available, so this is evidence for the
tested compatibility repair, not a claim that every display or driver crash is
fixed. HDR/SDR switching and unrelated crashes still need separate confirmation.

## Everything from 0.9.8 remains included

Native DoF stability and held ADS fixes, fixed poses with the supported-cape
correction, persistent solo AI modes, photo lights and presets, autofocus, scene
effects, screenshots, Director cameras, curated logos and the movable menu are
retained. Runtime behavior matches the registry-only test's 0.9.8 baseline.
Native DLLs, GPU programs, materials, lights and logos are byte-identical.
Package version metadata changes to 0.9.9, and source line endings are normalized;
those changes do not alter Lua behavior.

**Lighting: Not tested fully.** All existing feature limits still apply. See the
[0.9.8 notes](RELEASE-0.9.8.md) and [known issues](../../../docs/KNOWN-ISSUES.md).

## Complete downloads

Choose one **BSL v15+**, **MDL API 2**, or **LLL** package. Each ZIP includes its
runtime and required assets. GitHub offers all three; Nexus offers BSL and MDL.
MDL stays flat, without nested archives. No separate mod asset download or Link
addon is required.

Replace the previous Photo Mode package, deploy the included assets and restart
normally. Keep one Photo Mode runtime active. Preserve settings, bindings,
camera/lighting presets and screenshots. Shader packs that share the registry
still require a properly merged deployment.
