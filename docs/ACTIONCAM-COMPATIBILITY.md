# ActionCam coexistence

War Journalist supports the verified original ActionCam 2.3.1 (runtime 10.31)
and ActionCam 2.4 (runtime 10.32, Nexus file 68485). It leaves gameplay camera
behavior, profiles, First Person cleanup and ActionCam's binding-level choice
intact. During Photo Mode, including Cinema performance, ActionCam yields its
camera and profile shortcuts. Its separate Photo Mode bindings are excluded
while the adapter is attached, preventing competing camera controls.

Every supported camera closure is checked against an exact bundled LuaJIT
signature before its upvalues are changed. Unknown versions and modified
closures are refused without being overwritten. Failed startup restores the
original bindings and callbacks; failed camera cleanup keeps ownership until
restoration succeeds. No Links installation is required.

The signature manifest records the source and archive hashes for ActionCam 2.4
and its [original Nexus file](https://www.nexusmods.com/helldivers2/mods/16752?tab=files&file_id=68485).
That supplied Lua source has no explicit redistribution license in its header
or package manifest, so a second full original source copy is not bundled.
The original archive is used only for optional offline verification.

To reproduce those tests with the unchanged locally supplied 2.4 archive:

```powershell
py -3 tools/test_actioncam_compat.py --archive "C:\path\to\ActionCam-2.4\Addon\9ba626afa44a3aa3.patch_0"
```

The test first runs the bundled 2.3.1 source, then verifies 2.4's archive hash,
source hash and all camera closure signatures before running the same lifecycle
fixtures against its actual Lua source. It covers both load orders, late
loading, exclusive camera writes, enter/exit, First Person restoration, shortcut
priority, cleanup retries, and 2.4's None/Essential/Full levels and next/previous
profile controls. It runs in an isolated LuaJIT state, never in the game process.

After a deliberate audit of a new original archive, signatures can be regenerated
with `py -3 tools/actioncam_signatures.py --archive "C:\path\to\9ba626afa44a3aa3.patch_0"`.
This writes signatures only; it does not copy the original source or install
anything. Offline success does not establish live camera coexistence.
