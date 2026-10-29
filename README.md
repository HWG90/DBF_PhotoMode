![War Journalist](docs/artwork/war-journalist-0.9.7-cover.png)

# War Journalist 1.3.3

Photo Mode for Helldivers 2: set up shots with a free camera, lighting,
poses, camera paths and a first-person Handycam.

**[Download War Journalist 1.3.3 for Boot Mod Loader](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.3).** This is still the first pass of a full rewrite, so not everything from the old version is back yet. Import the ZIP into HD2 Arsenal, enable War Journalist and Assets, Deploy with the game closed, then start the game. Nothing else to install.

**New in 1.3.3:** works with the 29 October 2026 game update, Pose Stop works again, Handycam is now on Page Down so Steam's Ctrl+F11 recording works, the menu stays blurred with scene options on, Saved Shots work and stick to your Helldiver, the camera comes back where you left it, new Follow player - Pivot and Pin cameras, Freeze holds a running Helldiver, and Hide Torso, Hide Helmet and Hide carried weapons work on more armours. See the [1.3.3 notes](docs/RELEASE-1.3.3.md).

## What's in it

War Journalist runs on [Boot Mod Loader](https://github.com/pat-pat-patrick/boot-mod-loader). On Windows, the included helper (WJL) starts on its own and stops your keys and mouse from moving your Helldiver while Photo Mode is open.
You get the free camera and menu, lens controls, subject picking, separate Hide options, screenshots, Freeze and Resume, slow motion, lighting and Handycam.

- The menu shows your game's Toggle HUD key, and warns you if it isn't set.
  That key still works while the Photo menu or a frozen camera is open.
- Apply Pose resets the last pose first. Picking a different pose while one is
  playing switches to it straight away.

See the [1.3.0 changelog](docs/RELEASE-1.3.0.md) and the
[known issues](docs/KNOWN-ISSUES.md) for what works and what still needs testing.

## Known limits

Subject picking and hiding every piece of gear still need work.
The cape can come loose, and ragdolls can act up now and then. Freezing someone on a
hoverpack isn't perfect. Handycam turning and aim can be slightly off, and the game's
own map markers can drift. On Windows, War Journalist can't hide the HUD for you;
use the game's own Toggle HUD key. AI control is gone for now.
Native camera DoF works, including focus and aperture. Inverted depth, Thermal depth, Depth contours, Depth fog and Shader DoF are removed because depth shaders don't work right now. Menu options that can't be used are hidden.

## Chef's Shared Loader

Boot Mod Loader is the only supported loader right now. A Lite version for Chef's Shared Loader is planned, and getting whitelisted could let it do more. Neither is guaranteed.

## Development

See [BUILD.md](BUILD.md) for source checks and build entrypoints. Runtime source,
fixtures and builders live in `freecam/` and `tools/`. Local packages and test
output belong under `dist/` and are excluded from Git.

Defunct BSL, MDL and earlier LLL entrypoints, release tooling and historical
records are retained in [archive/](archive/README.md). Shared models still used
by the current runtime or fixtures remain in the active source tree.

Artwork credits, third-party licenses and asset provenance remain with their
respective source files and manifests.
