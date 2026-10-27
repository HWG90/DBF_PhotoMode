"""Scope the HUD key fix onto the last accepted development generation.

Builds a reviewable archive and byte receipt; --install atomically replaces only
the installed addon after rechecking the source archive and live generation.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import struct

from lupa.lua51 import LuaRuntime
from photo_assets import read_archive, archive_rows
from build_steam_archive import long_string

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2_steam/data/9ba626afa44a3aa3.patch_0')
OUT = ROOT / 'dist/releases/hud-binding-passthrough'
STATE = Path(os.environ['APPDATA']) / 'Arrowhead/Helldivers2'
CHANGED = ('windows_input_service.lua', 'vendor/wjl_input_service.lua', 'steam_input.lua', 'photo_menu.lua', 'steam_runtime.lua')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def accepted():
    token = (STATE / 'wj-dev-reload.request').read_text().strip()
    loaded = re.findall(r'Dev reload: loaded ([a-f0-9]{32})', (STATE / 'war_journalist_lua51.log').read_text(errors='replace'))[-1]
    assert token == loaded, 'Another development reload is pending'
    return token


def sources(text):
    matches = list(re.finditer(r'^SOURCES\["([^"\n]+)"\]=\[(=*)\[(.*?)\]\2\]\n', text, re.M | re.S))
    return {m[1]: m[3].removeprefix('\n') for m in matches}


def build():
    token = accepted()
    original = ARCHIVE.read_bytes()
    rows = read_archive(original)
    assert len(rows) == 1 and rows[0][3] == b''
    key, kind, payload, gpu = rows[0]
    length, version = struct.unpack_from('<II', payload)
    assert length == len(payload) - 8 and version == 2
    text = payload[8:].decode()
    lua = LuaRuntime()
    parse = lua.execute((ROOT / 'freecam/windows_dev_reload.lua').read_text()).parse
    base = {r.path: r.source for _, r in parse((STATE / f'wj-dev-{token}.lua-pack').read_bytes().decode()).items()}
    graph = dict(base)
    for name in CHANGED:
        path = 'src/' + name
        if name == 'steam_runtime.lua':
            # Concurrent Freeze work may exist in the checkout. Apply only our
            # menu callback to the accepted runtime, preserving every other byte.
            old = "  hud=hud and function()return handle.set('hide_hud',not handle.get('hide_hud'))end or nil})"
            new = "  hud_binding=deps.input_policy and deps.input_policy.require_keyboard==true and function()\n   return service.capabilities.hud_binding_label or'Unavailable',service.capabilities.hud_binding_warning\n  end or nil,\n" + old
            assert base[path].count(old) == 1 and 'hud_binding=' not in base[path]
            graph[path] = base[path].replace(old, new)
        else:
            graph[path] = (ROOT / 'freecam' / name).read_text()
    assert sorted(k for k in base if graph[k] != base[k]) == sorted('src/' + n for n in CHANGED)
    compile_lua = lua.eval('function(s,n)return assert(loadstring(s,n))end')
    for name, source in graph.items():
        compile_lua(source, '@' + name)
    start, end = text.index('local SOURCES={}\n'), text.index('local LIBRARIES={\n')
    replacement = 'local SOURCES={}\n' + ''.join('SOURCES[' + json.dumps(k) + ']=' + long_string(v) + '\n' for k, v in graph.items())
    updated = text[:start] + replacement + text[end:]
    assert sources(updated) == graph, 'Packaged source bytes differ'
    compile_lua(updated, '@installed-hud-binding-addon')
    encoded = updated.encode()
    body, sidecar = archive_rows([(key, kind, struct.pack('<II', len(encoded), 2) + encoded, gpu)])
    assert sidecar == b''
    unpacked = read_archive(body)
    assert unpacked[0][2][8:] == encoded
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'original.patch_0').write_bytes(original)
    (OUT / ARCHIVE.name).write_bytes(body)
    (OUT / 'addon.lua').write_text(updated, encoding='utf-8', newline='\n')
    receipt = dict(base_token=token, installed_path=str(ARCHIVE), original_sha256=digest(original),
                   addon_sha256=digest(body), modules=len(graph), changed_modules=['src/' + n for n in CHANGED],
                   accepted_generation_preserved=True, packaged_bytes_verified=True, lua_compilation_passed=True,
                   installed=False, restart_required=True, live_validation=False)
    (OUT / 'VALIDATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def install():
    receipt = json.loads((OUT / 'VALIDATION.json').read_text())
    assert accepted() == receipt['base_token'], 'A newer accepted runtime exists; rebuild first'
    assert digest(ARCHIVE.read_bytes()) == receipt['original_sha256'], 'Installed archive changed; rebuild first'
    body = (OUT / ARCHIVE.name).read_bytes()
    assert digest(body) == receipt['addon_sha256']
    temp = ARCHIVE.with_name(ARCHIVE.name + '.hud-binding.tmp')
    with temp.open('xb') as stream:
        stream.write(body)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, ARCHIVE)
    assert ARCHIVE.read_bytes() == body, 'Installed bytes differ'
    receipt.update(installed=True, installed_bytes_verified=True)
    (OUT / 'VALIDATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    print(json.dumps(install() if args.install else build(), indent=2))
