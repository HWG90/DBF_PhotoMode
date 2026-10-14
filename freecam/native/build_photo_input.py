"""Build the Photo-owned x64 input clone with a static CRT; never installs it."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
VCVARS = Path(r'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat')

def compile_at(output, commands):
    assert VCVARS.is_file(), 'MSVC x64 build environment missing'
    script = output / 'compile-photo-input.cmd'
    script.write_text('@echo off\ncall "'+str(VCVARS)+'" >nul\nif errorlevel 1 exit /b %errorlevel%\n'+
                      ''.join(command+'\nif errorlevel 1 exit /b %errorlevel%\n' for command in commands), encoding='utf-8')
    subprocess.run(['cmd', '/d', '/c', str(script)], cwd=output, check=True)

def build(output):
    output = output.resolve(); output.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'photo_input.cpp'
    name = 'mcm_input_'+hashlib.sha256(source.read_bytes()).hexdigest()[:12]+'.dll'
    compile_at(output, [f'cl /nologo /LD /MT /EHsc /O2 /W4 /WX "{source}" /Fo"{output / "photo_input.obj"}" /link /OUT:"{output / name}" /IMPLIB:"{output / "photo_input.lib"}" user32.lib',
                        f'dumpbin /dependents "{output / name}" > "{output / "imports.txt"}"'])
    dump = (output / 'imports.txt').read_text()
    imports = sorted(set(re.findall(r'^\s+([A-Za-z0-9_.-]+\.dll)\s*$', dump, re.M)), key=str.lower)
    assert {item.lower() for item in imports} == {'kernel32.dll', 'user32.dll'}, imports
    metadata = {'library': name, 'sha256': hashlib.sha256((output / name).read_bytes()).hexdigest(),
                'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'imports': imports,
                'runtime': 'Windows x64; static CRT', 'capability_export': 'int mcm_escape_passthrough(void): 1',
                'change': 'Forward physical Escape RAW and legacy down/up only in camera capture mode 3; menu mode 1 and all other keys retain capture/drain behavior.',
                'deployment': 'not installed', 'game_attached': False}
    (output / 'photo-input-native.json').write_text(json.dumps(metadata, indent=2)+'\n', encoding='utf-8')
    (output / 'library.txt').write_text(name+'\n', encoding='utf-8')
    print(json.dumps(metadata, indent=2)); return metadata

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=REPO / 'dist/review/native-menu-gate-098/native-input')
    build(parser.parse_args().output)
