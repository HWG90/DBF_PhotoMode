"""Focused offline alias/payload/path contracts; never installs game assets."""
import json
from pathlib import Path
import re
import struct
import tempfile
import unittest
from unittest import mock

import build_steam_overlay_assets as builder
import photo_assets


class PrivateOverlayAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = builder.source_snapshot()
        cls.files = builder.candidate_files()
        cls.source = {row[:2]: row for row in photo_assets.load_resources()}
        cls.actual = {row[:2]: row for row in photo_assets.read_archive(
            cls.files[builder.CPU_FILE], cls.files[builder.GPU_FILE])}
        cls.table = json.loads(cls.files['RESOURCE-TABLE.json'])
        cls.lookup = json.loads(cls.files['MATERIAL-LOOKUP.json'])
        cls.manifest = json.loads((photo_assets.ASSETS / 'manifest.json').read_bytes())

    def test_all_private_materials_keep_exact_payload_and_shader_link(self):
        aliases = set()
        for item in self.manifest['overlays']:
            private = 'mods/dbf_photo/materials/mapped_' + item['id']
            name = photo_assets.hash64(private)
            self.assertEqual(self.lookup[item['id']], private)
            self.assertNotIn(name, {row[0] for row in self.source.values()})
            self.assertNotIn(name, aliases); aliases.add(name)
            source = self.source[photo_assets.hash64(item['material']), photo_assets.MATERIAL]
            alias = self.actual[name, photo_assets.MATERIAL]
            self.assertEqual(alias[2:], source[2:])
            self.assertEqual(len(alias[2]), 144)
            shader_id = photo_assets.hash64(item['shader'])
            self.assertEqual(struct.unpack_from('<I', alias[2], 128)[0], shader_id >> 32)
            self.assertEqual(self.actual[shader_id, photo_assets.SHADER], self.source[shader_id, photo_assets.SHADER])
        self.assertEqual(len(aliases), 40)
        self.assertEqual(len(self.actual), 80)
        self.assertFalse(any(kind == photo_assets.GROUP for _, kind in self.actual))

    def test_private_lookup_covers_exact_portable_catalog(self):
        source = (builder.ROOT / 'freecam/composition.lua').read_text(encoding='utf-8')
        line = re.search(r'^M\.shaders=(.*)$', source, re.MULTILINE).group(1)
        catalog = re.findall(r"'([^']*)'", line)
        self.assertEqual(catalog[0], '')
        self.assertEqual(len(catalog), 41)
        self.assertEqual(set(self.lookup), set(catalog[1:]))

    def test_resource_table_offsets_hashes_and_detached_requirements(self):
        cpu, gpu = self.files[builder.CPU_FILE], self.files[builder.GPU_FILE]
        self.assertEqual(len(self.table['resources']), 80)
        for item in self.table['resources']:
            key = int(item['resource_hash64'], 16), int(item['type_hash64'], 16)
            row = self.actual[key]
            self.assertEqual(photo_assets.hash64(item['resource_name']), row[0])
            self.assertEqual(cpu[item['cpu_offset']:item['cpu_offset'] + item['cpu_bytes']], row[2])
            self.assertEqual(gpu[item['gpu_offset']:item['gpu_offset'] + item['gpu_bytes']], row[3])
            self.assertEqual(item['cpu_sha256'], photo_assets.sha256(row[2]))
            self.assertEqual(item['gpu_sha256'], photo_assets.sha256(row[3]))
        requirements = json.loads(self.files['SHADER-REGISTRY-REQUIREMENTS.json'])
        self.assertTrue(requirements['requirement_only'])
        self.assertTrue(requirements['requires_union_with_complete_current_registry'])
        self.assertEqual({int(item['resource_hash64'], 16) for item in requirements['shader_libraries']},
                         {name for name, kind in self.actual if kind == photo_assets.SHADER})
        for metadata in (self.table, requirements, json.loads(self.files['BUILD-RECEIPT.json'])):
            self.assertTrue(metadata['review_only'])
            for flag in ('installable', 'installed', 'registry_included', 'registry_union_qualified',
                         'archive_priority_qualified', 'coexistence_qualified', 'live_rendering_qualified'):
                self.assertFalse(metadata[flag])
        self.assertIn(b'NOT INSTALLABLE', self.files['REVIEW-ONLY.txt'])
        self.assertFalse(any('.patch_' in name or name.lower().endswith('.zip') for name in self.files))

    def test_checksums_determinism_and_original_assets_unchanged(self):
        checks = dict(line.split('  ', 1)[::-1] for line in self.files['FILES-SHA256.txt'].decode().splitlines())
        self.assertEqual(set(checks), set(self.files) - {'FILES-SHA256.txt'})
        for name, digest in checks.items():
            self.assertEqual(digest, photo_assets.sha256(self.files[name]))
        self.assertEqual(builder.candidate_files(), self.files)
        self.assertEqual(builder.source_snapshot(), self.original)

    def test_complete_stock_union_split_exact_payloads_and_registry(self):
        files = builder.candidate_files(include_stock_registry=True)
        core = photo_assets.read_archive(files[builder.CORE_CPU_FILE], files[builder.CORE_GPU_FILE])
        shared = photo_assets.read_archive(files[builder.SHARED_CPU_FILE], files[builder.SHARED_GPU_FILE])
        self.assertEqual(len(core), 41)
        self.assertEqual(len(shared), 40)
        self.assertEqual({row[1] for row in core}, {photo_assets.SHADER, photo_assets.GROUP})
        self.assertEqual({row[1] for row in shared}, {photo_assets.MATERIAL})
        expected_shaders = {key: row for key, row in self.source.items() if key[1] == photo_assets.SHADER}
        self.assertEqual({row[:2]: row for row in core if row[1] == photo_assets.SHADER}, expected_shaders)
        self.assertEqual({row[:2]: row for row in shared},
                         {key: row for key, row in self.actual.items() if key[1] == photo_assets.MATERIAL})
        group, = [row for row in core if row[1] == photo_assets.GROUP]
        self.assertEqual(group, photo_assets.registry_resource())
        stock = (photo_assets.ASSETS / self.manifest['original_registry']['file']).read_bytes()
        stock_ids = photo_assets.registry_ids(stock)
        ids = photo_assets.registry_ids(group[2])
        self.assertEqual(len(stock_ids), 77)
        self.assertEqual(len(ids), 117)
        self.assertEqual(ids[:77], stock_ids)
        self.assertEqual(set(ids[77:]), {name for name, _ in expected_shaders})
        header = bytearray(stock[:24]); struct.pack_into('<I', header, 16, 117)
        self.assertEqual(group[2][:24], bytes(header))
        self.assertEqual(group[2][24:24 + 77 * 8], stock[24:])
        table = json.loads(files['RESOURCE-TABLE.json'])
        receipt = json.loads(files['BUILD-RECEIPT.json'])
        self.assertEqual(receipt['resource_count'], 81)
        self.assertEqual(receipt['registry']['stock_ids'], 77)
        self.assertEqual(receipt['registry']['total_ids'], 117)
        self.assertEqual(receipt['registry']['required_effective_registry_sha256'], photo_assets.sha256(stock))
        self.assertFalse(receipt['registry']['effective_registry_verified'])
        self.assertFalse(receipt['registry']['stock_library_payloads_included'])
        self.assertTrue(receipt['registry']['requires_game_stock_libraries'])
        self.assertEqual({item['logical_archive']: item['resource_count'] for item in table['archives']},
                         {builder.CORE_ARCHIVE: 41, builder.SHARED_ARCHIVE: 40})
        actual = {row[:2]: row for row in core + shared}
        for item in table['resources']:
            cpu, gpu = files[item['cpu_file']], files[item['gpu_file']]
            row = actual[int(item['resource_hash64'], 16), int(item['type_hash64'], 16)]
            self.assertEqual(cpu[item['cpu_offset']:item['cpu_offset'] + item['cpu_bytes']], row[2])
            self.assertEqual(gpu[item['gpu_offset']:item['gpu_offset'] + item['gpu_bytes']], row[3])
            self.assertEqual(item['cpu_sha256'], photo_assets.sha256(row[2]))
            self.assertEqual(item['gpu_sha256'], photo_assets.sha256(row[3]))
            self.assertEqual(item['logical_archive'], builder.SHARED_ARCHIVE if row[1] == photo_assets.MATERIAL else builder.CORE_ARCHIVE)
        for metadata in (table, receipt, json.loads(files['SHADER-REGISTRY-REQUIREMENTS.json'])):
            self.assertTrue(metadata['registry_included'])
            for flag in ('installable', 'installed', 'registry_union_qualified', 'archive_priority_qualified',
                         'coexistence_qualified', 'live_rendering_qualified'):
                self.assertFalse(metadata[flag])
        self.assertNotIn(builder.CPU_FILE, files)
        self.assertNotIn(builder.GPU_FILE, files)
        self.assertIn(b'NOT INSTALLABLE', files['REVIEW-ONLY.txt'])
        self.assertFalse(any('.patch_' in name or name.lower().endswith('.zip') for name in files))
        checks = dict(line.split('  ', 1)[::-1] for line in files['FILES-SHA256.txt'].decode().splitlines())
        self.assertEqual(set(checks), set(files) - {'FILES-SHA256.txt'})
        for name, digest in checks.items(): self.assertEqual(digest, photo_assets.sha256(files[name]))
        self.assertEqual(builder.candidate_files(include_stock_registry=True), files)
        api_core, api_shared, api_receipt = builder.stock_union_resources()
        self.assertEqual(api_core, tuple(core))
        self.assertEqual(api_shared, tuple(shared))
        self.assertEqual(api_receipt, receipt)
        self.assertEqual(builder.source_snapshot(), self.original)

    def test_reject_incomplete_or_changed_registry_union(self):
        group = photo_assets.registry_resource()
        ids = list(photo_assets.registry_ids(group[2]))
        ids[-1] ^= 1
        changed = group[:2] + (group[2][:24] + struct.pack('<117Q', *ids), b'')
        with mock.patch.object(photo_assets, 'registry_resource', side_effect=[group, changed]):
            with self.assertRaisesRegex(ValueError, 'stock77'): builder.candidate_files(include_stock_registry=True)
        changed_header = group[:2] + (bytes([group[2][0] ^ 1]) + group[2][1:], b'')
        with mock.patch.object(photo_assets, 'registry_resource', side_effect=[group, changed_header]):
            with self.assertRaisesRegex(ValueError, 'stock77'): builder.candidate_files(include_stock_registry=True)

    def test_reject_changed_payload_and_material_collision(self):
        source_rows = list(self.source.values())
        position = next(i for i, row in enumerate(source_rows) if row[1] == photo_assets.MATERIAL)
        row = source_rows[position]
        source_rows[position] = row[:2] + (bytes([row[2][0] ^ 1]) + row[2][1:], row[3])
        with mock.patch.object(photo_assets, 'load_resources', return_value=source_rows):
            with self.assertRaises(ValueError): builder.candidate_files()
        native_hash = photo_assets.hash64
        first = self.manifest['overlays'][0]
        def collision(name):
            if name == builder.PRIVATE_PREFIX + first['id']: return native_hash(first['material'])
            return native_hash(name)
        with mock.patch.object(photo_assets, 'hash64', side_effect=collision):
            with self.assertRaisesRegex(ValueError, 'collision'): builder.candidate_files()
        changed = dict(self.original, **{'manifest.json': '0' * 64})
        with mock.patch.object(builder, 'source_snapshot', side_effect=[self.original, changed]):
            with self.assertRaisesRegex(ValueError, 'changed'): builder.candidate_files()

    def test_review_scope_fresh_output_and_exclusive_writes(self):
        for path in (builder.REVIEW, builder.ROOT / 'dist/releases/overlay-test',
                     photo_assets.ASSETS / 'overlay-test', builder.REVIEW / '../releases/overlay-test'):
            with self.assertRaises(ValueError): builder.build(path)
        with tempfile.TemporaryDirectory(prefix='photo-overlay-outside-') as outside:
            with self.assertRaises(ValueError): builder.build(Path(outside) / 'candidate')
        # A verified review-local temporary parent keeps all test cleanup scoped.
        builder.REVIEW.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='steam-overlay-tests-', dir=builder.REVIEW) as temporary:
            parent = Path(temporary).resolve()
            self.assertTrue(parent.is_relative_to(builder.REVIEW.resolve()))
            output = parent / 'candidate'
            receipt = builder.build(output)
            self.assertFalse(receipt['installable'])
            self.assertEqual({path.name: path.read_bytes() for path in output.iterdir()}, self.files)
            union_output = parent / 'stock-union-candidate'
            union_receipt = builder.build(union_output, include_stock_registry=True)
            self.assertFalse(union_receipt['installable'])
            self.assertTrue(union_receipt['registry_included'])
            self.assertEqual(union_receipt['resource_count'], 81)
            self.assertEqual({path.name: path.read_bytes() for path in union_output.iterdir()},
                             builder.candidate_files(include_stock_registry=True))
            with self.assertRaises(FileExistsError): builder.build(union_output, include_stock_registry=True)
            with self.assertRaises(FileExistsError): builder.build(output)
            self.assertEqual({path.name: path.read_bytes() for path in output.iterdir()}, self.files)
        self.assertEqual(builder.source_snapshot(), self.original)


if __name__ == '__main__':
    unittest.main(verbosity=2)
