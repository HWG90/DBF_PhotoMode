# Build

Chef Shared Loader rewrite: see [the port contract and preview build](docs/CHEF-LOADER-PORT.md).
This separate source-only Lua 5.1 candidate is not a full replacement for the legacy releases below.

Python 3 and a LuaJIT/Lua 5.1 compiler library are development tools, not player prerequisites. HD2_LUA51_DLL selects the compiler library; the default uses the installed game LuaJIT.

Build BSL with `py -3 freecam/build.py --output dist/releases/photo-0.6`, then MDL with `py -3 tools/build_mdl.py --output dist/releases/photo-0.6`. All camera/private runtime and decorative native assets are owned under freecam/vendor and freecam/assets/shaders. No DBF-HUD, DBF-MCM, external ActionCam, installed mod package or patched game asset is read during release builds. Vendored byte identities are checked before packaging.

Run `py -3 tools/run_tests.py --mcm-root <canonical DBF-MCM>` for isolated behavior fixtures, `py -3 tools/verify_release.py <ZIP>` for exact immutable release validation, and `py -3 tools/test_packaged_standalone.py <BSL ZIP> <MDL ZIP> --receipt <receipt.json>` for package-only standalone startup. The fixture runner's MCM source input is testing only; the packaged-startup check prohibits external source fallback.

The optional screenshot converter can be rebuilt from freecam/native/build_photo_capture.py with MSVC x64, static CRT; player packages include its verified binary. Vendored native DLL payloads are kept as hex in source and decoded into real DLLs during packaging.

BSL contains the runtime and native assets under Addon. MDL includes the loose addon plus GameData patches in the same ZIP. Numeric DoF and scene effects remain disabled until visual verification. Saved settings, diagnostics, game files and development evidence are excluded.
