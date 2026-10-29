# War Journalist 1.3.3 — Game update, Saved Shots and Follow cameras

Stop the action. Find your angle. Build the shot.

**A HUGE THANK YOU to everyone sharing photos, testing builds and reporting bugs.** Special thanks to **Scarpheon, Muchacho, JuanHalodiver and jager** of the Helldivers Modding Discord for bug testing. Your logs and reports found these. Keep the shots coming!

1.3.3 gets War Journalist working with the 29 October game update, fixes Pose Stop and gets Saved Shots working. Everything else is the same as 1.3.2. **Boot Mod Loader is the only supported loader right now.** A Lite version for Chef's Shared Loader is planned, and getting whitelisted could let it do more. Neither is guaranteed.

## Fixed

- **Works with the 29 October game update.** After the update, 1.3.2 lost its keyboard and mouse lock, PNG screenshots and scene effects. They're back.
- **Pose Stop works again.** In 1.3.2, stopping a pose could leave your Helldiver stuck in it until you restarted the game.
- **Steam's Ctrl+F11 recording works in Photo Mode.** Handycam used F11 and blocked it, so Handycam is now on **Page Down**. If you had Handycam on F11, it moves to Page Down once. A key you picked yourself stays.
- **The menu stays blurred** when Exposure or other scene options are on. Your screenshots still get the full effect.
- **Saved Shots work.** Saving used to say "Local player unavailable". Shots now stick to your Helldiver's head, chest or hips, so a shot saved on your face stays on your face when you turn. Shots saved in older versions still load.
- **Freeze holds a running Helldiver.** The game used to pull them out of Freeze. A brief flicker can still happen.
- **Hide carried weapons hides the slung primary while frozen.**
- **Hide Torso and Hide Helmet work on more armours.** Some chest pieces were missed, or hidden along with the helmet. Sleeves and waist pieces now stay visible in first person.
- **The first pose plays cleanly.** Your Helldiver resets before the pose starts, so the cape follows.

## New

- **The camera comes back where you left it.** Close Photo Mode, reopen it, and the camera is back in the same spot next to your Helldiver. A saved camera position still comes first. Turn it off under Camera > Saved camera. Handycam and Cinema shots aren't remembered.
- **Follow player cameras.** Two new Action camera modes. **Follow player - Pivot** stays where you put it and turns to keep your Helldiver in frame. **Follow player - Pin** moves along with your Helldiver.

The known bugs from 1.3.0 are still there: the cape sometimes comes loose, picking a subject sometimes fails, some Hide options miss things, AI control is gone for now, and depth shaders don't work (Native DoF does). See the [known issues](https://github.com/HWG90/DBF_PhotoMode/blob/main/docs/KNOWN-ISSUES.md).

## Install

Import the **BML ZIP** into HD2 Arsenal. Enable War Journalist and Assets with [Boot Mod Loader](https://www.nexusmods.com/helldivers2/mods/17754), Deploy with the game closed, then start the game. It replaces 1.3.2, and your settings, presets and screenshots are kept. Run only one copy of War Journalist. The helper (WJL) is included and starts on its own. You need the 29 October game update.

## Tested

- Tested in game on Linux (Proton) with Boot Mod Loader, including a fresh start from this exact ZIP. Everything above was checked except the next point.
- Not checked in game yet: the Follow player cameras, the cape after changing armour, and sleeves and waist pieces in first person.
- Not tested on Windows yet. Please let me know how it goes.

## Reporting bugs

Send these files, with anything private removed:

- `%APPDATA%\Arrowhead\Helldivers2\boot_mod_loader.log`
- `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log`
- `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`
