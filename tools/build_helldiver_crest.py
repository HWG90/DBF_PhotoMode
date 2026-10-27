"""Flatten the credited SVG into a small, tintable, hole-preserving Lua mesh.

Build dependency: mapbox-earcut==2.0.0, NumPy and Pillow. The local desktop
bundled Python supplies NumPy/Pillow; --deps can point to a local Earcut wheel
installation. Sharp is used only for an independent SVG raster comparison.
The original SVG is preserved unchanged. No game or native engine access.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'freecam/assets/logos/figma-community-1382854850516388445/Helldivers_2_Alt_Logo.svg'
OUTPUT = ROOT / 'freecam/assets/helldiver_crest.lua'
REVIEW = ROOT / 'dist/releases/photo-crest-review'
TOKEN = re.compile(r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?')


def cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def area(points):
    return sum(cross(a, b) for a, b in zip(points, points[1:] + points[:1])) / 2


def midpoint(a, b):
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


def chord_distance(point, start, end):
    dx, dy = end[0] - start[0], end[1] - start[1]
    length = dx * dx + dy * dy
    t = 0 if length == 0 else max(0, min(1, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / length))
    return math.hypot(point[0] - start[0] - t * dx, point[1] - start[1] - t * dy)


def flatten_cubic(a, b, c, d, tolerance, points, depth=0):
    # Convex-hull distance to the chord bounds the curve approximation error.
    if max(chord_distance(b, a, d), chord_distance(c, a, d)) <= tolerance:
        points.append(d)
        return
    assert depth < 20, 'Bezier subdivision did not converge'
    ab, bc, cd = midpoint(a, b), midpoint(b, c), midpoint(c, d)
    abc, bcd = midpoint(ab, bc), midpoint(bc, cd)
    middle = midpoint(abc, bcd)
    flatten_cubic(a, ab, abc, middle, tolerance, points, depth + 1)
    flatten_cubic(middle, bcd, cd, d, tolerance, points, depth + 1)


def cubic_area(points):
    # Exact Green integral for a cubic polynomial, independent of flattening.
    coefficients = []
    for axis in (0, 1):
        a, b, c, d = (p[axis] for p in points)
        coefficients.append([a, 3 * (b - a), 3 * (c - 2 * b + a), d - 3 * c + 3 * b - a])
    x, y = coefficients
    return sum((x[i] * j * y[j] - y[i] * j * x[j]) / (i + j) for i in range(4) for j in range(1, 4)) / 2


def rings(path, tolerance):
    tokens = TOKEN.findall(path)
    assert not TOKEN.sub('', path).strip(' ,\t\r\n'), 'Unsupported SVG path tokens'
    result = []; points = None; exact = 0; current = (0., 0.); index = 0; command = None
    arity = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6}
    while index < len(tokens):
        if tokens[index].isalpha():
            command = tokens[index]; index += 1
            assert command in (*arity, 'Z'), f'Unsupported SVG command {command}'
            if command == 'Z':
                assert points is not None and len(points) >= 3, 'Incomplete SVG contour'
                exact += cross(current, points[0]) / 2
                if points[-1] == points[0]:
                    points.pop()
                result.append((points, exact)); current = points[0]; points = None; exact = 0
                continue
        assert command in arity and index + arity[command] <= len(tokens), 'Unclosed SVG contour'
        values = list(map(float, tokens[index:index + arity[command]])); index += arity[command]
        if command == 'M':
            assert points is None, 'Open SVG contours are unsupported'
            current = (values[0], values[1]); points = [current]; command = 'L'; continue
        assert points is not None, 'SVG contour must begin with M'
        if command == 'C':
            control = [(values[i], values[i + 1]) for i in (0, 2, 4)]
            exact += cubic_area([current] + control)
            flatten_cubic(current, *control, tolerance, points)
            current = control[-1]
        else:
            target = {'L': lambda: (values[0], values[1]), 'H': lambda: (values[0], current[1]), 'V': lambda: (current[0], values[0])}[command]()
            exact += cross(current, target) / 2
            if target != points[-1]:
                points.append(target)
            current = target
    assert points is None, 'SVG contour must be explicitly closed'
    return result


def inside(point, polygon):
    x, y = point; result = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if (a[1] > y) != (b[1] > y) and x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]:
            result = not result
    return result


def contains_triangle(point, triangle):
    a, b, c = (triangle[i:i + 2] for i in (0, 2, 4))
    differences = [cross((q[0] - p[0], q[1] - p[1]), (point[0] - p[0], point[1] - p[1])) for p, q in ((a, b), (b, c), (c, a))]
    return min(differences) >= -1e-8 or max(differences) <= 1e-8


def fmt(value):
    return f'{value:.6f}'.rstrip('0').rstrip('.') or '0'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    parser.add_argument('--review', type=Path, default=REVIEW)
    parser.add_argument('--deps', type=Path, default=ROOT / 'dist/crest-build-deps')
    parser.add_argument('--tolerance', type=float, default=.06, help='Maximum cubic chord error in SVG units; 0.06 becomes 0.24px at4x')
    parser.add_argument('--node', type=Path)
    args = parser.parse_args()
    assert 0 < args.tolerance <= .1
    sys.path.insert(0, str(args.deps.resolve()))
    import numpy as np
    import mapbox_earcut
    from PIL import Image, ImageDraw, ImageFilter

    original = args.source.read_bytes(); source_hash = hashlib.sha256(original).hexdigest()
    root = ET.fromstring(original); left, top, width, height = map(float, root.attrib['viewBox'].split())
    assert left == top == 0 and width == 1375 and height == 550
    paths = root.findall('.//{http://www.w3.org/2000/svg}path')
    assert len(paths) == 15 and not any('transform' in node.attrib for node in root.iter()), 'Source structure changed'
    triangles = []; holes = []; vertices = 0; exact_area = 0.; flat_area = 0.
    for path in paths:
        contours = rings(path.attrib['d'], args.tolerance)
        contours.sort(key=lambda ring: -abs(area(ring[0])))
        outer = contours[0][0]
        assert path.attrib.get('fill-rule', 'nonzero') == 'evenodd' or len(contours) == 1
        assert all(inside(ring[0][0], outer) for ring in contours[1:]), 'A compound ring is not a hole'
        assert not any(inside(ring[0][0], other[0]) for i, ring in enumerate(contours[1:]) for j, other in enumerate(contours[1:]) if i != j), 'Nested hole unsupported'
        holes.extend(ring[0] for ring in contours[1:])
        exact_area += abs(contours[0][1]) - sum(abs(ring[1]) for ring in contours[1:])
        flat_area += abs(area(outer)) - sum(abs(area(ring[0])) for ring in contours[1:])
        points = [point for ring in contours for point in ring[0]]
        vertices += len(points)
        ends = np.cumsum([len(ring[0]) for ring in contours], dtype=np.uint32)
        indices = mapbox_earcut.triangulate_float64(np.asarray(points, dtype=np.float64), ends)
        for i in range(0, len(indices), 3):
            a, b, c = (points[int(index)] for index in indices[i:i + 3])
            if cross((b[0] - a[0], b[1] - a[1]), (c[0] - a[0], c[1] - a[1])) < 0:
                b, c = c, b
            # The source clip rect removes its ~2e-7-unit left overshoot.
            triangle = [round(max(0., min(width if j % 2 == 0 else height, value)), 6) for j, value in enumerate((*a, *b, *c))]
            if abs(area([triangle[j:j + 2] for j in (0, 2, 4)])) > 1e-10:
                triangles.append(triangle)
    assert len(holes) == 3 and len(triangles) <= 650
    mesh_area = sum(abs(area([t[i:i + 2] for i in (0, 2, 4)])) for t in triangles)
    assert abs(mesh_area - flat_area) < .001, 'Triangle mesh does not preserve flattened polygon area'
    assert abs(mesh_area - exact_area) / exact_area < .0002, 'Curve flattening exceeds SVG area tolerance'
    probes = 0
    for hole in holes:
        x0, y0 = min(p[0] for p in hole), min(p[1] for p in hole)
        x1, y1 = max(p[0] for p in hole), max(p[1] for p in hole)
        for y in range(1, 20):
            for x in range(1, 20):
                point = (x0 + (x1 - x0) * x / 20, y0 + (y1 - y0) * y / 20)
                if inside(point, hole):
                    assert not any(contains_triangle(point, t) for t in triangles), 'Mesh fills a transparent eye/nose'
                    probes += 1
    manifest = json.loads((args.source.parent / 'manifest.json').read_text(encoding='utf-8'))
    assert any(e['sha256'] == source_hash for e in manifest['entries']), 'Source hash no longer matches credited acquisition'
    comment = ('-- Deterministic mesh from Helldivers_2_Alt_Logo.svg; transparent eyes/nose.\n'
               f'-- Source SHA256: {source_hash}\n'
               f"-- Credit: {manifest['author']}; {manifest['license']}; {manifest['source_page']}\n"
               f'-- Cubic chord tolerance {args.tolerance:g} SVG units; {len(triangles)} triangles. Top-left origin.\n')
    lua = comment + f'return {{width={fmt(width)},height={fmt(height)},color={{255,255,255}},triangles={{\n'
    lua += ''.join(' {' + ','.join(map(fmt, triangle)) + '},\n' for triangle in triangles) + '}}\n'
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(lua, encoding='utf-8', newline='\n')
    args.review.mkdir(parents=True, exist_ok=True)

    scale = 4; size = (int(width * scale), int(height * scale))
    mask = Image.new('L', size, 0); draw = ImageDraw.Draw(mask)
    for triangle in triangles:
        draw.polygon([(triangle[i] * scale, triangle[i + 1] * scale) for i in (0, 2, 4)], fill=255)
    image = Image.new('RGBA', size, (255, 255, 255, 0)); image.putalpha(mask)
    image.save(args.review / 'helldiver-crest-mesh-400pct.png')
    preview = image.resize((1400, 560), Image.Resampling.LANCZOS)
    preview.save(args.review / 'helldiver-crest-transparent.png')
    dark = Image.new('RGBA', preview.size, (25, 28, 32, 255)); dark.alpha_composite(preview)
    dark.save(args.review / 'helldiver-crest-on-dark.png')

    node = args.node or Path(shutil.which('node') or 'node')
    env = dict(os.environ)
    reference = args.review / 'helldiver-crest-svg-400pct.png'
    script = "require('sharp')(process.argv[1]).resize({width:5500,height:2200}).ensureAlpha().png().toFile(process.argv[2]).catch(e=>{console.error(e);process.exit(1)})"
    subprocess.run([str(node), '-e', script, str(args.source.resolve()), str(reference.resolve())], env=env, check=True)
    svg_alpha = Image.open(reference).getchannel('A')
    ref = np.asarray(svg_alpha); raster = np.asarray(mask)
    solid = np.asarray(svg_alpha.point(lambda p: 255 if p == 255 else 0).filter(ImageFilter.MinFilter(3))) > 0
    empty = np.asarray(svg_alpha.point(lambda p: 255 if p == 0 else 0).filter(ImageFilter.MinFilter(3))) > 0
    missing = int(np.count_nonzero(solid & (raster == 0)))
    extra = int(np.count_nonzero(empty & (raster > 0)))
    assert missing == extra == 0, f'Interior SVG/mesh mismatch: missing={missing},extra={extra}'
    report = {'source_sha256': source_hash, 'source_file': args.source.relative_to(ROOT).as_posix(),
              'credit': {key: manifest[key] for key in ('author', 'author_url', 'license', 'license_url', 'source_page')},
              'width': width, 'height': height, 'origin': 'top-left', 'color': [255, 255, 255],
              'paths': len(paths), 'transparent_holes': len(holes), 'hole_probes': probes,
              'flattened_vertices': vertices, 'triangles': len(triangles), 'maximum_curve_chord_error_svg_units': args.tolerance,
              'maximum_curve_chord_error_pixels_at_400_percent': args.tolerance * 4,
              'exact_svg_area': exact_area, 'flattened_polygon_area': flat_area, 'triangle_mesh_area': mesh_area,
              'relative_area_difference_from_svg': abs(mesh_area - exact_area) / exact_area,
              'svg_raster_interior_missing_pixels': missing, 'svg_raster_interior_extra_pixels': extra,
              'reference_svg_renderer': 'Sharp/libvips, 5500x2200', 'lua_sha256': hashlib.sha256(lua.encode()).hexdigest(),
              'runtime_dependency': 'None; Lua table of triangles only', 'game_process_accessed': False}
    (args.review / 'crest-verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
