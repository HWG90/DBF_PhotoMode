"""One-shot, build-pinned read-only module inspection for the Windows test.

Requests QUERY_INFORMATION | VM_READ only. No attach, debug privilege changes,
injection, allocation, process writes, protection changes, or retry of denied
access. Analysis images are local evidence and must never be executed/shipped.
"""
from pathlib import Path
import ctypes as C
from ctypes import wintypes as W
import argparse
import hashlib
import json
import struct
import time

ROOT = Path(__file__).resolve().parents[1]
GAME = Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2_steam')
EXPECTED = {
    'helldivers2.exe': (GAME / 'bin/helldivers2.exe', '0acc07debe04714ae04281e1a66bd2eb9d3d85232953e32a93c8a3dd0874eabe'),
    'game.dll': (GAME / 'data/game/game.dll', '6d1d4d3bc6fc84801d9f8f1b310e13a603d07409f3d9495d74b42e1d0bb1c08f'),
}
LIMIT = 128 * 1024 * 1024


def main(pid, output):
    output = output.resolve()
    assert output.is_relative_to(ROOT / 'dist/review/windows-readonly-contract')
    output.mkdir(parents=True, exist_ok=False)
    report = {'pid': pid, 'access': 'PROCESS_QUERY_INFORMATION | PROCESS_VM_READ',
              'process_writes': False, 'modules': [], 'status': 'starting'}
    report_path = output / 'RESULT.json'
    def save():
        report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    save()
    k = C.WinDLL('kernel32', use_last_error=True)
    p = C.WinDLL('psapi', use_last_error=True)
    k.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    k.OpenProcess.restype = W.HANDLE
    k.CloseHandle.argtypes = [W.HANDLE]
    k.ReadProcessMemory.argtypes = [W.HANDLE, C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]
    k.ReadProcessMemory.restype = W.BOOL
    k.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
    p.EnumProcessModulesEx.argtypes = [W.HANDLE, C.POINTER(W.HMODULE), W.DWORD, C.POINTER(W.DWORD), W.DWORD]
    p.GetModuleFileNameExW.argtypes = [W.HANDLE, W.HMODULE, W.LPWSTR, W.DWORD]
    h = None
    try:
        report['phase'] = 'verify disk build'
        files = {}
        for name, (path, digest) in EXPECTED.items():
            data = path.read_bytes()
            assert hashlib.sha256(data).hexdigest() == digest, name + ' file build differs'
            files[name] = data
        report['phase'] = 'open process';save()
        h = k.OpenProcess(0x410, False, pid)
        if not h:
            report.update(status='access_denied', winerror=C.get_last_error())
            return
        path_buffer = C.create_unicode_buffer(32768)
        length = W.DWORD(len(path_buffer))
        report['phase'] = 'verify process path';save()
        assert k.QueryFullProcessImageNameW(h, 0, path_buffer, C.byref(length)), 'QueryFullProcessImageNameW failed'
        assert Path(path_buffer.value).resolve() == EXPECTED['helldivers2.exe'][0].resolve(), 'PID path differs'
        modules = (W.HMODULE * 1024)()
        needed = W.DWORD()
        report['phase'] = 'enumerate modules';save()
        assert p.EnumProcessModulesEx(h, modules, C.sizeof(modules), C.byref(needed), 3), 'EnumProcessModulesEx failed'
        assert needed.value <= C.sizeof(modules)
        selected = {}
        for module in modules[:needed.value // C.sizeof(W.HMODULE)]:
            report['phase'] = 'verify module paths'
            assert p.GetModuleFileNameExW(h, module, path_buffer, len(path_buffer)), 'GetModuleFileNameExW failed'
            path = Path(path_buffer.value)
            if path.name.lower() in EXPECTED:
                name = path.name.lower()
                assert path.resolve() == EXPECTED[name][0].resolve()
                selected[name] = int(module)
        assert set(selected) == set(EXPECTED), 'Required modules missing'
        started = time.monotonic()
        total = 0
        def read(address, size):
            nonlocal total
            assert 0 < size <= 65536 and 65536 <= address < 2**47 - size
            total += size
            assert total <= LIMIT and time.monotonic() - started < 30, 'Read budget exceeded'
            buf = C.create_string_buffer(size)
            got = C.c_size_t()
            ok = k.ReadProcessMemory(h, address, buf, size, C.byref(got))
            return buf.raw[:size] if ok and got.value == size else None
        for name, base in selected.items():
            report['phase'] = 'capture '+name;save()
            original = files[name]
            pe = struct.unpack_from('<I', original, 60)[0]
            opt = pe + 24
            header = read(base, 4096)
            assert header and header[:2] == b'MZ' and header[pe:pe+4] == b'PE\0\0'
            assert header[pe+8:pe+12] == original[pe+8:pe+12], 'Loaded PE timestamp differs'
            assert header[opt+56:opt+60] == original[opt+56:opt+60], 'Loaded image size differs'
            count, optional_size = struct.unpack_from('<H', original, pe+6)[0], struct.unpack_from('<H', original, pe+20)[0]
            assert 1 <= count <= 16
            # Preserve original import/export/unwind metadata. Replace only
            # captured sections; absent pages remain zero and are reported.
            image = bytearray(original)
            struct.pack_into('<Q', image, opt+24, base)
            row = {'name': name, 'base': hex(base), 'file_sha256': EXPECTED[name][1],
                   'pe_timestamp': header[pe+8:pe+12].hex(), 'sections': []}
            for index in range(count):
                at = opt + optional_size + index*40
                section = original[at:at+8].split(b'\0')[0].decode('ascii')
                virtual_size, rva, raw_size, raw_at = struct.unpack_from('<IIII', original, at+8)
                if section not in ('.text', '.rdata', '.data') or not raw_size:
                    continue
                assert raw_at + raw_size <= len(image) and raw_size <= 64*1024*1024
                captured, missing = 0, []
                for offset in range(0, raw_size, 4096):
                    size = min(4096, raw_size-offset)
                    data = read(base+rva+offset, size)
                    if data is None:
                        data = bytes(size)
                        missing.append(hex(rva+offset))
                    else:
                        captured += size
                    image[raw_at+offset:raw_at+offset+size] = data
                row['sections'].append({'name': section, 'rva': hex(rva), 'bytes': raw_size,
                                        'captured': captured, 'missing_pages': missing})
            out = output / (name + '.analysis.bin')
            out.write_bytes(image)
            row.update(analysis_image=str(out), analysis_sha256=hashlib.sha256(image).hexdigest())
            report['modules'].append(row)
            save()
        game_base = selected['game.dll']
        font = {}
        for name, rva in [('font', 0x312d998), ('atlas', 0x312e618), ('owner', 0x3180c08)]:
            value = read(game_base+rva, 8)
            font[name] = f'{struct.unpack("<Q", value)[0]:016x}' if value else None
        if font.get('owner'):
            address = int(font['owner'], 16)
            if 65536 <= address < 2**47-32:
                value = read(address+24, 8)
                font['material'] = f'{struct.unpack("<Q", value)[0]:016x}' if value else None
        report.update(status='captured', font=font, requested_bytes=total,
                      elapsed_seconds=round(time.monotonic()-started, 3))
    except BaseException as error:
        report.update(status='failed', error=str(error), winerror=C.get_last_error())
    finally:
        if h:
            k.CloseHandle(h)
        save()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', required=True, type=int)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    main(args.pid, args.output)
