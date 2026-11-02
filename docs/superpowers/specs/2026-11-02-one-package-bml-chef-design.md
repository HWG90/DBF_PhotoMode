# One War Journalist package for Boot Mod Loader and Chef Shared Loader — design

Date: 2026-11-02. Branch: `claude/wj-chef-unified`, from `claude/wj-bone-posing` f06a95c.
Status: approved in conversation (parts 1–4); this file is the written spec for review.

## Goal

One source and one release file. Today War Journalist has two of each: the Boot
Mod Loader build (`release/1.3.4`, then `claude/wj-bone-posing`) and the Chef
build (`claude/wj-chef-lite`, 1.3.3 plus chef-dev.2–dev.14, uncommitted). Every
fix has to be made twice, and players have to pick the right ZIP.

After this work there is one branch where every War Journalist change lands, one
committed builder, and one ZIP that runs Photo Mode under either loader.

Success:

- One ZIP installed through Arsenal starts Photo Mode under Boot Mod Loader
  0.13.4 alone, under Chef Shared Loader 1.5.1 alone, and exactly once when both
  are deployed.
- Under Boot Mod Loader it keeps everything 1.3.4 and bone posing have: the WJL
  helper (keyboard isolation, cursor clip, PNG screenshots), Handycam, hover
  pause, bone posing.
- Under Chef it keeps what chef-dev.14 has, without the depth trials: its own
  panel and cursor, arrow keys, `chef.capture` screenshots, scene effects, and
  focus depth through `chef.capture('depth')` from Chef 1.4.2.
- A player's settings and keys survive the update.

## Scope

In: the merge of the Chef line into the bone-posing line, one entry that picks
its host, one committed package builder, offline fixtures for both hosts, a dev
build staged in Arsenal, and three live runs.

Out, on record: the Proton (LuaJIT/LLL) build, depth-shader research (depth
shaders stay off on both loaders), the weather-control branch (it joins this
branch like any feature when ready), and the 1.4.0 release itself, which runs
in the War Journalism release session.

## Facts that shaped the design

- **Chef reads Lua resources up to 4 MiB.** Chef 1.5.1 `src/loader.lua:12476`:
  `MAX_ENTRIES, MAX_LUA = 200000, 4 * 1024 * 1024`; a larger resource is
  counted in `scan.big` and never run.
- **The BML bundle is 5,370,462 bytes** (bone-posing dev.1). Its 90 modules are
  3,386,537 bytes of source. The rest is the `LIBRARIES` table: five in-process
  `hd2_nativeinfo_*.dll` bridges as hex (about 1.9 MB). Boot Mod Loader refuses
  them (`mod.native_libraries` is true only under LLL) and Chef blocks
  `package.loadlib`. The WJL-only modules are 731,186 bytes, the helper payload
  668,795 of them. `chef_host.lua` and `chef_scene_resources.lua` add 25,131.
  All 90 modules plus the Chef host come to about 3.42 MB (3.26 MiB).
- **How Boot Mod Loader 0.13.4 picks mods** (its loader file,
  `f476df93691895fa.lua`): the first line must be
  `-- HD2-Addon: mods/<a>/<b>`. It does not run a mod that has
  `HD2-Requires: chef-shared-loader` in its first 1200 bytes, or that takes
  `local chef = ...` and uses it untested (`chef_untested`). After its own mods,
  when Chef's core is deployed, it hands the skipped ones to Chef
  (`ChefSharedLoaderHandoff`).
- **How Chef 1.5.1 starts addons:** it passes its helper table through `...`
  to every `-- HD2-Addon:`; other loaders pass the mod's name (MODDING.md,
  "Porting a boot-replacing mod"). It skips a mod that `package.loaded` or
  `__boot_mod_loader.mods` already lists as loaded ("Not starting a mod twice").
  It refuses another loader's `boot` (`__boot_mod_loader`).
- **Chef trusts one name for capture:** `TRUSTED` in Chef 1.5.1 `src/loader.lua`
  has `['mods/goose/war_journalist'] = { title = 'War Journalist', capture = true }`.
  Screenshots and depth captures depend on that name.
- **LLL calls an addon Chef-style** when a line starts with `local chef = ...`
  in its first 1200 bytes, or it requires `chef-shared-loader`
  (LLL `docs/CHEF-AND-BOOT-COMPAT.md`). Anything else it loads with `require`.
- **Boot Mod Loader names the key file after the mod:** `mod_id`, else the last
  part of the addon's name. Today that is `mbm_war_journalist_lua51_settings.txt`.
- **Chef sandbox source checks:** none; blocked calls fail only when made. A
  module that is never required under Chef never runs there.
- **Lua 5.1 limits:** `steam_runtime.lua` `M.new` is near 200 locals and its
  tick function at 60 upvalues. Both lines added state there since 1.3.3.

## Part 1: package and identity

- **One ZIP:** `War-Journalist-<version>.zip`, Arsenal/Nexus GUID
  `7020a1c8-01ed-4a9d-874f-f778916eb067` (the published entry, so BML players
  get an update). Name "War Journalist <version>". One option, "War Journalist",
  including the `War Journalist` folder and `Assets`.
- **One Lua resource:** `mods/goose/war_journalist` in
  `9ba626afa44a3aa3.patch_0`, first line
  `-- HD2-Addon: mods/goose/war_journalist`. No `HD2-Requires` line. The
  Chef 1.4.0 minimum is checked in code.
- **Settings:** WJ's own `dbf_freecam_lua51.ini` stays as it is (the project ID
  stays `dbf_freecam_lua51`; both builds already share it). Under Boot Mod
  Loader, the keys in `mbm_war_journalist_lua51_settings.txt` carry over to
  `mbm_war_journalist_settings.txt` the first time the new file is missing.
- **Size:** no `LIBRARIES` table. The builder fails above 3,800,000 bytes. If a
  later build reaches that, the WJL helper payload moves into a second resource
  with no `HD2-Addon` line, read only by the BML host.
- **Assets:** the Assets of `War-Journalist-1.3.4-BML.zip` (identical in
  bone-posing dev.1), pinned in the builder: `9ba626afa44a3aa3.patch_0`
  de5e7ace…, `ee6b1ba7e22d71ed.patch_0` adc22971…, its `.gpu_resources`
  feed3eb1…, the other three empty. Chef dev.14's trial depth-shader pairs are
  not shipped.
- **Version:** 1.4.0. After it ships, the Chef track's Arsenal entry
  `7b18fc08-a506-4cd3-a506-dbed18445576` and the GitHub `chefbuild` previews are
  retired.
- **Dropped:** under LLL this ZIP no longer installs native bridges. LLL
  players use the Proton build.

## Part 2: the entry and the hosts

The builder writes one head:

```lua
-- HD2-Addon: mods/goose/war_journalist
-- War Journalist <version>: one package for Boot Mod Loader and Chef Shared Loader.
local loader = ...
```

The variable is not named `chef`, so LLL does not take the addon for a Chef
addon, and Boot Mod Loader's `chef_untested` check has nothing to flag. Then:

- **Chef** (`type(loader) == 'table'`):
  - Below loader version 1.4.0 (`chef.loader_version`, compared by number
    parts): one `chef.log` line, "War Journalist needs Chef
    Shared Loader 1.4.0 or newer", and an addon whose hooks do nothing.
  - Otherwise chef-dev.14's head: `chef_host` (saves through `host.files`
    without `os.rename`/`os.remove`, `chef.capture` screenshots, `chef.hold_mouse`
    input with the virtual cursor, the render hook), `chef_scene_resources`,
    `host.depth` from 1.4.2, `mod.arrow_keys = true`, `require_keyboard = false`,
    log `war_journalist_chef.log`. Returns Chef's addon table
    (`update`, `render`, `shutdown`, `on_stop`).
- **LLL** (`rawget(_G, 'LiveLuaLoader')`): returns the entry, as today. No
  bridges.
- **Boot Mod Loader** (anything else): today's BML head: WJL helper started
  beside the game, `windows_input_service`, PNG through WJL, the game's
  `update` and `shutdown` wrapped, log `war_journalist_lua51.log`, the key
  carry-over, and dev reload in dev builds.

Shared by all three: `mod.require` over one `SOURCES` table, `main.lua` and the
steam51 module graph. Host differences reach the modules only through
`mod.host_loader` (`capture_service`, `scene_resources`, `depth_shaders`,
`focus_capture`, `require_keyboard`, `input_service`, `bindings`,
`capabilities.revision`) and `mod.arrow_keys`.

Merge rule for the shared modules (`steam_runtime`, `photo_menu`,
`control_legend`, `steam51`, `steam_input`, `steam_scene`,
`steam_scene_overlay`, `steam_focus_sampler`): every Chef change stays behind
one of those flags, so Boot Mod Loader behaves as before. The exception is
`steam_input`'s names 160–165 (left/right Shift, Ctrl, Alt), which help both.

Depth shaders: the Chef line removed its trial code in 71468fd (no trial
words, no probe file, no trial contracts), and `photo_options.lua` drops the
"Depth of field method" row under `without_depth_shaders`, which now holds on
both hosts. `windows_dev_reload.lua` stays a dev-only BML module.

Who runs it:

| Deployed | Started by | Host |
|---|---|---|
| Boot Mod Loader only | Boot Mod Loader | BML |
| Chef Shared Loader only | Chef | Chef |
| BML handing off to a Chef core | Boot Mod Loader; Chef skips it | BML |
| Chef's boot above BML | Chef | Chef |

## Part 3: source, builder and tests

- **Branch:** `claude/wj-chef-unified` in `~/Worktrees/linux-hd2/wj-chef-unified`,
  from `claude/wj-bone-posing` f06a95c (1.3.4 plus bone posing dev.6).
  `claude/wj-chef-lite` 71468fd (committed by its session: chef-dev.2–dev.16) is merged;
  the 41 shader `.hlsl` line-ending changes stay out. From then on BML, Chef and
  bone-posing work all land here.
- **Builder:** `tools/build_package.py`, committed.
  - `--dev` builds a dev package; without it, a release package. Output:
    `dist/review/package/<version>/War-Journalist-<version>.zip` plus a build
    receipt (module list, sizes, sha256s, test results); the ZIP carries
    `PROVENANCE.json` as now.
  - It writes the one head from the BML head (`build_steam_archive.py`
    `RUNTIME`) and the Chef head (`build_chef_archive.py` `RUNTIME`), packs
    `SOURCES` with the existing `long_string`/`build_id` helpers, and compiles
    the result.
  - It asserts: the first line, no `HD2-Requires`, no `LIBRARIES`, size at most
    3,800,000 bytes, the Assets' pinned sha256s, and in a release no dev-only
    module and no probe-file read.
  - Retired: `build_chef_archive.py` and `build_steam_archive.py` (their
    heads and fixtures move into `tools/package_head.py` and
    `tools/package_fixtures.py`), and the gitignored
    `dist/review/*/build_package.py` copies. The Chef Lite 0.6 builder
    `build_chef_candidate.py` and `freecam/chef/` are unused and left as they are.
- **Offline tests:**
  - `tools/test_steam_port.py` as now, Chef fixtures included.
  - The built ZIP started in each real Chef sandbox: 1.4.0, 1.4.1, 1.4.2-test1,
    1.5.0, 1.5.1 (`tools/test_chef_port.py` blobs). It starts, registers its
    keys, hooks render, makes no refused call and stops cleanly.
  - Boot Mod Loader 0.13.4's own checks (the `HD2-Requires` scan and
    `chef_untested`), lifted from its loader file, run over the built head:
    it must be a mod BML starts.
  - Host choice: a table gives Chef; the mod's name gives BML; `LiveLuaLoader`
    returns the entry; Chef below 1.4.0 stays off.
  - Key carry-over: an old file and no new one copies; an existing new file is
    left alone; no old file does nothing.
- **Live runs under Proton**, each with the log kept:
  1. Boot Mod Loader alone: WJL ready, a PNG saved, the bone page works.
  2. Chef 1.5.1 alone: the panel draws, a screenshot is saved, double-click
     focus lands.
  3. Both deployed: one War Journalist only, and the log names the BML host.

## Part 4: order and hand-offs

1. Message the Chef session ("War Journalist Chef Shared Loader compatibility")
   to commit chef-dev.2–dev.14 on `claude/wj-chef-lite` without the shader line
   endings, and to make no further Chef-only builds. Its next Chef work goes to
   `claude/wj-chef-unified`.
2. This session: the merge, the one head, the builder, the fixtures, a dev
   build staged in Arsenal entry `7020a1c8` with label, description and version
   updated, the Chef dev entry `7b18fc08`'s row switched off so one War
   Journalist runs, profile rows written with Arsenal closed, then the three live
   runs.
3. Tell the "Custom bone posing" session to commit on `claude/wj-chef-unified`
   from then on. The Proton bone-posing port keeps following those commits.
4. Hand 1.4.0 to the War Journalism release session: the builder, the ZIP, the
   test logs. That session updates the release skill (one ZIP, Chef support on
   the pages, no `chefbuild` previews) and does GitHub, Nexus, Ayaka and Discord.

## Risks and open points

- **Key carry-over timing:** Boot Mod Loader may read or write
  `mbm_war_journalist_settings.txt` when WJ registers its first binding. The copy
  must happen before that (the head runs before `main.lua`). If BML's order
  makes that impossible, pass `mod_id = 'war_journalist_lua51'` with each
  binding, if BML's binding API takes it, and keep the old file name instead.
  Checked against 0.13.4's source before the fixture is written.
- **Headroom:** about 750 KB below Chef's limit at the start. Bone posing and
  later features grow the bundle; the builder's 3,800,000-byte stop and the
  payload split are the answer, not a surprise at release time.
- **Merge conflicts and Lua 5.1 limits** in `steam_runtime.lua`: both lines added
  state since 1.3.3. New state goes into existing tables, not new locals or
  upvalues; the compile in the builder and the fixtures catch an overflow.
- **LLL without bridges:** not tested; behaviour there is whatever the LLL path
  gives without native helpers.
- **Chefbo** has chef-dev.10. Telling him about the single package is the
  release session's job.
