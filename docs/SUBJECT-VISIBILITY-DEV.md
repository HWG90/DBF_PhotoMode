# Subject attachment visibility hotfix

Development source; in-game acceptance is separate from the offline fixtures.
Published 0.9.5 release notes remain unchanged.

Hide entire player now includes the verified local hero, garment units, carried
equipment including the backpack, and their attached descendant units. Hide
carried weapons includes each inventory weapon and its descendants; it does not
hide the hero, armour or backpack. Hide armour includes garment descendants.
Unrelated world units, dropped equipment that is no longer attached, remote
players and scene lights are not selected by proximity or resource name.

The previous backend only selected root references. The read-only tree captured
on October 13 identified local weapon reference 4194651 with attached parts
4194654, 4194653, 4194652 and 4194650. Those separate render units explain the
floating parts left behind when the weapon root and player were invisible.
The same tree contained 26 real SDK units under the local hero.

The verified renderer implementation at executable RVA `2BEB90` traverses
`Unit + 1D8` (first child) and child `+ 1E0` (next sibling). Each child's `+ 1D0`
parent backpointer must match its parent. A child's full reference at `+ 8`
must resolve to that exact native pointer through the generation-checked Unit
registry, and every selected unit must belong to the same native world. Exact
PE stamps, visibility binding bytes, renderer vtable entries and child-reader
fingerprints are checked before using this layout. Traversal rejects cycles,
more than 256 selected units, and depth greater than 16. Handles come from the
actual `World.units` list; the backend never fabricates a Unit argument.
The Lua `Unit.is_child` binding discards the native result, so it is not used.

Evidence is retained locally under `dist/review/subject-visibility-dev`:
`hierarchy-bindings.asm.txt`, `child-native.asm.txt`, `unit-children.asm.txt`,
`unit-hierarchy.txt`, and `unit-hierarchy-tree.txt`. These are read-only native
observations, not package payload or source publication requirements.

The backend refreshes descriptors instead of caching groups solely by root
references. Mesh ownership uses the exact native mesh object inside a validated
Unit. If its mesh array changes or reorders, readback and restore locate that
same object in the current array rather than using a stale index or old pointer
array. A replacement object receives its own visibility lease. Pre-hidden meshes
are never made visible. Restore only changes a live captured object whose mask
still equals the value written by Photo Mode. A different mask is preserved;
retired objects are skipped and transient memory-read failures remain pending
for retry. A detached living component regains its original visibility.

The update-time refresh has its own clock, independent of UI capability polling.
It checks for new attachments at most every half second even when all original
meshes were already invisible. Unchanged hidden meshes produce no repeated
engine setters. Menu requests still queue for the owning update callback.

`subject.new(backend, log, existing)` supports a reversible live refresh after
the old service has restored its owned rows and drained pending requests. It
keeps the existing shared table, including the controller's captured reference.
The constructor rejects outstanding owned meshes or pending work. No closure
upvalues need to be changed. Root owns live refresh/deployment and its receipt.

Focused validation:

```powershell
py -3 tools/run_tests.py --fixture subject_tests.lua --fixture subject_backend_tests.lua --fixture director_tests.lua --fixture director_controls_tests.lua --receipt dist/validation/subject-visibility-dev.json
```

All four groups pass. The real backend fixture uses an injectable synthetic
memory image and SDK handles to test nested attachments, backpack inclusion,
weapon-only grouping, foreign world rejection, wrong parent rejection, sibling
cycles, descriptor refresh, mesh-array changes/reordering, original invisible
meshes, detachment/restore, recycled generations, transient read retry, and
empty shared-table refresh. It does not attach to a game process.

Live acceptance on October 13: the existing visibility service was refreshed
after verifying it had no pending or owned hidden meshes. Readback confirmed all
145 meshes across 26 local units hidden, including all 37 meshes in the six
weapon units. The user confirmed: "Yup - player is gone now". The comparison
also restored 144 originally visible meshes while preserving the one originally
invisible mesh. Early screenshots did not reliably correspond to the sampled
state, so they are not claimed as visual proof. The final read after the user
closed Photo Mode confirmed zero owned meshes and the original 144/1 split.

All 43 fixture groups and all three complete loader package checks passed.
The combined development package is in
`dist/releases/War-Journalist-0.9.5-light-and-subject-dev`. Its installed runtime
SHA-256 is `340202fb9e8885e8956ef861d20a98f35f6d74d58b495677332c53fa7bce1e2c`.
The next-launch install includes light retention and the color editor's Apply
button; the running process received only the visibility service refresh.
Game assets, saved settings, screenshots and public release archives were not
replaced. The previous installed runtime is backed up with the deployment
receipt in `dist/review/photo-light-retention-dev`.
