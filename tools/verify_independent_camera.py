"""Offline camera-generator contracts; never packages, installs or accesses a game process."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT/'dist/review/independent-camera-20261015'


def load(name,path):
    spec = importlib.util.spec_from_file_location(name,path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(body):
    return hashlib.sha256(body).hexdigest()


def verify():
    photo = load('verify_photo_builder',ROOT/'freecam/build.py')
    independent = load('verify_independent_builder',ROOT/'freecam/independent_build.py')
    read_text,read_bytes = Path.read_text,Path.read_bytes
    def allowed(path):
        assert 'actioncam' not in path.name.lower(), 'Owned generator read a removed third-party camera source'
    def allowed_text(path,*args,**kwargs):
        allowed(path);return read_text(path,*args,**kwargs)
    def allowed_bytes(path,*args,**kwargs):
        allowed(path);return read_bytes(path,*args,**kwargs)
    with patch.object(Path,'read_text',allowed_text),patch.object(Path,'read_bytes',allowed_bytes):
        source = independent.generate(dof_candidate=True,native_candidate=True,
                                      combined_scene_candidate=True,builder=photo)
        ownership = independent.ownership_source(photo)
    for token in ('__STUDIO_FEATURES__','__CAMERA_SCENE__','__CAMERA_MOTION__','__ANIMATION_STATE__'):
        assert token not in source,'Unexpanded owned runtime module: '+token
    assert "DBF_PHOTO_CAMERA_ENGINE','independent'" in source
    assert 'H.dbf_camera_ownership' in source and 'DBF_PHOTO_CAMERA_OWNERSHIP' in source
    for marker in ('local function bindings_step()','local function step(dt)'):
        assert source.count(marker)==1,'MDL lifecycle contract changed: '+marker
    for body in (source,ownership):
        assert 'actioncam' not in body.lower(), 'Third-party camera integration was embedded'
    photo.compile_lua(source.encode(),'Independent-camera-runtime')
    photo.compile_lua(ownership.encode(),'Independent-camera-ownership')
    mdl = source
    marker = 'local function bindings_step()'
    mdl = mdl.replace(marker,marker+"\n  local owner=rawget(_G,'DBF_PHOTO_MODE_OWNER');if owner and owner.stopped then return end",1)
    mdl += "\nreturn {stop=runtime.stop}\n"
    photo.compile_lua(mdl.encode(),'Independent-camera-MDL-stop-contract')
    results = {'independent': {'sha256':sha(source.encode()),'bytes':len(source.encode()),
                              'ownership_sha256':sha(ownership.encode()),
                              'third_party_camera_read':False,'lua_and_mdl_compile':True}}
    return {'checked_at_utc':datetime.now(timezone.utc).isoformat(),'passed':True,
            'candidate_only':True,'game_process_accessed':False,
            'deployment':'not installed','publication_performed':False,'results':results}


def verify_packages(paths,standalone=False):
    """Require candidate identity before reusing immutable asset/startup checks."""
    import sys
    sys.path.insert(0,str(ROOT/'tools'))
    import test_packaged_standalone as startup
    import verify_release
    import zipfile
    results=[]
    for path in paths:
        loader,entry,payload=startup.payload(path.resolve())
        with zipfile.ZipFile(path)as zipped:
            provenance=json.loads(zipped.read('PROVENANCE.json')if loader=='BSL'else payload['PROVENANCE.json'])
        assert provenance.get('camera_engine')=='independent'and provenance.get('candidate_only')is True,'Not an independent review candidate'
        assert 'src/camera_ownership.lua' in payload
        assert not any('actioncam' in name.lower() for name in payload), 'Removed third-party camera payload included'
        code=payload['src/camera_runtime.lua'].decode()
        assert "DBF_PHOTO_CAMERA_ENGINE','independent'"in code and 'actioncam' not in code.lower()
        if loader=='MDL':
            assert code.endswith('\nreturn {stop=runtime.stop}\n'),'Independent MDL teardown bypasses the owned runtime'
            assert 'local function step(dt)\n  local owner=rawget'not in code,'MDL blocks pending owned-runtime cleanup updates'
        for name in ('independent_runtime.lua','camera_scene.lua','camera_motion.lua','camera_ownership.lua','camera_lens.lua'):
            assert len(provenance['source_modules_sha256'].get(name,''))==64,'Owned source provenance missing: '+name
        with zipfile.ZipFile(path)as zipped:
            readme='CANDIDATE-README.txt'if loader=='BSL'else'dbf_freecam/CANDIDATE-README.txt'
            warning=zipped.read(readme)
            assert b'NOT A STABLE RELEASE'in warning and b'v1.0.1'in warning and b'assets are unchanged'in warning,'Candidate recovery notice missing'
            guide='INDEPENDENT-CAMERA.md'if loader=='BSL'else'dbf_freecam/INDEPENDENT-CAMERA.md'
            assert zipped.read(guide),'Independent camera test/recovery guide missing'
        # Asset closure, native DLL, module declarations and package startup
        # remain checked independently from the owned camera generator.
        result=verify_release.verify_current(path.resolve(),provenance['version'],standalone=standalone,
                                             input_recovery_candidate=provenance.get('candidate_profile')=='input-recovery')
        result.update(camera_engine='independent',candidate_only=True)
        results.append(result)
    return results


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packages',nargs='+',type=Path,help='Also verify explicitly named immutable independent loader ZIPs')
    parser.add_argument('--standalone',action='store_true',help='Run package-only mocked startup checks when --packages is supplied')
    parser.add_argument('--receipt',type=Path,default=REVIEW/'GENERATOR-VERIFICATION.json')
    args = parser.parse_args()
    receipt = verify()
    if args.packages:receipt['packages']=verify_packages(args.packages,args.standalone)
    args.receipt.parent.mkdir(parents=True,exist_ok=True)
    args.receipt.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt,indent=2))
