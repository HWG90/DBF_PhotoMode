# Known issues — War Journalist 1.3.3

1.3.3 works with the 29 October 2026 game update and fixes Pose Stop, Saved Shots and Steam's Ctrl+F11 ([1.3.3 notes](RELEASE-1.3.3.md)). 1.3.2 fixed the game waiting at startup, brought back PNG screenshots on Windows, and made first-person hiding, Handycam and Full Hide work with any armour ([1.3.2 notes](RELEASE-1.3.2.md)). 1.3.0 started a full rewrite of War Journalist in the game's own Lua. Boot Mod Loader is the only supported loader. A Lite version for Chef's Shared Loader is planned, and getting whitelisted could let it do more. Neither is guaranteed.

- **The cape sometimes comes loose**, mostly around Freeze, ragdolls and pose changes.
- **Picking a subject sometimes fails**, both automatic picking and clicking.
- **Some Hide options miss things.** Holstered weapons, scopes, magazines, backpack and support weapon parts and other gear can stay visible.
- **AI control is gone for now.** Passive, Dummy and no-aggro aren't available.
- A frozen ragdoll can spin now and then.
- Freezing someone on a hoverpack isn't perfect, and pressing Resume has launched people into the air.
- Depth shaders don't work. Inverted depth, Thermal depth, Depth contours, Depth fog and Shader DoF are removed from the menu. Use **Native camera DoF**; focus and aperture work.
- On Windows, War Journalist can't hide the HUD for you. Use the game's own Toggle HUD key (tested with `/`).
- Handycam around aiming down sights needs more testing. The camera can clip or miss your framing when it comes back, aim can look slightly off, and turning while walking backwards or sideways isn't fixed.
- A Helldiver frozen while running can flicker for a moment.
- Hide Cape can miss a modded cape. One report says opening Photo Mode from first person showed a headless body lying down; if you can make it happen, please tell me how.
- Not checked in game yet: the Follow player cameras, and the cape after changing armour.
- Lighting, outfits and gear, respawns and scene changes need more testing. Only a few armour sets were tried. HDR screenshots are saved as PNG, and their colours were only checked on one HDR screen.
- Default movement keys match your keyboard layout only while WJL is running. Keys you set earlier are kept. Only a US keyboard was checked.
- On Windows, if another program already uses a shortcut (for example a GPU overlay's Alt+R), that program keeps it and Photo Mode ignores that key combination.

Reporting bugs: send `%APPDATA%\Arrowhead\Helldivers2\boot_mod_loader.log`, `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log` and `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`, with anything private removed. The [1.3.0 changelog](RELEASE-1.3.0.md) lists everything that changed in the rewrite.
