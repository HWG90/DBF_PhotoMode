# War Journalist 0.9.10

A Helldivers 2 Photo Mode. This development candidate adds explicit camera
ownership when the supported standalone ActionCam foundation is also enabled.

- ActionCam keeps its normal gameplay camera, First Person behavior, settings
  and profiles outside Photo Mode.
- War Journalist owns camera position, FOV and photo controls exclusively during
  Photo Mode. ActionCam's own camera update and draw work yield until the photo
  camera, effects, poses, simulation and input finish restoring.
- First Person head/near-plane and FOV leases are restored before the photo
  camera takes ownership. Original transient camera state is cleared before
  ActionCam resumes, preventing a photo pose from becoming its gameplay baseline.
- Both startup orders are covered. The independently bound ActionCam Photo
  Mode actions yield to War Journalist, while its gameplay profile/restart
  shortcuts remain available outside Photo Mode. Held shortcuts drain before
  resuming to prevent an unintended action at photo exit.
- Sharing is limited to the exact audited ActionCam 2.3.1 / runtime 10.31 and
  ActionCam 2.4 / runtime 10.32 Lua
  contracts. Unknown versions are left untouched and cannot grant a photo
  camera lease. No engine-global setter changes or native hooks are used.

The 0.9.9 shader-registry repair and complete runtime/assets remain included.
Isolated tests execute the unchanged ActionCam source and verify both load
orders, gameplay FOV/profile behavior, exclusive photo writes, First Person
restoration, failed cleanup, callback chaining/errors and held binding edges.
Live coexistence still needs validation; this candidate makes no AMD crash
claim beyond the separately tested 0.9.9 registry repair.
