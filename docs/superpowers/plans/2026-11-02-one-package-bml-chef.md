# One War Journalist Package (Boot Mod Loader + Chef) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One branch and one ZIP whose single entry, `mods/goose/war_journalist`, runs Photo Mode under Boot Mod Loader or Chef Shared Loader.

**Architecture:** Merge the Chef line into the bone-posing line. A generated head (`tools/package_head.py`) wraps today's two heads as `boot_host()` and `chef_host(chef)` and picks one from `...`. One committed builder (`tools/build_package.py`) packs it, proves it in lupa against both hosts, BML 0.13.4's own start-up checks and Chef's real sandboxes, then zips it.

**Tech Stack:** PUC Lua 5.1 (game), Python 3 with lupa (`lupa.lua51`) for fixtures, HD2 patch archives via `tools/photo_assets.py`.

**Spec:** `docs/superpowers/specs/2026-11-02-one-package-bml-chef-design.md`

## Global Constraints

- PUC Lua 5.1 only, no FFI. Every module passes `build_steam_candidate.FFI` and compiles with `loadstring`.
- Resource: `mods/goose/war_journalist` (hash64 key `b42c756875139ce2`).
  - The first line is exactly `-- HD2-Addon: mods/goose/war_journalist`.
  - There's no `HD2-Requires` in the first 1200 bytes.
  - The head reads its argument as `local loader=...`, and no line in the first 1200 bytes starts `local chef = ...`.
- Project ID `dbf_freecam_lua51`, title `War Journalist`.
  - Logs: `war_journalist_lua51.log` (BML and LLL) and `war_journalist_chef.log` (Chef), both in the game's settings folder.
- Arsenal GUID `7020a1c8-01ed-4a9d-874f-f778916eb067`.
  - One option, `War Journalist`, including `War Journalist` and `Assets`.
  - Archive file `9ba626afa44a3aa3.patch_0`.
- Chef minimum 1.4.0, checked in code on `chef.loader_version`, compared by number parts.
- Bundle at most 3,800,000 bytes. No `LIBRARIES` table. `mod.native_libraries=false` on every host.
- Windows rules under BML:
  - no in-process DLL written or loaded;
  - WJL started once through cmd.exe, with no `start "` and no PowerShell.
- `freecam/steam_runtime.lua`: no new locals in `M.new` and no new upvalues in its tick. New state goes into existing tables.
- Builder output goes only under `dist/review/`. Version `1.4.0`; dev builds are `1.4.0-dev.N`.
- Never commit the 41 `freecam/assets/shaders/*.hlsl` line-ending changes. Stage files by name.
- Python: `PY=~/Worktrees/linux-hd2/wj-1.3.1-windows/dist/toolchain/venv/bin/python3` (has lupa and lz4), run from the worktree root.
  - Mount the Windows drive first (`udisksctl mount -b /dev/nvme0n1p2`) so `~/Worktrees/linux-hd2/DBF-MCM` resolves and the 13 feature fixtures run.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A module embedded in the bundle with a line `local chef = ...`.** BML's `for_chef` scans the whole file, not only the head, and would never start War Journalist. Pinned by Task 5's `bml_starts` over the built text.
2. **Chef version strings:**
   - `'1.10.0'` must pass the gate, which a plain string compare gets wrong;
   - `'1.4.2-test1'` must pass;
   - `nil` and `'1.3.9'` must stay off.
   Pinned in Task 3.
3. **Key carry-over:**
   - a new key file that already exists, even an empty one, is never overwritten;
   - an old file with CRLF line ends is copied byte for byte.
   Pinned in Task 4.
4. **Under Chef no BML-only module is ever compiled** (WJL payload, input service, helper start-up). Pinned in Task 3 by recording `loadstring` chunk names inside the sandbox.
5. **A bundle past the size limit fails the build with its size named,** not at release time. Pinned in Task 6.

---

### Task 1: Merge the Chef line

**Files:**
- Modify: `freecam/steam_runtime.lua:1734` (the one conflict: the menu deps block that starts at `without_depth_shaders=`)
- Merge brings 23 files from `claude/wj-chef-lite` 71468fd (`chef_host*`, `chef_scene_resources*`, `photo_menu`, `photo_options`, `steam51`, `steam_input`, `steam_focus_sampler*`, `control_legend`, tests, `tools/build_chef_archive.py`, `tools/test_chef_port.py`, `tools/test_steam_port.py`, `tools/chef-png/`)

**Interfaces:**
- Produces: the merged tree; `freecam/chef_host.lua` and `freecam/chef_scene_resources.lua` exist; `dist/chef-src/sandbox/sandbox-v{1.3.1,1.4.0,1.4.1,1.4.2-test1,1.5.0,1.5.1}.lua` exist (gitignored).

- [ ] **Step 1: Copy the gitignored Chef sandboxes**

Run: `mkdir -p dist/chef-src && cp -r ~/Worktrees/linux-hd2/wj-chef-lite/dist/chef-src/sandbox dist/chef-src/`
Expected: six or more `sandbox-v*.lua` files in `dist/chef-src/sandbox/`.

- [ ] **Step 2: Baseline the suite before merging**

Run: `$PY tools/test_steam_port.py | tail -3`
Expected: `"live_game_verified": false` with `"passed": true`, and no `"skipped"` rows.

- [ ] **Step 3: Merge**

Run: `git merge --no-ff --no-commit claude/wj-chef-lite`
Expected: `CONFLICT (content): Merge conflict in freecam/steam_runtime.lua` and nothing else.

- [ ] **Step 4: Resolve `steam_runtime.lua`**

Keep the bone-posing side (`pose_groups=` through `pose_delete=`), with its first line replaced by Chef's line, `without_depth_shaders=deps.engine_time_only==true and not deps.depth_shaders,`. Nothing sets `deps.depth_shaders` now, so behaviour is the same on both hosts. This exact resolution was compile-checked under Lua 5.1 on 2026-11-02.

- [ ] **Step 5: Run the suite on the merge**

Run: `$PY tools/test_steam_port.py | grep -c '"passed": true'`
Expected: the count from Step 2 plus the new fixtures (`chef_host_tests.lua` and `chef_scene_resources_tests.lua`), and no traceback.

- [ ] **Step 6: Check that every Chef change is behind a host flag**

Run: `git diff f06a95c -- freecam/steam_runtime.lua freecam/photo_menu.lua freecam/control_legend.lua freecam/steam51.lua freecam/steam_input.lua freecam/steam_focus_sampler.lua freecam/photo_options.lua`

Expected: each changed line is reached only through one of these:
- a `mod.host_loader` field (`capture_service`, `scene_resources`, `focus_capture`, `require_keyboard`, `input_service`, `bindings`);
- `mod.arrow_keys`, or what it sets (`keys.arrows`, `menu.shift_tabs`, `deps.legend.shift_tabs`);
- the `pressed()` `(down, fresh)` return, which is host-neutral.

The two intended changes for both hosts are `steam_input` names 160–165 and the `photo_options` "Depth of field method" row going away. Anything else is a finding: gate it, then rerun Step 5.

- [ ] **Step 7: Commit the merge**

```bash
git add freecam/steam_runtime.lua && git commit -m "Merge the Chef line (claude/wj-chef-lite 71468fd) into the one-package branch" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: One head, with the Boot Mod Loader and LLL hosts

**Files:**
- Create: `tools/package_head.py`, `tools/package_fixtures.py`, `tools/test_package.py`

**Interfaces:**
- Consumes: `build_steam_archive.long_string(text) -> str`, `build_steam_archive.build_id() -> str` (imported for now; they move in Task 6), `build_steam_archive.RUNTIME` (the BML head text, as the source to port), `build_steam_candidate.MODULES`, `DEV_ONLY`, `FFI`, `ROOT`.
- Produces:
  - `package_head`: `RESOURCE='mods/goose/war_journalist'`, `ID='dbf_freecam_lua51'`, `TITLE='War Journalist'`, `MINIMUM_CHEF='1.4.0'`, `MAX_BYTES=3_800_000`.
  - `package_head.compose(sources: dict[str, str], version: str, build: str, release: bool) -> str`. `sources` keys are `'main.lua'` and `'src/<module>'`.
  - `package_head.check_size(text: str, limit: int = MAX_BYTES) -> int`. Returns the byte count, or raises `AssertionError("Bundle over Chef's 4 MiB reading limit: <n> bytes > <limit>")`.
  - `package_fixtures.current_sources(release: bool) -> dict[str, str]`. `'main.lua'` is `freecam/steam51.lua`; plus `'src/'+name` for `MODULES`, minus `DEV_ONLY` when `release`.
  - `package_fixtures.boot_env() -> contextmanager yielding Path`. It sets APPDATA, LOCALAPPDATA and USERPROFILE to a temp tree, yields the game settings folder `<APPDATA>/Arrowhead/Helldivers2`, and restores the environment.
  - `package_fixtures.run_boot(text: str, answering: bool = False) -> dict`. Keys: `entry`, `first` (the update's two results), `calls`, `shut`, `keys` (dict of id to button), `launches` (list), `closes`.
  - `package_fixtures.verify_shape(text: str) -> None`, `verify_boot(text: str, release: bool) -> dict`, `verify_lll(text: str) -> None`.
  - `tools/test_package.py`: CLI `[--release] [--sandbox PATH=VERSION]...`. It composes from the current tree with version `'0.0.0-test'`, runs every `verify_*` that exists, prints a JSON summary and exits non-zero on the first failure.

- [ ] **Step 1: Write the fixtures**

Port `build_steam_archive.verify`'s BML and LLL parts into `package_fixtures.py` (the `host` and `answering` Lua stubs move into `run_boot`), with these changes:
- the chunk name is `'@mods/goose/war_journalist'`;
- there is no library block;
- the version/build regex checks `local VERSION,BUILD=` in the text.

```python
def verify_shape(text):
    first, head = text.split('\n', 1)[0], text[:1200]
    assert first == '-- HD2-Addon: mods/goose/war_journalist', first
    assert 'HD2-Requires' not in head
    assert '\nlocal loader=...\n' in head
    assert not re.search(r'(^|\n)local\s+chef\s*=\s*\.\.\.', head)
    assert 'local LIBRARIES' not in text

def verify_boot(text, release):
    # Every BML assertion of build_steam_archive.verify, unchanged: update/shutdown wrapping ('game', .5, 6, True),
    # WJL answering path ('WJL helper ready', PNG selected), one cmd.exe launch with '--launch', no 'start "', no
    # powershell, closes == 0, 'In-process native libraries are not used by the Windows build', keys all
    # 'war_journalist.*' with toggle 'p' and >= 13, 'Photo Mode started on Boot Mod Loader', the refusing-helper line,
    # release: no 'Native diagnostics (' and old dev markers ignored; dev: the two-generation live reload proof.
    ...
    for name in os.listdir(game):
        assert not name.endswith('.dll'), 'Boot Mod Loader wrote a bridge: ' + name

def verify_lll(text):
    # LiveLuaLoader={} then run the chunk with the mod's name as its argument, as LLL's plain require does:
    # chunk('mods/goose/war_journalist'). entry.live_lua_api == 1, entry.name == 'War Journalist',
    # on_enable/on_update/on_disable/on_cleanup_poll are functions, and LLL's Native folder stays empty (no bridges).
```

- [ ] **Step 2: Run them and see them fail**

Run: `$PY tools/test_package.py`
Expected: FAIL, `ImportError: cannot import name 'compose' from 'package_head'` (or the module is missing).

- [ ] **Step 3: Implement `package_head.compose`**

The generated text, in order:
1. The three comment lines: the `HD2-Addon` line; `-- War Journalist <version>: one package for Boot Mod Loader and Chef Shared Loader.`; `-- Generated by tools/build_package.py; edit freecam/ and tools/package_head.py instead.`
2. `local loader=...`
3. The `ID`, `TITLE`, `RELEASE_MODE`, `VERSION` and `BUILD` lines.
4. The `SOURCES` block (`long_string`).
5. One shared `local function requirer(mod,scope)`, returning `mod.require` exactly as both heads write it today.
6. `BOOT_HOST`.
7. `PICK`.

`BOOT_HOST` is `build_steam_archive.RUNTIME` wrapped as `local function boot_host() … end`, with these changes:
- the `LIBRARIES` install loop is deleted;
- `mod.native_libraries=false` replaces the `LiveLuaLoader` test;
- `mod.require` comes from `requirer`.

`PICK` is `return boot_host()` in this task.

- [ ] **Step 4: Run them and see them pass**

Run: `$PY tools/test_package.py && $PY tools/test_package.py --release`
Expected: both print JSON with `verify_shape`, `verify_boot` and `verify_lll` passed. Exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/package_head.py tools/package_fixtures.py tools/test_package.py
git commit -m "One package head: Boot Mod Loader and LLL hosts behind local loader=..." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The Chef host in the head

**Files:**
- Modify: `tools/package_head.py` (`CHEF_HOST`, `PICK`)
- Modify: `tools/build_steam_candidate.py` (`CHEF_ONLY=('chef_host.lua','chef_scene_resources.lua')`, `MODULES+=CHEF_ONLY`)
- Modify: `tools/package_fixtures.py`, `tools/test_package.py` (default `--sandbox` list)

**Interfaces:**
- Consumes: `compose`, `current_sources` (now including `CHEF_ONLY`), `test_chef_port.sandbox_text(path) -> (text, blob)`, `SANDBOX_BLOBS`.
- Produces:
  - `package_fixtures.BOOT_ONLY`: the 7-name tuple from `build_chef_archive.BOOT_ONLY`. Copy it; don't import it, because that file is deleted in Task 6.
  - `package_fixtures.verify_chef(text: str, sandbox: Path, chef_version: str) -> dict`. Keys: `sandbox_git_blob`, `chef_version`, `keys`, `render_hook_forwards`, `movement_keys`, `refused_calls`, `files_written`, `compiled`.
  - `package_fixtures.verify_chef_gate(text: str) -> None`.
  - `test_package.py`'s default sandbox runs:
    - `(sandbox-v1.4.0, '1.4.0')`, `(sandbox-v1.4.1, '1.4.1')`, `(sandbox-v1.4.2-test1, '1.4.2-test1')`, `(sandbox-v1.5.0, '1.5.0')`, `(sandbox-v1.5.1, '1.5.1')`;
    - plus `(sandbox-v1.5.1, '1.10.0')` for the version compare.

- [ ] **Step 1: Write the Chef fixtures**

`verify_chef`:
- Port `build_chef_archive.FIXTURE` and its assertions:
  - the start line names the version, with `', depth through chef.capture'` exactly when the version is 1.4.2 or newer;
  - `'Photo Mode started on Chef Shared Loader'`;
  - at least 13 keys, toggle `'p'`, movement `'up down left right'`;
  - the render hook forwards twice;
  - no `blocked:` line;
  - the only file written is `'C:/game/war_journalist_chef.log'`.
- Changes from the port:
  - the chunk is run as `chunk(chef)` with `TEXT` being our composed text;
  - the fixture wraps the env's `loadstring` to record each chunk name, and returns them as `compiled`.
- Then assert:

```python
assert not any(name.endswith(tuple('/src/' + m for m in BOOT_ONLY)) for name in result['compiled']), result['compiled']
```

`verify_chef_gate`:
- Load the text with a stub env: `io.open` and `os` error if touched, `stingray` empty.
- Call `chunk(chef)` for each `loader_version` in `('1.3.9', None, '1.3.1')`. Assert each returns a table, `addon.update(1/60)` runs three times without error, and `chef.log` received exactly one line, `'War Journalist needs Chef Shared Loader 1.4.0 or newer'`.

- [ ] **Step 2: Run and see them fail**

Run: `$PY tools/test_package.py`
Expected: FAIL in `verify_chef` (the BML host runs, with no `CHEF` table: `APPDATA unavailable` or a missing Chef start line).

- [ ] **Step 3: Implement `CHEF_HOST` and the pick**

`CHEF_HOST` is `build_chef_archive.RUNTIME` (as committed in 71468fd) wrapped as `local function chef_host(chef) … end`, with these changes:
- `local chef=CHEF` and its `assert` go;
- `mod.require` comes from `requirer`;
- the gate goes first: a `local function at_least(have,need)` that compares the leading `%d+` parts in order. `nil` is too old; a suffix after the numbers is ignored.
  - Below `MINIMUM_CHEF` the host does `chef.log('%s','War Journalist needs Chef Shared Loader 1.4.0 or newer')` and returns `{version=VERSION,update=function()end,render=function()end,shutdown=function()end,on_stop=function()end}`.

`PICK` becomes:

```lua
if type(loader)=='table'then return chef_host(loader)end
return boot_host()
```

- [ ] **Step 4: Run and see them pass**

Run: `$PY tools/test_package.py && $PY tools/test_package.py --release`
Expected: all six sandbox runs pass, the gate passes, and Task 2's checks still pass.

- [ ] **Step 5: Commit**

```bash
git add tools/package_head.py tools/package_fixtures.py tools/test_package.py tools/build_steam_candidate.py
git commit -m "One package head: Chef host behind the 1.4.0 gate; BML-only modules never compile under Chef" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Boot Mod Loader key carry-over

**Files:**
- Modify: `tools/package_head.py` (`BOOT_HOST`), `tools/package_fixtures.py`, `tools/test_package.py`

**Interfaces:**
- Consumes: `boot_env()`, `run_boot(text)`.
- Produces: `package_fixtures.verify_key_carry_over(text: str) -> None`.

**Why:**
- BML names the key list after the calling chunk's name: `mbm_<last part>` (`MBB.register` via `MOM.caller()`).
- It reads `<game>/mbm_<name>_settings.txt` when the first binding registers.
- WJ registers in `on_enable`, after the head has run.

- [ ] **Step 1: Write the fixture**

```python
def verify_key_carry_over(text):
    old_bytes = b'war_journalist_toggle_key=f8\r\n#end\r\n'
    with boot_env() as game:                       # old only -> copied byte for byte, old kept
        (game / 'mbm_war_journalist_lua51_settings.txt').write_bytes(old_bytes)
        run_boot(text)
        assert (game / 'mbm_war_journalist_settings.txt').read_bytes() == old_bytes
        assert (game / 'mbm_war_journalist_lua51_settings.txt').read_bytes() == old_bytes
        assert 'Keys carried over from mbm_war_journalist_lua51_settings.txt' in (game / 'war_journalist_lua51.log').read_text()
    with boot_env() as game:                       # new already there, even empty -> untouched
        (game / 'mbm_war_journalist_lua51_settings.txt').write_bytes(old_bytes)
        (game / 'mbm_war_journalist_settings.txt').write_bytes(b'')
        run_boot(text)
        assert (game / 'mbm_war_journalist_settings.txt').read_bytes() == b''
    with boot_env() as game:                       # neither -> nothing made
        run_boot(text)
        assert not (game / 'mbm_war_journalist_settings.txt').exists()
```

- [ ] **Step 2: Run and see it fail**

Run: `$PY tools/test_package.py`
Expected: FAIL at the first `read_bytes()` (`FileNotFoundError`).

- [ ] **Step 3: Implement the copy in `BOOT_HOST`**

Do it before `mod.require('main.lua')`, using `io.open` with `'rb'`/`'wb'` on `game..'/mbm_war_journalist_settings.txt'`. Copy only when the new file can't be opened for reading and the old one can. Log the line from the test. Add one comment saying why: 1.3.x was `mods/goose/war_journalist_lua51`.

- [ ] **Step 4: Run and see it pass**

Run: `$PY tools/test_package.py`
Expected: PASS, including `verify_key_carry_over`.

- [ ] **Step 5: Commit**

```bash
git add tools/package_head.py tools/package_fixtures.py tools/test_package.py
git commit -m "One package head: carry 1.3.x Boot Mod Loader keys over to the new mod name" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Boot Mod Loader's own start-up checks, and LLL's

**Files:**
- Create: `tools/bml_loader_checks.py`
- Modify: `tools/package_fixtures.py`, `tools/test_package.py`

**Interfaces:**
- Produces:
  - `bml_loader_checks.BML_LOADER = Path.home()/'.config/hd2arsenal/mods/Boot Mod Loader 17754 0.13.4 2026-10-29T18-06Z 2Gg9W5NsL_AR932415/Boot Mod Loader/f476df93691895fa.lua'`
  - `bml_loader_checks.BML_LOADER_SHA256 = '7cc69039cba22432b8ff8e02d0ce4a0d5208837910fb401d4dd3a2d58d9c18d0'`
  - `bml_loader_checks.bml_starts(text: str, loader: Path = BML_LOADER) -> tuple[bool, str]`. The reason is one of `'starts'`, `'no HD2-Addon line'` or `'for chef'`.
  - `bml_loader_checks.lll_chef_style(text: str) -> bool`. True when any line in the first 1200 bytes matches `^local\s+chef\s*=\s*\.\.\.`, or they contain `HD2-Requires: chef-shared-loader` or `HD2-Requires: chef-loader`. This is LLL's documented rule.
  - `package_fixtures.verify_loaders(text: str) -> dict`

- [ ] **Step 1: Write the fixture**

```python
def verify_loaders(text):
    assert bml_starts(text) == (True, 'starts')
    assert not lll_chef_style(text)
    add = '-- HD2-Addon: mods/a/b\n'
    assert bml_starts(add + '-- HD2-Requires: chef-shared-loader\nreturn 1\n') == (False, 'for chef')
    assert bml_starts(add + 'local chef = ...\nchef.log("x")\n') == (False, 'for chef')
    assert bml_starts(add + 'local chef = ...\nif type(chef)~="table" then return end\nchef.log("x")\n') == (True, 'starts')
    assert bml_starts('return 1\n') == (False, 'no HD2-Addon line')
    assert lll_chef_style(add + 'local chef = ...\n')
    return {'bml_0.13.4': 'starts', 'lll': 'not chef-style'}
```

- [ ] **Step 2: Run and see it fail**

Run: `$PY tools/test_package.py`
Expected: FAIL, `ModuleNotFoundError: bml_loader_checks`.

- [ ] **Step 3: Implement `bml_loader_checks.py`**

- Check the loader file's sha256 against the pin. Fail with "Boot Mod Loader 0.13.4 not found or changed" when it differs or is missing.
- Take the loader text from the line `local KEYWORD = {}` up to, but not including, `local function run(entry)`. That covers `KEYWORD`, `lua_tokens`, `chef_untested` and `for_chef`.
- Run it in a fresh `lupa.lua51.LuaRuntime` with `return for_chef` appended.
- The first-line test is `declared_in`'s pattern ported to Python: `^-- HD2-Addon: (mods/[A-Za-z0-9_]+/[A-Za-z0-9_/]+)\r?\n`, with a name that doesn't end in `/`.

- [ ] **Step 4: Run and see it pass**

Run: `$PY tools/test_package.py`
Expected: PASS, with `verify_loaders` reporting `{"bml_0.13.4": "starts", "lll": "not chef-style"}`.

- [ ] **Step 5: Commit**

```bash
git add tools/bml_loader_checks.py tools/package_fixtures.py tools/test_package.py
git commit -m "One package: prove Boot Mod Loader 0.13.4 starts it and LLL does not take it for a Chef addon" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The one builder

**Files:**
- Create: `tools/build_package.py`
- Modify: `tools/build_steam_candidate.py` (`build(output, release=False, bridges=True)`. With `bridges=False`, `manifest['native_libraries']=[]` and no DLL files.)
- Modify: `tools/package_head.py` (`long_string` and `build_id` move here unchanged; add `GUID`, `OPTION`, `ARCHIVE` and `ASSETS_SHA256`)
- Modify: `tools/package_fixtures.py` (`verify_zip`), `tools/test_package.py` (`test_size_cap`), `VERSION` (`1.4.0`)
- Modify: `tools/request_windows_reload.py:23` (the comment names `package_head.compose`), `BUILD.md` (new section "One package for Boot Mod Loader and Chef"), `docs/CHEF-LOADER-PORT.md` (one line: Chef builds now come from `tools/build_package.py`)
- Delete: `tools/build_steam_archive.py`, `tools/build_chef_archive.py`

**Interfaces:**
- Consumes: everything from Tasks 2–5; `photo_assets.archive_rows`, `read_archive`, `hash64`, `LUA`; `verify_installed_modules.audit`.
- Produces:
  - `package_head.GUID='7020a1c8-01ed-4a9d-874f-f778916eb067'`, `OPTION='War Journalist'`, `ARCHIVE='9ba626afa44a3aa3.patch_0'`. These live in `package_head` so that `package_fixtures` and `build_package` both import them without a cycle.
  - `build_package.ASSETS = Path.home()/'Worktrees/linux-hd2/wj-1.3.1-windows/dist/review/release-1.3.1/assets-1.3.0'`
  - `package_head.ASSETS_SHA256`, pinned:
    - `9ba626afa44a3aa3.patch_0`: `de5e7ace103a5f7121c57acaa3b4b323c60955309a31b04175bdc6f05028c8b2`
    - `ee6b1ba7e22d71ed.patch_0`: `adc229713e0573007e8b34dd7a7fb69a8de8cd92a0a75aa0e1bbfa46777de2be`
    - `ee6b1ba7e22d71ed.patch_0.gpu_resources`: `feed3eb14f8c3becd21698c1f73a7f116a532f54ce22009c3f992052f76e2f5d`
    - the three empty files: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
  - `build_package.RELEASE_DESCRIPTION: str | None = None`. The release session fills it; a release build refuses while it's `None`.
  - `build_package.build(release: bool, dev_number: int | None, sandboxes: list[tuple[Path, str]], assets: Path) -> dict`. Returns the receipt dict.
  - CLI: `build_package.py --dev N` or `--release`, `[--sandbox PATH=VERSION]...` (defaults to Task 3's list, the same parser as `test_package.py`), `[--assets DIR]`.
  - `package_fixtures.verify_zip(path: Path, release: bool) -> dict`

- [ ] **Step 1: Write `verify_zip` and `test_size_cap`**

```python
NAMES = {f'Assets/{a}{s}' for a in ('9ba626afa44a3aa3.patch_0', 'ee6b1ba7e22d71ed.patch_0') for s in ('', '.gpu_resources', '.stream')} | \
        {f'War Journalist/9ba626afa44a3aa3.patch_0{s}' for s in ('', '.gpu_resources', '.stream')} | \
        {'War Journalist/b42c756875139ce2.lua', 'manifest.json', 'PROVENANCE.json', 'INSTALL.txt', 'KNOWN-ISSUES.md',
         'LICENSE-Link.txt', 'LICENSE-Bingus.txt', 'Chef-LICENSE.txt', 'FILES-SHA256.txt'}

def verify_zip(path, release):
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        assert names - {'RELEASE-NOTES.md'} == NAMES and (not release or 'RELEASE-NOTES.md' in names), names ^ NAMES
        assert z.testzip() is None
        for line in z.read('FILES-SHA256.txt').decode().splitlines():
            digest, name = line.split('  ', 1); assert sha256(z.read(name)) == digest, name
        m = json.loads(z.read('manifest.json'))
        assert m['Guid'] == '7020a1c8-01ed-4a9d-874f-f778916eb067' and m['Name'].startswith('War Journalist ')
        assert m['Options'] == [{'Name': 'War Journalist', 'Description': 'Photo Mode and its assets.', 'Include': ['War Journalist', 'Assets']}]
        addon = z.read('War Journalist/b42c756875139ce2.lua').decode()
        verify_shape(addon); check_size(addon)
        assert ('local RELEASE_MODE=true' in addon) == release
        assert ('SOURCES["src/windows_dev_reload.lua"]' in addon) == (not release)
        assert 'a6f5f3f6aede55b22627911b0c4429169e98d4378b7ca934cced0e7fa67723ef' in addon   # the WJL helper ships
        for name, digest in ASSETS_SHA256.items(): assert sha256(z.read('Assets/' + name)) == digest, name
        return {'files': len(names), 'addon_bytes': len(addon.encode())}

def test_size_cap():
    check_size('x' * 10, limit=10)
    try: check_size('x' * 11, limit=10)
    except AssertionError as e: assert "over Chef's 4 MiB reading limit: 11 bytes > 10" in str(e)
    else: raise AssertionError('size cap did not fire')
```

- [ ] **Step 2: Run and see it fail**

Run: `$PY tools/test_package.py --zip dist/review/package/1.4.0-dev.1/War-Journalist-1.4.0-dev.1.zip`
Expected: FAIL, the file is not found. (`--zip PATH` runs `verify_zip` on that file. Add the flag now.)

- [ ] **Step 3: Implement `build_package.build`**

1. Build the candidate: `build_steam_candidate.build(review/'candidate', release, bridges=False)`. This runs `test_steam_port`, and its `audit` must pass.
2. Read `sources` from the candidate folder.
3. `compose`, then `check_size`.
4. Run every `verify_*` from Tasks 2–5.
5. Pack the archive envelope as the old packers did. The key must be `0xb42c756875139ce2`.
6. Lay out `dist/review/package/<version>/War-Journalist-<version>/`:
   - the `War Journalist/` payload;
   - `Assets/`, copied from `--assets` and checked against `ASSETS_SHA256`;
   - the licences, with `tools/chef-LICENSE.txt` copied as `Chef-LICENSE.txt`;
   - `KNOWN-ISSUES.md` from `docs/`;
   - `RELEASE-NOTES.md` from `docs/RELEASE-<version>.md`, required for a release and copied for dev only if it exists;
   - `INSTALL.txt`;
   - `manifest.json`, `PROVENANCE.json` and `FILES-SHA256.txt`.
7. ZIP it as `War-Journalist-<version>.zip` and run `verify_zip`.
8. Write `SHA256SUMS.txt` and `BUILD-RECEIPT.json`, holding the modules, sizes and sha256s, every verify result and the sandbox results.

Details:
- **Version.** `1.4.0` for a release, `1.4.0-dev.N` for `--dev N`. A release asserts that `VERSION` has no suffix and that `RELEASE_DESCRIPTION` is set.
- **Dev description:** "War Journalist <version>, DEVELOPMENT build: one package for Boot Mod Loader and Chef Shared Loader 1.4.0 or newer. On Boot Mod Loader the helper gives keyboard isolation and PNG screenshots; on Chef, arrow keys move the camera and screenshots are DDS. Bone posing on the Subject tab. Live Lua reload on Boot Mod Loader once wj-dev-reload.enabled is armed. Not for players. Use one War Journalist at a time."
- **`INSTALL.txt`:**
  - one paragraph for each loader;
  - "install one copy";
  - P opens Photo Mode;
  - Page Down toggles Handycam on Boot Mod Loader;
  - arrow keys on Chef.

Then:
- move `long_string` and `build_id` into `package_head.py`;
- delete the two old packers;
- fix the reload tool's comment;
- add the `BUILD.md` section, with the commands from Steps 4–5.

- [ ] **Step 4: Build dev.1 and verify the ZIP**

Run: `$PY tools/build_package.py --dev 1 && $PY tools/test_package.py --zip dist/review/package/1.4.0-dev.1/War-Journalist-1.4.0-dev.1.zip`
Expected: the builder prints the receipt with `addon_bytes` below 3,800,000; the tests exit 0 and `test_size_cap` passes.

- [ ] **Step 5: Check that a release build refuses without its texts**

Run: `$PY tools/build_package.py --release`
Expected: `AssertionError` naming the missing `docs/RELEASE-1.4.0.md` or `RELEASE_DESCRIPTION`, and no ZIP written.

- [ ] **Step 6: Commit**

```bash
git add tools/build_package.py tools/build_steam_candidate.py tools/package_head.py tools/package_fixtures.py tools/test_package.py VERSION tools/request_windows_reload.py BUILD.md docs/CHEF-LOADER-PORT.md
git rm tools/build_steam_archive.py tools/build_chef_archive.py
git commit -m "One builder for the one War Journalist package (1.4.0); the two old packers retire" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Stage dev.1 in HD2 Arsenal

**Files:**
- Modify (user data, backed up first): `~/.config/hd2arsenal/hd2a_data.json`
- Create: `~/.config/hd2arsenal/mods/War-Journalist-1.4.0-dev.1/`

**Interfaces:**
- Consumes: Task 6's folder `dist/review/package/1.4.0-dev.1/War-Journalist-1.4.0-dev.1/`.

- [ ] **Step 1: Back up**

Run: `cp ~/.config/hd2arsenal/hd2a_data.json ~/.config/hd2arsenal/repair-backups/hd2a_data-before-wj-one-package-dev.1-$(date -u +%Y%m%d-%H%M%S).json`
Expected: the backup is byte-identical to `hd2a_data.json` (check with `cmp`).

- [ ] **Step 2: Copy the package folder**

Run: `cp -r dist/review/package/1.4.0-dev.1/War-Journalist-1.4.0-dev.1 ~/.config/hd2arsenal/mods/`

- [ ] **Step 3: Update the library record (Arsenal may stay open)**

In `modsLibrary`, record `uuid` `7020a1c8-01ed-4a9d-874f-f778916eb067`, set:
- `path` to the new folder;
- `label` to `War Journalist 1.4.0-dev.1`;
- `description` to the manifest's `Description`;
- `luaPaths` to `[<new folder>/War Journalist/b42c756875139ce2.lua]`, with `hasLua` true.

Set `options[0].name` to `War Journalist` only if no `modsList` row stores option names for this uuid; otherwise leave it.

Replace exact strings in the raw bytes (indent 2, raw UTF-8, no trailing newline), and never touch `contentHash`.

Expected: reading the file back shows the new values, and `json.load` works.

- [ ] **Step 4: Profile rows (needs Arsenal closed)**

In the profile you test with ("Lua5.1"), switch off the row for `7b18fc08-a506-4cd3-a506-dbed18445576` (Chef dev.16) and make sure `7020a1c8`'s row is on.
- Write it from a background waiter modelled on `first-person/tools/add_profile_row.py`:
  - it waits until no process with executable `hd2arsenal` or `HD2Arsenal-*` exists and the file has been unchanged for 2 s;
  - it writes once;
  - it refuses if Arsenal comes back.
- Ask the user to close Arsenal.

Expected: after reopening, the user sees "War Journalist 1.4.0-dev.1" enabled and the Chef dev row off.

---

### Task 8: Live runs and hand-offs

**Files:**
- Create: `docs/LIVE-TEST-1.4.0-dev.md`

Logs are in `/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Roaming/Arrowhead/Helldivers2/`. Chef's `chef_loader.log` is wherever its README says. The user deploys and plays each run; you read the logs after each one.

- [ ] **Step 1: Boot Mod Loader alone** (BML 0.13.4 and WJ on, Chef off)

Expected:
- `boot_mod_loader.log` has `mods/goose/war_journalist (patch_N, … bytes): loaded`.
- `war_journalist_lua51.log` has `WJL helper ready`, `WJL PNG screenshots selected`, `Photo Mode started on Boot Mod Loader`, and on the first run `Keys carried over from mbm_war_journalist_lua51_settings.txt`.
- A PNG is saved after a screenshot.
- `mbm_war_journalist_settings.txt` holds the user's keys.
- The user confirms the bone page works.

- [ ] **Step 2: Chef 1.5.1 alone** (Chef and WJ on, BML off)

Expected:
- `war_journalist_chef.log` has `on Chef Shared Loader 1.5.1, screenshots through chef.capture, depth through chef.capture`, `Photo Mode started on Chef Shared Loader`, a saved screenshot, and `Helldiver selected (… m)` after a double-click.
- `chef_loader.log` has no `blocked:` line for War Journalist.

- [ ] **Step 3: Both deployed** (Chef 1.5.1 above BML 0.13.4 in the profile, so BML's boot runs and hands off)

Expected:
- `boot_mod_loader.log` shows War Journalist loaded by BML and `handed off to Chef Shared Loader`.
- A new `Photo Mode started on Boot Mod Loader` line appears in `war_journalist_lua51.log`, and no new line in `war_journalist_chef.log`.
- The user sees one Photo Mode.

- [ ] **Step 4: Record and commit**

Write `docs/LIVE-TEST-1.4.0-dev.md`. For each run: the time, the log lines quoted, and what the user saw.

```bash
git add docs/LIVE-TEST-1.4.0-dev.md && git commit -m "One package 1.4.0-dev.1: live runs on Boot Mod Loader, Chef and both" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand-offs**

- Message the "Custom bone posing" session: from now on it commits on `claude/wj-chef-unified`, builds with `tools/build_package.py --dev N`, and the Proton port follows those commits.
- Message the "War Journalism Release Protocol" session with the builder, the dev.1 receipt and `docs/LIVE-TEST-1.4.0-dev.md`. It writes `docs/RELEASE-1.4.0.md` and `RELEASE_DESCRIPTION`, updates the release skill (one ZIP, Chef support, no `chefbuild` previews) and ships 1.4.0.
- Update the memory file `wj-one-package-bml-chef.md` with the branch state.
