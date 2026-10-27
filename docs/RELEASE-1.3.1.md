# War Journalist 1.3.1 — Windows and Proton input fix

Stop the action. Find your angle. Build the shot.

**A HUGE THANK YOU to everyone sharing photos, testing builds and reporting bugs.** Your reports from Windows tracked this one down fast. Keep the shots coming!

Fixes for Windows players on 1.3.0. Everything else in 1.3.0 is unchanged; read the [1.3.0 notes](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.0) for features and limitations. **Boot Mod Loader is the only supported loader at the moment.** A Lite version for Chef's Shared Loader is planned; whitelist approval may allow fuller compatibility. Neither is guaranteed.

## Fixed

- **Photo Mode flashing and closing on Windows.** The panel only stayed up while the Photo Mode key was held, flickered, then closed with "Photo input keeps failing". WJL reserves Photo Mode's keys with every Ctrl/Shift/Alt combination. If any one of those shortcuts already belonged to another program, the whole keyboard reservation failed. GPU overlays, recorders and chat apps commonly own such shortcuts, for example AMD Software's Alt+R and Ctrl+Shift shortcuts. WJL now leaves a shortcut another program owns with that program and reserves everything else. That shortcut still never reaches the game. Any other reservation failure still stops input capture, as before.
- **Panel buttons and Handycam did nothing.** The same failure swallowed clicks, so Begin action shot and other buttons did not respond. If Handycam (F11 or Begin action shot) cannot start, the panel now says why, and the reason is written to `war_journalist_lua51.log`.
- **No PowerShell.** 1.3.0 started WJL through a PowerShell script. Proton has no PowerShell, so Photo Mode would not open there, and some Windows installs block it. The game now starts WJL with `cmd.exe`, which ships with Windows and Proton. WJL finds the game and checks the stock renderer itself, and is ready in well under a second.
- **Cursor stays in the game window.** While Photo Mode had the mouse, the cursor could leave the game window. WJL now keeps it inside the game's window while Photo Mode owns the pointer, puts the limit back after focus or mode changes, and removes only its own limit when Photo Mode closes or loses focus.
- **The Windows build follows Windows rules everywhere.** Under Boot Mod Loader, War Journalist no longer writes or loads in-game native DLLs (Windows refuses unsigned ones), including under Proton. A Proton run now takes the same paths a Windows player gets. Extras that only those DLLs provided under Proton are not part of this build.
- `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log` now names the shortcuts that were left to other programs, and says why WJL refused to start if it did.

All 1.3.0 known issues still apply: occasional cape detachment, intermittent subject selection, incomplete Hide options, no AI control, and no depth shaders (Native DoF works). See [known issues](https://github.com/HWG90/DBF_PhotoMode/blob/v1.3.1/docs/KNOWN-ISSUES.md).

## Install and upgrade

Import the complete **BML ZIP** into HD2 Arsenal, enable War Journalist and Assets with [Boot Mod Loader](https://www.nexusmods.com/helldivers2/mods/17754), Deploy with the game closed, then launch normally. It replaces 1.3.0 in place; settings, presets and screenshots are kept. Run one War Journalist at a time. WJL is bundled and starts automatically.

## Testing scope

- **Live on Linux/Proton, Boot Mod Loader:** the PowerShell-free build started WJL through `cmd.exe` and verified the stock renderer. Photo Mode opened and closed six times with keyboard capture acknowledged each time. With it open, WASD moved only the camera and clicks did not fire; normal controls returned on close. Under 1.3.0 the same install could not open Photo Mode ("Native keyboard isolation is required"). The cursor confinement and the no-DLL rule came after that run and still need a live pass.
- **Native Windows: not yet tested in game.** The shortcut fix targets the Windows reports; please test and report.
- The WJL helper was rebuilt with the same Visual Studio 2022 compiler and Windows SDK as 1.3.0. Its native keyboard, file, pointer and screenshot-job fixtures pass as Windows programs, including new cases for shortcuts owned by other programs. The 1.3.0 helper rebuilt from unchanged sources matched the shipped helper's code byte for byte.
- A start-up test runs the exact launcher through `_popen` under Wine against the real game executable. It covers readiness, game-root discovery, the renderer check (including a real installation, matching the old PowerShell check) and refusal of a different game build.
- All isolated Lua 5.1 fixtures pass. ZIP integrity, per-file checksums and normal-user startup checks pass.

## Reporting

Please include both logs: `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log` and `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`. Remove private information before sharing them.
