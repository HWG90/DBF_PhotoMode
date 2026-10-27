# War Journalist — Chef preview 5

Development prerelease for **Chef Shared Loader 1.2.3+ (API 3)**, reviewed against
Chef 1.2.4. Package version: **0.5.0-chef-preview.5**.

This is the Chef rewrite compared against War Journalist's 1.3.0 Steam workflows.
It is not full feature parity. **In-game behavior, visuals and performance have
not been verified in Chef.** Shader effects and AI controls are excluded.

## Included

- Freecam with rebindable controls, optional mouse look, smoothing, movement lock,
  wheel speed, world-up movement, roll/zoom rates, focal shortcuts and portrait tilt.
- Solo Freeze/slow motion, placed and path Cinema, editable camera paths,
  five scene bookmarks and five persistent camera presets.
- Three owned point/spot lights, color controls, markers and dragging, lighting
  rigs, five saved setups, same-scene restoration and edits at existing anchors.
- Frames, guides, tint/vignette/grain overlays, curated logos, a movable legend
  and an external screenshot view that hides WJ annotations while keeping artwork.
- Native bloom and native DoF switches. DoF uses the game's focus.
- Experimental selected-subject pose controls with 213 catalogue entries,
  restricted to the supported rig and disabled by default.
- Optional P/Backslash gameplay shortcuts and an option to retain the chosen
  slow-motion rate after manually closing the camera. Both start off.

Read the [feature matrix](https://github.com/HWG90/DBF_PhotoMode/blob/v0.5.0-chef-preview.5/docs/CHEF-FEATURE-MATRIX.md)
for individual feature status and restrictions. A [copyable BBCode version](https://github.com/HWG90/DBF_PhotoMode/blob/v0.5.0-chef-preview.5/docs/CHEF-FEATURE-MATRIX.bbcode)
is also included as a release asset.

## Install for testing

1. Install [Chef Shared Loader](https://github.com/Th3chef/Chef-Shared-Loader), version 1.2.3 or newer.
2. Import **War-Journalist-0.5.0-chef-preview.5.zip** into Arsenal/HD2 Mod Manager.
3. Enable its core with Chef, deploy through the manager and restart the game.
4. Open Chef's menu (F9 by default), select **War Journalist (Chef preview)** and
   enable **Photo camera (experimental)**. Close the menu after camera discovery.

Run only one War Journalist runtime. The ZIP contains the addon and its owned
light resource; it does not include Chef or replace the loader's boot resource.
See the bundled README for controls and cleanup/recovery instructions.

## Known limits

- Chef does not capture gameplay input; native chat, menus and gameplay can react
  to the same keys. Optional gameplay shortcuts suppress input only for Chef's menu.
- Time controls are for solo testing. They check visible peers, cannot observe
  earlier joining stages, and cannot read another mod's previous time multiplier.
  Avoid combining time mods. Cleanup normally requests 1x.
- Light range is 8 m by default; other ranges require native getter/readback support.
  Lighting and pose output remain visually unverified.
- WJ PNG capture, game HUD/subject/equipment hiding, Handycam/player follow,
  player-relative anchors, numeric DoF/autofocus, cape pose adaptation and
  frozen-ragdoll protections are unavailable. Use an external screenshot key.
- Shader effects and AI/passive/enemy controls are not included.

## Validation

- All **18 isolated Lua 5.1 source suites** passed.
- All **11 Chef suites** passed again using Lua decoded from the actual package.
- ZIP integrity, exact payload scope, per-file checksums, Lua compilation and
  source/package identity passed. Provenance hashes match the published Git bytes.
- Independent archive review confirmed two resources, canonical repacking and
  rejection of five malformed payload variants.
- These checks use mocked engine calls. Installation, loader acknowledgement,
  visible gameplay and deployed performance acceptance remain pending.

The package's provenance records its build-time state; this publication does not
change those embedded bytes. The SHA-256 of the ZIP is:

```text
124bff925564fbbf410f79eff5b90812211e29d63995b92218421f434422b0e5
```

`RELEASE-SHA256SUMS.txt` covers the ZIP and the two feature-matrix assets.

Source and build instructions are in the tagged
[Chef port documentation](https://github.com/HWG90/DBF_PhotoMode/blob/v0.5.0-chef-preview.5/docs/CHEF-LOADER-PORT.md).
Artwork attribution and Chef archive-code licensing are included in the package.
