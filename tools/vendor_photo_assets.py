"""One-time explicit vendor import; normal release builds never read HUD/game data.

Select a retained owning-HUD archive, its matching animated HLSL directory, and
the original 77-entry game registry. Copy only the 40 mapped shader/material
pairs after validating closure, variants and their source registry membership.
No unrelated resources, textures, fonts, scene/DoF experiments or settings copy.
"""
import argparse
import ctypes
import json
from pathlib import Path
import struct
import zipfile

import photo_assets as assets

ORIGINAL_GROUP_SHA256 = 'f62a82b5fc095c42958a1f30fe6a1f7846107d197960b3e5beb72bda18b86040'


def spec(name, body):
    return {'file': name, 'bytes': len(body), 'sha256': assets.sha256(body)}


def shader_sections(body):
    count = struct.unpack_from('<I', body, 28)[0]
    if count > 128 or 32 + count * 4 > len(body):
        raise ValueError('Shader section table exceeds DXBC bytes')
    sections = {}
    for offset in struct.unpack_from('<' + str(count) + 'I', body, 32):
        if offset + 8 > len(body):
            raise ValueError('Shader section header exceeds DXBC bytes')
        name = body[offset:offset + 4]
        size = struct.unpack_from('<I', body, offset + 4)[0]
        if offset + 8 + size > len(body):
            raise ValueError('Shader section exceeds DXBC bytes')
        sections[name] = body[offset + 8:offset + 8 + size]
    return sections


def validate_hlsl(source, library):
    """Compile in memory; prove owned HLSL matches the preserved pixel program."""
    compiler = ctypes.WinDLL('d3dcompiler_47.dll').D3DCompile
    compiler.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p,
                        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p,
                        ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint,
                        ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p)]
    compiler.restype = ctypes.c_long

    def take_blob(pointer):
        if not pointer:
            return b''
        methods = ctypes.cast(pointer, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        address = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(methods[3])(pointer)
        size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(methods[4])(pointer)
        result = ctypes.string_at(address, size)
        ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(methods[2])(pointer)
        return result

    code, error = ctypes.c_void_p(), ctypes.c_void_p()
    buffer = ctypes.create_string_buffer(source)
    result = compiler(buffer, len(source), None, None, None, b'hud_fill', b'ps_5_0',
                      1 << 15, 0, ctypes.byref(code), ctypes.byref(error))
    diagnostics, compiled = take_blob(error), take_blob(code)
    if result < 0:
        raise ValueError('Photo HLSL did not compile: ' + diagnostics.decode(errors='replace'))
    offset, size = assets._dxbc_windows(library)[1]
    original, rebuilt = shader_sections(library[offset:offset + size]), shader_sections(compiled)
    for name in (b'SHEX', b'SHDR', b'RDEF', b'ISGN', b'OSGN'):
        if original.get(name) != rebuilt.get(name):
            raise ValueError('Preserved shader differs from animated HLSL: ' + name.decode())
    return {'compiler': 'Windows d3dcompiler_47.dll D3DCompile', 'entry': 'hud_fill',
            'target': 'ps_5_0', 'optimization': 3,
            'instruction_reflection_and_signature_sections_match': True}


def vendor(source_zip, hlsl_dir, original_group, output):
    group = original_group.read_bytes()
    if len(assets.registry_ids(group)) != 77 or assets.sha256(group) != ORIGINAL_GROUP_SHA256:
        raise ValueError('Expected the verified ORIGINAL game default shader group')
    sources = sorted(hlsl_dir.glob('*.hlsl'))
    if len(sources) != 40:
        raise ValueError('Expected exactly 40 animated mapped HLSL sources')
    blobs, overlays = {'original-default-shaders.bin': group}, []
    with zipfile.ZipFile(source_zip) as archive:
        cpu_names = [name for name in archive.namelist()
                     if name.endswith('.patch_0') and '/native/' in '/' + name]
        if len(cpu_names) != 1:
            raise ValueError('Select a retained HUD archive with one native CPU archive')
        stem = cpu_names[0]
        cpu = archive.read(stem)
        gpu_name = stem + '.gpu_resources'
        stream_name = stem + '.stream'
        gpu_size = archive.getinfo(gpu_name).file_size
        stream_size = archive.getinfo(stream_name).file_size
        rows = assets.archive_index(cpu, gpu_size, stream_size)
        by_id = {row[:2]: row for row in rows}
        registry = by_id[(assets.hash64(assets.GROUP_NAME), assets.GROUP)]
        source_group = cpu[registry[2]:registry[2] + registry[7]]
        registered = set(assets.registry_ids(source_group))
        selected = []
        for path in sources:
            name = path.stem
            shader = 'mods/dbf_hud/shaders/mapped_' + name
            material = 'mods/dbf_hud/materials/mapped_' + name
            shader_row = by_id[(assets.hash64(shader), assets.SHADER)]
            material_row = by_id[(assets.hash64(material), assets.MATERIAL)]
            if shader_row[0] not in registered:
                raise ValueError('Mapped shader was not registered in source archive')
            if shader_row[8] or material_row[8] or material_row[9]:
                raise ValueError('Unexpected external material/stream dependency')
            shader_cpu = cpu[shader_row[2]:shader_row[2] + shader_row[7]]
            material_cpu = cpu[material_row[2]:material_row[2] + material_row[7]]
            if shader_cpu != struct.pack('<I', 4) or len(material_cpu) != 144:
                raise ValueError('Unsupported mapped shader/material CPU layout')
            if struct.unpack_from('<I', material_cpu, 128)[0] != assets.hash64(shader) >> 32 or material_cpu[132:] != b'\0' * 12:
                raise ValueError('Material variant/texture closure differs')
            blobs[name + '.material.bin'] = material_cpu
            blobs[name + '.shader.bin'] = shader_cpu
            blobs[name + '.hlsl'] = path.read_bytes()
            selected.append((shader_row[4], shader_row[9], name, shader, material))
        # One forward stream through the compressed GPU member; no 1 GB inflate
        # into memory and no copying of its unrelated native/font/texture bytes.
        with archive.open(gpu_name) as stream:
            for offset, size, name, shader, material in sorted(selected):
                stream.seek(offset)
                gpu = stream.read(size)
                if len(gpu) != size or len(assets._dxbc_windows(gpu)) != 2:
                    raise ValueError('Mapped shader GPU payload incomplete')
                proof = validate_hlsl(blobs[name + '.hlsl'], gpu)
                blobs[name + '.shader.gpu'] = gpu
                overlays.append({'id': name, 'material': material, 'shader': shader,
                                 'material_cpu': spec(name + '.material.bin', blobs[name + '.material.bin']),
                                 'shader_cpu': spec(name + '.shader.bin', blobs[name + '.shader.bin']),
                                 'shader_gpu': spec(name + '.shader.gpu', gpu),
                                 'hlsl': spec(name + '.hlsl', blobs[name + '.hlsl']),
                                 'hlsl_validation': proof})
    manifest = {'schema': 1, 'owner': 'War Journalist / DBF_PhotoMode',
                'source_archive': source_zip.name, 'source_archive_sha256': assets.sha256(source_zip.read_bytes()),
                'source_cpu_entry': stem, 'source_cpu_sha256': assets.sha256(cpu),
                'source_registry_sha256': assets.sha256(source_group),
                'source_shader_registrations': len(registered),
                'source_hlsl_directory': 'DBF-HUD/assets/panel-shaders/animated',
                'original_registry': spec('original-default-shaders.bin', group),
                'original_registry_provenance': 'Original ee6b1ba7e22d71ed base archive via read-only DSAR/DSAA bundles.nxa access; 953 base resources, 77 default registrations. Hash verified against the retained HUD original group, not an installed patch.',
                'dependencies': {'textures': [], 'fonts': [], 'other_mods': [],
                                 'game_render_targets': ['linear_depth'],
                                 'linear_depth_use': 'Only under scissor_mode > 0.5; Photo Mode sets scissor_mode=0.'},
                'coexistence_limit': 'Other packages replacing core/stingray_renderer/shader_libraries/default_shaders must union shader IDs. A separate higher-priority group can hide these or another mod\'s registrations; arbitrary patch stacking does not merge registry resources.',
                'resource_names_preserved': True, 'compiled_bytes_preserved': True,
                'textures_fonts_and_hud_runtime_included': False, 'scene_or_dof_assets_included': False,
                'live_validation': False, 'overlays': sorted(overlays, key=lambda row: row['id'])}
    # Materialize only after the complete dependency import has passed.
    output.mkdir(parents=True, exist_ok=True)
    for name, body in sorted(blobs.items()):
        target = output / name
        if target.exists() and target.read_bytes() != body:
            raise ValueError('Refusing to replace existing vendor blob: ' + name)
        target.write_bytes(body)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return assets.validate_assets(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-zip', type=Path, required=True)
    parser.add_argument('--hlsl-dir', type=Path, required=True)
    parser.add_argument('--original-group', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=assets.ASSETS)
    args = parser.parse_args()
    audit = vendor(args.source_zip, args.hlsl_dir, args.original_group, args.output)
    print(json.dumps({key: value for key, value in audit.items() if key != 'overlays'}, indent=2))


if __name__ == '__main__':
    main()
