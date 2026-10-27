# Build and validation

The current version is read from `VERSION` (1.3.0). Building source does not
publish a release or install anything into the game.

## Lua 5.1 checks

Use Python 3 with `lupa` providing the Lua 5.1 runtime:

```powershell
py -3 tools/test_steam_port.py --receipt dist/validation/lua51.json
```

The shared feature fixtures use a sibling `DBF-MCM` source checkout when
available. Missing shared-fixture dependencies are reported explicitly.

## Boot Mod Loader

Loader source and installation guidance: [Boot Mod Loader](https://github.com/pat-pat-patrick/boot-mod-loader).

`tools/build_steam_candidate.py` defines the current module graph and constructs
a folder candidate. `tools/build_steam_archive.py` packages that graph as a
Boot Mod Loader addon. Both default to development output under `dist/review`.
Inspect each tool's `--help` for required asset/native build inputs. Native bridge
sources are under `freecam/native/port51_src`; their availability depends on the
host. The Windows input helper remains a separate bundled process.

Run the Lua fixtures and verify the package's exact embedded source bytes,
checksums and startup/cleanup before distributing it. Numeric shader DoF and
scene effects must remain disabled until visually verified in the package.
Keep release artifacts under `dist/releases`.

## Chef preview

```powershell
py -3 tools/test_chef_port.py --sandbox <pinned-chef-sandbox.lua>
py -3 tools/build_chef_candidate.py --help
```

The [Chef port documentation](docs/CHEF-LOADER-PORT.md) identifies the required
upstream sandbox revision and preview limitations.

## Archived implementations

Retired BSL/MDL/LLL entrypoints and one-off deployment/review scripts are under
`archive/`. They are historical references, not supported build entrypoints.
