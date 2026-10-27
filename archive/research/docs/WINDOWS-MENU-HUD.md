# Photo menu HUD frame and native blur

The photo panel uses retained corner brackets, a small winged-skull badge and
header registration marks. No animations, texture uploads or input regions
were added by these decorations.

Native background blur uses the loaded
`content/ui/shared/material/gui_blur` material through `Gui.bitmap`. The
bitmap behind the main panel exactly matches that panel's rectangle; a second
bitmap matches the separate footer. The gap and surrounding game view stay
sharp. Moving/resizing the panel invalidates the same retained layout. Hidden
controls, capture and menu close retire the owned GUI primitives. Photographic
DoF, scene effects and saved settings are not changed.

The game's rect path did not apply the requested material and produced a white
fill during the first preview. That path was removed. Bitmap rendering was
checked first in a small test area, then visually verified across the screen,
and finally restricted to separate window/footer bounds at David's request.
The accepted scoped reload was 905a650a230e4b77bfcf335b3a41a265.

Tests cover bitmap material routing, positive/negative admission caching,
unchanged draw retention, separate exact bounds at multiple layouts, a clear
footer gap, and hiding the controls. The complete isolated fixture runner
passed. Native material lookup is cached per GUI session; no periodic material
probe or extra blur shader was added. The accepted in-game capture showed
115 FPS at 3840x2160; this is an observation, not a controlled benchmark.

Persisted in the game's startup archive and Arsenal store as
1.3.0-bml.1-portable.22.15-handycam.1-menu.1. Only photo_menu.lua and vendor/view.lua
were replaced in each archive. Existing differences in non-menu modules between
the game and stored package were preserved independently. Fresh-VM startup,
archive/module readback, ZIP and installed checksums passed; no actual game
restart was performed. Release artifact, receipts and rollback copies are under
`dist/releases/photo-menu-hud/persistent/`.
