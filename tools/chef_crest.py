"""Bake a bounded rectangle fallback from the credited crest's triangle mesh.

Performed at build time. The runtime never triangulates/rasterizes a logo.
The 64-row fallback preserves holes; native triangle drawing keeps full detail.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime


def fallback(source: Path) -> str:
    art = LuaRuntime().execute(source.read_text(encoding='utf-8'))
    width, height = art['width'], art['height']
    triangles = [[art['triangles'][i][j] for j in range(1, 7)] for i in range(1, len(art['triangles']) + 1)]
    rects = []
    rows = 64
    for row in range(rows):
        y = (row + .5) * height / rows
        spans = []
        for triangle in triangles:
            vertices = list(zip(triangle[::2], triangle[1::2]))
            crosses = []
            for (xa, ya), (xb, yb) in zip(vertices, vertices[1:] + vertices[:1]):
                if min(ya, yb) <= y < max(ya, yb):
                    crosses.append(xa + (xb - xa) * (y - ya) / (yb - ya))
            if len(crosses) == 2:
                spans.append((min(crosses), max(crosses)))
        merged = []
        for left, right in sorted(spans):
            if merged and left <= merged[-1][1] + .001:
                merged[-1][1] = max(merged[-1][1], right)
            else:
                merged.append([left, right])
        for left, right in merged:
            rects.append((left, row * height / rows, right - left, height / rows))
    assert 0 < len(rects) <= 256, 'Crest fallback exceeds its draw budget'
    encoded = ',\n'.join('{' + ','.join(f'{n:.6f}' for n in rect) + '}' for rect in rects)
    return ('-- Derived from assets/helldiver_crest.lua; gehryguest, CC BY 4.0.\n'
            '-- Build-time 64-row union of the original mesh.\n'
            f'return {{width={width},height={height},color={{255,255,255}},rects={{\n{encoded}\n}}}}\n')


def logos(source: Path) -> str:
    """Bound each curated logo to 512 immediate draws, including lettermarks."""
    collection = LuaRuntime().execute(source.read_text(encoding='utf-8'))
    encoded = []
    for index in range(4, 14):
        art = collection[index]
        triangles = [[row[j] for j in range(1, 7)] for row in (art['triangles'] or {}).values()]
        boxes = [[row[j] for j in range(1, 5)] for row in (art['rects'] or {}).values()]
        rows = 64
        while True:
            rectangles = []
            for row in range(rows):
                y = (row + .5) * art['height'] / rows
                spans = [(x, x + w) for x, top, w, h in boxes if top <= y < top + h]
                for triangle in triangles:
                    vertices = list(zip(triangle[::2], triangle[1::2]))
                    crosses = []
                    for (xa, ya), (xb, yb) in zip(vertices, vertices[1:] + vertices[:1]):
                        if min(ya, yb) <= y < max(ya, yb):
                            crosses.append(xa + (xb - xa) * (y - ya) / (yb - ya))
                    if len(crosses) == 2:
                        spans.append((min(crosses), max(crosses)))
                merged = []
                for left, right in sorted(spans):
                    if merged and left <= merged[-1][1] + .001:
                        merged[-1][1] = max(merged[-1][1], right)
                    else:
                        merged.append([left, right])
                rectangles += [(left, row * art['height'] / rows, right - left, art['height'] / rows) for left, right in merged]
            if len(rectangles) <= 512:
                break
            rows //= 2
            assert rows >= 8, 'Logo exceeds bounded draw budget'
        assert rectangles, 'Logo lost its geometry'
        data = ','.join('{' + ','.join(f'{v:.6f}' for v in rect) + '}' for rect in rectangles)
        color = ','.join(str(art['color'][i]) for i in range(1, 4))
        encoded.append(f'[{index}]=' + '{width=' + str(art['width']) + ',height=' + str(art['height']) +
                       ',color={' + color + '},rects={' + data + '}}')
    return '-- Bounded row-span derivatives of assets/logo_art.lua; source credits retained in package.\nreturn {' + ',\n'.join(encoded) + '}\n'
