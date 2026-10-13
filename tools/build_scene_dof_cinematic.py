"""Compile a separate strength/bokeh candidate; never install or mutate release snapshots.

Reuses the audited resolved-v2 native-library serializer and DXBC compiler. The
new source hash gives distinct shader/material/program identities. Runtime and
release integration are deliberately separate from this candidate builder.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import build_scene_dof_resolved_v2 as base

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'freecam/assets/shaders/scene_dof_cinematic_v1.hlsl'
ACCEPTED = ROOT / 'freecam/assets/shaders/release-0.9.5/resolved.hlsl'
ACCEPTED_SHA = '8a8fd1f00bd99bfa772db8af71f3c5003f5c7f8a90f4b304597f1a9825e4cf84'
sha = lambda data: hashlib.sha256(data).hexdigest()


def function(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    at = opening + 1
    while depth:
        if source[at] == '{':
            depth += 1
        elif source[at] == '}':
            depth -= 1
        at += 1
    return source[start:at]


def verify_preserved(source, accepted):
    pieces = {}
    for signature in ('float3 decode_resolved(', 'float3 encode_display(', 'float3 thermal('):
        original = function(accepted, signature)
        assert function(source, signature) == original, 'Accepted color math changed: ' + signature
        pieces[signature] = sha(original.encode())
    # Both neutral GUI alpha and the complete scene/color-effect implementation
    # remain exact, including native focused-HDR passthrough and UI alpha.
    marker = ' if(!scene&&(scissor_rect.w<=0.0||opacity<=0.0))'
    tail = accepted[accepted.index(marker):]
    assert source[source.index(marker):] == tail, 'Accepted composition/effect tail changed'
    pieces['neutral_and_scene_composition_tail'] = sha(tail.encode())
    for register in ('register(t1)', 'register(s1)', 'register(t0)', 'register(s0)',
                     'register(b0)', 'register(b2)', 'packoffset(c48)', 'packoffset(c8)'):
        assert source.count(register) == accepted.count(register)
    return pieces


def numeric_receipt():
    def physical(depth, focus, aperture, fov, height):
        focal = .012 / math.tan(fov * .5)
        return focal*focal*(depth-focus)/(aperture*depth*max(.001, focus-focal))*height/.048

    def radius(depth, focus, aperture, fov, height, carrier):
        limit = max(0., min(192., carrier)) if math.isfinite(carrier) else 0.
        coc = physical(depth, focus, aperture, fov, height) * (limit / 24.)
        return max(-limit, min(limit, coc)) if math.isfinite(coc) else 0.

    cases = 0
    for depth in (.001, .1, 1., 1.4, 5., 10., 100., 100000.):
        for focus in (.1, 1.4, 5., 20., 100.):
            for aperture in (1.2, 2., 5.6, 22.):
                for fov in (.02, .9, 2.9):
                    for height in (1., 720., 1440., 2160., 4320.):
                        raw = physical(depth, focus, aperture, fov, height)
                        baseline = max(-24., min(24., raw))
                        unity = radius(depth, focus, aperture, fov, height, 24.)
                        assert unity == baseline
                        for gain in (0., 1., 2., 4., 8.):
                            actual = radius(depth, focus, aperture, fov, height, gain * 24.)
                            assert math.isfinite(actual) and abs(actual) <= gain * 24.
                            assert math.isclose(actual, baseline * gain, rel_tol=1e-14, abs_tol=1e-12)
                            if depth == focus:
                                assert actual == 0.
                        cases += 1
    for bad in (float('nan'), float('inf'), -float('inf'), -1.):
        assert radius(100., 5., 1.2, .9, 1440., bad) == 0.
    assert abs(radius(.001, 100., 1.2, .02, 4320., 10000.)) <= 192.
    # Uniform scene radiance remains unchanged by normalized highlight weights,
    # including HDR working values; clipping belongs to the existing carrier.
    for rgb in ((0., 0., 0.), (.01, .5, 2.), (100., 4., .2)):
        for count in (32, 64, 128):
            gathered, total = list(rgb), 1.
            for tap in range(count):
                weight = math.exp2(-(tap % 7)/7.) * (1. + .5 * min(8., max(0.,
                    sum(c*w for c, w in zip(rgb, (.2126, .7152, .0722))) - 1.)))
                gathered = [a+c*weight for a, c in zip(gathered, rgb)]
                total += weight
            assert all(math.isclose(a/total, c, rel_tol=1e-13, abs_tol=1e-13)
                       for a, c in zip(gathered, rgb))
    sample = {str(gain): radius(100000., 5., 1.2, .9, 1440., gain*24.) for gain in (1, 4, 8)}
    return {'passed': True, 'physical_cases': cases, 'unity_gain_exact_algebraic_match': True,
            'uniform_radiance_normalization': True, 'finite_radius_limit_pixels': 192,
            'focus_5m_f12_1440px_far_radius_by_gain': sample,
            'scope': 'CPU arithmetic and unchanged source contracts; not observed GPU output'}


def build(output):
    output = Path(output)
    assert not output.exists(), 'Preserve existing named candidates'
    baseline = ACCEPTED.read_bytes()
    assert sha(baseline) == ACCEPTED_SHA, 'Frozen accepted source changed'
    source = SOURCE.read_bytes()
    preserved = verify_preserved(source.decode(), baseline.decode())
    numeric = numeric_receipt()
    original_source = base.SOURCE
    try:
        base.SOURCE = SOURCE
        receipt = base.build(output)
    finally:
        base.SOURCE = original_source
    assert sha(ACCEPTED.read_bytes()) == ACCEPTED_SHA
    manifest = json.loads((ACCEPTED.parent / 'manifest.json').read_text())
    old_names = {pair[key] for pair in manifest['pairs'] for key in ('shader', 'material')}
    assert receipt['shader'] not in old_names and receipt['material'] not in old_names
    receipt.update({
        'candidate_kind': 'cinematic-strength-single-pass',
        'accepted_color_source_sha256': ACCEPTED_SHA,
        'accepted_color_and_composition_exact_text': preserved,
        'unity_gain_sampling_preserved': True,
        'blur_quality': {'standard_taps_unity': 32, 'high_taps_unity': 64,
                         'standard_taps_above_unity': 64, 'high_taps_above_unity': 128,
                         'deterministic_disk': True, 'normalized_existing_highlight_weights': True},
        'strength_contract': {'carrier': 'scissor_rect.w', 'encoding': '24 * gain',
                              'gain_min': 0, 'gain_max': 8, 'suggested_default_gain': 4,
                              'maximum_radius_pixels': 192},
        'numeric_strength_verification': numeric,
        'limitations': ['Single-pass gather retains the accepted depth-discontinuity rejection.',
                        'Near-field silhouette expansion needs separate foreground/mask passes.',
                        'Existing RGBA8 GUI HDR-white/gamut clipping is unchanged.',
                        'Larger-radius quality/performance needs live visual verification.'],
    })
    receipt['uniforms']['scissor_rect'][3] = '24_times_strength_gain_0_disables_8_max'
    receipt['uniforms']['atlas_scissor'][3] = 'quality_0_standard_1_high; unity32/64, stronger64/128'
    files = {path.name: sha(path.read_bytes()) for path in output.iterdir() if path.is_file() and path.name != 'BUILD-RECEIPT.json'}
    receipt['self_contained_candidate_files'] = files
    (output / 'BUILD-RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = build(args.output.resolve())
    print(json.dumps({key: result[key] for key in ('shader', 'material', 'hlsl_sha256',
        'shader_gpu_sha256', 'material_sha256', 'emitted_pixel_window_bytes',
        'numeric_strength_verification')}, indent=2))
