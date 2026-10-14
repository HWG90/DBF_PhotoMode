War Journalist 0.9.5 - Helldivers 2 Photo Mode

CHOOSE ONE LOADER PACKAGE
BSL (recommended): requires Bingus Shared Loader v15+ / API 1. Import the full
BSL ZIP into HD2 Arsenal, enable it alongside BSL, deploy, then restart normally.
The Addon folder contains the complete runtime and all required assets.

MDL: requires MDL API 2. Copy dbf_freecam into
%LOCALAPPDATA%/MDL/Helldivers2/Mods. Import this complete MDL ZIP into Arsenal,
enable and deploy its GameData assets, or install GameData manually as below.
Arsenal installs the assets only; copying dbf_freecam installs the MDL runtime.
Enable War Journalist in MDL and restart. No nested archive is required.

LLL: copy dbf_freecam into %LOCALAPPDATA%/LLL/Helldivers2/Mods. Deploy the
included Arsenal asset ZIP, then enable the addon and restart normally.
LLL downloads are hosted on GitHub; Nexus offers BSL and MDL.

All runtime, shader, material, light and logo resources are included in each
loader download. No separate asset download, MCM, DBF-HUD, ActionCam, or Link's
Link to Memory is required. MCM integration is optional. Disable older Photo
Mode runtimes and the original ActionCam; keep only one Photo Mode runtime.
Preserve saved settings, camera presets and Screenshots when upgrading.
Replace an older separate Photo asset package with the matching bundled assets.

MANUAL ASSET INSTALL
With the game closed, copy the patch triplets from Addon (BSL) or GameData
(MDL) into Helldivers 2/data. For each base, use the next unused patch_N and
use that same N for its CPU, .gpu_resources and .stream companions. Preserve
the 9ba626afa44a3aa3 and ee6b1ba7e22d71ed base names. Never replace a different
mod's patch. Other mods replacing the shader registry need a registration
merge; use a mod manager with merging support when combining them.
For LLL the same files are inside its bundled Arsenal asset ZIP's Assets folder.
For MDL, choose either Arsenal deployment or manual GameData installation,
not both. The complete MDL ZIP is the Arsenal asset installer.

CONTROLS (DEFAULTS; YOUR SAVED BINDINGS TAKE PRIORITY)
P: Photo Mode. Pause: screenshot (rebindable). Tab: camera/menu focus.
Camera: WASD move, Shift/Ctrl rise/descend, mousewheel speed, Q/E roll,
L lock camera, H hide controls. Menu: W/S rows, A/D values, Q/E tabs.
Enter edits a value; Enter or clicking away commits it, Escape cancels.
Right-click resets. Hold Shift while dragging for one-tenth slider sensitivity.
Focus distance steps: 0.01 m, or 0.001 m with Shift.
Double-click a subject outside the menu in menu focus to focus on it. Center
auto-focus continually follows center-screen depth. Manual edits override it.
Drag the title bar to move the menu. Resize with its corner grip. Position
and size survive restarts. The left-edge controls drawer has a movable tab.

LENS, DIRECTOR AND LIGHTING
Native camera has adjustable focus/aperture. Shader (preview) adds 32/64-sample
round/hex bokeh. Full-resolution scene effects and color grading can be used
alongside Shader DoF. WARMING UP SCENE means resources are still loading.
Director stores five camera positions/angles relative to the player; these
presets survive restarts. The separate temporary Save Camera action retains
a shot only within its configured radius and current scene/session.
Lighting supports up to three owned point/spot lights, intensity up to 10,000,
range up to 1,000 m, color, placement offsets, camera follow and location markers.
The dedicated mission light asset fix is included: Not tested fully. Lights
and subject visibility changes are cleaned up when leaving Photo Mode.

PAUSE AND CAPTURE
Pause and slow motion require a verified solo session. Freecam can still be
used in multiplayer. Guarded hoverpack pause neutralizes automatic thrust
before zero time, checks neutral hover controls, then restores thrust after resuming.
Entering and leaving Photo Mode preserves held gameplay inputs; it does not
send synthetic key or mouse-button releases. Held ADS remains available for posing.
Active-hover pause is refused with connected or unidentified controllers.
Losing input capture during guarded hover pause resumes the simulation first.
The reported hoverpack + melee pause/resume reproduction passed in development;
this is not a claim that every equipment combination is covered.
BSL PNGs: %LOCALAPPDATA%/DBF/PhotoMode/Screenshots.
MDL/LLL PNGs: dbf_freecam/Screenshots. The Pause shortcut uses the addon capture,
not Windows Print Screen. Ship UI may remain visible in some captures.

See RELEASE-NOTES.md and KNOWN-ISSUES.md for features and validation limits.
Camera foundation: ActionCam 2.3.1 by HuedPurple.
Bingus native UI/font reader: CowboyBingus (0BSD license included).
Selected native reader work: Link (MIT license included). Link's addon is not
required. Artwork remains property of its respective owners; original logo
sources and author attribution are bundled in assets/logos.
