"""Build or explicitly run the standalone SDR WGC Helldivers window-capture proof.

Build offline: py -3.14 tools/capture_game_window.py --build-only
Inspect:      py -3.14 tools/capture_game_window.py --inspect --pid N
Capture:      py -3.14 tools/capture_game_window.py --pid N --output C:/ABS/name.png
No automatic game discovery, injection, input changes, desktop fallback or polling.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'freecam/native/window_capture.cpp'
VC = Path('C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207')
SDK = Path('C:/Program Files (x86)/Windows Kits/10')
SDK_VERSION = '10.0.26100.0'
COMPILER = VC / 'bin/Hostx64/x64/cl.exe'
REVIEW = (ROOT / 'dist/review').resolve()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(directory):
    directory = directory.resolve()
    if directory == REVIEW or not directory.is_relative_to(REVIEW):
        raise ValueError('Build outputs must be inside a dedicated dist/review subdirectory')
    include = [VC / 'include'] + [SDK / 'Include' / SDK_VERSION / part for part in ('ucrt', 'shared', 'um', 'winrt', 'cppwinrt')]
    libraries = [VC / 'lib/x64', SDK / 'Lib' / SDK_VERSION / 'ucrt/x64', SDK / 'Lib' / SDK_VERSION / 'um/x64']
    if not COMPILER.is_file() or not all(path.is_dir() for path in include + libraries):
        raise FileNotFoundError('Pinned VC 14.44.35207 / SDK 10.0.26100.0 toolchain is unavailable')
    directory.mkdir(parents=True, exist_ok=True)
    builder = Path(__file__).resolve()
    source_hash, builder_hash = digest(SOURCE), digest(builder)
    env = os.environ.copy()
    env['INCLUDE'] = ';'.join(map(str, include))
    env['LIB'] = ';'.join(map(str, libraries))
    env['PATH'] = str(COMPILER.parent) + ';' + str(SDK / 'bin' / SDK_VERSION / 'x64') + ';' + env.get('PATH', '')
    executable = directory / 'window_capture.exe'
    command = [str(COMPILER), '/nologo', '/std:c++17', '/EHsc', '/permissive-', '/Zc:__cplusplus', '/MT', '/O2', '/W4', '/WX',
               '/DUNICODE', '/D_UNICODE', str(SOURCE), '/Fo' + str(directory / 'window_capture.obj'),
               '/Fe' + str(executable), '/link', '/INCREMENTAL:NO', '/Brepro',
               'd3d11.lib', 'dxgi.lib', 'dwmapi.lib', 'windowsapp.lib', 'windowscodecs.lib', 'ole32.lib', 'user32.lib']
    result = subprocess.run(command, env=env, cwd=directory, capture_output=True, text=True)
    (directory / 'build.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError('Compilation failed; see ' + str(directory / 'build.log') + '\n' + result.stdout + result.stderr)
    if digest(SOURCE) != source_hash or digest(builder) != builder_hash:
        raise RuntimeError('Source or builder changed during compilation; build is not attested')
    receipt = {'built': True, 'capture_executed': False, 'source': str(SOURCE), 'source_sha256': source_hash,
               'builder': str(builder), 'builder_sha256': builder_hash,
               'executable': str(executable), 'executable_sha256': digest(executable),
               'compiler': str(COMPILER), 'compiler_sha256': digest(COMPILER), 'vc_version': VC.name, 'sdk_version': SDK_VERSION,
               'command': command, 'mode': 'SDR BGRA8 prototype; HDR not qualified',
               'frame_wait_ms': 5000,
               'crop_policy': 'physical client region; exact WGC-to-window/DWM frame size match; reject ambiguous origins',
               'dpi_policy': 'helper thread per-monitor-v2; prior context restored; no process DPI change',
               'output_policy': 'absolute PNG; CREATE_NEW delete-on-close staging; flushed atomic non-replacing handle rename',
               'scope': 'external unique game HWND; no game memory, hooks, injection, focus or cursor ownership'}
    (directory / 'BUILD.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return receipt


def run_verified(pid, arguments, directory):
    if pid <= 0 or pid > 0xffffffff:
        raise ValueError('--pid must be a positive DWORD')
    receipt = json.loads((directory / 'BUILD.json').read_text(encoding='utf-8'))
    executable = directory / 'window_capture.exe'
    if digest(SOURCE) != receipt['source_sha256'] or digest(executable) != receipt['executable_sha256']:
        raise ValueError('Capture executable/source differs from the offline build receipt')
    result = subprocess.run([str(executable), *arguments],
                            capture_output=True, text=True, encoding='utf-8', timeout=20, creationflags=subprocess.CREATE_NO_WINDOW)
    reply = json.loads(result.stdout)
    reply['executable_sha256'] = receipt['executable_sha256']
    reply['source_sha256'] = receipt['source_sha256']
    if result.returncode or not reply.get('ok'):
        raise RuntimeError(json.dumps(reply))
    return reply


def capture(pid, output, directory):
    if not output.is_absolute() or output.suffix.lower() != '.png' or not output.parent.is_dir():
        raise ValueError('--output must be an absolute .png path with an existing parent directory')
    if output.exists():
        raise FileExistsError('Output already exists; never overwrite a capture')
    return run_verified(pid, ['--pid', str(pid), '--output', str(output)], directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--inspect', action='store_true', help='Read window/display metadata without starting WGC')
    parser.add_argument('--build-dir', type=Path, default=REVIEW / 'window-capture-client')
    parser.add_argument('--pid', type=int)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        if args.build_only:
            if args.pid is not None or args.output is not None or args.inspect:
                parser.error('--build-only must not include capture arguments')
            result = build(args.build_dir)
        elif args.inspect:
            if args.pid is None or args.output is not None:
                parser.error('Inspect requires explicit --pid and no --output')
            result = run_verified(args.pid, ['--inspect', '--pid', str(args.pid)], args.build_dir.resolve())
        else:
            if args.pid is None or args.output is None:
                parser.error('Capture requires explicit --pid and --output; use --build-only to compile offline')
            result = capture(args.pid, args.output, args.build_dir.resolve())
        print(json.dumps(result, indent=2))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
