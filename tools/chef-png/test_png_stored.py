"""Run the Lua tests, then decode what png_stored.lua writes and check every pixel.
Prints how long a 1920x1080 frame takes. Writes nothing unless --out is given."""
from pathlib import Path
import argparse, json, random, struct, sys, time, zlib

HERE = Path(__file__).resolve().parent


def chunks(png):
    assert png[:8] == b'\x89PNG\r\n\x1a\n', 'signature'
    at, out = 8, []
    while at < len(png):
        length, kind = struct.unpack_from('>I4s', png, at)
        data = png[at + 8:at + 8 + length]
        crc, = struct.unpack_from('>I', png, at + 8 + length)
        assert crc == zlib.crc32(kind + data) & 0xffffffff, 'CRC of ' + kind.decode()
        out.append((kind, data))
        at += 12 + length
    assert out[0][0] == b'IHDR' and out[-1][0] == b'IEND', 'IHDR first, IEND last'
    idats = [i for i, (k, _) in enumerate(out) if k == b'IDAT']
    assert idats and idats == list(range(idats[0], idats[-1] + 1)), 'IDAT chunks are consecutive'
    return out


def stream(png):
    return b''.join(d for k, d in chunks(png) if k == b'IDAT')


def blocks(zstream):
    """Walk the blocks and count them."""
    assert zstream[:2] == b'\x78\x01'
    at, count, final = 2, 0, False
    while at < len(zstream) - 4:
        assert not final, 'data after the final block'
        head, length, nlength = zstream[at], struct.unpack_from('<HH', zstream, at + 1)[0], struct.unpack_from('<HH', zstream, at + 1)[1]
        assert head in (0, 1) and nlength == length ^ 0xffff and length <= 65535, 'stored block header'
        final = head == 1
        at += 5 + length
        count += 1
    assert final and at == len(zstream) - 4, 'the stream ends with the final block and the Adler-32'
    return count


def decode(png):
    out = chunks(png)
    w, h, depth, color, comp, filt, inter = struct.unpack('>IIBBBBB', out[0][1])
    assert (color, comp, filt, inter) == (2, 0, 0, 0) and depth in (8, 16), 'IHDR'
    stream = b''.join(d for k, d in out if k == b'IDAT')
    assert stream[:2] == b'\x78\x01', 'zlib header'
    raw = zlib.decompress(stream)  # also checks the Adler-32 trailer
    bpp = 3 * depth // 8
    assert len(raw) == h * (1 + w * bpp), 'decoded size'
    rows = []
    for y in range(h):
        row = raw[y * (1 + w * bpp):(y + 1) * (1 + w * bpp)]
        assert row[0] == 0, 'filter byte'
        rows.append(row[1:])
    return w, h, depth, rows, [k for k, _ in out]


def expect_sdr(bgra, w, h, pitch=None):
    pitch = pitch or w * 4
    rows = []
    for y in range(h):
        r = bgra[y * pitch:y * pitch + w * 4]
        rows.append(bytes(b for x in range(w) for b in (r[x * 4 + 2], r[x * 4 + 1], r[x * 4])))
    return rows


def expect_hdr(packed, w, h):
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            v, = struct.unpack_from('<I', packed, (y * w + x) * 4)
            for c in (v & 1023, (v >> 10) & 1023, (v >> 20) & 1023):
                row += struct.pack('>H', (c << 6) | (c >> 4))
        rows.append(bytes(row))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, help='also write the sample PNGs here')
    parser.add_argument('--size', default='1920x1080', help='timed frame size')
    args = parser.parse_args()
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(encoding=None)
    import os
    previous = os.getcwd()
    os.chdir(HERE)
    try:
        assert lua.eval(b'_VERSION') == b'Lua 5.1' and lua.eval(b'jit==nil and bit==nil'), 'plain Lua 5.1 without bit'
        lua.execute((HERE / 'png_stored_tests.lua').read_bytes())
        png = lua.execute(b"return dofile('png_stored.lua')")
    finally:
        os.chdir(previous)
    rng = random.Random(20261031)
    report = {'lua_tests': 'passed'}
    samples = {}

    def encode(spec, step=None):
        t = lua.table_from({k.encode(): v for k, v in spec.items()})
        job = png.begin(t)
        parts = [job.head]
        n = 0
        while not job.done:
            parts.append(job.step(job, step if step else 1 << 30))
            n += 1
        parts.append(job.tail)
        return b''.join(parts), n

    # SDR, padded rows, a few step sizes.
    w, h, pitch = 37, 11, 37 * 4 + 12
    bgra = bytes(rng.randrange(256) for _ in range(pitch * h))
    expected = expect_sdr(bgra, w, h, pitch)
    whole, _ = encode({'width': w, 'height': h, 'format': b'bgra8', 'data': bgra, 'pitch': pitch})
    for step in (1, 200, 70000, None):
        out, steps = encode({'width': w, 'height': h, 'format': b'bgra8', 'data': bgra, 'pitch': pitch}, step)
        assert stream(out) == stream(whole), f'step {step} changed the stream'
        dw, dh, depth, rows, kinds = decode(out)
        assert (dw, dh, depth) == (w, h, 8) and rows == expected, f'SDR pixels (step {step})'
    samples['sdr_37x11.png'] = whole
    # Rows that cross block boundaries.
    w, h = 1000, 70
    bgra = bytes(rng.randrange(256) for _ in range(w * h * 4))
    out, steps = encode({'width': w, 'height': h, 'format': b'bgra8', 'data': bgra}, 50000)
    dw, dh, depth, rows, kinds = decode(out)
    assert rows == expect_sdr(bgra, w, h), 'SDR 1000x70 pixels'
    assert blocks(stream(out)) >= 3 and steps == 6, ('SDR 1000x70 across blocks', blocks(stream(out)), steps)
    assert blocks(stream(whole)) == 1 and blocks(stream(samples['sdr_37x11.png'])) == 1
    assert stream(out) == stream(encode({'width': w, 'height': h, 'format': b'bgra8', 'data': bgra})[0])
    samples['sdr_1000x70.png'] = out
    # HDR.
    w, h = 23, 9
    packed = b''.join(struct.pack('<I', rng.randrange(1 << 32)) for _ in range(w * h))
    out, _ = encode({'width': w, 'height': h, 'format': b'rgb10a2', 'data': packed}, 400)
    dw, dh, depth, rows, kinds = decode(out)
    assert (dw, dh, depth) == (w, h, 16) and rows == expect_hdr(packed, w, h), 'HDR samples'
    assert kinds[1] == b'cICP', 'cICP follows IHDR'
    samples['hdr_23x9.png'] = out
    # A DDS the way the game writes it.
    w, h = 16, 4
    bgra = bytes(rng.randrange(256) for _ in range(w * h * 4))
    header = bytearray(148)
    header[0:4] = b'DDS '
    struct.pack_into('<I', header, 4, 124); struct.pack_into('<I', header, 12, h); struct.pack_into('<I', header, 16, w)
    struct.pack_into('<I', header, 20, w * 4); header[84:88] = b'DX10'
    struct.pack_into('<IIII', header, 128, 28, 3, 0, 1)
    job = png.begin_dds(bytes(header) + bgra)
    parts = [job.head]
    while not job.done:
        parts.append(job.step(job, 64))
    parts.append(job.tail)
    out = b''.join(parts)
    assert decode(out)[3] == expect_sdr(bgra, w, h) and job.dds.engine_label is True, 'DDS path'
    samples['dds_16x4.png'] = out
    # Pillow, if installed.
    try:
        from PIL import Image
        import io
        for name, blob in samples.items():
            image = Image.open(io.BytesIO(blob)); image.load()
        image = Image.open(io.BytesIO(samples['sdr_1000x70.png']))
        assert image.mode == 'RGB' and image.size == (1000, 70)
        report['pillow'] = 'opened all samples; SDR mode RGB'
    except ImportError:
        report['pillow'] = 'not installed'
    # Timing.
    tw, th =(int(v) for v in args.size.split('x'))
    block = bytes(rng.randrange(256) for _ in range(65536))
    frame = (block * (tw * th * 4 // 65536 + 1))[:tw * th * 4]
    for fmt in ('bgra8', 'rgb10a2'):
        t = lua.table_from({b'width': tw, b'height': th, b'format': fmt.encode(), b'data': frame})
        job = png.begin(t)
        started = time.perf_counter(); steps = 0; longest = 0.0; out_bytes = len(job.head) + len(job.tail)
        while not job.done:
            s0 = time.perf_counter(); out_bytes += len(job.step(job, 262144)); steps += 1
            longest = max(longest, time.perf_counter() - s0)
        total = time.perf_counter() - started
        report[fmt] = {'frame': args.size, 'input_mb': round(tw * th * 4 / 1048576, 1), 'output_mb': round(out_bytes / 1048576, 1),
                       'seconds': round(total, 2), 'input_mb_per_s': round(tw * th * 4 / 1048576 / total, 2),
                       'steps_of_256k': steps, 'longest_step_ms': round(longest * 1000, 1),
                       'estimate_3840x2160_s': round(total * (3840 * 2160) / (tw * th), 1)}
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        for name, blob in samples.items():
            (args.out / name).write_bytes(blob)
        report['written'] = str(args.out)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
