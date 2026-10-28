# War Journalist 1.3.2 — startup fix and PNG screenshots

Stop the action. Find your angle. Build the shot.

Fixes the game stopping on a black screen while it starts with War Journalist enabled, and brings back PNG screenshots on Windows. Everything else in 1.3.1 is unchanged; read the [1.3.1 notes](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.1) and the [1.3.0 notes](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.0) for features and limitations. **Boot Mod Loader is the only supported loader at the moment.**

## Fixed

- **The game no longer waits for WJL while it starts.** 1.3.0 and 1.3.1 started WJL, the bundled input helper, while the game was starting, and the game waited for it. On some Windows PCs that wait took several seconds or never ended. The game sat on a black screen, then closed or had to be closed. A Boot Mod Loader log from one such PC showed 15 of 20 starts stopping inside that wait, and none with War Journalist disabled. Antivirus checking a new, unsigned program is one known cause of such a wait. The game now starts WJL and carries on at once. Photo Mode becomes available as soon as WJL answers, normally well under a second later. If WJL refuses to run or has not answered after 90 seconds, Photo Mode starts without it, and `war_journalist_lua51.log` says why.
- **No hidden dialogs.** 1.3.1 started WJL through `start`. When the WJL program was missing or blocked, `start` showed a dialog that could sit behind the game. `cmd.exe` now runs WJL directly, so the same problem only writes an error to the log.
- **PNG screenshots on Windows again.** 1.3.0 and 1.3.1 saved Windows screenshots as the game engine's raw DDS files, which most photo viewers cannot open. The engine still writes the DDS, which works on every PC. WJL now converts it to a PNG outside the game, using the converter War Journalist 0.9.x used, for SDR and HDR10 alike. HDR shots keep their DDS beside the PNG; SDR shots keep only the PNG. If a shot cannot be converted, its DDS is saved instead and the log says why. Screenshots go to the same folder as before (normally `Pictures`).
- **Toggle HUD binding found in a second Steam library.** Photo Mode reads the game's Toggle HUD key from Steam's own folder. It looked for that folder only around the game, so with Helldivers 2 in a second library (for example `D:\SteamLibrary`, or any library under Proton) the menu said "Could not read the game's Toggle HUD binding." It now also tries the Steam folder Proton names, and Steam's default folder on Windows.
- **POV hiding, Handycam and Full Hide work with any armour.** These features recognised only the armour set they were first tested with; with any other set they stopped with "POV hiding is not yet available for this outfit". War Journalist now finds the armour pieces attached to the selected Helldiver's skeleton and groups them by the bones they follow: helmet, torso, cape, and arms and legs. The first tested set still uses its checked list. The log names the pieces found.
- **Exposure, contrast and saturation on modded installs.** These sliders need War Journalist's scene effects, which start only after WJL confirms the game's renderer is unmodified. That check gave up past 128 patch files or 8,192 patch entries, so large mod setups lost the sliders (and every scene effect) even when no mod touched the renderer. It now checks up to 4,096 patch files and 4 million entries, and still refuses any patch that replaces the renderer.
- **All hiding in one place.** Hide helmet, Hide torso and Hide cape moved from Director to Subject > Visibility, beside Hide entire player, armour and weapons. Director keeps Handycam's own settings. Handycam always hides the helmet while it is attached.
- **One WJL file.** WJL is now always `wjl_steam_service.exe` in `%APPDATA%\Arrowhead\Helldivers2`. Its bytes are checked before every start, and a copy from another release is replaced, never run. Earlier releases named each copy after its hash and left them behind. War Journalist removes those, and 1.3.0's `wjl_startup.log`.

All 1.3.0 known issues still apply: occasional cape detachment, intermittent subject selection, incomplete Hide options, no AI control, and no depth shaders (Native DoF works). See [known issues](https://github.com/HWG90/DBF_PhotoMode/blob/v1.3.2/docs/KNOWN-ISSUES.md).

## Install and upgrade

Import the complete **BML ZIP** into HD2 Arsenal, enable War Journalist and Assets with [Boot Mod Loader](https://www.nexusmods.com/helldivers2/mods/17754), Deploy with the game closed, then launch normally. It replaces 1.3.1 in place; settings, presets and screenshots are kept. Run one War Journalist at a time. WJL is bundled and starts automatically.

## Testing scope

- **Not yet tested in game.** Live tests on Linux/Proton and native Windows are pending. Under Proton, screenshots take the same DDS-to-PNG path as on Windows; the Linux capture worker is used only when WJL is not connected.
- Isolated Lua 5.1 fixtures cover the new startup:
  - the launcher is started and never waited on;
  - WJL is looked for once a frame and connected when it answers;
  - a refusal is reported within a second;
  - WJL not answering ends after 90 seconds;
  - the game never closes the launcher before WJL answers.
- Fixtures for screenshots: WJL's reply format; the DDS written into WJL's folder, converted and moved; SDR DDS removed, HDR10 DDS kept; the DDS kept when WJL refuses, fails or is cancelled; never replacing a file.
- WJL was rebuilt with the same Visual Studio 2022 compiler and Windows SDK, warnings as errors, and its native fixtures pass. Under Wine, the start-up test now sends real SDR and HDR10 DDS files through WJL's screenshot job. Every PNG pixel matched the 0.9.x converter's math.
- The package check runs the archive as Boot Mod Loader does, twice:
  - with a WJL that refuses at once: Photo Mode started on the first frame, with DDS screenshots, and the launcher was never waited on;
  - with a WJL that answers a few frames later: Photo Mode waited for it, then selected WJL PNG screenshots.
- A start-up test runs the exact launcher under Wine against the real game executable. It covers readiness, game-root discovery, the renderer check, refusal of a different game build, and a WJL program removed after it was written (the launcher returns at once). A folder name with spaces, parentheses and `&` was also checked.

## Reporting

Please include `%APPDATA%\Arrowhead\Helldivers2\boot_mod_loader.log`, `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log` and `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`. Remove private information before sharing them.
