# Known issues — War Journalist 1.4.0

1.4.0 is one download for both Boot Mod Loader and Chef's Shared Loader 1.4.0 or newer. It adds bone posing and saved poses, renames the Windows helper to `war_journalist_helper.exe`, and Center auto-focus works as intended now ([1.4.0 notes](RELEASE-1.4.0.md)). 1.3.3 works with the 29 October 2026 game update and fixes Pose Stop, Saved Shots and Steam's Ctrl+F11 ([1.3.3 notes](RELEASE-1.3.3.md)). 1.3.2 fixed the game waiting at startup, brought back PNG screenshots on Windows, and made first-person hiding, Handycam and Full Hide work with any armour ([1.3.2 notes](RELEASE-1.3.2.md)). 1.3.0 started a full rewrite of War Journalist in the game's own Lua.

- **The cape sometimes comes loose**, mostly around Freeze, ragdolls and pose changes.
- **Picking a subject sometimes fails**, both automatic picking and clicking.
- **Some Hide options miss things.** Holstered weapons, scopes, magazines, backpack and support weapon parts and other gear can stay visible.
- **AI control is gone for now.** Passive, Dummy and no-aggro aren't available.
- A frozen ragdoll can spin now and then.
- Freezing someone on a hoverpack isn't perfect, and pressing Resume has launched people into the air.
- Depth shaders don't work. Inverted depth, Thermal depth, Depth contours, Depth fog and Shader DoF are removed from the menu. Use **Native camera DoF**; focus and aperture work.
- On Windows, War Journalist can't hide the HUD for you. Use the game's own Toggle HUD key (tested with `/`).
- Handycam around aiming down sights needs more testing. The camera can clip or miss your framing when it comes back, aim can look slightly off, and turning while walking backwards or sideways isn't fixed. (Fixed after 1.3.3: aiming down sights was sometimes missed and the Handycam stayed beside the raised weapon, because the game dropped the click that started the check; the Handycam now also steps aside when the camera itself shows you're aiming, no click needed.)
- A Helldiver frozen while running can flicker for a moment.
- Bone posing works on your own Helldiver, after Freeze Action. A pose can vanish if you froze your Helldiver mid-stride. While your edits are kept, Refresh and Select in the Subject tab are locked; Reset pose unlocks them and clears the edits.
- **On Chef's Shared Loader there is no helper**, because Chef doesn't let mods start programs. Your keys still reach the game while Photo Mode is open (the camera moves with the arrow keys), and screenshots are DDS files instead of PNG. Double-click focus and Center auto-focus need Chef 1.5.1 or newer, and War Journalist stays off on Chef older than 1.4.0.
- Center auto-focus can focus on a Helldiver hidden behind something in the middle of the screen.
- Hide Cape can miss a modded cape. One report says opening Photo Mode from first person showed a headless body lying down; if you can make it happen, please tell me how.
- Not checked in game yet: the Follow player cameras, and the cape after changing armour.
- Lighting, outfits and gear, respawns and scene changes need more testing. Only a few armour sets were tried. HDR screenshots are saved as PNG, and their colours were only checked on one HDR screen.
- Default movement keys match your keyboard layout only while WJL is running. Keys you set earlier are kept. Only a US keyboard was checked.
- Windows Defender quarantined the 1.3.3 helper for one player. That was a false alarm, and 1.4.0's helper is easier for Windows to recognise. Windows may still warn about it until Microsoft has reviewed it; if it does, please tell me what it says.
- On Windows, if another program already uses a shortcut (for example a GPU overlay's Alt+R), that program keeps it and Photo Mode ignores that key combination.

Reporting bugs: tell me your loader and its version, and send the logs from `%APPDATA%\Arrowhead\Helldivers2\`, with anything private removed. Boot Mod Loader: `boot_mod_loader.log`, `war_journalist_lua51.log` and `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`. Chef's Shared Loader: `chef_loader.log` and `war_journalist_chef.log`. The [1.3.0 changelog](RELEASE-1.3.0.md) lists everything that changed in the rewrite.
