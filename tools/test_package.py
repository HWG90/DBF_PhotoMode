"""Compose the one War Journalist package from this tree and prove it offline on every host.

Usage: python tools/test_package.py [--release] [--sandbox PATH=VERSION]...
Prints a JSON summary; exits non-zero on the first failure. Never builds a ZIP or installs."""
from pathlib import Path
import argparse
import json

from build_steam_archive import build_id
import package_fixtures as fixtures
from package_head import check_size, compose


def sandbox_arg(value):
    path, _, version = value.partition('=')
    assert path and version, '--sandbox takes PATH=VERSION'
    return Path(path), version


def prove(text, release, sources):
    """Every proof the package has, in order; returns the summary."""
    summary = {'bytes': check_size(text)}
    assert fixtures.packed_sources(text) == sources, 'A module differs after packing'
    summary['modules'] = len(sources) - 1
    fixtures.verify_shape(text)
    summary['verify_shape'] = 'passed'
    summary['verify_boot'] = fixtures.verify_boot(text, release)
    fixtures.verify_lll(text)
    summary['verify_lll'] = 'passed'
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true', help='public text: no dev-only modules, RELEASE_MODE=true')
    parser.add_argument('--sandbox', type=sandbox_arg, action='append', default=None, metavar='PATH=VERSION')
    args = parser.parse_args()
    sources = fixtures.current_sources(args.release)
    text = compose(sources, '0.0.0-test', build_id(), args.release)
    print(json.dumps({'release': args.release, **prove(text, args.release, sources)}, indent=2))


if __name__ == '__main__':
    main()
