# Build and validation

This branch is the Proton LuaJIT integration candidate. Use `tools/build_proton_candidate.py` and then `tools/build_proton_archive.py`. See [the port report](docs/PROTON-LUA51-PARITY-20261106.md) for source revisions, verification and live acceptance. The BML/Chef instructions below describe the Lua 5.1 source line.

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
a folder candidate. `tools/build_package.py` packages that graph as the one
War Journalist package (below). Both write under `dist/review`.
Inspect each tool's `--help` for required asset/native build inputs. Native bridge
sources are under `freecam/native/port51_src`; their availability depends on the
host. The Windows input helper remains a separate bundled process; the exact
sources of the shipped helper are in `helper/` ([helper/README.md](helper/README.md)).

Run the Lua fixtures and verify the package's exact embedded source bytes,
checksums and startup/cleanup before distributing it. Numeric shader DoF and
scene effects must remain disabled until visually verified in the package.
Keep release artifacts under `dist/releases`.

## One package for Boot Mod Loader and Chef

One ZIP, one resource (`mods/goose/war_journalist`): Boot Mod Loader runs it with
the WJL helper, Chef Shared Loader 1.4.0 or newer runs it with its own host, and
the head picks from the loader's argument. `tools/package_head.py` writes the head
(`boot_host`, `chef_host`, the version gate, the 1.3.x key carry-over);
`tools/package_fixtures.py` holds the offline proofs.

Two inputs are gitignored copies, pinned by hash; copy them into a fresh
worktree before building:
- Chef's own `src/chef_loader/sandbox.lua` per release, as
  `dist/chef-src/sandbox/sandbox-v<version>.lua` (blobs in
  `tools/test_chef_port.py`), from `~/Worktrees/linux-hd2/wj-chef-lite/dist/chef-src/sandbox/`.
- Boot Mod Loader 0.13.4's loader, `f476df93691895fa.lua` (sha256
  `7cc69039…`), as `dist/bml-src/f476df93691895fa.lua`, from the Boot Mod
  Loader 0.13.4 folder in `~/.config/hd2arsenal/mods/`. Without the copy the
  Arsenal folder is read, as long as it still holds 0.13.4.

```bash
python tools/test_package.py            # compose from this tree, prove it on every host
python tools/test_package.py --release
python tools/build_package.py --dev 1   # dist/review/package/1.4.0-dev.1/
python tools/test_package.py --zip dist/review/package/1.4.0-dev.1/War-Journalist-1.4.0-dev.1.zip
python tools/build_package.py --release # needs docs/RELEASE-<VERSION>.md and RELEASE_DESCRIPTION
```

The text must stay under 3,800,000 bytes: Chef never runs a Lua resource over
4 MiB, and the build stops with the size named.

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
