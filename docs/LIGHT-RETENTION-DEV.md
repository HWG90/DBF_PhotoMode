# Photo light retention hotfix

Installed local development candidate; published 0.9.5 packages retain their original behavior.
Lighting remains **Not tested fully** until the new lifecycle is accepted in game.

Exiting Photo Mode destroys every temporary owned light unit but remembers up to
three light definitions for the current scene. Each definition contains its ID,
settings and numeric camera basis/anchor. No Unit, Light, engine vector or World
handle is retained in the saved definitions. Reopening Photo Mode automatically
creates fresh owned units at those positions, with the same settings and selected
light. Follow-camera lights retain their last position for initial recreation and
resume following the current camera on subsequent updates. There are no lights
left illuminating normal gameplay.

Removing a light removes it from the setup remembered on the next exit. Remove
all, explicit `clear`/`close`, and loader shutdown discard the whole retained
setup. Pending creates or slider edits are discarded on exit; only completed
settings are remembered. Missing camera/resource/scene information keeps the
setup available for a later update. Failed destruction or recreation keeps owned
cleanup handles and retries without creating duplicate lights.

The camera foundation documents that the game reuses the main-world object for
ship and mission. `build.py` therefore provides `scene_context()` on the manager,
returning the tracked world and `WORLD.epoch` during both active and inactive
frames. A changed world or epoch invalidates the retained setup. An unknown
generation cannot recreate a setup or dereference a generation-stamped unit.
The generation check runs before any native unit access. The update callback
continues to be the only drain for menu requests and automatic recreation.

The new `saved_setup()` method returns a deep copy of the retained numeric data
for diagnostics. Existing table identity, controller references and update/cache
methods survive an idle in-place constructor refresh. An occupied handoff can
include `scene_epoch` to stamp existing owned records before installing methods.
An old live runtime also needs a scene provider; merely refreshing the factory
without that provider does not enable retention safely.

Run the focused fixture without attaching to the game:

```powershell
py -3 tools/run_tests.py --fixture photo_lights_tests.lua --receipt dist/validation/photo-light-retention-dev.json
```

The fixture covers full controller exit/re-entry without Add light, exact fixed
placement, saved point/spot settings and selection, disabled/follow lights,
uncommitted edit cancellation, rollback retention, cleanup/recreation failure,
missing resources/camera/generation, explicit removal/clear, table refresh, and
scene changes with a reused world handle. It does not establish visible GPU
illumination or in-game menu acceptance.

The final candidate passed all 42 isolated fixture groups and standalone package
checks for BSL, MDL and LLL. Complete development archives are retained under
`dist/releases/War-Journalist-0.9.5-light-retention-dev`. The follow-up candidate
also adds a visible **Apply** button to the RGB color editor; it closes the editor
while retaining the previewed color. Pointer interaction and placement passed at
1920x1080 and 800x600. Complete packages with both fixes passed their standalone
checks under `dist/releases/War-Journalist-0.9.5-light-retention-apply-dev`.

The local LLL `src/actioncam.lua` was backed up and replaced with the validated
generated runtime, SHA256
`f262ef08a6b95bdaeed01344674a92f84324dd0b2854bf7001b4b4f9a3efad04`.
The final marker readback guard also checks scene generation before accessing
units. Existing dedicated light assets are byte-identical and need no deployment.
Settings, screenshots, other runtime files and Arsenal source were untouched.
The deployment receipt and rollback copies are under
`dist/review/photo-light-retention-dev`. The initial candidate was installed while
the game was closed; the user launched before the final marker guard was written.
The final runtime is on disk for the next normal restart. No live refresh was performed.

Next-launch acceptance remains open: add and position lights, exit Photo Mode,
then reopen it and confirm they return without Add light. Remove one, repeat,
and verify only the remaining lights return.
