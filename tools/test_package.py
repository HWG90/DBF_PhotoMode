"""Compose the one War Journalist package from this tree and prove it offline on every host.

Usage: python tools/test_package.py [--release] [--sandbox PATH=VERSION]... [--zip PATH]
Prints a JSON summary; exits non-zero on the first failure. Never builds a ZIP or installs."""
from pathlib import Path
import argparse
import json
import tempfile

import package_fixtures as fixtures
from package_head import ROOT, build_id, check_size, compose


# Chef's own sandbox.lua per release (gitignored copies), and the version each run reports.
# 1.10.0 on the 1.5.1 sandbox proves the version gate compares numbers, not strings.
SANDBOX_DIR = ROOT / 'dist/chef-src/sandbox'
SANDBOXES = [(SANDBOX_DIR / 'sandbox-v1.4.0.lua', '1.4.0'), (SANDBOX_DIR / 'sandbox-v1.4.1.lua', '1.4.1'),
             (SANDBOX_DIR / 'sandbox-v1.4.2-test1.lua', '1.4.2-test1'), (SANDBOX_DIR / 'sandbox-v1.5.0.lua', '1.5.0'),
             (SANDBOX_DIR / 'sandbox-v1.5.1.lua', '1.5.1'), (SANDBOX_DIR / 'sandbox-v1.5.1.lua', '1.10.0')]
if (SANDBOX_DIR / 'sandbox-v1.5.2.lua').exists():
    SANDBOXES.append((SANDBOX_DIR / 'sandbox-v1.5.2.lua', '1.5.2'))


def sandbox_arg(value):
    path, _, version = value.partition('=')
    assert path and version, '--sandbox takes PATH=VERSION'
    return Path(path), version


def prove(text, release, sources, sandboxes):
    """Every proof the package has, in order; returns the summary."""
    summary = {'bytes': check_size(text)}
    assert fixtures.packed_sources(text) == sources, 'A module differs after packing'
    summary['modules'] = len(sources) - 1
    fixtures.verify_shape(text)
    summary['verify_shape'] = 'passed'
    summary['verify_loaders'] = fixtures.verify_loaders(text)
    summary['verify_boot'] = fixtures.verify_boot(text, release)
    fixtures.verify_key_carry_over(text)
    summary['verify_key_carry_over'] = 'passed'
    fixtures.verify_lll(text)
    summary['verify_lll'] = 'passed'
    summary['verify_chef'] = [fixtures.verify_chef(text, path, version) for path, version in sandboxes]
    fixtures.verify_chef_gate(text)
    summary['verify_chef_gate'] = 'passed'
    return summary


def test_size_cap():
    check_size('x' * 10, limit=10)
    try:
        check_size('x' * 11, limit=10)
    except AssertionError as error:
        assert 'Bundle is 11 bytes, over the 10-byte cap (Chef 1.5.1 reads at most 4 MiB)' in str(error), error
    else:
        raise AssertionError('size cap did not fire')


def test_versions():
    """Chef's gate reads a version's leading number parts; one or two parts mean zeros after."""
    assert fixtures.numbers('1.4.2-test1') == (1, 4, 2)
    assert fixtures.numbers('1.10.0') == (1, 10, 0)
    assert fixtures.numbers('1.5') == (1, 5, 0)
    assert fixtures.numbers('2') == (2, 0, 0)


def test_zip_mode():
    """A built ZIP says whether it is a release; --release only has to agree with it."""
    release, dev = 'local RELEASE_MODE=true\n', 'local RELEASE_MODE=false\nSOURCES["src/windows_dev_reload.lua"]=1\n'
    assert fixtures.zip_mode(release, None) is True and fixtures.zip_mode(dev, None) is False
    assert fixtures.zip_mode(release, True) is True
    try:
        fixtures.zip_mode(dev, True)
    except AssertionError as error:
        assert 'a development build, but --release was given' in str(error), error
    else:
        raise AssertionError('a dev ZIP passed as a release')


def test_embedded_binaries():
    """The helper and the scene registry ship as base64; each decodes to its pinned bytes (the
    registry is the shipped ee6b1ba7e22d71ed.patch_0 asset)."""
    import base64
    import hashlib
    import re
    from package_head import ASSETS_SHA256
    def field(path, name):
        text = (ROOT / 'freecam' / path).read_text()
        match = re.search(name + r'="([^"]*)"', text)
        assert match, f'{path} has no {name} field'
        return match.group(1)
    helper = base64.b64decode(field('wjl_helper_payload.lua', 'base64'), validate=True)
    assert hashlib.sha256(helper).hexdigest() == fixtures.HELPER_SHA256 == field('wjl_helper_payload.lua', 'sha256')
    registry = base64.b64decode(field('engine_scene_registry.lua', 'base64'), validate=True)
    assert hashlib.sha256(registry).hexdigest() == ASSETS_SHA256[field('engine_scene_registry.lua', 'name')]


def test_helper_sources():
    """helper/native holds the exact sources compiled into the shipped helper, listed in
    helper/HELPER.json; a rebuilt payload without its sources fails here."""
    import hashlib
    record = json.loads((ROOT / 'helper/HELPER.json').read_text())
    assert record['sha256'] == fixtures.HELPER_SHA256, 'helper/ holds the sources of another helper than the one that ships'
    files = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in (ROOT / 'helper/native').iterdir()}
    assert files == record['sources'], sorted(set(files.items()) ^ set(record['sources'].items()))


def test_clear_outputs():
    """A rebuild clears the last build's ZIP, sums and receipt first, so a failed build never
    leaves them looking current; the candidate's LLL ZIP never stays beside the real one."""
    from build_package import clear_outputs
    with tempfile.TemporaryDirectory() as temp:
        review = Path(temp)
        stale = [review / 'War-Journalist-1.4.0-dev.9.zip', review / 'SHA256SUMS.txt', review / 'BUILD-RECEIPT.json',
                 review / 'candidate' / 'War-Journalist-1.4.0-steam51-dev-LLL.zip']
        (review / 'candidate').mkdir()
        for path in stale:
            path.write_text('old')
        kept = review / 'candidate' / 'BUILD-RECEIPT.json'
        kept.write_text('candidate receipt')
        clear_outputs(review, 'War-Journalist-1.4.0-dev.9')
        assert not any(path.exists() for path in stale) and kept.exists(), sorted(p.name for p in review.rglob('*'))


def test_loader_pin():
    """Boot Mod Loader 0.13.4 comes from the first copy that still matches its pin."""
    from bml_loader_checks import pinned_loader
    with tempfile.TemporaryDirectory() as temp:
        wrong, right = Path(temp) / 'wrong.lua', Path(temp) / 'right.lua'
        wrong.write_text('-- a newer Boot Mod Loader\n')
        right.write_bytes(pinned_loader().read_bytes())
        assert pinned_loader([wrong, right]) == right
        try:
            pinned_loader([wrong, Path(temp) / 'missing.lua'])
        except AssertionError as error:
            assert 'Boot Mod Loader 0.13.4 not found or changed' in str(error), error
        else:
            raise AssertionError('a changed loader was accepted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true', help='public text: no dev-only modules, RELEASE_MODE=true')
    parser.add_argument('--sandbox', type=sandbox_arg, action='append', default=None, metavar='PATH=VERSION')
    parser.add_argument('--zip', type=Path, help='check a built ZIP instead of composing from the tree')
    args = parser.parse_args()
    test_size_cap()
    test_versions()
    test_zip_mode()
    test_clear_outputs()
    test_embedded_binaries()
    test_helper_sources()
    test_loader_pin()
    if args.zip:
        print(json.dumps({'zip': str(args.zip), 'test_size_cap': 'passed', **fixtures.verify_zip(args.zip, args.release or None)}, indent=2))
        return
    sources = fixtures.current_sources(args.release)
    text = compose(sources, '0.0.0-test', build_id(), args.release)
    print(json.dumps({'release': args.release, **prove(text, args.release, sources, args.sandbox or SANDBOXES)}, indent=2))


if __name__ == '__main__':
    main()
