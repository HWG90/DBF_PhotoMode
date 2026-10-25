"""Temporary-filesystem cold-test contracts; never opens the installed game data."""
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

import install_steam_overlay_assets as tool
import photo_assets as assets


def dsar(chunks):
    head = bytearray(32)
    head[:4] = b'DSAR'
    struct.pack_into('<I', head, 8, len(chunks))
    at = 32 + len(chunks) * 32
    logical, table, payload = 0, bytearray(), bytearray()
    for body, unpacked, kind in chunks:
        table += struct.pack('<QQIIBB6x', logical, at, unpacked, len(body), kind, 0)
        payload += body
        logical += unpacked
        at += len(body)
    return bytes(head + table + payload)


class ColdOverlayInstall(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='photo-overlay-install-tests-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.data = self.root / 'data'; self.data.mkdir()
        self.review = self.root / 'review'; self.review.mkdir()
        self.preserved = {}
        for index in (0, 1):
            name = '9ba626afa44a3aa3.patch_' + str(index)
            cpu, gpu = assets.archive_rows([(assets.hash64('fixture/' + name), assets.LUA, b'fixture', b'')])
            for suffix, body in (('', cpu), ('.gpu_resources', gpu), ('.stream', b'')):
                (self.data / (name + suffix)).write_bytes(body)
                self.preserved[name + suffix] = assets.sha256(body)
        self.original = self.snapshot()
        self.patch_data = mock.patch.object(tool, 'DATA', self.data); self.patch_data.start(); self.addCleanup(self.patch_data.stop)
        self.patch_review = mock.patch.object(tool, 'REVIEW', self.review); self.patch_review.start(); self.addCleanup(self.patch_review.stop)
        self.patch_preserved = mock.patch.object(tool, 'EXPECTED_PRESERVED', self.preserved); self.patch_preserved.start(); self.addCleanup(self.patch_preserved.stop)
        self.patch_closed = mock.patch.object(tool, 'game_closed', return_value=None)
        self.closed = self.patch_closed.start(); self.addCleanup(self.patch_closed.stop)
        self.patch_qualifier = mock.patch.object(tool, 'qualify_base', return_value={'fixture': True, 'stock_ids_present': 77})
        self.qualifier = self.patch_qualifier.start(); self.addCleanup(self.patch_qualifier.stop)
        self.candidate = self.review / 'candidate'
        tool.build(self.candidate)

    def snapshot(self):
        return {path.name: path.read_bytes() for path in self.data.iterdir() if path.is_file()}

    def install(self):
        return tool.install(self.candidate, self.review / 'deployment')

    def test_build_exact_six_native_payloads_and_fresh_scope(self):
        core, shared, source = tool.builder.stock_union_resources()
        for name, expected in ((tool.CORE, core), (tool.SHARED, shared)):
            folder = self.candidate / 'Assets'
            actual = assets.read_archive((folder / name).read_bytes(), (folder / (name + '.gpu_resources')).read_bytes(),
                                         (folder / (name + '.stream')).read_bytes())
            self.assertEqual(actual, list(expected))
        self.assertEqual(len(list((self.candidate / 'Assets').iterdir())), 6)
        audit = json.loads((self.candidate / 'NATIVE-ASSET-CANDIDATE.json').read_bytes())
        self.assertEqual(audit['source'], source)
        self.assertEqual(audit['registry_ids'], 117)
        self.assertTrue(audit['development_only'])
        self.assertFalse(audit['native_selection_qualified'])
        self.assertEqual(self.closed.call_count, 0)
        with self.assertRaises(FileExistsError): tool.build(self.candidate)
        for target in (self.review, self.root / 'outside', self.review / '../outside'):
            with self.assertRaises(ValueError): tool.build(target)
        self.assertEqual(self.snapshot(), self.original)

    def test_install_publish_order_verified_receipt_and_hash_owned_rollback(self):
        native_link = os.link
        published = []
        def link(source, target):
            published.append(Path(target).name)
            return native_link(source, target)
        with mock.patch.object(tool.os, 'link', side_effect=link):
            receipt = self.install()
        self.assertEqual(published, list(tool.PUBLISH_ORDER))
        self.assertTrue(receipt['installed'])
        self.assertEqual(receipt['native_selection'], 'pending cold-load test')
        self.assertGreaterEqual(self.closed.call_count, 19)
        self.assertEqual(self.qualifier.call_count, 3)
        for name in tool.NAMES:
            self.assertEqual((self.data / name).read_bytes(), (self.candidate / 'Assets' / name).read_bytes())
        for name, body in self.original.items(): self.assertEqual((self.data / name).read_bytes(), body)
        self.assertFalse(any(path.name.endswith('.stage') for path in self.data.iterdir()))
        # The durable plan is sufficient even if a process dies before its final receipt.
        result = tool.rollback(self.review / 'deployment/INSTALL-PLAN.json')
        self.assertTrue(result['rolled_back'])
        self.assertEqual(set(result['removed']), set(tool.NAMES))
        self.assertTrue(all(result['preserved_files_unchanged'].values()))
        self.assertEqual(self.snapshot(), self.original)
        self.assertEqual(tool.rollback(self.review / 'deployment/DEPLOYMENT.json')['removed'], [])

    def test_game_open_refuses_install_and_rollback_without_mutation(self):
        self.closed.return_value = False
        with self.assertRaisesRegex(ValueError, 'Close'): self.install()
        self.assertEqual(self.snapshot(), self.original)
        self.assertFalse((self.review / 'deployment').exists())
        self.closed.return_value = None
        self.install()
        installed = self.snapshot()
        self.closed.return_value = False
        with self.assertRaisesRegex(ValueError, 'Close'): tool.rollback(self.review / 'deployment/DEPLOYMENT.json')
        self.assertEqual(self.snapshot(), installed)

    def test_candidate_tampering_and_extra_paths_are_refused(self):
        path = self.candidate / 'Assets' / tool.CORE
        body = path.read_bytes(); path.write_bytes(body[:-1] + bytes([body[-1] ^ 1]))
        with self.assertRaisesRegex(ValueError, 'bytes differ'): self.install()
        self.assertEqual(self.snapshot(), self.original)
        path.write_bytes(body)
        (self.candidate / 'unexpected').write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'file set'): self.install()
        self.assertEqual(self.snapshot(), self.original)

    def test_occupied_target_and_competing_registry_or_alias_are_refused(self):
        target = self.data / (tool.CORE + '.stream'); target.write_bytes(b'foreign')
        with self.assertRaisesRegex(ValueError, 'occupied'): self.install()
        self.assertEqual(target.read_bytes(), b'foreign')
        target.unlink()
        for kind, name in ((assets.GROUP, assets.hash64(assets.GROUP_NAME)),
                           (assets.SHADER, 123),
                           (assets.MATERIAL, assets.hash64(tool.builder.PRIVATE_PREFIX + 'glass'))):
            # Use a real catalog ID for the alias collision case.
            if kind == assets.MATERIAL:
                first = json.loads((assets.ASSETS / 'manifest.json').read_bytes())['overlays'][0]['id']
                name = assets.hash64(tool.builder.PRIVATE_PREFIX + first)
            cpu, _ = assets.archive_rows([(name, kind, b'foreign', b'')])
            other = self.data / '0000000000000001.patch_7'; other.write_bytes(cpu)
            with self.assertRaisesRegex(ValueError, 'competing'): self.install()
            self.assertEqual(other.read_bytes(), cpu)
            other.unlink()
        self.assertEqual(self.snapshot(), self.original)

    def test_preserved_loader_or_light_changes_are_refused(self):
        for name in self.preserved:
            path = self.data / name
            path.write_bytes(self.original[name] + b'tamper')
            with self.assertRaises(ValueError): self.install()
            self.assertEqual(path.read_bytes(), self.original[name] + b'tamper')
            path.write_bytes(self.original[name])
        self.assertEqual(self.snapshot(), self.original)

    def test_link_failure_removes_only_owned_files_and_stages(self):
        native_link, calls = os.link, []
        def fail(source, target):
            calls.append(target)
            if len(calls) == 3: raise OSError('injected publish failure')
            return native_link(source, target)
        with mock.patch.object(tool.os, 'link', side_effect=fail):
            with self.assertRaisesRegex(OSError, 'injected'): self.install()
        failure = json.loads((self.review / 'deployment/FAILURE.json').read_bytes())
        self.assertEqual(failure['cleanup_errors'], [])
        self.assertEqual(self.snapshot(), self.original)
        self.assertTrue((self.review / 'deployment/ROLLBACK.zip').is_file())

    def test_interrupted_stage_creation_cleans_its_owned_empty_prefix(self):
        with mock.patch.object(tool, 'append_owner', side_effect=OSError('injected journal failure')):
            with self.assertRaisesRegex(OSError, 'journal'): self.install()
        self.assertEqual(self.snapshot(), self.original)
        failure = json.loads((self.review / 'deployment/FAILURE.json').read_bytes())
        self.assertEqual(failure['cleanup_errors'], [])

    def test_publish_collision_never_overwrites_or_deletes_the_other_owner(self):
        native_link, calls = os.link, []
        foreign = b'other owner'
        def collide(source, target):
            calls.append(Path(target))
            if len(calls) == 3:
                Path(target).write_bytes(foreign)
            return native_link(source, target)
        with mock.patch.object(tool.os, 'link', side_effect=collide):
            with self.assertRaises(FileExistsError): self.install()
        self.assertEqual(calls[-1].read_bytes(), foreign)
        self.assertEqual(set(self.snapshot()) - set(self.original), {calls[-1].name})
        self.assertTrue(json.loads((self.review / 'deployment/FAILURE.json').read_bytes())['cleanup_errors'])

    def test_game_open_during_publish_leaves_receipt_for_later_guarded_rollback(self):
        native_link = os.link
        def opens(source, target):
            native_link(source, target)
            self.closed.return_value = False
        with mock.patch.object(tool.os, 'link', side_effect=opens):
            with self.assertRaisesRegex(ValueError, 'Close'): self.install()
        failure = self.review / 'deployment/FAILURE.json'
        self.assertTrue(json.loads(failure.read_bytes())['cleanup_errors'])
        self.closed.return_value = None
        self.assertTrue(tool.rollback(failure)['rolled_back'])
        self.assertEqual(self.snapshot(), self.original)

    def test_rollback_refuses_tampered_bytes_receipt_archive_and_identical_foreign_inode(self):
        self.install()
        receipt = self.review / 'deployment/DEPLOYMENT.json'
        target = self.data / tool.SHARED
        body = target.read_bytes()
        target.write_bytes(body + b'tamper')
        installed = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'changed/unowned'): tool.rollback(receipt)
        self.assertEqual(self.snapshot(), installed)
        target.write_bytes(body)
        archive = self.review / 'deployment/ROLLBACK.zip'
        archived = archive.read_bytes(); archive.write_bytes(archived + b'tamper')
        with self.assertRaisesRegex(ValueError, 'archive changed'): tool.rollback(receipt)
        archive.write_bytes(archived)
        foreign = self.data / 'foreign.tmp'; foreign.write_bytes(body)
        os.replace(foreign, target)
        installed = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'changed/unowned'): tool.rollback(receipt)
        self.assertEqual(self.snapshot(), installed)

    def test_base_qualification_failure_does_not_create_review_or_game_files(self):
        self.qualifier.side_effect = ValueError('base fingerprint changed')
        with self.assertRaisesRegex(ValueError, 'fingerprint'): self.install()
        self.assertFalse((self.review / 'deployment').exists())
        self.assertEqual(self.snapshot(), self.original)

    def test_incomplete_ownership_journal_never_reports_or_removes_unknown_paths(self):
        self.install()
        (self.review / 'deployment/OWNERSHIP.jsonl').write_bytes(b'')
        installed = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'journal is missing'):
            tool.rollback(self.review / 'deployment/INSTALL-PLAN.json')
        self.assertEqual(self.snapshot(), installed)

    def base_fixture(self):
        stock = (assets.ASSETS / 'original-default-shaders.bin').read_bytes()
        ids = assets.registry_ids(stock)
        libraries = list(ids) + [100000 + index for index in range(813)]
        resources = [(name, assets.SHADER, b'', b'') for name in libraries]
        resources += [(assets.hash64(assets.GROUP_NAME), assets.GROUP, stock, b'')]
        resources += [(200000 + index, assets.LUA, b'', b'') for index in range(66)]
        cpu, _ = assets.archive_rows(resources)
        rows = assets.archive_index(cpu)
        length = tool.table_length(cpu[:72])
        group, = [row for row in rows if row[1] == assets.GROUP]
        expected = dict(tool.EXPECTED_BASE, logical_cpu_bytes=len(cpu), native_table_sha256=assets.sha256(cpu[:length]),
                        registry_cpu_offset=group[2])
        # One logical archive, one bundle, one mapping. No GPU companion exists.
        index = bytearray(68)
        index[:4] = b'DSAA'
        struct.pack_into('<II', index, 12, 1, 1)
        archive_name = tool.builder.CORE_ARCHIVE.encode() + b'\0'
        bundle_name = b'bundles.0.nxa\0'
        struct.pack_into('<QIIQ', index, 24, len(cpu), 68, 1, 52)
        struct.pack_into('<I', index, 48, 68 + len(archive_name))
        struct.pack_into('<I4xI3xB', index, 52, 0, 0, 0)
        index += archive_name + bundle_name
        (self.data / 'bundles.nxa').write_bytes(dsar([(bytes(index), len(index), 0)]))
        (self.data / 'bundles.0.nxa').write_bytes(dsar([(cpu, len(cpu), 0)]))
        return expected

    def test_actual_bounded_reader_qualifies_synthetic_table_stock_closure_without_gpu(self):
        expected = self.base_fixture()
        self.patch_qualifier.stop()
        with mock.patch.object(tool, 'EXPECTED_BASE', expected):
            result = tool.qualify_base(self.data)
        self.assertEqual(result['stock_ids_present'], 77)
        self.assertEqual(result['read_bounds']['chunks'], 2)
        self.assertLess(result['read_bounds']['inflated_bytes'], 18 * 1024 * 1024)
        self.assertEqual(set(result['bundle_metadata']), {'bundles.nxa', 'bundles.0.nxa'})

    def test_actual_bounded_reader_rejects_selected_chunk_over_limit_and_total_inflation(self):
        self.patch_qualifier.stop()
        payload = b'x' * (1024 * 1024 + 1)
        (self.data / 'bundles.nxa').write_bytes(dsar([(payload, len(payload), 0)]))
        with self.assertRaisesRegex(ValueError, '1 MiB'): tool.qualify_base(self.data)
        # Repeated small compressed chunks inflate to the bounded 18 MiB ceiling.
        import sys
        sys.path.insert(0, str(tool.ROOT / 'dist/analysis-deps'))
        from lz4.block import compress
        zeros = b'\0' * (1024 * 1024)
        packed = compress(zeros, store_size=False)
        (self.data / 'bundles.nxa').write_bytes(dsar([(packed, len(zeros), 3)] * 19))
        with self.assertRaisesRegex(ValueError, '18 MiB'): tool.qualify_base(self.data)


if __name__ == '__main__':
    unittest.main(verbosity=2)
