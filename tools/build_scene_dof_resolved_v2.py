"""Build an isolated PQ resolved-color compositor; never deploy or replace assets."""
import argparse
import ctypes
import hashlib
import json
import math
from pathlib import Path
import struct

import photo_assets

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'freecam/assets/shaders/scene_dof_resolved_v2.hlsl'
TEMPLATE = SOURCE.parent / 'dof_library_template.gpu'
WINDOW = 7152
COLOR_NAME = 'output_target'
sha = lambda body: hashlib.sha256(body).hexdigest()


def _math_receipt():
    """Exercise the exact shader/native GUI round trip below UI white.

    This proves numeric units/transfer arithmetic, not resource binding or GPU
    behavior. The native final compositor's inverse GUI matrix is retained as
    recorded float constants; its rounding accounts for the residual.
    """
    matrix = ((1.63504, -.60563, -.07635),
              (-.12325, 1.13885, -.01029),
              (-.01716, -.10173, 1.21073))
    inverse = ((.637920, .343095, .043148),
               (.069171, .915945, .012151),
               (.014851, .081825, .827577))
    multiply = lambda a, value: tuple(sum(x * y for x, y in zip(row, value)) for row in a)
    def pq_encode(nits):
        p = (max(0., nits) / 10000.) ** (2610. / 16384.)
        return ((3424. / 4096. + (2413. / 128.) * p) /
                (1. + (2392. / 128.) * p)) ** (2523. / 32.)
    def pq_decode(value):
        p = min(1., max(0., value)) ** (32. / 2523.)
        return 10000. * (max(p - 3424. / 4096., 0.) /
                         max(2413. / 128. - (2392. / 128.) * p, .000001)) ** (16384. / 2610.)
    def srgb_encode(value):
        value = max(0., value)
        return value * 12.92 if value <= .0031308 else 1.055 * value ** (1. / 2.4) - .055
    def srgb_decode(value):
        return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4
    cases = []
    max_error = 0.
    colors = ((.0001, .0001, .0001), (.002, .01, .04), (.05, .05, .05),
              (.18, .18, .18), (.95, .95, .95), (.7, .1, .05),
              (.05, .65, .1), (.05, .1, .75), (.8, .6, .05))
    for white in (48., 203., 336.35858, 800.):
        for color in colors:
            native_nits = multiply(inverse, tuple(c * white for c in color))
            pq = tuple(pq_encode(n) for n in native_nits)
            decoded_nits = tuple(pq_decode(c) for c in pq)
            gui = tuple(max(0., c) / white for c in multiply(matrix, decoded_nits))
            carrier = tuple(srgb_encode(c) for c in gui)
            # Native GUI EOTF, multiplication by ui_brightness, inverse matrix.
            restored_gui = tuple(srgb_decode(c) * white for c in carrier)
            restored_nits = multiply(inverse, restored_gui)
            error = max(abs(a - b) / white for a, b in zip(native_nits, restored_nits))
            max_error = max(max_error, error)
            assert all(math.isfinite(c) and 0. <= c <= 1. for c in carrier)
            assert error < .00002, (white, color, error)
            cases.append({'ui_white_nits': white, 'gui_linear': color,
                          'normalized_native_nits_error': error})
    # Packing must preserve both endpoints of fog opacity independently of debug.
    for debug in (False, True):
        for fog in (0., .25, .5, 1.):
            packed = fog + (1000. if debug else 0.)
            actual_debug = packed >= 1000.
            actual_fog = max(0., min(1., packed - (1000. if actual_debug else 0.)))
            assert actual_debug == debug and actual_fog == fog
    return {'passed': True, 'cases': len(cases), 'maximum_normalized_native_nits_error': max_error,
            'vectors': cases, 'ui_white_units': 'absolute nits', 'extra_exposure_calibration': False,
            'fog_debug_pack_endpoints_passed': True,
            'scope': 'CPU arithmetic only; not a live texture/constant-binding verification'}


class Compiler:
    def __init__(self):
        self.dll = ctypes.WinDLL('d3dcompiler_47.dll')

    @staticmethod
    def blob(pointer):
        table = ctypes.cast(pointer, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        address = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(table[3])(pointer)
        size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(table[4])(pointer)
        result = ctypes.string_at(address, size)
        ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(table[2])(pointer)
        return result

    def compile(self, source):
        function = self.dll.D3DCompile
        function.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p,
            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p,
            ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p)]
        function.restype = ctypes.c_long
        buffer = ctypes.create_string_buffer(source)
        result, error = ctypes.c_void_p(), ctypes.c_void_p()
        status = function(buffer, len(source), SOURCE.name.encode(), None, None,
                          b'photo_resolved_v2', b'ps_5_0', 1 << 15, 0,
                          ctypes.byref(result), ctypes.byref(error))
        message = self.blob(error).decode(errors='replace') if error else ''
        assert status >= 0, message
        return self.blob(result), message

    def listing(self, data):
        function = self.dll.D3DDisassemble
        function.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint,
                             ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
        function.restype = ctypes.c_long
        buffer, result = ctypes.create_string_buffer(data), ctypes.c_void_p()
        assert function(buffer, len(data), 0, None, ctypes.byref(result)) >= 0
        return self.blob(result).decode(errors='replace')

    def padded(self, code):
        function = self.dll.D3DSetBlobPart
        function.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint,
            ctypes.c_uint, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_void_p)]
        function.restype = ctypes.c_long
        def pad(size):
            buffer, private = ctypes.create_string_buffer(code), ctypes.create_string_buffer(size)
            result = ctypes.c_void_p()
            assert function(buffer, len(code), 10, 0, private, size, ctypes.byref(result)) >= 0
            return self.blob(result)
        first = pad(4)
        window = max(WINDOW, ((len(first) + 15) // 16) * 16)
        padded = pad(window - len(first) + 4)
        assert len(padded) == window and struct.unpack_from('<I', padded, 24)[0] == window
        self.listing(padded)
        return padded, window


def build(output, color_name=COLOR_NAME):
    output = Path(output)
    assert not output.exists(), 'Preserve existing named candidates'
    assert color_name == COLOR_NAME, 'This candidate requires the graded full-size PQ output_target'
    source, original = SOURCE.read_bytes(), TEMPLATE.read_bytes()
    assert sha(original) == '6729d404ca524fc4dd20a986fdab5bd65f54b9fca126fccda96b4c42afb492b7'
    content_id = sha(source)[:16]
    shader = 'mods/dbf_photo/shaders/scene_dof_resolved_v2_' + content_id
    material_name = 'mods/dbf_photo/materials/scene_dof_resolved_v2_' + content_id
    compiler = Compiler()
    code, warning = compiler.compile(source)
    assembly = compiler.listing(code)
    assert all(name in assembly for name in ('__tex_diffuse_map', '__tex_photo_color', 'CB0[49]', 'CB2[9]'))
    assert 'edge_fade_offset' not in assembly and 'clip_box' in assembly and 'atlas_scissor' in assembly
    vertex_assembly = compiler.listing(original[0xff0:0xff0 + 5160])
    assert 'cbuffer c_per_object' in vertex_assembly and 'dcl_constantbuffer CB2[5]' in vertex_assembly
    assert all(name not in vertex_assembly for name in ('cbuffer c0', 'clip_box', 'scissor_mode'))
    padded, window = compiler.padded(code)

    # Preserve the established native library ABI, including the vertex DXBC,
    # material metadata and 120-byte binding tail. No guessed offset relocation.
    assert len(original) == 0x40d0
    assert struct.unpack_from('<I', original, 0xaa8)[0] == 5160
    assert struct.unpack_from('<I', original, 0xbe8)[0] == WINDOW
    assert photo_assets._dxbc_windows(original) == [(0xff0, 5160), (0x2468, WINDOW)]
    assert 0xff0 + 5160 + 80 == 0x2468 and 0x2468 + WINDOW == 0x4058
    assert len(original[0x4058:]) == 120
    for old_offset in (0xff0, 0x2468, 0x4058, len(original)):
        assert not any(struct.unpack_from('<I', original, at)[0] == old_offset
            for at in list(range(0, 0xff0, 4)) + list(range(0x4058, len(original) - 3, 4)))
    body, allowed = bytearray(original), set()
    program_id = photo_assets.hash64(shader + ':default:PLATFORM_WIN32:RENDERER_D3D11') >> 32
    variant_id = photo_assets.hash64(shader) >> 32
    pixel_id = photo_assets.hash64(shader + ':pixel') >> 32
    replacements = {struct.unpack_from('<I', original, 0x88)[0]: program_id,
                    struct.unpack_from('<I', original, 0xe0)[0]: variant_id,
                    struct.unpack_from('<I', original, 0xbec)[0]: pixel_id}
    assert len(replacements) == 3 and len(set(replacements.values())) == 3
    counts = {key: 0 for key in replacements}
    for at in range(0, len(original) - 3, 4):
        if 0xff0 <= at < 0xff0 + 5160 or 0x2468 <= at < 0x2468 + WINDOW:
            continue
        value = struct.unpack_from('<I', original, at)[0]
        if value in replacements:
            struct.pack_into('<I', body, at, replacements[value])
            counts[value] += 1
            allowed.update(range(at, at + 4))
    assert sorted(counts.values()) == [1, 2, 2]
    old_color = photo_assets.hash64('hdr0_div4_fullres') >> 32
    color_offsets = (0x5f8, 0xf38, 0x40a0, 0x40bc)
    assert [at for at in range(0, len(original) - 3, 4)
            if struct.unpack_from('<I', original, at)[0] == old_color] == list(color_offsets)
    for at in color_offsets:
        struct.pack_into('<I', body, at, photo_assets.hash64(color_name) >> 32)
        allowed.update(range(at, at + 4))
    assert all(at in allowed for at, (a, b) in enumerate(zip(original, body)) if a != b)
    metadata = bytes(body)
    struct.pack_into('<I', body, 0xbe8, window)
    body[0x2468:0x4058] = padded
    delta, tail = window - WINDOW, 0x4058 + window - WINDOW
    assert len(body) == len(original) + delta and delta % 16 == 0
    assert photo_assets._dxbc_windows(body) == [(0xff0, 5160), (0x2468, window)]
    assert body[0xff0:0xff0 + 5160] == original[0xff0:0xff0 + 5160]
    assert body[tail:] == metadata[0x4058:]
    roundtrip = bytearray(body)
    roundtrip[0x2468:0x2468 + window] = metadata[0x2468:0x4058]
    struct.pack_into('<I', roundtrip, 0xbe8, WINDOW)
    assert bytes(roundtrip) == metadata
    material = bytearray((SOURCE.parent / 'dof_local_depth.material.bin').read_bytes())
    struct.pack_into('<I', material, 128, variant_id)
    math_receipt = _math_receipt()

    receipt = {'candidate': True, 'installed': False, 'live_verified': False,
        'shader': shader, 'material': material_name, 'content_id': content_id,
        'hlsl_source_path': SOURCE.relative_to(ROOT).as_posix(), 'hlsl_sha256': sha(source),
        'shader_gpu_sha256': sha(body), 'material_sha256': sha(material),
        'color_resource_name': color_name, 'color_resource_hash': f'{photo_assets.hash64(color_name) >> 32:08x}',
        'color_resource_live_binding_verified': False,
        'color_space': 'native graded ST2084 PQ scene -> absolute nits -> native GUI primaries / verified UI white -> sRGB GUI OETF',
        'native_gui_eotf_evidence': 'dist/dof-investigation-20261011/gui-color-transfer-readonly/622ae073dee47dad-a280.asm.txt',
        'white_carrier': 'clip_box.w (existing vector4 material payload); no edge_fade_offset scalar',
        'uniforms': {'scissor_rect': ['focus_m', 'aperture_fstop', 'fov_radians', 'blur_pixels_0_disables_dof'],
            'atlas_scissor': ['scene_depth_range_m', 'fog_maximum_opacity_plus_depth_debug_1000', 'blades_0_circle_6_hex', 'quality_0_32_1_64'],
            'scissor_mode': 'effect_0_to_9', 'threshold_fade': 'effect_strength', 'desaturate': 'fog_half_density_m',
            'clip_box': ['exposure_EV', 'contrast', 'saturation', 'native_ui_brightness_nits']},
        'neutral_dof_composition': 'focused pixels native passthrough; gather once in linear GUI light; smooth GUI alpha=blur opacity; no double opacity interpolation',
        'scene_composition': 'scene effects/color controls after optional bokeh in one source-aware pass; full scene alpha',
        'hdr_limitations': 'RGBA8 GUI carrier clips blurred/effected energy above UI white and out-of-GUI-gamut colors; neutral focused native HDR remains untouched',
        'blur_quality': {'standard_taps': 32, 'high_taps': 64, 'changed_from_previous': False},
        'pixel_bytes_unstripped': len(code), 'pixel_bytes_stripped': None,
        'pixel_window_bytes': WINDOW, 'emitted_pixel_window_bytes': window,
        'emitted_full_reflection': True, 'native_vertex_byte_identity': True,
        'native_parameter_and_binding_abi_preserved': True,
        'vertex_uniform_separation': {'vertex_b2': 'c_per_object transform/flag buffer', 'pixel_b2': 'c0 material buffer', 'vertex_has_clip_box_or_scissor_mode': False},
        'content_identified_ids': {'program': f'{program_id:08x}', 'variant': f'{variant_id:08x}', 'pixel': f'{pixel_id:08x}'},
        'library_expansion_bytes': delta, 'stage_length_field': {'offset': '0xbe8', 'original': WINDOW, 'candidate': window},
        'serialized_tail_relocation': {'old_offset': '0x4058', 'new_offset': hex(tail), 'bytes': 120, 'byte_identity': True},
        'reverse_splice_roundtrip': True, 'expanded_library_live_load_verified': False,
        'numeric_color_verification': math_receipt, 'compiler_messages': warning}
    output.mkdir(parents=True)
    (output / 'scene_dof_combined.hlsl').write_bytes(source)
    (output / 'scene_dof_combined.asm.txt').write_text(assembly)
    (output / 'native_vertex_preserved.asm.txt').write_text(vertex_assembly)
    (output / 'scene_dof_combined.ps.dxbc').write_bytes(code)
    (output / 'scene_dof_combined.gpu').write_bytes(body)
    (output / 'scene_dof_combined.material.bin').write_bytes(material)
    (output / 'BUILD-RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--color-name', default=COLOR_NAME)
    args = parser.parse_args()
    print(json.dumps(build(args.output.resolve(), args.color_name), indent=2))
