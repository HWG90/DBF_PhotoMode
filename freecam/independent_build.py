"""Generate an opt-in owned camera runtime; never patch a vendor camera source."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MODULES = ('independent_runtime.lua', 'camera_scene.lua', 'camera_motion.lua', 'camera_ownership.lua', 'camera_lens.lua')


def studio_builder():
    spec = importlib.util.spec_from_file_location('independent_photo_studio', ROOT/'build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def ownership_source(builder=None):
    """Retain the loader-facing .new API; legacy signatures are fallback only."""
    builder = builder or studio_builder()
    gateway = (ROOT/'camera_ownership.lua').read_text(encoding='utf-8')
    # This reads the exact-signature catalogue and compatibility adapter, not
    # ActionCam's controller source. The gateway constructs it only if needed.
    legacy = builder.actioncam_compat_source(verify_foundation=False)
    return ('local legacy_factory=(function()\n'+legacy+'\nend)()\n'
            'local gateway=(function()\n'+gateway+'\nend)()\n'
            'return {new=function(G,log)return gateway.new(G,log,legacy_factory)end}\n')


def generate(dof_candidate=False,scene_candidate=False,native_candidate=False,
             combined_scene_candidate=False,builder=None):
    builder = builder or studio_builder()
    source = (ROOT/'independent_runtime.lua').read_text(encoding='utf-8')
    token = '__STUDIO_FEATURES__'
    if source.count(token) != 1:
        raise ValueError('Owned camera runtime must embed the studio exactly once')
    lifecycle=('DBF_PHOTO_LENS=(function()\n'+(ROOT/'camera_lens.lua').read_text(encoding='utf-8')+
               '\nend)().new(DBF_PHOTO_LENS,function()return scene end)\n')
    source = source.replace(token, builder.studio_source(
        dof_candidate=dof_candidate,scene_candidate=scene_candidate,
        native_candidate=native_candidate,combined_scene_candidate=combined_scene_candidate,
        camera_lifecycle=lifecycle))
    for token,name in (('__CAMERA_SCENE__','camera_scene.lua'),
                       ('__CAMERA_MOTION__','camera_motion.lua'),
                       ('__ANIMATION_STATE__','animation_state.lua')):
        if source.count(token) != 1:
            raise ValueError('Owned camera module embed contract changed: '+token)
        source = source.replace(token,(ROOT/name).read_text(encoding='utf-8'))
    # Ownership is normally a separate loader module. Support an explicitly
    # requested template embed without requiring another manifest module.
    if '__CAMERA_OWNERSHIP__' in source:
        if source.count('__CAMERA_OWNERSHIP__') != 1:
            raise ValueError('Owned camera ownership embed contract changed')
        source = source.replace('__CAMERA_OWNERSHIP__',ownership_source(builder))
    if native_candidate:
        source = "rawset(_G,'DBF_PHOTO_NATIVE_LENS_CANDIDATE',true)\n"+source
    return "rawset(_G,'DBF_PHOTO_CAMERA_ENGINE','independent')\n"+source
