![War Journalist](docs/artwork/war-journalist-0.9.7-cover.png)

# War Journalist 1.3.0

Photo Mode for Helldivers 2: compose shots with a free camera, lighting,
subject poses, camera paths and first-person Handycam.

**1.3.0 is in development.** Existing `1.3.0-bml.1` downloads are earlier test
builds. This source update does not publish a new release.

## Current runtime

The Lua 5.1 rewrite targets [Boot Mod Loader](https://github.com/pat-pat-patrick/boot-mod-loader). The Windows WJL helper starts
automatically and provides keyboard/mouse isolation while Photo Mode owns input.
The source includes the camera and menu improvements, native lens controls,
subject selection, independent visibility options, screenshots, Freeze/Resume,
slow motion, lighting, and Handycam ADS handoffs.

- The menu displays your game's Toggle HUD binding and warns if it is unbound.
  That key remains available while the Photo menu or frozen camera owns input.
- Apply Pose resets the previous pose first. Changing an already-held pose resets
  and applies the new selection automatically.
- Retained menu geometry, cached font metrics and event-driven state changes keep
  unchanged controls idle. Camera and cleanup ownership checks remain mandatory.

See the [1.3.0 changelog](docs/RELEASE-1.3.0.md) and
[known issues](docs/KNOWN-ISSUES.md) for supported behavior and testing limits.

## Current limitations

Subject selection and complete equipment hiding still need broader coverage.
Cape detachment and rare ragdoll issues remain. Hoverpack pause uses a near-zero
fallback. Handycam body turning, aim parallax, and drifting native world HUD
markers remain unresolved. Automatic native HUD hiding is unavailable on Windows;
use the game's own Toggle HUD binding. Enemy AI controls are unavailable.
Depth shaders and numeric shader DoF remain disabled pending visual validation.

## Chef preview

The separate [Chef Shared Loader preview](docs/CHEF-LOADER-PORT.md) remains under
active development in `freecam/chef/`. It has its own capability limits and is not
a replacement for the current BML version.

## Development

See [BUILD.md](BUILD.md) for source checks and build entrypoints. Runtime source,
fixtures and builders live in `freecam/` and `tools/`. Local packages and test
output belong under `dist/` and are excluded from Git.

Defunct BSL, MDL and earlier LLL entrypoints, release tooling and historical
records are retained in [archive/](archive/README.md). Shared models still used
by the current runtime or fixtures remain in the active source tree.

Artwork credits, third-party licenses and asset provenance remain with their
respective source files and manifests.
