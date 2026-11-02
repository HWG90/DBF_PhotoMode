# Custom bone posing — design

Date: 2026-10-31. Branch: `claude/wj-bone-posing`, from the 1.3.4 release line.
Status: approved in conversation (sections 1–5), prototype in progress.

## Goal

Let a player pose a Helldiver bone by bone inside Photo Mode, and keep poses
as files that load again later, instead of only choosing from the sampled
emote catalogue.

Success: freeze, pick a bone, turn it, see it move, save, restart the game,
load the pose back onto a Helldiver, and Reset leaves the skeleton as it was.

## Scope

In: a per-bone editor in the Subject tab (sliders plus a viewport drag
handle), a bone marker, and pose files with save, overwrite, load, delete and
rescan. Snapshotting the frozen skeleton is saving with no edits.

Out, on record: bone translation, mirroring, in-game renaming, sampling more
game clips, enemies, and the Chef build. The Boot Mod Loader build only.

## Constraints that shaped the design

- Bone writes are proven only while Freeze Action holds true-zero time. The
  editor rides on the existing subject lease and inherits that gate.
- The game exposes no directory listing to Lua, and plain Lua cannot create a
  folder. Pose files are flat, numbered, and discovered by probing.
- `steam_runtime.lua`'s constructor is at Lua 5.1's 200-local limit and its
  tick at the 60-upvalue limit. New state lives in a module held as one field.
- Every bone write stays inside `steam_subject.lua`'s lease and ledger so
  restoration, cape maintenance and foreign-change detection are unchanged.

## 1. Pose data and maths

Editable nodes are 8..92 of the 107-node Helldiver rig, the same range the
catalogue writes. Node values are the controller's numeric nodes: `p` (3),
`q` (4, xyzw), `s` (3), optionally `pose` (12 canonical scalars). The editor
changes only `q`.

Groups (node numbers in brackets):

- Body: Body root [8], Hips [10], Spine 1 [22], Spine 2 [27], Chest [29],
  Neck [90], Head [91]
- Left arm: Clavicle [43], Shoulder [45], Elbow [47], Hand [48],
  Shoulder twist [46], Hand twist [65], Shoulder armour [44]
- Right arm: Clavicle [66], Shoulder [68], Elbow [70], Hand [72],
  Shoulder twist [69], Hand twist [71], Shoulder armour [67]
- Left leg: Thigh [17], Knee [18], Foot [19], Ball [20], Toe [21]
- Right leg: Thigh [11], Knee [13], Foot [14], Ball [15], Toe [16]
- Left hand: Thumb 1–3 [62,63,64], Index 1–3 [59,60,61],
  Middle 1–3 [56,57,58], Ring 1–3 [53,54,55], Pinky 1–3 [50,51,52]
- Right hand: Thumb 1–3 [87,88,89], Index 1–3 [82,83,84],
  Middle 1–3 [79,80,81], Ring 1–3 [76,77,78], Pinky 1–3 [73,74,75]
- Cape: Cape 1–8 [35..42]
- Aim and gear: Aim [9], Head aim [92], Weapon mount [33], Weapon aim [34],
  Hand aim [86], Left hand mount [49], Right hand mount [85], Pistol [12],
  Backpack [30], Sling [28], Support [32], Support MG [31], Pouch [23],
  Intel pad [24], Designator [25], Knife [26]

Every node 8..92 appears exactly once; a fixture checks that and that names
match the rig table in `assets/steam_subject_poses.lua`.

Base frame: a copy of nodes 8..92 taken when editing starts, from the frame
the lease currently authors, or from a fresh snapshot of the frozen skeleton
when nothing is held. Choosing a catalogue pose or loading a file replaces the
base and clears all angles; the status says "Edits cleared".

Angles: per node, Bend, Swing and Twist in degrees, each clamped to
[-180, 180], default 0. From the rig data every limb bone runs along its own
X axis and elbows and knees hinge about Z, so Twist is about local X, Bend
about local Z, Swing about local Y, the same names on every bone.

Composition: `target.q = normalize(compose(base.q, bend, swing, twist))`,
with the delta applied in the bone's own frame. The side of the quaternion
product that means "bone frame" in the engine's convention is one constant
in one function, pinned by a numeric fixture and confirmed live (an elbow
Bend must fold the forearm, not swing it). Pure Lua quaternion maths, no
engine calls.

A composed frame always carries node 8 from the base and is applied as
`full_body=true`. Nodes with zero angles are passed through as the base node
table, so unchanged bones compare equal and are never rewritten.

Resets: Reset bone zeroes one node; Reset edits zeroes all and keeps the base;
the existing Reset pose restores the skeleton and drops base and angles.

## 2. Controller change and runtime wiring

`steam_subject.lua`:

- `apply(id)` keeps its signature. Its body after `prepare(id)` becomes an
  internal apply of a prepared frame under a key and label.
- New `apply_frame(frame, label)`: validates and copies `frame.nodes[8..92]`
  (`copy_node`), canonicalises only nodes whose PQS differs from the current
  authored target (others reuse the target node, matrix included), then runs
  the shared apply under the reserved key `edited`. The same-key shortcut does
  not apply to edited frames. Status: "Edited pose held on the selected
  subject" (label used when given).
- New read-only `target_frame()` (what the lease authors now; nil when no
  lease) and `current_frame()` (a copied snapshot of the frozen skeleton; no
  lease).
- `labels` gains no entries; `edited` is never offered as a catalogue id.

`steam_subject_native.lua`: new guarded read `node_position(target, rig,
index)` returning the node's world translation, nil when the subject is not
valid. Used only by the marker.

`pose_editor.lua` (new, no engine access): groups, base, angles, compose,
status text, dirty flag, and the menu actions as closures. Constructed by the
runtime when the subject service loads; kept for the whole game session.
Held by the runtime as the field `self.pose_editor`.

Runtime (`steam_runtime.lua`):

- `subject_action` gains the method `apply_frame`. It keeps the existing
  release of Freeze holds and ragdoll. If no pose is held it takes the
  first-pose path: reset, `pending_pose={frame=…, updates=2}`, apply in
  `settle_pose`. If a pose is held it calls the controller directly, without
  the reset catalogue switches perform.
- Once per update, beside `settle_pose`, a dirty editor composes and applies.
  A burst of slider changes produces one apply per update.
- Catalogue pose applied → editor rebases and clears. Reset pose, subject
  change or refresh → editor cleared. Photo Mode close → an editor with edits
  keeps them and applies them again to the Helldiver selected on the next
  open; one without edits clears (user, 2026-11-02). Time resumes → the
  controller restores as today; the editor keeps base and angles as the
  working pose; a slider move or Apply edits re-applies once frozen again.
- Refusals surface through the existing notice and once-per-reason log.

## 3. Menu rows, viewport drag and the bone marker

New group "Pose editor" in the Subject tab after Pose, before Visibility:

| id | type | notes |
| --- | --- | --- |
| `bone_group` | choice | nine groups |
| `bone` | choice | dynamic per group; index clamped on group change |
| `bone_bend`, `bone_swing`, `bone_twist` | slider | -180..180, step 1, fine 0.1 |
| `bone_drag_handle` | handle | left-drag: Bend (x), Swing (y); wheel and middle-drag: Twist; Shift fine |
| `bone_reset`, `bone_reset_all`, `bone_apply` | button | Reset bone, Reset edits, Apply edits |
| `bone_marker` | toggle | default on |
| `bone_status`, `bone_hint` | text | status and guidance |

Group "Saved poses": `pose_file` (choice), `pose_load`, `pose_save_new`,
`pose_overwrite`, `pose_delete`, `pose_rescan` (buttons), `pose_files_status`,
`pose_files_hint` (text).

Sliders mirror the selected bone: when selection or base changes the runtime
writes the bone's angles into the three rows behind a sync guard, as the light
rows follow the selected light. Stored values are never read back.

Enabled rules: dropdowns and the marker toggle always; sliders, drag, resets,
Apply edits and file actions only with a selected Helldiver, true-zero
Freeze, and no pending subject action, with the existing disabled hint.

Drag handle: `photo_menu.lua` replaces its three `handycam_position_handle`
id checks with a per-row `drag` descriptor: the action name and the mapping
of horizontal, vertical, wheel and middle-drag to value ids with scale and
limit. The Handycam row declares a descriptor reproducing today's behaviour;
the bone row declares its own.

Marker: with the toggle on and a bone selected, a small ring at the bone and
a short line to its parent, projected with `photo_light_gizmos.project` and
the same camera frame the light gizmos use. Positions from
`node_position`; a failed read hides the marker. Display only.

No new key bindings.

## 4. Pose files

Location: the settings folder (`host.config_dir`, next to
`director-shots.ini`), names `wj-pose-01.txt` … `wj-pose-99.txt`.

Discovery: probe the 99 names with an open attempt on Photo Mode open, after
save and delete, and on Rescan. Copied-in files appear when they use a free
number. (Deviation from "lists every file", accepted: no listing exists.)

Display: `NN — label`. Default label on save: base pose label + " edits", or
"Snapshot". Overwrite keeps the file's existing label.

Format (text, one key per line; strict):

```
version=1
rig=4d1c334d294dfa97
nodes=107
label=Salute edits
source=salute
8=px,py,pz;qx,qy,qz,qw;sx,sy,sz
…
92=…
```

Rejected: missing or repeated line, unknown key, non-finite value, quaternion
norm outside [0.99, 1.01], rig mismatch ("This pose is for a different rig"),
size over 32 KB.

Writing: temp file, backup, rename, as `director.lua` does, lifted into
`pose_files.lua` with an injected filesystem. A failed write leaves the old
file intact and reports why.

Actions: Save as new (lowest free number, reselect), Overwrite selected
(label kept), Load (parse, `apply_frame` full body, becomes base, angles
cleared, needs true zero), Delete selected (file and backup, then rescan),
Rescan.

Chef later: same format, Chef's folder.

## 5. Tests, live acceptance, sequencing

Fixtures (real Lua 5.1 via `tools/test_steam_port.py`):

- `pose_editor_tests.lua`: group coverage and names, clamping, quaternion
  maths against known values, pinned composition order, unchanged nodes pass
  through, rebase, resets, status.
- `pose_files_tests.lua`: exact round trip, every rejection, probing with a
  fake filesystem (gaps, cap), lowest free number, overwrite keeps label,
  failed write leaves old file, delete removes backup.
- `steam_subject_tests.lua` additions: `apply_frame` writes only changed
  nodes and reuses canonical matrices, refuses without true zero, restores,
  foreign-change detection, `target_frame`/`current_frame`.
- `pose_editor_runtime_tests.lua`: rows, enabled rules, one apply per update,
  first apply resets and settles, held apply direct, rebase on catalogue
  pose, clears, working pose survives unfreeze, sync guard, file actions.
- `photo_menu_interaction_tests.lua`: Handycam unchanged through the
  descriptor; bone handle mapping with Shift fine; marker rows.

Live acceptance order: elbow Bend calibration (flip the composition constant
once if it swings), shoulder Twist, children, fingers, head, cape bones, body
root; slider drag cost via the operation clock; cape follows and restores;
teammate subject; save, restart, load, overwrite label, delete, copied file
after Rescan, corrupt file; unfreeze mid-edit then Apply edits; leave Photo
Mode edited; marker on and off.

Sequencing: editor model → files → controller → runtime and rows → menu drag
and marker → build graph and manifest → dev package in Arsenal → live
calibration. Fixtures green before each next step. Release happens in a
release session; no version bump here.
