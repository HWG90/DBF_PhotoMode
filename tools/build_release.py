"""Build all self-contained War Journalist 0.9.5 loader packages; never installs."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PurePosixPath
import struct
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build_preview
import dof_assets
import photo_assets
import photo_light_assets

VERSION='0.9.5'
SNAPSHOTS=ROOT/'freecam/assets/shaders/release-0.9.5'
APPROVED_GPU='f5960f63e1247ac40af4bb37ccbd59ac26c9168aad9eb40936c082c9ddf40194'
BASE_REVIEW_SHA='be8b821b545a8146d8c340aa552a3c6dc02b70c39376d3e8bc9e054391ebc866'
BASE_REVIEW=ROOT/'dist/releases/photo-scene-depth-review/War-Journalist-Scene-Depth-Candidate-Assets.zip'
ACTIVE_MODULES=('animation_state.lua','chat_context.lua','look.lua','simulation.lua','simulation_backend.lua',
    'photo_options.lua','lens.lua','composition.lua','postfx.lua','photo_runtime.lua','hud.lua','render_profile.lua',
    'camera_profile.lua','photo_menu.lua','control_legend.lua','screenshot.lua','screenshot_backend.lua',
    'depth_resource.lua','focus_sampler.lua','photo_lights.lua','subject_backend.lua','subject.lua','director.lua',
    'saved_camera.lua','controller.lua','input_release.lua','input_release_backend.lua','hover_pause.lua',
    'hover_pause_backend.lua','scene_dof_overlay.lua','shader_template_guard.lua','standalone.lua',
    'bsl_startup.lua','mdl.lua','lll.lua','assets/logo_art.lua','assets/helldiver_crest.lua')

def sha(body):return hashlib.sha256(body).hexdigest()
def json_bytes(value):return(json.dumps(value,indent=2)+'\n').encode()
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def row_identity(rows):
    return sha(json_bytes([{'name':f'{name:016x}','type':f'{kind:016x}','cpu':sha(cpu),'gpu':sha(gpu)}for name,kind,cpu,gpu in sorted(rows)]))

def promote_snapshots():
    """Explicit, reversible promotion of approved bytes; compilation is unnecessary."""
    core,shared,_=build_preview.resources(None)
    assert sha(BASE_REVIEW.read_bytes())==BASE_REVIEW_SHA,'Reference base ZIP changed'
    with zipfile.ZipFile(BASE_REVIEW)as z:
        for archive,rows in [('ee6b1ba7e22d71ed',core),('9ba626afa44a3aa3',shared)]:
            path='Assets/'+archive+'.patch_0'
            assert sorted(photo_assets.read_archive(z.read(path),z.read(path+'.gpu_resources')))==sorted(rows),'Base source assets differ from retained preview'
    manifest={'version':VERSION,'base_core_rows_sha256':row_identity(core),'base_shared_rows_sha256':row_identity(shared),
              'base_reference_zip_sha256':BASE_REVIEW_SHA,'pairs':[]}
    for label,folder in [('resolved',ROOT/'dist/releases/photo-resolved-compositor-v2-review'),('legacy',ROOT/'dist/releases/photo-combined-scene-dof-hdr1-guarded')]:
        info=json.loads((folder/'BUILD-RECEIPT.json').read_text())
        pair={'label':label,'shader':info['shader'],'material':info['material'],'files':{},
              'color_resource_name':info['color_resource_name'],'native_vertex_byte_identity':info['native_vertex_byte_identity'],
              'native_parameter_and_binding_abi_preserved':info['native_parameter_and_binding_abi_preserved']}
        for source,suffix,key in [('scene_dof_combined.gpu','.gpu','shader_gpu_sha256'),('scene_dof_combined.material.bin','.material.bin','material_sha256'),('scene_dof_combined.hlsl','.hlsl','hlsl_sha256')]:
            body=(folder/source).read_bytes();assert sha(body)==info[key],'Snapshot hash differs: '+source
            name=label+suffix;destination=SNAPSHOTS/name;destination.parent.mkdir(parents=True,exist_ok=True)
            if destination.exists():assert destination.read_bytes()==body,'Preserve a different existing snapshot'
            else:destination.write_bytes(body)
            pair['files'][name]=sha(body)
        if label=='resolved':assert pair['files']['resolved.gpu']==APPROVED_GPU
        manifest['pairs'].append(pair)
    path=SNAPSHOTS/'manifest.json'
    if path.exists():assert json.loads(path.read_text())==manifest,'Snapshot manifest changed'
    else:path.write_bytes(json_bytes(manifest))
    return manifest

def resources(output=None):
    """Return source-owned frozen bytes; no dist or installed-game inputs."""
    manifest=json.loads((SNAPSHOTS/'manifest.json').read_text())
    core,shared,_=build_preview.resources(output)
    assert row_identity(core)==manifest['base_core_rows_sha256']and row_identity(shared)==manifest['base_shared_rows_sha256'],'Base assets differ from promoted closure'
    group=next(row for row in core if row[1]==photo_assets.GROUP);ids=list(photo_assets.registry_ids(group[2]));assert len(ids)==317
    pairs=manifest['pairs'];assert len(pairs)==2
    overlay=(ROOT/'freecam/scene_dof_overlay.lua').read_text()
    approved=json.loads((ROOT/'docs/RESOLVED-COMPOSITOR-VERIFICATION.json').read_text())
    for pair in pairs:
        bodies={name:(SNAPSHOTS/name).read_bytes()for name in pair['files']}
        assert all(sha(bodies[name])==digest for name,digest in pair['files'].items()),'Frozen shader bytes changed'
        label=pair['label'];gpu,material=bodies[label+'.gpu'],bodies[label+'.material.bin'];sid=photo_assets.hash64(pair['shader'])
        assert sid not in ids and len(material)==144 and struct.unpack_from('<I',material,128)[0]==sid>>32
        assert pair['native_vertex_byte_identity']and pair['native_parameter_and_binding_abi_preserved']
        if label=='resolved':
            assert sha(gpu)==APPROVED_GPU==approved['shader_gpu_sha256']and approved['user_accepted_colors']
            assert "M.shader='"+pair['shader']+"'"in overlay and "M.material='"+pair['material']+"'"in overlay and "M.color_target='output_target'"in overlay
            assert (ROOT/'freecam/assets/shaders/scene_dof_resolved_v2.hlsl').read_bytes().replace(b'\r\n',b'\n')==bodies[label+'.hlsl'].replace(b'\r\n',b'\n'),'Current approved HLSL differs from frozen source'
        ids.append(sid);core.append((sid,photo_assets.SHADER,struct.pack('<I',4),gpu));shared.append((photo_assets.hash64(pair['material']),photo_assets.MATERIAL,material,b''))
    registry=bytearray(group[2][:24]);struct.pack_into('<I',registry,16,len(ids));registry+=struct.pack('<%dQ'%len(ids),*ids)
    core=[(row[0],row[1],bytes(registry),row[3])if row[1]==photo_assets.GROUP else row for row in core]
    shared=photo_light_assets.merge_resources(shared)
    assert len(core)==45 and len(shared)==45 and len(ids)==319
    for rows in (core,shared):
        cpu,gpu=photo_assets.archive_rows(rows);assert sorted(photo_assets.read_archive(cpu,gpu))==sorted(rows)
    cpu,gpu=photo_assets.archive_rows(shared)
    audit={'version':VERSION,'shader_libraries_core':44,'materials_shared':44,'registry_resources_core':1,'registry_ids':319,'decorative_pairs':40,
           'base_core_rows_sha256':manifest['base_core_rows_sha256'],'base_shared_rows_sha256':manifest['base_shared_rows_sha256'],
           'resolved_gpu_sha256':APPROVED_GPU,'resolved_hdr_colors_user_accepted':True,'resolved_verification':approved,
           'legacy_combined_retained':True,'native_numeric_dof_enabled':True,'lighting_status':photo_light_assets.TESTING_STATUS,
           'photo_light':photo_light_assets.validate_bundled_archive(cpu,gpu),'frozen_shader_manifest_sha256':sha((SNAPSHOTS/'manifest.json').read_bytes()),
           'installation_performed':False,'release_runtime_live_verified':False}
    return core,shared,audit

def checksums(files):return ''.join(sha(body)+'  '+name+'\n'for name,body in sorted(files.items())if name!='FILES-SHA256.txt').encode()
def zip_bytes(files):
    files=dict(files);files['FILES-SHA256.txt']=checksums(files);buffer=io.BytesIO()
    with zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED)as z:
        for name,body in sorted(files.items()):
            p=PurePosixPath(name);assert not p.is_absolute()and'..'not in p.parts and'\\'not in name;z.writestr(name,body)
    with zipfile.ZipFile(io.BytesIO(buffer.getvalue()))as z:assert z.testzip()is None and len(z.namelist())==len(files)and all(z.read(name)==body for name,body in files.items())
    return buffer.getvalue()

def asset_files(core,shared,audit,prefix):
    files={}
    for name,rows in [('ee6b1ba7e22d71ed',core),('9ba626afa44a3aa3',shared)]:
        cpu,gpu=photo_assets.archive_rows(rows)
        for suffix,body in [('',cpu),('.gpu_resources',gpu),('.stream',b'')]:files[prefix+name+'.patch_0'+suffix]=body
    return files

def public_docs(files):
    for target,path in [('README.md',ROOT/'README.md'),('KNOWN-ISSUES.md',ROOT/'docs/KNOWN-ISSUES.md'),('RELEASE-NOTES.md',ROOT/'docs'/('RELEASE-'+VERSION+'.md'))]:
        if path.is_file():files[target]=path.read_bytes()
    files['PHOTO-LIGHT-ASSET.md']=(ROOT/'docs/PHOTO-LIGHT-ASSET.md').read_bytes()
    return files

def build(output):
    output=output.resolve();output.mkdir(parents=True,exist_ok=True)
    photo=load('release_photo_build',ROOT/'freecam/build.py');foundation=(ROOT/'freecam/vendor/actioncam-2.3.1.lua').read_bytes()
    vendor=json.loads((ROOT/'freecam/vendor/PROVENANCE.json').read_text());assert sha(foundation)==vendor['actioncam_source_sha256']
    generated=photo.patch(foundation.decode(),dof_candidate=True,native_candidate=True,combined_scene_candidate=True).encode()
    photo.compile_lua(generated,'WarJournalist-'+VERSION)
    assert b'e07f49224f0a5759'in generated and b'PhotoHoverGuardInstall'not in generated and b'__INPUT_RELEASE__'not in generated
    (output/'ActionCam-Freecam.lua').write_bytes(generated)
    core,shared,audit=resources(output)
    provenance={'version':VERSION,'runtime_sha256':sha(generated),'source_modules_sha256':{name:sha((ROOT/'freecam'/name).read_bytes())for name in ACTIVE_MODULES},
                'asset_audit':audit,'native_capture_library':photo.capture_library_name(),'hoverpack_native_hook_withdrawn':True,'deployment':'not installed','publication_performed':False}
    (output/'PROVENANCE.json').write_bytes(json_bytes(provenance))
    original_payload=photo.payload_files
    def payload(folder):
        files=original_payload(folder)
        for p in sorted((ROOT/'freecam/assets/logos').rglob('*')):
            if p.is_file():files['assets/logos/'+p.relative_to(ROOT/'freecam/assets/logos').as_posix()]=p.read_bytes()
        files=public_docs(files)
        assert not any('PhotoHoverGuard'in name or name=='hover-library.txt'for name in files)
        return files
    photo.payload_files=payload
    previous_resources=dof_assets.resources;dof_assets.resources=resources
    try:
        bsl=photo.package_bsl(output,version=VERSION,dof_candidate=True)
        mdl=load('release_mdl',ROOT/'tools/build_mdl.py').package(output,version=VERSION,payload_factory=payload)
    finally:dof_assets.resources=previous_resources
    assets=asset_files(core,shared,audit,'Assets/')
    assets['manifest.json']=json_bytes({'Version':1,'Guid':'3e25431a-27e8-4b7a-b355-3956c1caa8d8','Name':'War Journalist '+VERSION+' Assets',
        'Description':'Complete decorative, focus/compositor and Photo light assets. Lighting: Not tested fully.',
        'Options':[{'Name':'Complete Photo Mode assets','Include':['Assets']}]})
    assets['ASSET-MANIFEST.json']=json_bytes(audit);assets['INSTALL.txt']=b'Import this complete asset ZIP into HD2Arsenal, enable and deploy, then restart normally. Use exactly one War Journalist runtime loader. All assets are included; no separate mod asset download is required. Lighting: Not tested fully.\n'
    asset_name='War-Journalist-'+VERSION+'-Assets.zip';asset_body=zip_bytes(assets);(output/asset_name).write_bytes(asset_body)
    # MDL retains its raw GameData route and includes an Arsenal-importable ZIP.
    with zipfile.ZipFile(mdl)as z:mdl_files={name:z.read(name)for name in z.namelist()if name!='FILES-SHA256.txt'}
    mdl_files['Arsenal/'+asset_name]=asset_body;mdl.write_bytes(zip_bytes(mdl_files))
    lll_files=payload(output);lll_files['main.lua']=(ROOT/'freecam/lll.lua').read_bytes();lll_files['config/defaults.cfg']=b'{}\n'
    modules=sorted(name for name in lll_files if name.startswith('src/')and name.endswith('.lua'))
    lll_files['manifest.json']=json_bytes({'id':'dbf_freecam','name':'War Journalist','version':VERSION,'author':'Goose',
        'lll':{'entry':'main.lua','defaults':'config/defaults.cfg','modules':modules,'restart_only':True,'retain_until_exit':True}})
    lll_files['ASSET-MANIFEST.json']=json_bytes(audit)
    lll_files['INSTALL.txt']=(ROOT/'freecam/README.md').read_bytes()+b'\nLLL: copy dbf_freecam into the LLL Mods directory. Import the included Arsenal/ asset ZIP, enable and deploy the assets, and restart normally. Choose one Photo Mode runtime loader. All required assets are inside this download.\n'
    for name,body in lll_files.items():
        if name.endswith('.lua'):photo.compile_lua(body,'WarJournalist-LLL-'+name)
    files={'dbf_freecam/'+name:body for name,body in lll_files.items()};files.update(asset_files(core,shared,audit,'GameData/'))
    files['Arsenal/'+asset_name]=asset_body;files['INSTALL.txt']=lll_files['INSTALL.txt'];lll=output/('War-Journalist-'+VERSION+'-LLL.zip');lll.write_bytes(zip_bytes(files))
    paths=[bsl,mdl,lll]
    for path in (mdl,lll):
        with zipfile.ZipFile(path)as z:
            assert z.read('Arsenal/'+asset_name)==asset_body
            assert z.read('GameData/9ba626afa44a3aa3.patch_0')==asset_files(core,shared,audit,'GameData/')['GameData/9ba626afa44a3aa3.patch_0']
    # Refresh the MDL receipt after adding the nested asset installer.
    mdl_receipt=json.loads((output/'MDL-BUILD-RECEIPT.json').read_text());mdl_receipt['sha256']=sha(mdl.read_bytes());mdl_receipt['bundled_arsenal_asset_zip']=asset_name;(output/'MDL-BUILD-RECEIPT.json').write_bytes(json_bytes(mdl_receipt))
    receipt={'version':VERSION,'checked_at_utc':datetime.now(timezone.utc).isoformat(),'assets':audit,
             'artifacts':{p.name:{'sha256':sha(p.read_bytes()),'bytes':p.stat().st_size}for p in paths},
             'nested_assets':{'name':asset_name,'sha256':sha(asset_body),'bytes':len(asset_body),'distribution':'Embedded inside MDL/LLL; standalone file is local helper only'},'all_assets_bundled_per_loader':True,
             'source_snapshots_only':True,'game_process_accessed':False,'deployment':'not installed','publication_performed':False}
    (output/'RELEASE-BUILD-RECEIPT.json').write_bytes(json_bytes(receipt));(output/'SHA256SUMS.txt').write_text(''.join(sha(p.read_bytes())+'  '+p.name+'\n'for p in paths))
    print(json.dumps({'output':str(output),**receipt},indent=2));return paths

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,default=ROOT/'dist/releases/photo-0.9.5')
    parser.add_argument('--promote-assets',action='store_true',help='Promote the explicitly approved retained compositor snapshots once')
    args=parser.parse_args()
    if args.promote_assets:promote_snapshots()
    build(args.output)
