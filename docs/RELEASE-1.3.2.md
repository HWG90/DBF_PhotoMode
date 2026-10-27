# War Journalist 1.3.2 — startup fix and PNG screenshots

Stop the action. Find your angle. Build the shot.

Fixes the game stopping on a black screen while it starts with War Journalist enabled, and brings back PNG screenshots on Windows. Everything else in 1.3.1 is unchanged; read the [1.3.1 notes](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.1) and the [1.3.0 notes](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.0) for features and limitations. **Boot Mod Loader is the only supported loader at the moment.**

## Fixed

- **The game no longer waits for WJL while it starts.** 1.3.0 and 1.3.1 started WJL, the bundled input helper, while the game was starting, and the game waited for it. On some Windows PCs that wait took several seconds or never ended. The game sat on a black screen, then closed or had to be closed. A Boot Mod Loader log from one such PC showed 15 of 20 starts stopping inside that wait, and none with War Journalist disabled. Antivirus checking a new, unsigned program is one known cause of such a wait. The game now starts WJL and carries on at once. Photo Mode becomes available as soon as WJL answers, normally well under a second later. If WJL refuses to run or has not answered after 90 seconds, Photo Mode starts without it, and `war_journalist_lua51.log` says why.
- **No hidden dialogs.** 1.3.1 started WJL through `start`. When the WJL program was missing or blocked, `start` showed a dialog that could sit behind the game. `cmd.exe` now runs WJL directly, so the same problem only writes an error to the log.
- **PNG screenshots on Windows again.** 1.3.0 and 1.3.1 saved Windows screenshots as the game engine's raw DDS files, which most photo viewers cannot open. WJL now captures the game window and saves a PNG. The capture uses Windows Graphics Capture, outside the game, and needs Windows 10 version 1903 or later. It works on SDR displays only. With HDR on, or where Windows Graphics Capture is unavailable, screenshots stay DDS. A PNG failure that retrying won't fix, or two failures in a row, switches the rest of the session to DDS, and the log says why. Screenshots go to the same folder as before (normally `Pictures`).
- **Old WJL copies removed.** Each release that changed WJL left its own `wjl_steam_service_<id>.exe` in `%APPDATA%\Arrowhead\Helldivers2`. War Journalist now removes the copies from 1.3.0 and the 1.3.1 test builds, and 1.3.0's `wjl_startup.log`. WJL itself is unchanged from 1.3.1, so the same `wjl_steam_service_4249097cb43acbbe.exe` stays.

All 1.3.0 known issues still apply: occasional cape detachment, intermittent subject selection, incomplete Hide options, no AI control, and no depth shaders (Native DoF works). See [known issues](https://github.com/HWG90/DBF_PhotoMode/blob/v1.3.2/docs/KNOWN-ISSUES.md).

## Install and upgrade

Import the complete **BML ZIP** into HD2 Arsenal, enable War Journalist and Assets with [Boot Mod Loader](https://www.nexusmods.com/helldivers2/mods/17754), Deploy with the game closed, then launch normally. It replaces 1.3.1 in place; settings, presets and screenshots are kept. Run one War Journalist at a time. WJL is bundled and starts automatically.

## Testing scope

- **Not yet tested in game.** Live tests on Linux/Proton and native Windows are pending. PNG capture can only be checked on Windows: Proton has no Windows Graphics Capture, and on Linux the Linux capture worker makes the PNGs.
- Isolated Lua 5.1 fixtures cover the new startup:
  - the launcher is started and never waited on;
  - WJL is looked for once a frame and connected when it answers;
  - a refusal is reported within a second;
  - WJL not answering ends after 90 seconds;
  - the game never closes the launcher before WJL answers.
- Fixtures for screenshots: WJL's reply format, PNG by default, and DDS after an HDR start, a lasting refusal, or two failed PNGs in a row.
- The package check runs the archive as Boot Mod Loader does, twice:
  - with a WJL that refuses at once: Photo Mode started on the first frame, with DDS screenshots, and the launcher was never waited on;
  - with a WJL that answers a few frames later: Photo Mode waited for it, then selected PNG capture.
- A start-up test runs the exact launcher under Wine against the real game executable. It covers readiness, game-root discovery, the renderer check, refusal of a different game build, and a WJL program removed after it was written (the launcher returns at once). A folder name with spaces, parentheses and `&` was also checked.

## Reporting

Please include `%APPDATA%\Arrowhead\Helldivers2\boot_mod_loader.log`, `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log` and `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`. Remove private information before sharing them.
