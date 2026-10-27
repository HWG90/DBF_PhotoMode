# War Journalist 1.3.0-bml.1 — Boot Mod Loader testing build

**Testing pre-release for the current Lua 5.1 game (Helldivers 2 Steam build 26088801) under Boot Mod Loader.** It was developed and tested on Linux/Proton. Native Windows results are what this pre-release is for.

**A HUGE THANK YOU to everyone submitting photos, testing builds and reporting bugs.** Keep the shots coming!

### Download
| File | What it is |
|---|---|
| `War-Journalist-1.3.0-bml.1-BML.zip` | War Journalist (Lua 5.1) for Boot Mod Loader, with its assets. Import into HD2 Arsenal and enable it with [Boot Mod Loader](https://www.nexusmods.com/helldivers2/mods/17754). |
| `RELEASE-SHA256SUMS.txt` | SHA-256 of the ZIP. |

### What's new
- **Runs under Boot Mod Loader**, with no FFI.
  - Its keys appear in HD2 Mod Setting GUI under "War Journalist" and can also be set from the Photo panel.
  - Boot Mod Loader holds them back while the game has no focus or chat is open.
- **Mouse in the Photo panel:** a drawn pointer moves with the mouse, and clicks work. Camera look uses the engine's mouse.
- **Keys stay with Photo Mode:** while Photo Mode is open, its keys are reserved so they no longer move your Helldiver. This is LLL's key reservation, now running in-game. (Linux/Proton)
- **Clean ship screenshots:** the ship HUD is switched off while Photo Mode is open and in screenshots, using the game's own Toggle HUD state. It comes back when Photo Mode closes. (Linux/Proton)
- **Level start:** Photo Mode opens with a level horizon and Roll back at 0.
- **Screenshots:** where the War Journalist Linux capture worker runs, they are PNG. Elsewhere the engine writes the frame as DDS into LLL's Screenshots folder, your Pictures folder or the game's settings folder.
- **No more lock-out:** the "Enable Photo Mode" switch is gone. It could only be turned back on from the panel it closed.
- **Subject and Hover pause:** subject controls come on once the game has run their code, usually within the first minute. Hover pause says once that it is waiting for its code, which is ready after a Hover Pack has been used.

### Tested
- **Live on Linux/Proton, Boot Mod Loader 0.11.0:**
  - Startup and the key list in HD2 Mod Setting GUI.
  - Rebinding from the panel.
  - Mouse and panel clicks.
  - Subject select and pose.
  - PNG screenshots through the Linux worker.
  - Ship HUD gone in screenshots.
  - The key reservation coming up when Photo Mode opens.
- **Fixtures only:** the level start, the mission HUD and the engine DDS screenshot path.
- **Native Windows: not tested.** Please test it.

### Known limits
- **Native Windows refuses unsigned DLLs (error 577), and every native bridge in this package is unsigned.**
  - Expect no subject poses, no hover pause, no native lens and no HUD hiding there.
  - Keys are not reserved there either, so WASD moves your Helldiver too.
  - Screenshots use the engine DDS path, which is untested.
  - Please report what works, with your `%APPDATA%\Arrowhead\Helldivers2\war_journalist_lua51.log`.
- No Enemy behavior (Passive/Dummy): it needs FFI.
- This build logs HUD probe and native diagnostic lines for testing.
- Lighting: **Not tested fully**.
- The 1.2.1 BSL/MDL/LLL packages are for the previous game build and remain on GitHub.

### Install
1. Import the ZIP into HD2 Arsenal.
2. Enable it together with Boot Mod Loader.
3. Deploy, then restart the game normally.

Settings are kept. Run one War Journalist at a time: disable any LLL or LuaJIT build of War Journalist first.
