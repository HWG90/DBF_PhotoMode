"""Build the standalone Windows WIC screenshot converter with a static CRT."""
import hashlib
import json
import argparse
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent
source = root / 'photo_capture.cpp'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,default=root.parents[1] / 'dist/photo-capture-native')
output=parser.parse_args().output.resolve()
output.mkdir(parents=True, exist_ok=True)
vcvars = Path(r'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat')
assert vcvars.is_file(), 'MSVC x64 build environment missing'
name = 'photo_capture_' + hashlib.sha256(source.read_bytes()).hexdigest()[:16] + '.dll'
command = (f'call "{vcvars}" >nul && cl /nologo /LD /MT /EHsc /std:c++17 /O2 /W4 /WX '
           f'"{source}" /Fo"{output / "photo_capture.obj"}" /link '
           f'/OUT:"{output / name}" /IMPLIB:"{output / "photo_capture.lib"}" ole32.lib windowscodecs.lib')
subprocess.run(command, shell=True, check=True, cwd=output)
metadata = {'library': name, 'sha256': hashlib.sha256((output / name).read_bytes()).hexdigest(),
            'export': 'int PhotoDDSConvert(const wchar_t *input, const wchar_t *output)',
            'color_export': 'int PhotoDDSConvertColor(const wchar_t *input, const wchar_t *output, uint32_t encoding, float white_nits)',
            'color_encodings': {'0':'Original SDR/linear format interpretation','1':'HDR10 ST2084/PQ BT.2020 RGB10, absolute nits to BT.709, luminance Reinhard mapping, sRGB encoding'},
            'hdr_requires_explicit_capture_profile': True,
            'png_color_space':'sRGB; perceptual rendering intent',
            'success': 1, 'failure': 0, 'error': 'GetLastError()',
            'dxgi_formats': [28, 29, 87, 91, 88, 93, 24, 10, 2, 27, 90, 92, 23, 9, 1],
            'typeless_interpretation': {'27': 28, '90': 87, '92': 88, '23': 24, '9': 10, '1': 2},
            'overwrite': False, 'runtime': 'Windows WIC; static CRT'}
(output / 'photo-capture-native.json').write_text(json.dumps(metadata, indent=2) + '\n')
print(json.dumps(metadata, indent=2))
