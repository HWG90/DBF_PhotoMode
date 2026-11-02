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
        assert "over Chef's 4 MiB reading limit: 11 bytes > 10" in str(error), error
    else:
        raise AssertionError('size cap did not fire')


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
    test_loader_pin()
    if args.zip:
        print(json.dumps({'zip': str(args.zip), 'test_size_cap': 'passed', **fixtures.verify_zip(args.zip, args.release)}, indent=2))
        return
    sources = fixtures.current_sources(args.release)
    text = compose(sources, '0.0.0-test', build_id(), args.release)
    print(json.dumps({'release': args.release, **prove(text, args.release, sources, args.sandbox or SANDBOXES)}, indent=2))


if __name__ == '__main__':
    main()
