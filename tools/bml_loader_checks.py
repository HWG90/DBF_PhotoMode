"""Would the loaders start this text? Boot Mod Loader 0.13.4's own for_chef, lifted from the
installed loader and run in Lua 5.1, and LLL's documented Chef-addon rule. Offline only."""
from pathlib import Path
import hashlib
import re

from package_head import ROOT

BML_LOADER = Path.home() / '.config/hd2arsenal/mods/Boot Mod Loader 17754 0.13.4 2026-10-29T18-06Z 2Gg9W5NsL_AR932415/Boot Mod Loader/f476df93691895fa.lua'
BML_LOADER_SHA256 = '7cc69039cba22432b8ff8e02d0ce4a0d5208837910fb401d4dd3a2d58d9c18d0'
# A pinned copy (gitignored, see BUILD.md) first, so an Arsenal update of Boot Mod Loader stops no build.
LOADER_COPIES = (ROOT / 'dist/bml-src/f476df93691895fa.lua', BML_LOADER)
# declared_in's first-line pattern: the resource the loader runs.
ADDON_LINE = re.compile(r'-- HD2-Addon: (mods/[A-Za-z0-9_]+/[A-Za-z0-9_/]+)\r?\n')
LLL_CHEF_LINE = re.compile(r'^local\s+chef\s*=\s*\.\.\.', re.M)

_for_chef = {}


def pinned_loader(candidates=LOADER_COPIES):
    """The first copy of Boot Mod Loader 0.13.4 whose bytes still match the pin."""
    for path in candidates:
        if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == BML_LOADER_SHA256:
            return path
    raise AssertionError('Boot Mod Loader 0.13.4 not found or changed: ' + ', '.join(str(p) for p in candidates))


def for_chef(loader):
    """The loader's for_chef(source), with KEYWORD, lua_tokens and chef_untested beside it."""
    if loader not in _for_chef:
        data = loader.read_bytes() if loader.is_file() else b''
        if hashlib.sha256(data).hexdigest() != BML_LOADER_SHA256:
            raise AssertionError('Boot Mod Loader 0.13.4 not found or changed: ' + str(loader))
        text = data.decode('utf-8')
        start, stop = text.index('\nlocal KEYWORD = {}\n') + 1, text.index('\nlocal function run(entry)\n') + 1
        from lupa.lua51 import LuaRuntime
        _for_chef[loader] = LuaRuntime().execute(text[start:stop] + 'return for_chef\n')
    return _for_chef[loader]


def bml_starts(text, loader=None):
    """(True, 'starts') when Boot Mod Loader would run the text itself; else why not."""
    loader = loader or pinned_loader()
    found = ADDON_LINE.match(text)
    if not found or found.group(1).endswith('/'):
        return False, 'no HD2-Addon line'
    if for_chef(loader)(text):
        return False, 'for chef'
    return True, 'starts'


def lll_chef_style(text):
    """LLL treats a text as a Chef addon when its first 1200 bytes say so."""
    head = text.encode('utf-8')[:1200].decode('utf-8', 'ignore')
    return bool(LLL_CHEF_LINE.search(head)) or 'HD2-Requires: chef-shared-loader' in head or 'HD2-Requires: chef-loader' in head
