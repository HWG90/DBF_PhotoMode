# War Journalist 1.3.1 — Windows input fix

Fixes for Windows players on 1.3.0. Everything else in 1.3.0 is unchanged; read the [1.3.0 notes](RELEASE-1.3.0.md) for features and limitations.

## Fixed

- **Photo Mode flashing and closing on Windows.** The panel only stayed up while the Photo Mode key was held, flickered, then closed with "Photo input keeps failing". WJL reserves Photo Mode's keys with every Ctrl/Shift/Alt combination. If any one of those shortcuts already belonged to another program, the whole keyboard reservation failed. GPU overlays, recorders and chat apps commonly own such shortcuts, for example AMD Software's Alt+R and Ctrl+Shift shortcuts. WJL now leaves a shortcut another program owns with that program and reserves everything else. That shortcut still never reaches the game. Any other reservation failure still stops input capture, as before.
- **Panel buttons and Handycam did nothing.** The same failure swallowed clicks, so Begin action shot and other buttons did not respond. If Handycam (F11 or Begin action shot) cannot start, the panel now says why, and the reason is written to `war_journalist_lua51.log`.
- `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log` now names the shortcuts that were left to other programs.

## Testing scope

The WJL helper was rebuilt with the same Visual Studio 2022 compiler and Windows SDK as 1.3.0. Its native keyboard, file, pointer and screenshot-job fixtures pass as Windows programs, including new cases for shortcuts owned by other programs. All Lua 5.1 fixtures pass. The 1.3.0 helper rebuilt from unchanged sources matched the shipped helper's code byte for byte. **Not yet tested in game on a PC with a conflicting shortcut.**

## Reporting

Please include both logs: `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log` and `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`. Remove private information before sharing them.
