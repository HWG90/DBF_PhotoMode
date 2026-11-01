# War Journalist 1.3.4 — Defender helper update and Center auto-focus fix

Stop the action. Find your angle. Build the shot.

**A HUGE THANK YOU to everyone sharing photos, testing builds and reporting bugs.** Thanks to **JuanHalodiver** for reporting the Windows Defender warning. Keep the shots coming!

1.3.4 changes the small helper that War Journalist starts on Windows and fixes Center auto-focus at 4K. Everything else is the same as 1.3.3. **Boot Mod Loader is the only supported loader right now.** A Lite version for Chef's Shared Loader is planned, and getting whitelisted could let it do more. Neither is guaranteed.

## Why

Windows Defender quarantined the 1.3.3 helper (`wjl_steam_service.exe`) for one player. It's a false alarm: Defender was guessing about a brand-new file with no details on it. Without the helper, Photo Mode still opens, but you lose the keyboard and mouse lock, PNG screenshots and scene effects.

## Changed

- **The helper has a new name:** `war_journalist_helper.exe`. The old `wjl_steam_service.exe` is deleted when the game starts.
- **The helper says what it is.** Its file details now show War Journalist, HWG90 and a version number.
- **One helper file across game updates.** Until now, every game update meant a brand-new helper file. Now the mod tells the helper which game version to expect, so the same file keeps working and Windows doesn't see a new, unknown file after every game update.
- **No hidden files.** The helper no longer hides the small files it makes while saving a screenshot. They're still deleted when it closes.
- **Center auto-focus works at 4K.** Before, it could turn itself off to avoid stutter, as it did at 4K. Now a Helldiver in the middle of the screen stays in focus as you move, and scenery comes into focus when the camera stops. No stutter.

Windows may still warn about the new file until Microsoft has reviewed it. If Defender flags it, please tell me and include the name it shows.

All the known bugs from 1.3.0 are still there: the cape sometimes comes loose, picking a subject sometimes fails, some Hide options miss things, AI control is gone for now, and depth shaders don't work (Native DoF does). See the [known issues](https://github.com/HWG90/DBF_PhotoMode/blob/main/docs/KNOWN-ISSUES.md).

## Install

Import the **BML ZIP** into HD2 Arsenal. Enable War Journalist and Assets with [Boot Mod Loader](https://www.nexusmods.com/helldivers2/mods/17754), Deploy with the game closed, then start the game. It replaces 1.3.3, and your settings, presets and screenshots are kept. Run only one copy of War Journalist. The helper is included and starts on its own. You need the 29 October game update.

## Tested

- Tested in game on Linux (Proton) with Boot Mod Loader, including Center auto-focus at 4K.
- Not tested on Windows yet. Please let me know how it goes, and whether Defender says anything.

## Reporting bugs

Send these files, with anything private removed:

- `%APPDATA%\Arrowhead\Helldivers2\boot_mod_loader.log`
- `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log`
- `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`
