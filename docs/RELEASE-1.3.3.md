# War Journalist 1.3.3 — Game update, Saved Shots and Follow cameras

Stop the action. Find your angle. Build the shot.

**A HUGE THANK YOU to everyone sharing photos, testing builds and reporting bugs.** Special thanks to **Scarpheon, Muchacho, JuanHalodiver and jager** of the Helldivers Modding Discord for bug testing; your logs and reports found these. Keep the shots coming!

Brings War Journalist up to the 29 October 2026 game update, fixes Pose Stop, and makes Saved Shots work under Boot Mod Loader. Everything else in 1.3.2 is unchanged; read the [1.3.2 notes](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.2) and the [1.3.0 notes](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v1.3.0) for features and limitations. **Boot Mod Loader is the only supported loader at the moment.** A Lite version for Chef's Shared Loader is planned; whitelist approval may allow fuller compatibility. Neither is guaranteed.

## Fixed

- **Works with the 29 October game update.** The update changed the game's executable, so 1.3.2's WJL refused to run ("installed game hashes do not match"). Photo Mode then started without keyboard isolation, cursor confinement, PNG screenshots or scene effects. WJL now accepts the updated game (build 26251122). The game's stock renderer is unchanged, and WJL still checks it before scene effects start.
- **Pose Stop restores your Helldiver.** In 1.3.2, playing a pose and pressing Stop could leave the Helldiver in the pose, and every later Stop or Recover was refused until the game restarted. The cape check compared an engine name that is only valid for a moment. It now compares the name's text.
- **Steam's Ctrl+F11 recording works in Photo Mode.** F11 was Handycam's key and WJL reserved it with every modifier, so Steam never saw Ctrl+F11. Handycam now defaults to **Page Down**, and WJL leaves F11 to the game. A saved F11 moves to Page Down once, in War Journalist's settings and in Boot Mod Loader's key settings. A key you chose or unbound stays.
- **The menu stays blurred with Exposure and other scene options on.** With any scene option set, the area behind the panel turned sharp. The scene grade now leaves out the panel and footer backdrops while the panel is shown. Screenshots are still fully graded.
- **Saved Shots work under Boot Mod Loader.** Save always said "Local player unavailable". Saved Shots now anchor on the selected Helldiver, including the one picked automatically, and on the nearest of its head, chest or hips. A shot saved on your face stays on your face when you turn. Shots saved by earlier versions still load.
- **A Helldiver frozen while running stays frozen.** The game put the body's animation back mid-freeze, and Freeze let go. Freeze now takes the body back and holds the pose until Resume. A brief flicker can remain while the game keeps trying.
- **Hide carried weapons hides the slung primary while frozen.** Freeze held the carry sockets (sling, pouch, support weapon) while the game kept moving the gear, so they drifted apart and the gear was not recognised. Freeze now leaves those sockets to the game.
- **Hide Torso and Hide Helmet on more armours.** Some armours build their chest shells on the whole rig, or with the same bones as the helmet, so Hide Torso missed them or Hide Helmet took them. Armour pieces are now sorted by the parts of the body their meshes are named for (chest, shoulders, head, pelvis, thighs, upper arms, cape), then by where they sit on the body, then by their bones. Sleeves without hands and waist pieces that reach the chest now count as body, so first-person views keep them.
- **Apply resets the pose first.** Applying the first pose resets the Helldiver, waits for the body to settle, then applies, so the cape follows the new pose. Changing a pose that is already held happens at once.

## New

- **The camera returns where you left it.** Closing Photo Mode remembers the camera relative to the selected Helldiver for this game session, and reopening returns there with the same field of view and roll. A saved camera position still takes priority. Turn it off with Camera > Saved camera > "Reopen at the last camera, relative to the Helldiver". Handycam and Cinema shots are not remembered.
- **Follow player cameras.** Action camera mode has two new options. **Follow player - Pivot** keeps the camera where you placed it and turns it to follow the selected Helldiver, keeping your framing. **Follow player - Pin** keeps the camera's offset and direction and moves it with the Helldiver.

All 1.3.0 known issues still apply: occasional cape detachment, intermittent subject selection, incomplete Hide options, no AI control, and no depth shaders (Native DoF works). See [known issues](https://github.com/HWG90/DBF_PhotoMode/blob/v1.3.3/docs/KNOWN-ISSUES.md).

## Install and upgrade

Import the complete **BML ZIP** into HD2 Arsenal, enable War Journalist and Assets with [Boot Mod Loader](https://www.nexusmods.com/helldivers2/mods/17754), Deploy with the game closed, then launch normally. It replaces 1.3.2 in place; settings, presets and screenshots are kept. Run one War Journalist at a time. WJL is bundled and starts automatically. This version needs the 29 October 2026 game update (build 26251122).

## Testing scope

- **Live on Linux/Proton, Boot Mod Loader, game build 26251122**, with development builds of this release:
  - WJL started and verified the game and its renderer, and the keyboard lease worked;
  - Pose Stop restored the Helldiver;
  - Steam's Ctrl+F11 and Handycam on Page Down;
  - the menu blur with Exposure on, and a fully graded screenshot;
  - Saved Shots on the selected Helldiver, following the face, and the camera returning on reopen;
  - Freeze while running (a brief flicker remains);
  - the first pose's cape;
  - Hide carried weapons with the slung primary;
  - Hide Torso on several armours and Hide Helmet.
- **Not yet confirmed in game:** the Follow player cameras, the cape after an armour change, and the newest armour sorting (sleeves and waist pieces kept in first person).
- **Native Windows:** not tested in game for this release. Please report.
- The exact final ZIP's cold start is recorded in the publication record.
- Normal-user build: development reload is not included, and inventories and test activations are disabled. Unavailable menu controls are omitted.
- WJL was rebuilt with the same Visual Studio 2022 compiler and Windows SDK as 1.3.2. A start-up test runs it under Wine against the real updated game, including the renderer check, and its native fixtures pass.
- Isolated Lua 5.1 fixtures cover every change above, including rigid and skinned armour pieces, retired keys moving to Page Down, scratch engine names across frames, and the menu's graded cut-outs.

## Reporting

Please include `%APPDATA%\Arrowhead\Helldivers2\boot_mod_loader.log`, `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log` and `%LOCALAPPDATA%\WJL\Helldivers2\Steam\service.log`. Remove private information before sharing them.
