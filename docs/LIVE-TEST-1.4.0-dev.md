# War Journalist 1.4.0-dev: live runs, 2026-11-02

One package (`tools/build_package.py`), one Arsenal entry (uuid 7020a1c8, profile "Lua5.1"),
Helldivers 2 Steam build 26251122 under Proton. Logs are in the prefix's
`AppData/Roaming/Arrowhead/Helldivers2/`. Times are local.

| Build | Commit | Package SHA-256 | Stamp under Photo Mode |
|---|---|---|---|
| 1.4.0-dev.1 | f3be411 | f7211cfd0f4fce0ca82c6d0185f5f5b8d4f3b46c90b1b164d115a8d938715bce | 20261102.1338-f3be411 |
| 1.4.0-dev.2 | 70eb156 | 1ab97a385b40de9007bbe7fbf14ba4aa9a41adb3c96a00c971da7f80541f5700 | 20261102.1703-70eb156 |
| 1.4.0-dev.3 | d035e77 | 4ac81462d04727105468c0ba7d52a299824c96c8a4149b409e8cd8158ed2d7dc | 20261102.1717-d035e77 |

## Run 1: Boot Mod Loader 0.13.4 alone (dev.1), 11:50

`boot_mod_loader.log`:

    11:50:43 mods/goose/war_journalist (patch_0, 3445006 bytes): loaded in 110 ms
    11:50:43 settings window: mbm_war_journalist_lua51_options.json is no mod's this game: renamed .stale (its settings stay)
    11:50:43 ModBindingsMenu: War Journalist (mods/goose/war_journalist), 16 key(s) -> mbm_war_journalist_options.json

`war_journalist_lua51.log`:

    11:50:42 Keys carried over from mbm_war_journalist_lua51_settings.txt
    11:50:43 WJL helper ready 0.3 s after launch
    11:50:43 WJL PNG screenshots selected (engine DDS converted by WJL): C:/users/steamuser/AppData/Local/LLL/Helldivers2/Screenshots
    11:50:43 Photo Mode started on Boot Mod Loader
    11:51:09 Screenshot saved: …/Screenshots/War-Journalist-20261102-115107-24266318-1.png

`mbm_war_journalist_settings.txt` is byte-identical to the old `mbm_war_journalist_lua51_settings.txt`.
The user played it and asked for one change: bone edits should survive closing Photo Mode.

## Bone edits survive closing Photo Mode (dev.2, then dev.3), 12:06–12:28

- dev.2 (70eb156): edits came back on every reopen. After quick close/reopen cycles,
  discovery refused every open from 12:08:07 (`Subject discovery detail: Retire owned
  subjects before refreshing`). Cause: a body frozen while moving gets its own bone mode back
  from the game, which repaints the original pose under the held edit; the close found
  everything foreign, wrote and committed nothing, and the native adapter kept its write
  ledger and cape for the session. Reproduced offline with the real adapter and controller.
- dev.3 (d035e77): the controller has the adapter reconcile after a foreign restore.
  12:23–12:28: 94 opens and 95 discoveries, every one listing the Helldiver, no refusals;
  eight takeovers, each logged and each followed by a working discovery, e.g.

      12:25:28 Subject pose taken over by the game; its write ledger and cape released without writes
      12:25:31 Subject discovery: scanned=1 listed=1 elapsed_ms=1.000
      12:25:31 Helldiver selected (1.2 m)

  The user: "Discovery held". While a pose is held the Subject tab locks Refresh and Select
  (by design); kept edits hold one on every open, and Reset pose unlocks it and clears the
  edits. The user confirmed that is the expected behaviour.

## Run 2: Chef Shared Loader 1.5.1 alone (dev.3), 12:30

`chef_loader.log`:

    12:30:11 trusted: mods/goose/war_journalist (screenshots)
    12:30:11 started mods/goose/war_journalist 1.4.0-dev.3 (9ba626afa44a3aa3.patch_0; 8.0 ms, +3819 KB)
    12:30:11 updated mods/goose/war_journalist: 1.3.3-chef-dev.15 -> 1.4.0-dev.3

No `blocked:` line. `war_journalist_chef.log`:

    12:30:11 War Journalist 1.4.0-dev.3 (20261102.1717-d035e77) on Chef Shared Loader 1.5.1, screenshots through chef.capture, depth through chef.capture
    12:30:11 Photo Mode started on Chef Shared Loader
    12:31:31 Screenshot saved: C:/users/steamuser/AppData/Roaming/Arrowhead/Helldivers2/goose_war_journalist_capture_47.dds

Kept bone edits applied again on four reopens under Chef. Screenshots are DDS: Chef runs no
programs, so the PNG helper cannot start (documented in INSTALL.txt). No double-click pick
this run; picks are shared code and logged on BML dev.3 (12:25:31 above).

## Run 3: both deployed, Chef 1.5.1 above Boot Mod Loader 0.13.4 (dev.3), 12:33

Arsenal deployed Chef as patch_2 and Boot Mod Loader as patch_3, so Boot Mod Loader's boot owns
start-up. `boot_mod_loader.log`:

    12:33:53 mods/goose/war_journalist (patch_0, 3446999 bytes): loaded in 82 ms
    12:33:53 started 1 of 1 mods in 113 ms

`war_journalist_lua51.log`:

    12:33:54 WJL helper ready 0.3 s after launch
    12:33:54 WJL PNG screenshots selected (engine DDS converted by WJL): …/Screenshots
    12:33:54 Photo Mode started on Boot Mod Loader
    12:34:44 Screenshot saved: …/Screenshots/War-Journalist-20261102-123441-48081844-1.png

Nothing new in `chef_loader.log` or `war_journalist_chef.log` after 12:33:27 (run 2's game):
Chef did not start this launch, so War Journalist ran once. The plan's expected
`handed off to Chef Shared Loader` line does not exist in Boot Mod Loader 0.13.4; it hands
only Chef-style mods to Chef, and this package is built not to be one.

## Not checked live

- Importing 1.4.0 over a 1.3.4 entry: the option is now "War Journalist", not "War
  Journalist (Lua 5.1)"; the local entry kept the old name.
- Under Chef: double-click pick, bone page beyond kept edits.
- LLL host.
