"""Compile credited local logo silhouettes into self-contained, tintable GUI meshes.

This changes no source artwork. Build-only dependencies: Pillow, NumPy,
opencv-python-headless 4.12 and mapbox-earcut 2.0. SVG rasterization uses Sharp.
The game uses only the emitted Lua triangles, without texture/material assets.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'freecam/assets'
MARKER = '\n-- BEGIN CURATED LOGO MESHES\n'
CHOICES = [(7, 139968, 'Helldivers 2 — wide'), (8, 139970, 'Helldivers 2 — compact'),
           (9, 108334, 'Helldivers II crest'), (10, 108191, 'Super Citizen Edition'),
           (11, 139972, 'Omens of Tyranny'), (12, 139966, 'Heart of Democracy'),
           (13, 148760, 'Into the Unjust')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deps', type=Path, action='append', default=[])
    parser.add_argument('--node', required=True, type=Path)
    parser.add_argument('--node-modules', required=True, type=Path)
    parser.add_argument('--review', type=Path, default=ROOT / 'dist/releases/photo-logo-0.9.5-review')
    args = parser.parse_args()
    for folder in args.deps:
        sys.path.insert(0, str(folder.resolve()))
    import cv2
    import mapbox_earcut
    import numpy as np
    from PIL import Image, ImageDraw

    args.review.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ASSETS / 'logos/steamgriddb-5403655/manifest.json').read_text())
    entries = {e['id']: e for e in manifest['entries']}
    assert len(entries) == 8 and manifest['humor_or_meme_branding_excluded']
    source_svg = ASSETS / 'logos/alphaccca/Super_Earth.svg'
    earth_manifest = json.loads((source_svg.parent / 'manifest.json').read_text())
    assert any(e['file'] == source_svg.name and e['sha256'] == hashlib.sha256(source_svg.read_bytes()).hexdigest() for e in earth_manifest['entries'])
    earth_raster = args.review / 'super-earth-source.png'
    script = 'require(process.argv[1])(process.argv[2]).resize({width:1320}).png().toFile(process.argv[3])'
    subprocess.run([str(args.node), '-e', script, str(args.node_modules / 'sharp'), str(source_svg), str(earth_raster)], check=True)
    sources = [(4, 'Super Earth crest', source_svg, earth_raster, [255, 255, 255])]
    for index, asset_id, name in CHOICES:
        entry = entries[asset_id]
        path = ASSETS / 'logos/steamgriddb-5403655' / entry['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
        assert not entry['tags'].get('humor')
        sources.append((index, name, path, path, [255, 233, 0] if asset_id in (139970, 108191) else [255, 255, 255]))
    receipt = []
    output = []
    thumbnails = []
    for index, name, original, raster, color in sources:
        image = Image.open(raster).convert('RGBA')
        # Opaque dark lettering is a cutout in these tintable insignia. The
        # combined luminance/alpha mask also retains their distressed detailing.
        rgba = np.asarray(image, dtype=np.float32)
        mask = ((rgba[:, :, :3].max(axis=2) * rgba[:, :, 3] / 255) >= 128).astype('uint8') * 255
        nonzero = cv2.findNonZero(mask)
        assert nonzero is not None
        x, y, w, h = cv2.boundingRect(nonzero)
        mask = mask[y:y+h, x:x+w]
        scale = min(1., 1536 / max(w, h))
        mask = cv2.resize(mask, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA)
        mask = (mask >= 128).astype('uint8') * 255
        height, width = mask.shape
        contours, hierarchy = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
        hierarchy = hierarchy[0]
        triangles = []
        for contour_index, contour in enumerate(contours):
            if hierarchy[contour_index][3] >= 0 or abs(cv2.contourArea(contour)) < 3:
                continue
            outer = cv2.approxPolyDP(contour, 1., True)[:, 0, :]
            if len(outer) < 3:
                continue
            rings = [outer]
            child = hierarchy[contour_index][2]
            while child >= 0:
                hole = cv2.approxPolyDP(contours[child], 1., True)[:, 0, :]
                if len(hole) >= 3:
                    rings.append(hole)
                child = hierarchy[child][0]
            vertices = np.concatenate(rings).astype(np.float64)
            ends = np.cumsum([len(r) for r in rings], dtype=np.uint32)
            indices = mapbox_earcut.triangulate_float64(vertices, ends)
            for offset in range(0, len(indices), 3):
                points = vertices[indices[offset:offset+3]]
                ab, ac = points[1]-points[0], points[2]-points[0]
                if abs(float(ab[0]*ac[1]-ab[1]*ac[0])) > 0:
                    triangles.append(points.flatten().astype(int).tolist())
        assert 0 < len(triangles) <= 2500
        # Independently rasterize the triangles: their image must preserve the
        # source's cutouts and connected components, not just its bounding box.
        rendered = Image.new('L', (width, height)); draw = ImageDraw.Draw(rendered)
        for triangle in triangles:
            draw.polygon(list(zip(triangle[::2], triangle[1::2])), fill=255)
        predicted = np.asarray(rendered) > 0
        truth = mask > 0
        iou = float(np.logical_and(predicted, truth).sum() / np.logical_or(predicted, truth).sum())
        assert iou > .94, (name, iou)
        preview = Image.new('RGB', (600, 210), '#202427')
        rendered.thumbnail((570, 165), Image.Resampling.LANCZOS)
        layer = Image.new('RGB', rendered.size, tuple(color))
        preview.paste(layer, ((600-rendered.width)//2, (175-rendered.height)//2), rendered)
        ImageDraw.Draw(preview).text((12, 184), name, fill='white')
        thumbnails.append(preview)
        source_hash = hashlib.sha256(original.read_bytes()).hexdigest()
        output.append(f'-- {name}; source SHA256 {source_hash}\n')
        output.append(f'logos[{index}]={{width={width},height={height},color={{{",".join(map(str,color))}}},triangles={{\n')
        output.extend(' {'+','.join(map(str,t))+'},\n' for t in triangles)
        output.append('}}\n')
        receipt.append({'index': index, 'name': name, 'source': str(original.relative_to(ROOT)).replace('\\','/'),
                        'source_sha256': source_hash, 'width': width, 'height': height,
                        'triangles': len(triangles), 'source_mask_iou': iou})
    artifact = ASSETS / 'logo_art.lua'
    original = artifact.read_text().split(MARKER)[0]
    if original.startswith('return '):
        original = 'local logos=' + original[len('return '):]
    assert original.startswith('local logos=')
    artifact.write_text(original.rstrip() + MARKER + ''.join(output) + 'return logos\n', encoding='utf-8')
    sheet = Image.new('RGB', (1200, 210 * ((len(thumbnails)+1)//2)))
    for i, thumbnail in enumerate(thumbnails):
        sheet.paste(thumbnail, (i%2*600, i//2*210))
    sheet.save(args.review / 'compiled-logo-contact-sheet.png')
    report = {'compiled_runtime': 'freecam/assets/logo_art.lua', 'runtime_dependencies': [],
              'source_art_unchanged': True, 'tintable_monochrome_geometry': True, 'entries': receipt}
    (args.review / 'BUILD-RECEIPT.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    (ASSETS / 'logos/runtime-manifest.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
