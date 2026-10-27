"""Publish one immutable Lua generation and atomically request a private BML reload.

The resident development adapter must already have been installed and enabled at
game startup. This never deploys archives, changes shaders, or restarts the game.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import uuid

from build_steam_candidate import ROOT, MODULES


def payload():
    from lupa.lua51 import LuaRuntime
    compile_lua = LuaRuntime().eval('function(s,n) return assert(loadstring(s,n)) end')
    rows = [('main.lua', ROOT / 'freecam/steam51.lua')]
    rows += [('src/' + name, ROOT / 'freecam' / name) for name in MODULES]
    chunks = [f'WJL-LUA-1\n{len(rows)}\n'.encode()]
    for name, path in rows:
        # Match build_steam_archive.bundle(): universal newline decoding makes
        # Windows working-tree CRLF compare exactly with resident archive text.
        source = path.read_text(encoding='utf-8').encode('utf-8')
        compile_lua(source.decode('utf-8'), '@' + name)
        chunks.extend([f'{name}\n{len(source)}\n'.encode(), source])
    data = b''.join(chunks)
    assert len(data) <= 8 * 1024 * 1024
    return data, len(rows)


def atomic_write(path, data):
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    with temp.open('xb') as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(os.environ['APPDATA']) / 'Arrowhead/Helldivers2')
    parser.add_argument('--enable', action='store_true', help='Arm development mode for the next game launch; does not request a reload.')
    parser.add_argument('--output', type=Path, help='Build a payload offline only; do not write a live request.')
    args = parser.parse_args()
    if args.enable:
        assert not args.output
        atomic_write(args.directory / 'wj-dev-reload.enabled', b'wjl-dev-reload-v1\n')
        print('Development reload armed for the next launch; resident adapter installation required.')
        return
    data, count = payload()
    digest = hashlib.sha256(data).hexdigest()
    if args.output:
        atomic_write(args.output, data)
        print(json.dumps(dict(payload=str(args.output), sha256=digest, modules=count, requested=False)))
        return
    assert (args.directory / 'wj-dev-reload.enabled').read_bytes() == b'wjl-dev-reload-v1\n', 'Development mode is not armed'
    token = uuid.uuid4().hex
    target = args.directory / f'wj-dev-{token}.lua-pack'
    atomic_write(target, data)
    atomic_write(args.directory / 'wj-dev-reload.request', (token + '\n').encode())
    print(json.dumps(dict(token=token, payload=str(target), sha256=digest, modules=count, requested=True, runtime_acceptance='pending: check Dev reload log')))


if __name__ == '__main__':
    main()
