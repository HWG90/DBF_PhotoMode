# Known issues in 0.6 Preview

- Focus distance and aperture/f-stop have no working implementation in this release. Both sliders are disabled.
- Scene color/depth shader effects are disabled and not included.
- Exposure, saturation and contrast controls are unavailable.
- Native bloom/DoF toggles use the game's existing graphics. They do not provide custom focus or aperture.
- Built-in PNG capture may retain ship UI; HDR capture brightness can differ from the displayed image. Steam screenshots are an alternative.
- All 40 decorative shader overlays are included. They tint/pattern the image; they do not implement scene sampling or numeric DoF. Other shader packs that replace the default shader registry require merged registrations.

Camera controls, pause/slow motion, composition, menu controls and saved camera positions remain available. Pause and slow motion require a verified solo session.
