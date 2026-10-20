"""Build a complete native lens and controls legend test; no deployment."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, re, struct, sys, zipfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/releases/photo-autofocus-left-dock-crest-review-r2'
COMBINED=ROOT/'dist/releases/photo-combined-scene-dof-hdr1-guarded'
DEV_VERSION='0.9-dev.20261013.3'
sys.path.insert(0,str(ROOT/'tools'))
import photo_assets, lua_archive
sha=lambda b:hashlib.sha256(b).hexdigest()
def write(name,body):
 p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
def sums(files):return ''.join(sha(body)+'  '+name+'\n' for name,body in sorted(files.items())).encode()
def package(name,files):
 files['FILES-SHA256.txt']=sums(files)
 with zipfile.ZipFile(OUT/name,'w',zipfile.ZIP_DEFLATED)as z:
  for key,body in sorted(files.items()):z.writestr(key,body)
 with zipfile.ZipFile(OUT/name)as z:assert z.testzip()is None and len(z.namelist())==len(files) and {key:z.read(key)for key in z.namelist()}==files
def main(recovery=False):
 assert not OUT.exists(),'Preserve previous candidate'
 color_verified=False
 checks=json.loads((ROOT/'dist/validation/hover-data-all-fixtures.json').read_text());assert checks['passed']
 spec=importlib.util.spec_from_file_location('photo_build',ROOT/'freecam/build.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
 foundation=(ROOT/'freecam/vendor/actioncam-2.3.1.lua').read_bytes();vendor=json.loads((ROOT/'freecam/vendor/PROVENANCE.json').read_text());assert sha(foundation)==vendor['actioncam_source_sha256']
 generated=build.patch(foundation.decode(),dof_candidate=True,scene_candidate=False,native_candidate=True,combined_scene_candidate=not recovery).encode();build.compile_lua(generated,'native-legend-runtime')
 asset=ROOT/'dist/releases/photo-scene-depth-review/War-Journalist-Scene-Depth-Candidate-Assets.zip';asset_body=asset.read_bytes();assert sha(asset_body)=='be8b821b545a8146d8c340aa552a3c6dc02b70c39376d3e8bc9e054391ebc866'
 with zipfile.ZipFile(asset)as z:assert z.testzip()is None;assets={n:z.read(n)for n in z.namelist()}
 core=photo_assets.read_archive(assets['Assets/ee6b1ba7e22d71ed.patch_0'],assets['Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources'])
 shared=photo_assets.read_archive(assets['Assets/9ba626afa44a3aa3.patch_0'],assets['Assets/9ba626afa44a3aa3.patch_0.gpu_resources'])
 assert len(core)==43 and len(shared)==42 and len(photo_assets.registry_ids(next(r[2]for r in core if r[1]==photo_assets.GROUP)))==317
 if not recovery:
  combined=COMBINED
  cb=json.loads((combined/'BUILD-RECEIPT.json').read_text());cgpu=(combined/'scene_dof_combined.gpu').read_bytes();cmat=(combined/'scene_dof_combined.material.bin').read_bytes()
  assert sha(cgpu)==cb['shader_gpu_sha256'] and sha(cmat)==cb['material_sha256']
  verification=json.loads((ROOT/'docs/RESOLVED-COMPOSITOR-VERIFICATION.json').read_text())
  color_verified=verification['user_accepted_colors']and verification['shader_gpu_sha256']==sha(cgpu)
  assert cb['color_resource_name'] in ('hdr1','output_target') and cb['reverse_splice_roundtrip'] and cb['native_vertex_byte_identity']
  target=re.search(r"^M.color_target='([^']+)'$",(ROOT/'freecam/scene_dof_overlay.lua').read_text(),re.M)
  assert target and target.group(1)==cb['color_resource_name']
  hlsl=ROOT/cb.get('hlsl_source_path','freecam/assets/shaders/scene_dof_combined_candidate.hlsl')
  assert hlsl.resolve().is_relative_to(ROOT) and sha(hlsl.read_bytes())==cb['hlsl_sha256']
  shader=cb.get('shader','mods/dbf_photo/shaders/scene_dof_combined_v1');material=cb.get('material','mods/dbf_photo/materials/scene_dof_combined_v1')
  overlay=(ROOT/'freecam/scene_dof_overlay.lua').read_text();assert f"M.shader='{shader}'"in overlay and f"M.material='{material}'"in overlay
  pairs=[(shader,material,cgpu,cmat)]
  if shader!='mods/dbf_photo/shaders/scene_dof_combined_v1':
   old=ROOT/'dist/releases/photo-combined-scene-dof-hdr1-guarded'
   legacy=json.loads((old/'BUILD-RECEIPT.json').read_text());lg=(old/'scene_dof_combined.gpu').read_bytes();lm=(old/'scene_dof_combined.material.bin').read_bytes()
   assert sha(lg)==legacy['shader_gpu_sha256'] and sha(lm)==legacy['material_sha256']
   pairs.insert(0,('mods/dbf_photo/shaders/scene_dof_combined_v1','mods/dbf_photo/materials/scene_dof_combined_v1',lg,lm))
  group=next(row for row in core if row[1]==photo_assets.GROUP);ids=list(photo_assets.registry_ids(group[2]))
  for shader_name,material_name,_,_ in pairs:
   sid=photo_assets.hash64(shader_name);assert sid not in ids;ids.append(sid)
  registry=bytearray(group[2][:24]);struct.pack_into('<I',registry,16,len(ids));registry+=struct.pack('<'+str(len(ids))+'Q',*ids)
  core=[(row[0],row[1],bytes(registry),row[3])if row[1]==photo_assets.GROUP else row for row in core]+[(photo_assets.hash64(s),photo_assets.SHADER,struct.pack('<I',4),g)for s,m,g,b in pairs]
  shared=shared+[(photo_assets.hash64(m),photo_assets.MATERIAL,b,b'')for s,m,g,b in pairs]
  assert len(core)==43+len(pairs) and len(shared)==42+len(pairs)
  for base,rows in [('ee6b1ba7e22d71ed',core),('9ba626afa44a3aa3',shared)]:
   cpu,gpu=photo_assets.archive_rows(rows);assert sorted(photo_assets.read_archive(cpu,gpu))==sorted(rows)
   assets['Assets/'+base+'.patch_0']=cpu;assets['Assets/'+base+'.patch_0.gpu_resources']=gpu
  for name,body in [('manifest.json',assets['manifest.json']),('ASSET-RECEIPT.json',(json.dumps({'candidate':True,'shader_libraries':len(shared),'materials':len(shared),'registry_ids':len(ids),'color_source':cb['color_resource_name'],'color_live_verified':color_verified,'color_verification_scope':verification['scope']if color_verified else None,'combined_gpu_sha256':sha(cgpu),'legacy_combined_retained':len(pairs)>1},indent=2)+'\n').encode())]:assets[name]=body
  assets['FILES-SHA256.txt']=sums({n:b for n,b in assets.items()if n!='FILES-SHA256.txt'})
  import io
  buffer=io.BytesIO()
  with zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED)as z:
   for n,b in sorted(assets.items()):z.writestr(n,b)
  asset_body=buffer.getvalue()
 else:
  # Preserve the known standard-size shader library and every base ZIP byte.
  assert asset_body==asset.read_bytes() and sha(asset_body)=='be8b821b545a8146d8c340aa552a3c6dc02b70c39376d3e8bc9e054391ebc866'
  assert len(core)==43 and len(shared)==42
  assert len(photo_assets.registry_ids(next(r[2]for r in core if r[1]==photo_assets.GROUP)))==317
 shader_count,registry_count=(42,317)if recovery else(len(shared),len(ids))
 color_source='hdr0_div4_fullres'if recovery else cb['color_resource_name']

 provenance={'candidate':True,'native_numeric_candidate':True,'native_source_setter_rva':'0x2DD5E0','native_source_trial_visually_verified':True,'integrated_runtime_live_verified':False,'legend_live_verified':False,'fixture_groups_passed':len(checks['results']),'runtime_sha256':sha(generated),'modules_sha256':{p.name:sha(p.read_bytes())for p in sorted((ROOT/'freecam').glob('*.lua'))if not p.name.endswith('_tests.lua')},'asset_zip_sha256':sha(asset_body),'scene_visual_verified':False,'combined_scene_dof_candidate':not recovery,'color_source':color_source,'color_binding_live_verified':False,'shader_libraries':shader_count,'materials':shader_count,'registry_ids':registry_count,'click_and_center_autofocus_previous_candidate_user_verified':True,'crest_previous_candidate_visually_verified':True}
 if not recovery:
  provenance.update(native_profile_instances_supported=True,native_instance_fix_user_verified=True,animation_graph_guard_sites=7,animation_graph_guard_user_test_no_crash=True,hoverpack_zero_step_fixed=False)
  provenance.update(hoverpack_native_hook_withdrawn=True,input_release_on_entry_exit=True,hoverpack_data_only_candidate=True,hoverpack_field='entity_definition+0x9C',hoverpack_requires_neutral_input=True,hoverpack_controller_support=False)
  provenance.update(menu_layout_reset_on_startup=False,persistent_main_menu_layout=True,drawer_layout_reset_on_startup=True,compact_photo_ui=True,movable_photo_menu=True,shift_drag_scrub_sensitivity=.1,self_contained_chat_opening_guard=True,links_addon_required=False,ship_hud_margin_1080=180,persistent_double_click_focus=True,owned_photo_lights=True,resolved_color_candidate={'shader':shader,'color_source':color_source,'white_carrier':'clip_box.w','native_transfer_math_verified':True,'live_rendered_colors_verified':color_verified,'live_verification_scope':verification['scope']if color_verified else None,'hdr_gui_ceiling':True},legacy_combined_retained=len(pairs)>1)
 if recovery:
  provenance.update(recovery=True,experimental_combined_compositor_removed=True,standard_size_shader_preview_restored=True,scene_effects_disabled=True,base_asset_zip_unmodified=True,recovery_runtime_live_verified=False,
   recovery_notice='Experimental combined compositor removed. Known standard-size Shader preview restored. Native focus/autofocus, screenshots, legend, crest and warmup retained. Scene effects disabled pending a corrected compositor.')
 write('ActionCam-Freecam.lua',generated);write('PROVENANCE.json',(json.dumps(provenance,indent=2)+'\n').encode())
 runtime=build.payload_files(OUT)
 logos=ROOT/'freecam/assets/logos'
 for p in logos.rglob('*'):
  if p.is_file()and(p.suffix.lower()in('.png','.svg','.json')or p.name=='README.md'):runtime['assets/logos/'+p.relative_to(logos).as_posix()]=p.read_bytes()
 template=ROOT/'dist/releases/photo-0.7-lll-local/Runtime/dbf_freecam'
 runtime['main.lua']=(ROOT/'freecam/lll.lua').read_bytes();runtime['config/defaults.cfg']=b'{}\n'
 version='0.7-native-recovery-test'if recovery else DEV_VERSION
 manifest=json.loads((template/'manifest.json').read_text());manifest['version']=version;runtime['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
 install=b'''WAR JOURNALIST - NATIVE FOCUS/APERTURE AND CONTROLS LEGEND TEST
LLL: install dbf_freecam in the LLL Mods directory. Deploy the included asset ZIP
through Arsenal if the 0.7 shader/scene assets are not already installed. Restart
normally once. Preserve saved settings. BSL: import the complete BSL ZIP, enable
and deploy; use one Photo runtime loader at a time.
Camera: select Native camera, enable DoF, then adjust focus and aperture. Focus
steps are 0.01 m, or 0.001 m with Shift. Typed values commit when leaving a box.
Legend: left-screen-edge dock, three columns by default. Its side arrow opens
or collapses it and can be dragged vertically. Drag the title to undock, snap
to the left screen edge to dock, or use DOCK. Resize with the mirrored main-window grip. Controls follow menu/camera
focus. Composition offers Two/Three columns, docking and layout settings.
Hide photo controls also hides the legend. W/S selects rows; A/D changes values.
This development build uses processed full-size PQ scene color with the native
GUI transfer and a vector white carrier. No scene-specific exposure/saturation
compensation is applied. The HDR compositor colors passed ON/OFF game captures
and user acceptance. Blurred HDR energy above GUI white
remains limited by the game GUI carrier. Native stays the quality baseline.
Scene effects and Shader DoF remain available together. The prior combined
shader/material remain in the asset package. Install the bundled assets even
if an earlier Photo Mode build was installed, then restart normally once.
Compact photo UI: Camera actions, Lens, Color, Effects, Lighting, Composition.
Drag the title bar to move the menu and footer together. The default position
clears the ship HUD. Menu position and size are retained through restarts.
Double-click a scene subject in menu focus to focus repeatedly; TAB shows the
cursor. Manual typing overrides autofocus. No Activate button is required.
Lighting: add up to three owned Point/Spot lights; position, color, intensity,
range, cone, follow camera, and remove selected/all. Exit clears owned lights.
Actual rendered lighting still needs an in-game check. Lens presets use the
existing FOV setting; tilt shortcuts and gameplay focal-length readout included.
The drawer resets once at startup; the main menu keeps its saved position and
size. Camera/effect values and bindings stay saved.
Hold Shift while dragging a slider for one-tenth pointer sensitivity. Keys that
open Photo controls are ignored while the game chat text box is active; blocked
held keys require release before reopening. This reader is bundled: Link's Link
to Memory was used for research and is not required to use Photo Mode.
Auto-focus waits for two stable seconds after display-buffer changes before
resuming depth readback. Click focus, center autofocus and the replacement crest
were verified in the previous runtime. Original transparent SteamGridDB logos are included as asset files,
with source/uploader metadata; this package does not add them to the logo picker.
Native focus/aperture passed a mission test using an instanced camera profile.
The source now validates exact instance identity instead of excluding all
nonzero instances. All seven animation-state reads check live Unit and graph
presence first; the guarded live ragdoll/respawn test reported no crash.
The native hoverpack hook was withdrawn after a live crash. No native hover
hook or MinHook library is included. The data-only hover pause candidate disables
automatic thrust per owned pack, verifies neutral input, then permits zero time.
It restores the original field after time resumes. Connected or unidentified
controllers refuse this hover pause. Full crash-reproduction acceptance is pending.
Held controls are released before pause/input capture and again after exit;
entry waits for a resumed engine update and the input-release readback.
Mission light availability is still under development.
The temporary
live verifier from the crashed session is excluded. No public release changed.
'''
 if recovery:
  install=b'''WAR JOURNALIST - NATIVE AND SHADER RECOVERY TEST
LLL: install dbf_freecam in the LLL Mods directory. Deploy the included asset ZIP
through Arsenal to restore the matching standard-size shader assets, then restart
normally once. Preserve saved settings. BSL: import the complete BSL ZIP, enable
and deploy; use one Photo runtime loader at a time.
The experimental combined compositor is removed. The previously proven,
standard-size Shader preview is restored with its original assets. It uses the
native quarter-resolution display blur buffer and preserves focused scene pixels.
Scene color/depth effects are disabled in this recovery pending a corrected
compositor. This package does not claim the experimental full-resolution shader
or compositor is fixed.
Native focus/aperture, click focus, center autofocus, screenshots, left-edge dock,
movable dock tab, contextual controls legend, replacement crest and scene warmup
notice are retained. Focus steps are 0.01 m, or 0.001 m with Shift. Typed values
commit when leaving a box. W/S selects rows; A/D changes values.
Select Native camera and enable DoF to test native focus and aperture. During
initial loading the WARMING UP SCENE notice clears when resources are ready.
Auto-focus waits for stable display buffers before depth readback. Hide photo
controls also hides the legend. Drag its side tab vertically, drag the title to
undock, snap to the left screen edge to dock, or use DOCK. Resize with the
mirrored main-window grip. Legend controls follow menu/camera focus.
All 42 shader/material pairs and 317 shader registry IDs from the unchanged
base asset ZIP are included. Original transparent SteamGridDB logos and their
source metadata are included as files; this does not add them to the logo picker.
The native setter and earlier autofocus/crest candidate passed live checks.
This recovery runtime, cold-start timing and screenshot correction still require
in-game verification. Temporary live diagnostic helpers are excluded.
No public release changed.
'''
 runtime['INSTALL.txt']=install;runtime['FILES-SHA256.txt']=sums(runtime)
 for n,b in runtime.items():
  if n.endswith('.lua'):build.compile_lua(b,n)
  write('Runtime/dbf_freecam/'+n,b)
 lll={'dbf_freecam/'+n:b for n,b in runtime.items()};lll['Arsenal/War-Journalist-Native-Legend-Assets.zip']=asset_body;lll['INSTALL.txt']=install
 package('War-Journalist-Native-Legend-LLL.zip',lll);write('War-Journalist-Native-Legend-Assets.zip',asset_body)
 embedded=[]
 for n,b in sorted(runtime.items()):
  if n.endswith('.dll'):v='{hex='+build.lua_bytes(b.hex().encode())+'}'
  elif n.startswith('src/')or n=='standalone-library.txt':v=build.lua_bytes(b)
  else:continue
  embedded.append('['+build.lua_bytes(n.encode())+']='+v+',')
 startup=(ROOT/'freecam/bsl_startup.lua').read_text().replace('-- __EMBEDDED_FILES__','\n'.join(embedded)).replace('__VERSION__',version).replace('__CAPTURE_LIBRARY__',build.capture_library_name()).encode();build.compile_lua(startup,'native-legend-BSL')
 envelope=struct.pack('<II',len(startup),2)+startup;cpu,gpu=photo_assets.archive_rows(shared+[(lua_archive.hash_name('mods/dbf_photomode/startup'),lua_archive.LUA_TYPE,envelope,b'')])
 assert sorted(r for r in photo_assets.read_archive(cpu,gpu)if r[1]!=lua_archive.LUA_TYPE)==sorted(shared)
 bm={'Version':1,'Guid':'0a1f063d-d880-4282-a5c3-89f9efc52b21','Name':'War Journalist - Native Recovery Test'if recovery else'War Journalist - Native Lens and Legend Test','Description':f'Complete test runtime and all {shader_count} shader/material pairs. Requires BSL v15+; MCM optional.','Options':[{'Name':'War Journalist native lens test','Include':['Addon']} ]}
 bsl={'manifest.json':(json.dumps(bm,indent=2)+'\n').encode(),'INSTALL.txt':install,'PROVENANCE.json':runtime['PROVENANCE.json'],'VENDOR-PROVENANCE.json':runtime['VENDOR-PROVENANCE.json'],'LICENSE-Bingus.txt':runtime['LICENSE-Bingus.txt'],'Addon/9ba626afa44a3aa3.patch_0':cpu,'Addon/9ba626afa44a3aa3.patch_0.gpu_resources':gpu,'Addon/9ba626afa44a3aa3.patch_0.stream':b''}
 bsl['LICENSE-Link.txt']=runtime['LICENSE-Link.txt']
 for suffix in('','.gpu_resources','.stream'):bsl['Addon/ee6b1ba7e22d71ed.patch_0'+suffix]=assets['Assets/ee6b1ba7e22d71ed.patch_0'+suffix]
 for n,b in runtime.items():
  if n.startswith('assets/'):bsl[n]=b
 package('War-Journalist-Native-Legend-BSL.zip',bsl)
 write('PACKAGE-RECEIPT.json',(json.dumps(provenance,indent=2)+'\n').encode());print(OUT)
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--output',type=Path,required=True)
 parser.add_argument('--combined-dir',type=Path,default=COMBINED)
 parser.add_argument('--recovery',action='store_true',help='Remove the experimental compositor, restore unchanged proven Shader assets and disable scene effects')
 args=parser.parse_args();OUT=args.output.resolve();COMBINED=args.combined_dir.resolve();main(recovery=args.recovery)
