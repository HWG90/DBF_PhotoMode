# War Journalist helper (WJL)

`war_journalist_helper.exe` is the small Windows program War Journalist starts under Boot Mod
Loader. It keeps Photo Mode's keys and mouse away from the game, saves screenshots as PNG, and
checks the stock renderer before scene effects are allowed. The mod ships it inside the package
(`freecam/wjl_helper_payload.lua`), writes it to `%APPDATA%\Arrowhead\Helldivers2\`, checks its
bytes before every start, and starts it through `cmd.exe` (`freecam/wjl_helper_startup.lua`).

`native/` holds the exact sources compiled into the shipped helper: SHA-256 `a6f5f3f6…`, version
1.3.4.0, MSVC under wine. `HELPER.json` lists each file's SHA-256, and `tools/test_package.py`
checks both against the payload.

- The program is `steam_service.c`, which includes `steam_files.c`, `steam_pointer.c`,
  `steam_keyboard.c`, `steam_screenshot_jobs.c` and `steam_codec.c`, linked with
  `steam_screenshot.cpp` and the version resource `war_journalist_helper.rc`.
- `test_steam_files.c`, `test_steam_pointer.c`, `test_steam_keyboard.c` and
  `test_steam_screenshot_jobs.c` run during every build.
- `lll_ffi.c`, `input_guard.c`, `lean_runtime.c` and the other tests come along from LLL and are
  not part of the helper.

These sources are LLL's `native/` code ([HWG90/LLL](https://github.com/HWG90/LLL)) as patched by
`tools/build_windows_input_helper.py`. `tools/windows_input_shortcut.patch` shows the main
changes. The LLL state they were patched from is not a pushed LLL commit, so this folder is the
record.

## Rebuilding

```bash
python3 tools/build_windows_input_helper.py --lll <LLL checkout> --wine-msvc <MSVC + Windows SDK copy>
```

The build rewrites this folder, `HELPER.json`, the patch and the payload. A build from another
folder gives a different file (MSVC names one type after the full source path), so pin the new
SHA-256 as `HELPER_SHA256` in `tools/package_fixtures.py`.
