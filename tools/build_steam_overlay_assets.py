"""Build review-only private material aliases; never installs or emits a patch.

Shader identities and compiled payloads remain exactly as vendored. An explicit
stock-union mode includes a baseline registry for review, without qualifying
effective archive priority or coexistence with other registrations.
"""
import argparse
import json
from pathlib import Path
import re
import struct

import photo_assets

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / 'dist/review'
PRIVATE_PREFIX = 'mods/dbf_photo/materials/mapped_'
CPU_FILE = 'private-overlays.resources.cpu.bin'
GPU_FILE = 'private-overlays.resources.gpu.bin'
CORE_ARCHIVE = 'ee6b1ba7e22d71ed'
SHARED_ARCHIVE = '9ba626afa44a3aa3'
CORE_CPU_FILE = 'core-' + CORE_ARCHIVE + '.resources.cpu.bin'
CORE_GPU_FILE = 'core-' + CORE_ARCHIVE + '.resources.gpu.bin'
SHARED_CPU_FILE = 'shared-' + SHARED_ARCHIVE + '.resources.cpu.bin'
SHARED_GPU_FILE = 'shared-' + SHARED_ARCHIVE + '.resources.gpu.bin'
NOTICE = ('NOT INSTALLABLE: shader registry union/coexistence and live rendering '
          'must be qualified before any installation.\n'
          'Review payload only; no game patch, installer or default_shaders '
          'replacement is included. Frozen source assets remain unchanged.\n')
UNION_NOTICE = ('NOT INSTALLABLE: effective archive priority, registry coexistence '
                'and live rendering remain unqualified.\n'
                'Review payload only; no game patch or installer is emitted. '
                'The registry contains all 77 vendored stock IDs and the exact '
                '40 decorative library IDs, with all 40 decorative CPU/GPU '
                'libraries included. Stock library payloads remain supplied '
                'by the game. Other active shader registrations require a '
                'complete effective union. Frozen source assets remain unchanged.\n')


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode('utf-8')


def source_snapshot():
    folder = photo_assets.ASSETS
    manifest_body = (folder / 'manifest.json').read_bytes()
    manifest = json.loads(manifest_body)
    names = {'manifest.json', manifest['original_registry']['file']}
    for overlay in manifest['overlays']:
        names.update(overlay[key]['file'] for key in ('material_cpu', 'shader_cpu', 'shader_gpu', 'hlsl'))
    if any(Path(name).name != name for name in names):
        raise ValueError('Source assets must use leaf filenames')
    return {name: photo_assets.sha256((folder / name).read_bytes()) for name in sorted(names)}


def candidate_files(include_stock_registry=False):
    """Return deterministic artifact bytes, after validating immutable sources."""
    before = source_snapshot()
    audit = photo_assets.validate_assets()
    manifest_body = (photo_assets.ASSETS / 'manifest.json').read_bytes()
    if audit['manifest_sha256'] != before['manifest.json'] or photo_assets.sha256(manifest_body) != before['manifest.json']:
        raise ValueError('Source manifest changed while validating the review candidate')
    manifest = json.loads(manifest_body)
    source = {row[:2]: row for row in photo_assets.load_resources()}
    if len(source) != 80:
        raise ValueError('Expected exactly 40 original material/shader pairs')
    source_names = {row[0] for row in source.values()}
    resources, descriptions, lookup, requirements = [], {}, {}, []
    for overlay in manifest['overlays']:
        label = overlay['id']
        if not isinstance(label, str) or not re.fullmatch(r'[a-z][a-z0-9_]*', label) or label in lookup:
            raise ValueError('Invalid or duplicate overlay ID')
        old_name = 'mods/dbf_hud/materials/mapped_' + label
        shader_name = 'mods/dbf_hud/shaders/mapped_' + label
        if overlay['material'] != old_name or overlay['shader'] != shader_name:
            raise ValueError('Established source resource names changed')
        private_name = PRIVATE_PREFIX + label
        private_id = photo_assets.hash64(private_name)
        shader_id = photo_assets.hash64(shader_name)
        material = source[photo_assets.hash64(old_name), photo_assets.MATERIAL]
        shader = source[shader_id, photo_assets.SHADER]
        if private_id in source_names or (private_id, photo_assets.MATERIAL) in descriptions:
            raise ValueError('Private material resource identity collision')
        variant = shader_id >> 32
        if (len(material[2]) != 144 or material[3] or
                photo_assets.sha256(material[2]) != overlay['material_cpu']['sha256'] or
                struct.unpack_from('<I', material[2], 128)[0] != variant or
                photo_assets.sha256(shader[2]) != overlay['shader_cpu']['sha256'] or
                photo_assets.sha256(shader[3]) != overlay['shader_gpu']['sha256']):
            raise ValueError('Aliased payload or shader linkage differs from the validated source')
        alias = (private_id, photo_assets.MATERIAL, material[2], material[3])
        resources.extend((alias, shader))
        lookup[label] = private_name
        descriptions[alias[:2]] = {'overlay': label, 'resource_name': private_name,
            'resource_type': 'material', 'source_resource_name': old_name,
            'shader_resource_name': shader_name, 'shader_hash64': f'{shader_id:016x}',
            'material_variant_id': f'{variant:08x}'}
        descriptions[shader[:2]] = {'overlay': label, 'resource_name': shader_name,
            'resource_type': 'shader_library', 'source_resource_name': shader_name}
        requirements.append({'resource_name': shader_name, 'resource_hash64': f'{shader_id:016x}'})
    if len(lookup) != 40 or len(descriptions) != 80 or len({row[:2] for row in resources}) != 80:
        raise ValueError('Private overlay closure must have 40 distinct aliases and shaders')
    registry = None
    archives = [('detached', None, CPU_FILE, GPU_FILE, resources)]
    if include_stock_registry:
        group = photo_assets.registry_resource()
        stock = (photo_assets.ASSETS / manifest['original_registry']['file']).read_bytes()
        stock_ids = photo_assets.registry_ids(stock)
        library_ids = tuple(photo_assets.hash64(item['shader']) for item in manifest['overlays'])
        ids = photo_assets.registry_ids(group[2])
        if (group[:2] != (photo_assets.hash64(photo_assets.GROUP_NAME), photo_assets.GROUP) or group[3] or
                photo_assets.sha256(stock) != before[manifest['original_registry']['file']] or
                len(stock_ids) != 77 or len(ids) != 117 or ids != stock_ids + library_ids or
                group[2][:16] != stock[:16] or group[2][20:24] != stock[20:24] or
                group[0] in {row[0] for row in resources}):
            raise ValueError('Registry must preserve the complete stock77 plus exact40 shader union')
        descriptions[group[:2]] = {'resource_name': photo_assets.GROUP_NAME,
            'resource_type': 'shader_library_group', 'source_resource_name': photo_assets.GROUP_NAME}
        archives = [
            ('core', CORE_ARCHIVE, CORE_CPU_FILE, CORE_GPU_FILE,
             [row for row in resources if row[1] == photo_assets.SHADER] + [group]),
            ('shared', SHARED_ARCHIVE, SHARED_CPU_FILE, SHARED_GPU_FILE,
             [row for row in resources if row[1] == photo_assets.MATERIAL])]
        registry = {'scope': 'vendored-stock-77-plus-exact-40-decorative-libraries',
            'stock_ids': 77, 'decorative_ids': 40, 'total_ids': 117,
            'stock_registry_sha256': photo_assets.sha256(stock),
            'required_effective_registry_sha256': photo_assets.sha256(stock),
            'effective_registry_verified': False,
            'candidate_registry_sha256': photo_assets.sha256(group[2]),
            'stock_library_payloads_included': False, 'requires_game_stock_libraries': True}
    rows, payloads, archive_table = [], {}, []
    for role, logical_archive, cpu_file, gpu_file, archive_resources in archives:
        cpu, gpu = photo_assets.archive_rows(archive_resources)
        actual = photo_assets.read_archive(cpu, gpu)
        expected = {row[:2]: row for row in archive_resources}
        if len(actual) != len(expected) or {row[:2]: row for row in actual} != expected:
            raise ValueError('Review archive round trip changed a resource')
        payloads.update({cpu_file: cpu, gpu_file: gpu})
        archive_table.append({'role': role, 'logical_archive': logical_archive,
            'cpu_file': cpu_file, 'gpu_file': gpu_file, 'resource_count': len(actual),
            'cpu_sha256': photo_assets.sha256(cpu), 'gpu_sha256': photo_assets.sha256(gpu)})
        for row in photo_assets.archive_index(cpu, len(gpu)):
            description = dict(descriptions[row[0], row[1]])
            body, external = cpu[row[2]:row[2] + row[7]], gpu[row[4]:row[4] + row[9]]
            description.update({'resource_hash64': f'{row[0]:016x}', 'type_hash64': f'{row[1]:016x}',
                'cpu_file': cpu_file, 'gpu_file': gpu_file, 'logical_archive': logical_archive,
                'cpu_offset': row[2], 'cpu_bytes': len(body), 'cpu_sha256': photo_assets.sha256(body),
                'gpu_offset': row[4], 'gpu_bytes': len(external), 'gpu_sha256': photo_assets.sha256(external)})
            rows.append(description)
    if source_snapshot() != before:
        raise ValueError('Source assets changed while building the review candidate')
    qualification = {'review_only': True, 'installable': False, 'installed': False,
        'registry_included': include_stock_registry, 'registry_union_qualified': False,
        'archive_priority_qualified': False,
        'coexistence_qualified': False, 'live_rendering_qualified': False}
    notice = UNION_NOTICE if include_stock_registry else NOTICE
    files = {**payloads, 'REVIEW-ONLY.txt': notice.encode('utf-8'),
        'MATERIAL-LOOKUP.json': json_bytes(lookup),
        'RESOURCE-TABLE.json': json_bytes({'schema': 1, **qualification,
            'archives': archive_table, 'resources': rows}),
        'SHADER-REGISTRY-REQUIREMENTS.json': json_bytes({'schema': 1, **qualification,
            'requirement_only': True, 'requires_union_with_complete_current_registry': True,
            'registry_resource_name': photo_assets.GROUP_NAME,
            'registry_resource_hash64': f'{photo_assets.hash64(photo_assets.GROUP_NAME):016x}',
            'shader_libraries': sorted(requirements, key=lambda item: item['resource_name']),
            'coexistence_limit': audit['coexistence_limit']}),
        'BUILD-RECEIPT.json': json_bytes({'schema': 1, **qualification, 'notice': notice,
            'materials': 40, 'shader_libraries': 40, 'resource_count': len(rows),
            'archives': archive_table, 'registry': registry,
            'private_material_prefix': PRIVATE_PREFIX, 'source_manifest_sha256': audit['manifest_sha256'],
            'source_files_sha256': before, 'source_assets_unchanged': True,
            'material_bytes_unchanged': True, 'shader_identities_and_bytes_unchanged': True})}
    files['FILES-SHA256.txt'] = ''.join(photo_assets.sha256(body) + '  ' + name + '\n'
        for name, body in sorted(files.items())).encode('ascii')
    return files


def stock_union_resources():
    """Return exact (core41, shared40, receipt) rows for a separate cold installer.

    This validates source bytes only. The installer must independently verify
    the effective base registry fingerprint and account for every active patch.
    """
    files = candidate_files(include_stock_registry=True)
    core = tuple(photo_assets.read_archive(files[CORE_CPU_FILE], files[CORE_GPU_FILE]))
    shared = tuple(photo_assets.read_archive(files[SHARED_CPU_FILE], files[SHARED_GPU_FILE]))
    return core, shared, json.loads(files['BUILD-RECEIPT.json'])


def review_path(output):
    output = Path(output).resolve()
    review = REVIEW.resolve()
    if output == review or not output.is_relative_to(review):
        raise ValueError('Output must be a new child directory under dist/review')
    if output.exists():
        raise FileExistsError('Refusing to overwrite an existing review or frozen candidate')
    return output


def build(output, include_stock_registry=False):
    output = review_path(output)
    files = candidate_files(include_stock_registry=include_stock_registry)
    output.parent.mkdir(parents=True, exist_ok=True)
    output = review_path(output)
    output.mkdir()
    # Mark the directory before publishing any binary payload, even if IO fails.
    for name in ['REVIEW-ONLY.txt'] + [name for name in sorted(files) if name != 'REVIEW-ONLY.txt']:
        with (output / name).open('xb') as stream:
            stream.write(files[name])
    for name, body in files.items():
        if (output / name).read_bytes() != body:
            raise ValueError('Review artifact byte verification failed: ' + name)
    return {'output': str(output), 'review_only': True, 'installable': False,
        'resource_count': 81 if include_stock_registry else 80,
        'registry_included': include_stock_registry, 'archive_priority_qualified': False,
        'files_sha256': {name: photo_assets.sha256(body) for name, body in sorted(files.items())}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True,
                        help='New directory under dist/review; existing paths are refused')
    parser.add_argument('--include-stock-registry', action='store_true',
                        help='Review core/shared split with complete stock77 plus decorative40 registry; still not installable')
    args = parser.parse_args()
    print(json.dumps(build(args.output, include_stock_registry=args.include_stock_registry), indent=2))
