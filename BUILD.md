# Build

Install Python 3 and MSVC x64 tools for the optional PNG converter. Use the game's lua51.dll for Lua compilation (`HD2_LUA51_DLL` selects an alternate installed path).

Build the converter with `python freecam/native/build_photo_capture.py`.
Run `python freecam/build.py --actioncam <ActionCam-2.3.1-archive> --output dist/releases/photo-0.5`. The ActionCam archive is a local build input; its source hashes and credit are recorded in the package. The builder copies the public MCM service/native input dependency from the canonical DBF-MCM sibling checkout; `--mcm-root` overrides that path.

Then run `python tools/build_mdl.py --output dist/releases/photo-0.5` to package the MDL API 2 alternative from that generated camera source.

Run `python tools/run_tests.py --mcm-root ../DBF-MCM --native` for the isolated fixtures. Verify each ZIP with `python tools/verify_release.py <release.zip>`.

The primary distribution is the BSL ZIP; MDL is the alternative. No scene shader native assets are included. Saved settings, diagnostics, game files, screenshots from tests and development evidence are excluded from packages.
