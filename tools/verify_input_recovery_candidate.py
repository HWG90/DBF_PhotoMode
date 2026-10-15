"""Verify explicitly opted-in input-recovery development ZIPs; never installs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_packaged_standalone as startup
import verify_release


def sha(body):
    return hashlib.sha256(body).hexdigest()


def verify_packages(paths, standalone=False, source_root=None):
    source_root = (source_root or ROOT).resolve()
    results = []
    for path in paths:
        path = path.resolve()
        loader, entry, payload = startup.payload(path)
        with zipfile.ZipFile(path) as zipped:
            provenance = json.loads(zipped.read('PROVENANCE.json') if loader == 'BSL' else payload['PROVENANCE.json'])
            readme = 'CANDIDATE-README.txt' if loader == 'BSL' else 'dbf_freecam/CANDIDATE-README.txt'
            warning = zipped.read(readme)
            assert all(text in warning for text in (b'INPUT RECOVERY', b'NOT A STABLE RELEASE', b'v1.0.1', b'assets are unchanged')), 'Input recovery/recovery notice missing'
            assert b'candidate_profile=input-recovery' in warning, 'Candidate profile not disclosed'
            guide = 'INPUT-RECOVERY.md' if loader == 'BSL' else 'dbf_freecam/INPUT-RECOVERY.md'
            assert zipped.read(guide) == (source_root/'docs/INPUT-RECOVERY.md').read_bytes(), 'Reviewed input recovery guide missing or changed'
        assert provenance.get('version') == '1.0.1', 'Unexpected candidate package schema'
        assert provenance.get('candidate_only') is True and provenance.get('candidate_profile') == 'input-recovery', 'Not an input recovery development candidate'
        engine = provenance.get('camera_engine')
        assert engine in ('legacy', 'independent'), 'Candidate camera engine missing'
        code = payload['src/actioncam.lua'].decode()
        assert "rawset(_G,'DBF_PHOTO_INPUT_RECOVERY_CANDIDATE',true)" in code, 'Candidate runtime marker missing'
        for feature in ('DBF_PHOTO_EDITOR_INPUT', 'DBF_PHOTO_INPUT_RECOVERY', 'H.dbf_input_recovery'):
            assert feature in code, 'Input recovery API/hook missing: '+feature
        modules = provenance['source_modules_sha256']
        for required in ('controller.lua', 'input_recovery.lua', 'photo_input_capture.lua'):
            assert required in modules, 'Candidate source provenance missing: '+required
        for name, digest in modules.items():
            relative = Path(name)
            assert not relative.is_absolute() and '..' not in relative.parts, 'Invalid source provenance path'
            source = source_root/'freecam'/relative
            assert source.is_file() and sha(source.read_bytes()) == digest, 'Reviewed source hash mismatch: '+name
        if engine == 'independent':
            assert "DBF_PHOTO_CAMERA_ENGINE','independent'" in code and 'local function legacy_bindings_step()' not in code
            for required in ('independent_runtime.lua', 'camera_scene.lua', 'camera_motion.lua', 'camera_ownership.lua', 'camera_lens.lua'):
                assert required in modules, 'Independent camera provenance missing: '+required
            if loader == 'MDL':
                assert code.endswith('\nreturn {stop=runtime.stop}\n'), 'Owned MDL stop contract missing'
                assert 'local function step(dt)\n  local owner=rawget' not in code, 'MDL blocks pending owned-runtime cleanup updates'
        else:
            assert "DBF_PHOTO_CAMERA_ENGINE','independent'" not in code, 'Camera engine provenance disagrees with runtime'
        # This exception is explicit and applies only after candidate identity,
        # recovery disclosure, API markers and reviewed source hashes pass.
        # Default verify_release callers still reject both unreleased APIs.
        result = verify_release.verify_current(path, '1.0.1', standalone=standalone,
                                               input_recovery_candidate=True)
        result.update(camera_engine=engine, candidate_only=True, candidate_profile='input-recovery',
                      reviewed_source_root=str(source_root), reviewed_source_hashes=True)
        results.append(result)
    return {'checked_at_utc':datetime.now(timezone.utc).isoformat(), 'passed':True,
            'candidate_only':True, 'candidate_profile':'input-recovery',
            'game_process_accessed':False, 'deployment':'not installed',
            'publication_performed':False, 'packages':results}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', nargs='+', type=Path)
    parser.add_argument('--standalone', action='store_true', help='Execute only package-owned mocked startup; never attaches to a game')
    parser.add_argument('--source-root', type=Path, default=ROOT, help='Exact reviewed source export used to build the candidate')
    parser.add_argument('--receipt', type=Path, default=ROOT/'dist/review/input-recovery-20261015/PACKAGE-VERIFICATION.json')
    args = parser.parse_args()
    result = verify_packages(args.packages, args.standalone, args.source_root)
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
