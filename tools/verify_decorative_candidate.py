"""Verify a decorative replacement candidate offline; never deploys or touches the game.

Each DXBC payload in a shader library is followed by a native stage record:
u32 stage id, padding to 8 bytes relative to the resource start, then the
binding words (0, 0x330, ...). All 40 shipped overlays, the scene template and
the live-qualified SDR library follow that rule. The first replacement build
(decorative-v2-r3) moved five pixel records by 4 bytes without re-padding,
so the renderer read shifted bindings and crashed at first draw.

This check requires, per replacement: identical vertex payload and stage
records, identical binding words after alignment, changes outside the pixel
payload limited to the content IDs and pixel length, matching pixel shader
declarations, a material differing only in its shader reference, and archives
preserving every prior resource with only the reviewed additions.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess

import photo_assets as a

SIZE_AT, PIXEL_ID_AT, PROGRAM_AT, VARIANT_AT = 0xbe0, 0xbe4, 0x88, 0xe0


def stage_record(body, start, end):
    ident = struct.unpack_from('<I', body, start)[0]
    content = (start + 4 + 7) // 8 * 8
    return ident, body[start + 4:content], body[content:end]


def declarations(listing):
    # Temp counts differ between pattern bodies; input linkage comes from the
    # ISGN signature (compared separately), so only the register is kept here.
    out = []
    for line in listing.splitlines():
        line = line.strip()
        if not line.startswith('dcl_') or line.startswith(('dcl_temps', 'dcl_indexableTemp')):
            continue
        if line.startswith('dcl_input_ps'):
            line = re.sub(r'(v\d+)\.[xyzw]+', r'\1', line)
        out.append(line)
    return sorted(out)


def signature(code, tag):
    """Signature elements without the per-shader used-component mask."""
    count = struct.unpack_from('<I', code, 28)[0]
    for index in range(count):
        at = struct.unpack_from('<I', code, 32 + index * 4)[0]
        if code[at:at + 4] != tag:
            continue
        data = at + 8
        elements = []
        for element in range(struct.unpack_from('<I', code, data)[0]):
            name_at, semantic, system, kind, register, mask = struct.unpack_from('<5IB', code, data + 8 + element * 24)
            name = code[data + name_at:code.index(b'\0', data + name_at)].decode()
            elements.append((name, semantic, system, kind, register, mask))
        return elements
    raise AssertionError('DXBC signature chunk missing')


class Listing:
    def __init__(self, compiler, dll, scratch):
        self.compiler, self.dll, self.scratch = compiler.resolve(), dll.resolve(), scratch

    def __call__(self, code):
        key = hashlib.sha256(code).hexdigest()
        src, dst, err = (self.scratch / (key + suffix) for suffix in ('.dxbc', '.listing', '.error'))
        src.write_bytes(code)
        win = lambda p: 'Z:' + str(p.resolve()).replace('/', '\\')
        env = dict(os.environ, WINEPREFIX=str(self.compiler.parent / 'prefix'), WINEDEBUG='-all')
        subprocess.run(['wine', str(self.compiler), win(self.dll), 'listing', win(src), win(dst), win(err)],
                       env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=45)
        return dst.read_bytes().rstrip(b'\0').decode(errors='replace')


def rows(path):
    return a.read_archive(path.read_bytes(), Path(str(path) + '.gpu_resources').read_bytes())


def verify(candidate, base_assets, listing):
    receipt = json.loads((candidate / 'DECORATIVE-CANDIDATE.json').read_text())
    materials = receipt['materials']
    base = {label: rows(base_assets / (label + '.patch_0')) for label in ('ee6b1ba7e22d71ed', '9ba626afa44a3aa3')}
    built = {label: rows(candidate / 'Assets' / (label + '.patch_0')) for label in base}
    report = {'candidate': str(candidate), 'replacements': {}}

    # Archive preservation: every prior non-registry row byte-identical; only reviewed additions.
    expected_added = set()
    for name, material in materials.items():
        expected_added.add((a.hash64(material.replace('/materials/', '/shaders/')), a.SHADER))
        expected_added.add((a.hash64(material), a.MATERIAL))
    for label in base:
        before = {r[:2]: r for r in base[label]}
        after = {r[:2]: r for r in built[label]}
        assert len(after) == len(built[label]), 'Duplicate resource rows in ' + label
        for key, row in before.items():
            assert key in after, 'Prior resource removed from ' + label
            if row[1] != a.GROUP:
                assert after[key] == row, 'Prior resource changed in ' + label
        added = set(after) - set(before)
        assert added <= expected_added, 'Unreviewed resource added to ' + label
        expected_added -= added
        groups = [key for key in before if key[1] == a.GROUP]
        for key in groups:
            old_ids, new_ids = list(a.registry_ids(before[key][2])), list(a.registry_ids(after[key][2]))
            shader_ids = [a.hash64(m.replace('/materials/', '/shaders/')) for m in materials.values()]
            assert new_ids == old_ids + shader_ids, 'Registry is not prior registrations plus the replacements'
            assert after[key][2][:16] == before[key][2][:16] and after[key][3] == before[key][3]
            report['registry'] = {'prior': len(old_ids), 'candidate': len(new_ids)}
    assert not expected_added, 'Reviewed replacement missing from candidate archives'

    core = {r[:2]: r for r in built['ee6b1ba7e22d71ed']}
    shared = {r[:2]: r for r in built['9ba626afa44a3aa3'] + built['ee6b1ba7e22d71ed']}
    prior = {r[:2]: r for r in base['ee6b1ba7e22d71ed'] + base['9ba626afa44a3aa3']}
    for name, material in materials.items():
        shader = material.replace('/materials/', '/shaders/')
        old_shader = 'mods/dbf_hud/shaders/mapped_' + name
        original = prior[a.hash64(old_shader), a.SHADER][3]
        body = core[a.hash64(shader), a.SHADER][3]
        assert core[a.hash64(shader), a.SHADER][2] == prior[a.hash64(old_shader), a.SHADER][2]
        (va, vs), (pa, ps) = a._dxbc_windows(original)
        windows = a._dxbc_windows(body)
        assert windows[0] == (va, vs) and windows[1][0] == pa, name + ': payload offsets moved'
        size = windows[1][1]
        assert struct.unpack_from('<I', body, SIZE_AT)[0] == size and struct.unpack_from('<I', original, SIZE_AT)[0] == ps
        assert len(body) - len(original) == size - ps

        # Content IDs are the only header/record words allowed to differ.
        ids = {struct.unpack_from('<I', original, PROGRAM_AT)[0]: a.hash64(shader + ':default:PLATFORM_WIN32:RENDERER_D3D11') >> 32,
               a.hash64(old_shader) >> 32: a.hash64(shader) >> 32,
               struct.unpack_from('<I', original, PIXEL_ID_AT)[0]: a.hash64(shader + ':pixel') >> 32}
        old_tail, new_tail = original[pa + ps:], body[pa + size:]
        assert len(old_tail) == len(new_tail)
        for old_part, new_part, offset in ((original[:pa], body[:pa], 0), (old_tail, new_tail, pa + ps)):
            for at in range(0, len(old_part), 4):
                before_word = struct.unpack_from('<I', old_part, at)[0]
                after_word = struct.unpack_from('<I', new_part, at)[0]
                if before_word == after_word:
                    continue
                if offset == 0 and at == SIZE_AT:
                    continue
                assert ids.get(before_word) == after_word, '%s: unexpected change at 0x%x' % (name, offset + at)

        # Stage records: same residue, same padding, same binding words after alignment.
        records = {}
        for stage, old_start, old_end, new_start, new_end in (
                ('vertex', va + vs, pa, va + vs, pa),
                ('pixel', pa + ps, len(original), pa + size, len(body))):
            old_id, old_pad, old_words = stage_record(original, old_start, old_end)
            new_id, new_pad, new_words = stage_record(body, new_start, new_end)
            assert old_start % 8 == new_start % 8, '%s: %s stage record residue changed' % (name, stage)
            assert old_pad == new_pad == bytes(len(new_pad)) and old_words == new_words
            assert struct.unpack_from('<2I', new_words) == (0, 0x330)
            assert ids.get(old_id, old_id) == new_id
            records[stage] = {'offset_mod8': new_start % 8, 'pad_bytes': len(new_pad), 'binding_words_identical': True}

        # Pixel payload: valid DXBC with the original interface declarations.
        code = body[pa:pa + size]
        source = (a.ROOT / 'freecam/assets/decorative-v2' / (name + '.hlsl')).read_bytes()
        assert struct.unpack_from('<I', code, 24)[0] == size and code[:4] == b'DXBC'
        old_declarations = declarations(listing(original[pa:pa + ps]))
        new_listing = listing(code)
        new_declarations = declarations(new_listing)
        for tag in (b'ISGN', b'OSGN'):
            assert signature(code, tag) == signature(original[pa:pa + ps], tag), name + ': stage signature differs'
        assert new_declarations == old_declarations, '%s: interface declarations differ\n%s\n%s' % (
            name, old_declarations, new_declarations)

        # Material: byte-identical except its shader reference.
        old_material = prior[a.hash64('mods/dbf_hud/materials/mapped_' + name), a.MATERIAL][2]
        new_material = shared[a.hash64(material), a.MATERIAL][2]
        assert len(old_material) == len(new_material)
        assert struct.unpack_from('<I', old_material, 128)[0] == a.hash64(old_shader) >> 32
        assert struct.unpack_from('<I', new_material, 128)[0] == a.hash64(shader) >> 32
        assert old_material[:128] == new_material[:128] and old_material[132:] == new_material[132:]

        report['replacements'][name] = {
            'shader': shader, 'material': material, 'pixel_bytes': size, 'original_pixel_bytes': ps,
            'pixel_size_mod16_preserved': size % 16 == ps % 16, 'stage_records': records,
            'declarations': len(new_declarations), 'hlsl_sha256': hashlib.sha256(source).hexdigest(),
            'instruction_lines': sum(1 for line in new_listing.splitlines() if re.match(r'^\s*[a-z_]+(\s|$)', line)
                                     and not line.strip().startswith(('dcl_', 'ps_', '//')))}
    report['passed'] = True
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for name in ('candidate', 'base-assets', 'compiler', 'dll'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    scratch = args.candidate.resolve() / 'verify-scratch'
    scratch.mkdir(exist_ok=True)
    result = verify(args.candidate.resolve(), args.base_assets.resolve(), Listing(args.compiler, args.dll, scratch))
    (args.candidate / 'DECORATIVE-VERIFY.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'replacements'}, indent=2))
    for name, row in result['replacements'].items():
        print(name, row['pixel_bytes'], row['stage_records']['pixel'], row['declarations'], row['instruction_lines'])
