# DDS screenshot to PNG, in plain Lua

`png_stored.lua` turns a screenshot DDS into a PNG. Plain Lua 5.1, no `bit` library, no native code. It works a slice at a time so no single call runs long.

The PNG is uncompressed. It is about the size of the raw pixels, and any image viewer opens it.

| In | Out |
|----|-----|
| SDR screenshot (BGRA, what the loader saves normally) | 8-bit RGB PNG |
| HDR screenshot (10-bit RGB) | 16-bit RGB PNG tagged as HDR10 |

## How to use it

```lua
local png=dofile('png_stored.lua')

local job=png.begin_dds(dds_bytes)
out:write(job.head)
repeat
  local chunk=job:step(65536)      -- about this many bytes of input per call
  if chunk~=''then out:write(chunk)end
until job.done
out:write(job.tail)
```

- `job:step(bytes)` does a slice and hands back a piece of the file. It returns `''` when it has not got a full piece yet. Write what comes back as it comes.
- The output is the same whatever step size you use. You can change it between calls.
- `job.done`, `job:progress()` (0 to 1), `job.width`, `job.height`, `job.format`.
- `png.begin{width=,height=,format=,data=}` takes raw pixels instead of a DDS.
- `png.encode(spec)` does the whole thing in one call. Fine for small images.

Spread the calls over frames with `chef.spread` or a timer. Pick the step size from how much frame time you want to spend (see below).

## Speed

Measured on a 1920x1080 frame in plain Lua 5.1 (no JIT), on a 2026 desktop:

| Frame | Total time | 4K estimate |
|-------|------------|-------------|
| SDR 1920x1080 | 0.8 s | about 3 s |
| HDR 1920x1080 | 1.8 s | about 7 s |

So a 4K SDR shot at 64 KB a step costs about 6 ms a frame for 8 or 9 seconds. Halve the step, halve the cost, twice as long. HDR is a bit over double. Nothing comes close to Chef's 3-second limit.

Memory: the input string plus under 64 KB of carry. The checksum table is about 1 MB, built once.

## Tested

- `png_stored_tests.lua`: checksums, chunk layout, same output at every step size, HDR header, the DDS reader, bad input is refused.
- `test_png_stored.py`: decodes every PNG the module writes and checks every pixel against the source. Also opens them with Pillow when it is installed.
- The sample files opened fine in ImageMagick 7 and Pillow 13.

Run it with a Python that has `lupa`:

```bash
python -I tools/chef-png/test_png_stored.py --out dist/review/chef-png
```

## Not tested

- A real screenshot DDS from the game. The header layout is what the loader and War Journalist both see, but no game file has gone through it yet.
- How the HDR PNG looks. It is tagged HDR10. A viewer that understands the tag shows it right; one that does not shows it flat and bright.
