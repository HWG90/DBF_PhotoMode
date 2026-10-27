# Known issues — 1.3.0 Lua rewrite

1.3.0 is the first pass of a total Lua 5.1 rewrite. Boot Mod Loader is the only supported loader. Chef Lite is planned; whitelist approval may permit fuller compatibility, with no approval or parity guarantee.

- **Cape detachment still occasionally happens**, particularly during Freeze, ragdolls and pose transitions.
- **New subject selection sometimes fails**, including automatic discovery and clicks. Session recovery is improved, not universally reliable.
- **Some Hide options do not work fully**: holstered weapons, scopes, magazines, backpack/support-weapon parts and other attachments can remain visible.
- **AI control is no longer possible in the current implementation.** Passive, Dummy and no-aggro are unavailable.
- Rare frozen-ragdoll spinning remains. Failed smooth-freeze and forced body/cape transform experiments were removed.
- Hover Freeze uses a near-zero fallback, not a thrust-only correction. Detection may include dropped packs; ragdoll/collision launching on Resume has been reported. Exact-zero hover safety is not established.
- Use **Native camera DoF**. Depth shaders currently do not work. Inverted depth, Thermal depth, Depth contours, Depth fog and Shader DoF/bokeh are removed from the current menu. Native focus/aperture work. Public scene effects stay disabled until visually verified.
- Automatic native HUD hiding is not restored on Windows. Use your game's Toggle HUD binding; the tester used `/`.
- Handycam ADS transitions need wider coverage; occasional camera-return/clipping and normal-aim parallax remain possible. Backward/strafe body turning and drifting native world HUD markers are not corrected.
- Lighting, outfits/equipment, respawns and scene changes need broader coverage. SDR is the qualified capture path; HDR capture is not promised.

The final 1.3.0 bundle is being prepared. Earlier `1.3.0-bml.1` assets do not contain every later fix. See the [full changelog](RELEASE-1.3.0.md) and [release protocol](../archive/research/docs/RELEASE-PROTOCOL-1.3.0.md). Historical issue text remains in Git history and older release notes.
