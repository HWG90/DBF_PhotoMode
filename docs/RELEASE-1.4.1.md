# War Journalist 1.4.1 — Game update, All-Bones mode and Natural limits

Stop the action. Find your angle. Build the shot.

**A HUGE THANK YOU to everyone sharing photos, testing builds and reporting bugs.** Thanks to **aharen_1**, **Devist8er** and **oldtr** for the reports behind several of these fixes. Keep the shots coming!

**One download for both loaders.** The same ZIP works with **Boot Mod Loader** and with **Chef's Shared Loader** 1.4.0 or newer. There's no separate Chef version to pick: whichever loader you use, this is the only file you need.

1.4.1 works with the 11 November game update and makes bone posing easier: All-Bones mode shows every bone at once, and Natural limits keeps joints bending the way a body does.

## New

- **Works with the 11 November game update.** After that update, 1.4.0 lost its keyboard and mouse lock, PNG screenshots and scene effects.
- **All-Bones mode.** With your Helldiver frozen and selected, the Pose editor now starts with a ring on every bone, and the group under your mouse lights up. Click a ring to pick that bone and its group; click the scene away from the rings to see all bones again. Switch **All-Bones mode** off for the old one-group view.
- **Natural limits.** Bones now stay inside what the game's own poses do: knees bend one way only and elbows don't bend backwards. The sliders and drags stop at the limit. Switch **Natural limits** off for free movement. Cape and gear bones are always free.

## Fixed

- **Posing with a hover pack around.** Poses and the bone editor no longer refuse with "Freeze Action first" when someone in the mission has a hover pack.
- **Helldivers with holster mods can be posed.** Mods that move holsters (such as Diver Dock) no longer leave your Helldiver "follow only".
- **A weapon swap during a pose no longer freezes the game.** The bone the game moves is left to the game, and Resume and Close always get time moving again.
- **If a pose ever gets stuck,** Ctrl+Shift+F10 now lets it go and gets time moving again.
- **Smoothed mouse look** no longer spins the wrong way after a fast swipe.
- **Photo Mode says why** when it won't open, in a short banner, and the Subject tab says why no Helldiver can be posed.
- **Follow cameras** keep the nearest pin in crowded scenes.
- **A smaller download.**

## On Chef's Shared Loader: read this first

War Journalist on Chef is more limited than on Boot Mod Loader:

- **No helper.** Chef doesn't let mods start programs, so the helper that Boot Mod Loader uses can't run. That means:
  - **your keys still reach the game while Photo Mode is open**, which is why the camera moves with the arrow keys instead of W/A/S/D;
  - **screenshots are DDS files, not PNG.** They're saved in the game's settings folder (`%APPDATA%\Arrowhead\Helldivers2`). Open them with an image viewer that reads DDS, or convert them.
- **Double-click focus and Center auto-focus need Chef 1.5.1 or newer.** On older versions, use Manual focus.
- **War Journalist needs Chef 1.4.0 or newer.** On older versions it stays off.
- Keys: P opens Photo Mode, the arrow keys move the camera and the panel, and Shift with Left or Right changes tabs. Change keys in F9 > War Journalist or in the panel.

All the known bugs from 1.4.0 are still there: the cape sometimes comes loose, picking a subject sometimes fails, some Hide options miss things, AI control is gone for now, and depth shaders don't work (Native DoF does). See the [known issues](https://github.com/HWG90/DBF_PhotoMode/blob/main/docs/KNOWN-ISSUES.md).

## Install

Import the ZIP into HD2 Arsenal and make sure **War Journalist** is switched on. It's the same ZIP for [Boot Mod Loader](https://www.nexusmods.com/helldivers2/mods/17754) and [Chef's Shared Loader](https://www.nexusmods.com/helldivers2/mods/17760) 1.4.0 or newer. Deploy with the game closed, then start the game.

It replaces 1.4.0, and your keys, settings, presets, saved poses and screenshots are kept. Run only one copy of War Journalist. You need the 11 November game update. Boot Mod Loader 0.13.4 may say it wasn't made for this game version; War Journalist still starts with it.

Developed on Linux via Proton.

## Reporting bugs

Tell me your loader and its version, and send these files from `%APPDATA%\Arrowhead\Helldivers2\`, with anything private removed:

- Boot Mod Loader: `boot_mod_loader.log`, `war_journalist_lua51.log`, and `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`
- Chef's Shared Loader: `chef_loader.log` and `war_journalist_chef.log`
