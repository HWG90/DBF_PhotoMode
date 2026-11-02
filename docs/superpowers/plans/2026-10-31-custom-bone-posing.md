# Custom Bone Posing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A per-bone pose editor in War Journalist's Subject tab, with numbered pose files, applied through the existing subject lease.

**Architecture:** A pure editor module composes a full 85-node frame from a base frame plus per-bone Bend/Swing/Twist angles; the subject controller gains `apply_frame` so edited frames use the same lease, ledger and restoration as catalogue poses; the runtime adds rows, a drag handle, a marker and file actions without new locals or upvalues. A pure files module encodes, decodes and probes `wj-pose-NN.txt`.

**Tech Stack:** Lua 5.1 (Boot Mod Loader build, no FFI), fixtures run through `tools/test_steam_port.py` with lupa (`~/Worktrees/linux-hd2/wj-1.3.1-windows/dist/toolchain/venv/bin/python`).

**Spec:** `docs/superpowers/specs/2026-10-31-custom-bone-posing-design.md`

## Global Constraints

- Lua 5.1 only: no `goto`, no integer division, no `bit`; fixtures assert `_VERSION=='Lua 5.1'`.
- `steam_runtime.lua` `M.new` is at the 200-local limit and its tick at the 60-upvalue limit: add state only as fields on `self`, never new locals or upvalues.
- Editable nodes are exactly 8..92; a frame always carries node 8 and is applied with `full_body=true`.
- Angles are degrees clamped to `[-180,180]`; Twist is local X, Bend local Z, Swing local Y.
- Bone writes only through `steam_subject.lua`; no direct `Unit.*` calls from the editor, files or runtime additions.
- Pose files: `host.config_dir..'/wj-pose-'..string.format('%02d',n)..'.txt'`, n in 1..99, at most 32768 bytes, format version 1, rig `4d1c334d294dfa97`, nodes 107.
- Every new module is pure (no `stingray`, no `io`) except `pose_files.lua`, which takes an injected filesystem `{open,rename,remove}`.
- Commit after each task with the `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` trailer. Fixtures green before each commit.

## Review Focus

- A slider drag preview in progress when the bone selection changes must be discarded, not applied to the new bone (Task 6 test "preview discarded on bone change").
- A pose file that exists but cannot be read or is empty must list as `NN — unreadable` and refuse Load with a reason, never raise (Task 2 test "unreadable file listed").
- The selected Helldiver retiring mid-edit (teammate leaves) must refuse the next apply with the controller's message, keep the working pose, and hide the marker (Task 4 test "subject retires mid-edit", Task 7 test "marker hides on failed read").
- Save as new while nothing is held and time is not at true zero must refuse with "Freeze Action first" rather than snapshot a moving skeleton (Task 5 test "save needs true zero").
- All 99 numbers taken must make Save as new refuse with "No free pose number; delete one first" (Task 2 test "cap reached").

---

### Task 1: Editor model and maths (`pose_editor.lua`)

**Files:**
- Create: `freecam/pose_editor.lua`
- Test: `freecam/pose_editor_tests.lua`
- Modify: `tools/test_steam_port.py` (append `'pose_editor_tests.lua'` to `FIXTURES`)

**Interfaces:**
- Consumes: node tables `{p={x,y,z},q={x,y,z,w},s={x,y,z},pose=…?}` as `steam_subject.lua` copies them; the rig table `bank.rig.nodes[i]={parent=,name=,bone=}` from `freecam/assets/steam_subject_poses.lua`.
- Produces:
  - `M.GROUPS`: ordered list of `{id,label,bones={{node=,label=},…}}` exactly as the spec lists them (ids `body,left_arm,right_arm,left_leg,right_leg,left_hand,right_hand,cape,gear`).
  - `M.rig_names`: `{[node]=rig name}` for every node named in the spec's groups (used by the coverage test and the runtime's sanity check).
  - `M.BONE_FRAME_SIDE`: `'right'` (delta multiplied on the right of the base). One constant, flipped only after live calibration.
  - `M.quat_multiply(a,b)`, `M.quat_axis_angle(x,y,z,degrees)`, `M.quat_normalize(q)` → quaternion `{x,y,z,w}`.
  - `M.compose(base_q,bend,swing,twist)` → normalized quaternion: `base ⊗ Rz(bend) ⊗ Ry(swing) ⊗ Rx(twist)` when `BONE_FRAME_SIDE=='right'`, the mirrored product otherwise.
  - `M.new()` → editor with: `rebase(frame,label)`, `clear()`, `has_base()`, `base_label()`, `select(node)`, `selected()`, `set_angle(node,axis,degrees)` (axis `'bend'|'swing'|'twist'`; returns false,'…' for non-finite or unknown node), `angles(node)` → `bend,swing,twist`, `reset_bone(node)`, `reset_all()`, `edited()` (any nonzero), `dirty()`, `compose_frame()` → `{full_body=true,nodes={[8..92]=node}}` and clears dirty, `status(group_label,bone_label)` → one line.

- [ ] **Step 1: Write the failing fixture**

```lua
-- freecam/pose_editor_tests.lua
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local E=dofile('freecam/pose_editor.lua');local bank=dofile('freecam/assets/steam_subject_poses.lua')
-- Group coverage: every node 8..92 exactly once, names match the rig.
local seen={};for _,g in ipairs(E.GROUPS)do for _,b in ipairs(g.bones)do
 assert(not seen[b.node],'Node listed twice: '..b.node);seen[b.node]=true
 assert(bank.rig.nodes[b.node].name==E.rig_names[b.node],'Rig name mismatch at '..b.node)end end
for i=8,92 do assert(seen[i],'Node not grouped: '..i)end
assert(#E.GROUPS==9 and E.GROUPS[1].id=='body'and E.GROUPS[9].id=='gear')
-- Quaternion maths against known values.
local function near(a,b)for i=1,4 do if math.abs(a[i]-b[i])>1e-9 then return false end end;return true end
assert(near(E.quat_axis_angle(0,0,1,90),{0,0,math.sin(math.rad(45)),math.cos(math.rad(45))}))
assert(near(E.quat_multiply({0,0,0,1},{.1,.2,.3,.9}),{.1,.2,.3,.9}),'Identity is neutral')
assert(near(E.quat_normalize({0,0,0,2}),{0,0,0,1}))
-- Composition order pinned: Bend 90 on identity about Z; Twist 90 about X.
assert(near(E.compose({0,0,0,1},90,0,0),E.quat_axis_angle(0,0,1,90)))
assert(near(E.compose({0,0,0,1},0,0,90),E.quat_axis_angle(1,0,0,90)))
local b=E.quat_axis_angle(0,1,0,30)
assert(near(E.compose(b,45,0,0),E.quat_multiply(b,E.quat_axis_angle(0,0,1,45))),'Delta on the bone side')
assert(E.compose({0,0,0,1},0,0,0)[4]==1 and E.BONE_FRAME_SIDE=='right')
-- Editor lifecycle.
local function node(x)return{p={x,0,0},q={0,0,0,1},s={1,1,1},pose={1,0,0,0,1,0,0,0,1,x,0,0}}end
local frame={nodes={}};for i=8,92 do frame.nodes[i]=node(i)end
local e=E.new();assert(not e.has_base()and not e.dirty())
e.rebase(frame,'Salute');assert(e.has_base()and e.base_label()=='Salute'and not e.edited())
assert(e.select(70)and e.selected()==70)
assert(e.set_angle(70,'bend',45)and e.dirty()and e.edited())
assert(select(2,e.set_angle(70,'bend',0/0))=='Angle must be a number')
assert(select(2,e.set_angle(5,'bend',1))=='Unknown bone')
e.set_angle(70,'twist',400);local _,_,t=e.angles(70);assert(t==180,'Clamped')
local out=e.compose_frame();assert(out.full_body==true and not e.dirty())
assert(out.nodes[8]==frame.nodes[8]and out.nodes[47]==frame.nodes[47],'Unchanged bones pass the base table through')
assert(out.nodes[70]~=frame.nodes[70]and out.nodes[70].pose==nil and near(out.nodes[70].q,E.compose({0,0,0,1},45,0,180)))
assert(out.nodes[70].p[1]==70 and out.nodes[70].s[1]==1,'Position and scale untouched')
e.reset_bone(70);assert(not e.edited()and e.dirty());e.set_angle(48,'swing',10);e.reset_all();assert(not e.edited())
e.set_angle(48,'swing',10);e.rebase(frame,'Wave');assert(not e.edited()and e.base_label()=='Wave','Rebase clears angles')
e.clear();assert(not e.has_base()and e.selected()==70,'Clear keeps the selection')
assert(e.status('Right arm','Elbow'):find('Right arm / Elbow',1,true))
print('Pose editor: groups, quaternion maths, pinned composition, pass-through and lifecycle passed')
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/Worktrees/linux-hd2/wj-1.3.1-windows/dist/toolchain/venv/bin/python -c "import lupa.lua51 as l;r=l.LuaRuntime();r.execute(open('freecam/pose_editor_tests.lua').read())"` from the worktree root.
Expected: error opening `freecam/pose_editor.lua`.

- [ ] **Step 3: Implement `freecam/pose_editor.lua`**

Pure module per the Interfaces block. `GROUPS` lists the spec's nodes and labels; `rig_names` maps each to its rig name (`boss`, `hips`, `spine1`, `spine2`, `chest`, `neck`, `head`, `l_clavicle`, …, `weapon_aim` for node 86, `aim_weapon` for 34, `attach_weapon` for 33). `compose_frame` returns the base node table itself for nodes with all-zero angles and a fresh `{p=copy,q=compose(...),s=copy}` without `pose` otherwise. `status` returns `base_label..' edits'` or `base_label` plus `'  |  '..group..' / '..bone..string.format('  Bend %d  Swing %d  Twist %d',…)`, or `'Freeze Action, then pick a bone'` without a base.

- [ ] **Step 4: Run the fixture to verify it passes**

Same command as Step 2. Expected: the final `print` line.

- [ ] **Step 5: Register and run the suite**

Append `FIXTURES+=('pose_editor_tests.lua',)` to `tools/test_steam_port.py`. Run `…/venv/bin/python tools/test_steam_port.py`. Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add freecam/pose_editor.lua freecam/pose_editor_tests.lua tools/test_steam_port.py
git commit -m "Pose editor: bone groups, quaternion maths and composed frames"
```

---

### Task 2: Pose files (`pose_files.lua`)

**Files:**
- Create: `freecam/pose_files.lua`
- Test: `freecam/pose_files_tests.lua`
- Modify: `tools/test_steam_port.py`

**Interfaces:**
- Consumes: frames `{full_body=true,nodes={[8..92]={p,q,s}}}` from Task 1's `compose_frame` or the controller's `current_frame`.
- Produces:
  - `M.MAXIMUM=99`, `M.MAX_BYTES=32768`, `M.RIG='4d1c334d294dfa97'`.
  - `M.path(folder,n)` → `folder..'/wj-pose-NN.txt'`.
  - `M.encode(frame,meta)` → text; `meta={label=,source=}`; numbers with `'%.17g'`; lines `version=1`, `rig=…`, `nodes=107`, `label=…`, `source=…`, then `N=px,py,pz;qx,qy,qz,qw;sx,sy,sz` for N=8..92.
  - `M.decode(text)` → `frame{full_body=true,label=,source=,nodes=}` or `nil,why` with the spec's messages: `'This pose is for a different rig'`, `'Pose file is too large'`, `'Pose file is missing node N'`, `'Pose file repeats N'`, `'Pose file has an unknown line'`, `'Pose value is not a number'`, `'Pose quaternion is not normalised'`.
  - `M.storage(folder,fs)` → store with `list()` → ordered `{{number=,label=,readable=bool}}`, `labels()` → `{'NN — label'}` or `{'No saved poses'}`, `rescan()`, `load(number)` → frame or `nil,why`, `save_new(frame,meta)` → `number` or `nil,why`, `overwrite(number,frame)` (keeps the file's label) → `true` or `false,why`, `delete(number)` → `true` or `false,why`.

- [ ] **Step 1: Write the failing fixture**

```lua
-- freecam/pose_files_tests.lua
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local F=dofile('freecam/pose_files.lua')
local function frame(x)local f={full_body=true,nodes={}};for i=8,92 do f.nodes[i]={p={x+i,.5,-.25},q={0,0,math.sin(.3),math.cos(.3)},s={1,1,1}}end;return f end
local text=F.encode(frame(1),{label='Arms crossed',source='salute'})
assert(text:find('^version=1\nrig=4d1c334d294dfa97\nnodes=107\nlabel=Arms crossed\nsource=salute\n8='))
local back,why=F.decode(text);assert(back,why);assert(back.label=='Arms crossed'and back.full_body==true)
for i=8,92 do for k=1,3 do assert(back.nodes[i].p[k]==frame(1).nodes[i].p[k])end;assert(back.nodes[i].q[4]==math.cos(.3))end
assert(select(2,F.decode(text:gsub('rig=4d1c334d294dfa97','rig=0000000000000000')))=='This pose is for a different rig')
assert(select(2,F.decode(text:gsub('\n50=[^\n]*','')))=='Pose file is missing node 50')
assert(select(2,F.decode(text..'\n50=0,0,0;0,0,0,1;1,1,1'))=='Pose file repeats 50')
assert(select(2,F.decode(text..'\ncolour=red'))=='Pose file has an unknown line')
assert(select(2,F.decode(text:gsub('\n9=[^\n]*','\n9=1,nan,0;0,0,0,1;1,1,1')))=='Pose value is not a number')
assert(select(2,F.decode(text:gsub('\n9=[^\n]*','\n9=1,0,0;0,0,0,2;1,1,1')))=='Pose quaternion is not normalised')
assert(select(2,F.decode(text..string.rep('\n',32768)))=='Pose file is too large')
-- Fake filesystem: files[path]=content; open modes 'rb'/'wb'; rename/remove.
local files,fail_write={},false
local fs={}
function fs.open(path,mode)
 if mode=='rb'then local c=files[path];if c==nil then return nil,'missing'end;return{read=function()return c end,close=function()end}end
 if fail_write then return nil,'disk full'end
 local buf={};return{write=function(_,s)buf[#buf+1]=s;return true end,close=function()files[path]=table.concat(buf);return true end}
end
function fs.rename(a,b)if files[a]==nil then return nil,'missing'end;files[b]=files[a];files[a]=nil;return true end
function fs.remove(p)if files[p]==nil then return nil,'missing'end;files[p]=nil;return true end
assert(F.path('C:/cfg',7)=='C:/cfg/wj-pose-07.txt')
local store=F.storage('C:/cfg',fs)
assert(#store.list()==0 and store.labels()[1]=='No saved poses')
assert(store.save_new(frame(1),{label='First',source='snapshot'})==1 and files['C:/cfg/wj-pose-01.txt'])
files['C:/cfg/wj-pose-05.txt']=F.encode(frame(5),{label='Dropped in',source='file'});files['C:/cfg/wj-pose-03.txt']=''
store.rescan();local l=store.list();assert(#l==3 and l[2].number==3 and l[2].readable==false and store.labels()[2]=='03 — unreadable','unreadable file listed')
assert(store.labels()[3]=='05 — Dropped in');assert(select(2,store.load(3))~=nil and not store.load(3))
assert(store.save_new(frame(2),{label='Second'})==2,'Lowest free number')
assert(store.overwrite(5,frame(9))and F.decode(files['C:/cfg/wj-pose-05.txt']).label=='Dropped in','Overwrite keeps the label')
assert(F.decode(files['C:/cfg/wj-pose-05.txt']).nodes[8].p[1]==17)
fail_write=true;local before=files['C:/cfg/wj-pose-05.txt'];assert(not store.overwrite(5,frame(1))and files['C:/cfg/wj-pose-05.txt']==before,'Failed write leaves the old file');fail_write=false
files['C:/cfg/wj-pose-02.txt.bak']='x';assert(store.delete(2)and files['C:/cfg/wj-pose-02.txt']==nil and files['C:/cfg/wj-pose-02.txt.bak']==nil)
for n=1,99 do files[F.path('C:/cfg',n)]=F.encode(frame(n),{label='n'..n})end;store.rescan()
assert(select(2,store.save_new(frame(1),{label='x'}))=='No free pose number; delete one first','cap reached')
print('Pose files: round trip, rejections, probing, numbering, overwrite, failed write, delete and cap passed')
```

- [ ] **Step 2: Run it to verify it fails** (same runner idiom as Task 1). Expected: cannot open `freecam/pose_files.lua`.

- [ ] **Step 3: Implement `freecam/pose_files.lua`**

Encode/decode per Interfaces; `decode` parses `key=value` lines, caps at `MAX_BYTES` before parsing, requires the five header keys first in any order and nodes 8..92 each once, quaternion norm within `[0.99,1.01]`. `storage` probes `path(folder,n)` for n=1..99 with `fs.open(path,'rb')`, decoding only the header (first 400 bytes) to get the label; `readable=false` when open succeeds but decode of the whole file fails or the file is empty. Writes follow `director.lua`'s `storage.save` dance (`.tmp`, `.bak`, rename) with the injected `fs`.

- [ ] **Step 4: Run the fixture to verify it passes.** Expected: the final `print` line.

- [ ] **Step 5: Register (`FIXTURES+=('pose_files_tests.lua',)`), run the suite.** Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add freecam/pose_files.lua freecam/pose_files_tests.lua tools/test_steam_port.py
git commit -m "Pose files: numbered text files with strict decode and probing"
```

---

### Task 3: Controller `apply_frame`, read-only frames, adapter node position

**Files:**
- Modify: `freecam/steam_subject.lua` (`M.new`: `apply`, new `apply_frame`, `target_frame`, `current_frame`, `node_position`)
- Modify: `freecam/steam_subject_native.lua` (new `self.node_position(target,rig,index)`)
- Test: `freecam/steam_subject_tests.lua` (append a block), `freecam/steam_subject_native_tests.lua` (append a case)

**Interfaces:**
- Consumes: frames from Task 1 (`{full_body=true,nodes={[8..92]=node}}`).
- Produces (on the controller):
  - `apply_frame(frame,label)` → `true` or `false,message`; status state `'posed'`, `status.pose=='edited'`, message `(label or 'Edited pose')..' held on the selected subject'`.
  - `target_frame()` → `{nodes={[8..92]=copied node}}` of what the lease authors now, or `nil,'No pose is held'`.
  - `current_frame()` → copied snapshot nodes 8..92 (`{nodes=…}`) without taking a lease, or `nil,why`; refuses with `'True-zero Freeze Action is required'` when not frozen.
  - `node_position(index)` → `{x,y,z}` or `nil,why`; requires a selected subject and `adapter.node_position`.
- Adapter: `node_position(target,rig,index)` → `{x,y,z}` via `U.world_pose(r.unit,index)` translation under `result(...)`, `lifetime(r)` and `index>=1 and index<=107`.

- [ ] **Step 1: Write the failing controller cases** (append to `freecam/steam_subject_tests.lua`, before its final print)

```lua
do -- apply_frame: edited frames share the lease; only changed nodes are written
 local f=fixture();f.select()
 local function edited(x)local fr={full_body=true,nodes={}};for i=8,92 do fr.nodes[i]=copy(f.b.nodes[i])end;fr.nodes[70]={p=copy(f.b.nodes[70].p),q={0,0,math.sin(.4),math.cos(.4)},s={1,1,1}};return fr end
 f.frozen=false;assert(select(2,f.controller.apply_frame(edited()))=='True-zero Freeze Action is required');f.frozen=true
 assert(f.controller.apply_frame(edited(),'Salute edits'));local s=f.controller.status()
 assert(s.state=='posed'and s.pose=='edited'and s.message=='Salute edits held on the selected subject')
 assert(f.node_writes==1 and f.written[1]==70 and f.mode_writes==1,'One changed node, one mode write')
 local t=f.controller.target_frame();assert(t.nodes[70].q[3]==math.sin(.4)and t.nodes[8].p[1]==f.original.nodes[8].p[1])
 assert(f.controller.apply_frame(edited()),'Re-applying the same frame writes nothing');assert(f.node_writes==1)
 assert(f.controller.apply('full')and f.controller.status().pose=='full','A catalogue pose still applies over an edited lease')
 assert(f.controller.reset());f.restored()
 assert(select(2,f.controller.target_frame())=='No pose is held')
 local c=f.controller.current_frame();assert(c.nodes[8].p[1]==f.b.nodes[8].p[1]and c.nodes[92]and f.controller.status().state=='selected','Snapshot without a lease')
 f.adapter.node_position=function(target,rig,index)assert(index==70);return{1,2,3}end
 assert(f.controller.node_position(70)[3]==3)
 f.validation='unknown';assert(not f.controller.apply_frame(edited()),'Unknown lifetime refuses like apply')
end
```

(`fixture()` in that file must expose `f.restored` as the existing blocks do; follow the neighbouring block that calls `f.restored()`.)

- [ ] **Step 2: Run `steam_subject_tests.lua` to verify it fails.** Expected: `attempt to call field 'apply_frame'`.

- [ ] **Step 3: Implement in `freecam/steam_subject.lua`**

Split `self.apply(id)` after `prepare(id)` into `local function apply_prepared(prepared,key,label_text)` holding the snapshot/lease/write/commit body; `apply(id)` calls it with `labels[id]`. `apply_frame(frame,label)` builds `prepared` by `copy_node` for 8..92, then for each node that `same_node`s the current authored target (`lease.nodes[i].value or lease.original.nodes[i]` when a lease exists) reuses that target node, else `adapter.canonical_node` as `prepare` does; `full_body=true`; calls `apply_prepared(prepared,'edited',label or 'Edited pose')`. In `apply_prepared` the `if pose==id then return true end` shortcut runs only when `key~='edited'`. `target_frame`/`current_frame`/`node_position` per Interfaces, reusing `snapshot()`.

- [ ] **Step 4: Run `steam_subject_tests.lua` to verify it passes.**

- [ ] **Step 5: Native adapter case** (append to `freecam/steam_subject_native_tests.lua`, using its existing engine double): `assert(adapter.node_position(target,rig,70)[1]==<the double's world_pose translation x>)` and `assert(select(2,adapter.node_position(target,rig,200)))`. Implement `self.node_position` in `steam_subject_native.lua` next to `self.position`.

- [ ] **Step 6: Run the whole suite.** Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add freecam/steam_subject.lua freecam/steam_subject_native.lua freecam/steam_subject_tests.lua freecam/steam_subject_native_tests.lua
git commit -m "Subject controller: apply_frame, target and current frames, node position read"
```

---

### Task 4: Runtime: editor lifecycle, rows, apply path, slider sync

**Files:**
- Modify: `freecam/photo_options.lua` (defaults, new rows, Subject tab groups)
- Modify: `freecam/steam_runtime.lua` (`subject_action`, `settle_pose`, `load_subject`, `sync_subject`, actions table, tick)
- Modify: `freecam/steam51.lua` (`deps.pose_editor=mod.require('src/pose_editor.lua')`)
- Modify: `freecam/steam_subject_runtime_tests.lua` (export: `if rawget(_G,'DBF_PHOTO_SUBJECT_FIXTURE_ONLY')then return fixture end` before its first `do`)
- Test: `freecam/pose_editor_runtime_tests.lua`
- Modify: `tools/test_steam_port.py`

**Interfaces:**
- Consumes: Task 1 editor; Task 3 `apply_frame`, `target_frame`, `current_frame`; `subject_action`, `subject_call`, `sync_subject`, `handle`, `controls`, `texts`, `notice` as they exist in `steam_runtime.lua`.
- Produces:
  - Options defaults: `bone_group=1, bone=1, bone_bend=0, bone_swing=0, bone_twist=0, bone_marker=true`.
  - Rows (ids per spec §3) in a Subject group `'Pose editor'` placed after `'Pose'`: `bone_group`, `bone`, `bone_bend`, `bone_swing`, `bone_twist`, `bone_drag_handle`, `bone_reset`, `bone_reset_all`, `bone_apply`, `bone_marker`, `bone_status`, `bone_hint`. Sliders: `slider(id,label,-180,180,1)` with `fine_step=.1`. Buttons via `director_action`. `bone_drag_handle` is a `type='button'` row with `drag=M.bone_drag` (descriptor consumed in Task 6).
  - `saved_actions`: `bone_reset`, `bone_reset_all`, `bone_apply`, `bone_select_change(id,value)`, `bone_angle_change(id,value)`, `bone_adjust(values,finish)`.
  - Runtime fields: `self.pose_editor` (Task 1 instance or nil), `self.bone_sync` (boolean guard), `self.pending_pose={frame=…,updates=2}` alongside the existing `{id=…}` form.
  - `subject_action('apply_frame',frame,settled)`.
  - `sync_subject` sets `disabled` on all `bone_*` rows except the dropdowns and the toggle: enabled iff `enabled and not subject_pending and s.selected and simulation and simulation.owns_zero()`; `texts.bone_status.label=self.pose_editor and self.pose_editor.status(...)`.

- [ ] **Step 1: Write the failing runtime fixture**

```lua
-- freecam/pose_editor_runtime_tests.lua
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
DBF_PHOTO_SUBJECT_FIXTURE_ONLY=true;local fixture=dofile('freecam/steam_subject_runtime_tests.lua');DBF_PHOTO_SUBJECT_FIXTURE_ONLY=nil
local E=dofile('freecam/pose_editor.lua')
local function near(a,b)for i=1,4 do if math.abs(a[i]-b[i])>1e-9 then return false end end;return true end
local function elbow(f)assert(f.runtime.handle.set('bone_group',3));assert(f.runtime.handle.set('bone',3));end -- Right arm / Elbow = node 70
do -- first edit resets and settles, later edits apply directly, one write per update
 local f=fixture();f.enable();f.select();elbow(f)
 assert(f.controls.bone_bend.disabled==false,'Frozen, selected: sliders live')
 local writes=f.node_writes;assert(f.runtime.handle.set('bone_bend',45))
 f.step(.016,1);assert(f.subject.status().state~='posed','First edit waits for the reset to settle')
 f.settle();local s=f.subject.status();assert(s.state=='posed'and s.pose=='edited',s.message)
 assert(near(f.b.nodes[70].q,E.compose(f.original_b[70].q,45,0,0))and f.b.nodes[47].q[4]==1)
 local after_first=f.node_writes
 assert(f.runtime.handle.set('bone_bend',50));assert(f.runtime.handle.set('bone_bend',55));assert(f.runtime.handle.set('bone_twist',10))
 f.step(.016,1);assert(f.node_writes==after_first+1,'A burst of changes is one write per update')
 assert(near(f.b.nodes[70].q,E.compose(f.original_b[70].q,55,0,10)))
 assert(f.runtime.handle.set('bone',4));assert(f.runtime.handle.get('bone_bend')==0 and f.runtime.handle.get('bone_twist')==0,'Sliders follow the selected bone')
 assert(f.runtime.handle.set('bone',3));assert(f.runtime.handle.get('bone_bend')==55,'…and show its angles again')
 local w=f.node_writes;f.step(.016,1);assert(f.node_writes==w,'Slider sync is not an edit')
 assert(f.controls.bone_status.label:find('Right arm / Elbow',1,true))
 assert(f.action('subject_pose_stop'));f.restored();assert(f.runtime.handle.get('bone_bend')==0,'Reset pose clears edits')
end
do -- catalogue pose while editing rebases and clears; unfreeze keeps the working pose
 local f=fixture();f.enable();f.select();elbow(f)
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle()
 f.runtime.handle.set('subject_pose',2);f.settle();assert(f.subject.status().pose=='pushup' or f.subject.status().pose~='edited')
 assert(f.runtime.handle.get('bone_bend')==0,'Rebase clears angles')
 f.runtime.handle.set('bone_bend',20);f.step(.016,1);assert(f.subject.status().pose=='edited')
 assert(f.runtime.handle.set('freeze_player',false));f.step(.016,1);assert(f.subject.status().state~='posed')
 assert(f.runtime.handle.get('bone_bend')==20,'Working pose survives an unfreeze')
 assert(f.runtime.handle.set('freeze_player',true));for _=1,3 do f.step(.016,1)end
 assert(f.action('bone_apply'));f.settle();assert(f.subject.status().pose=='edited','Apply edits brings it back')
 assert(f.action('subject_pose_stop'));f.restored()
end
do -- subject retires mid-edit
 local f=fixture();f.enable();f.select();elbow(f)
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle();assert(f.subject.status().pose=='edited')
 f.b.alive=false;f.runtime.handle.set('bone_bend',40);f.step(.016,1)
 assert(f.subject.status().state=='retired'and f.runtime.handle.get('bone_bend')==40,'Refused apply keeps the working pose')
end
do -- not frozen: rows disabled; Reset edits
 local f=fixture();f.enable();f.select();elbow(f)
 assert(f.runtime.handle.set('freeze_player',false));f.step(.016,1);assert(f.controls.bone_bend.disabled==true)
 assert(f.runtime.handle.set('freeze_player',true));for _=1,3 do f.step(.016,1)end;assert(f.controls.bone_bend.disabled==false)
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle();assert(f.action('bone_reset_all'));f.step(.016,1)
 assert(f.subject.status().pose=='edited'and near(f.b.nodes[70].q,f.original_b[70].q),'Reset edits holds the plain base')
 assert(f.action('subject_pose_stop'));f.restored()
end
print('Pose editor runtime: settle, coalesced apply, slider sync, rebase, unfreeze, retire and enabled rules passed')
```

(Adjust the `subject_pose` index assertion to the second catalogue id the bank exposes, read from `f.subject.catalog[2].id`.)

- [ ] **Step 2: Export the subject fixture and run the new fixture to verify it fails.** Expected: `bone_group` unknown control.

- [ ] **Step 3: Rows in `freecam/photo_options.lua`**

Add defaults; build the group lists from `pose_editor.GROUPS` (`require` is not available in options; pass the module in through `saved_actions.pose_groups`, falling back to `{'Body'}`/`{'Hips'}` placeholders in fixtures without it). Choice rows: `bone_group` and `bone` with `on_change=function(v)saved_actions.bone_select_change(id,v)end`; sliders with `on_change=function(v)saved_actions.bone_angle_change(id,v)end`. Hint text: `'Freeze Action, then move a slider or drag. Bend, Swing and Twist turn the bone around its own axes; children follow. Picking another pose clears edits.'`

- [ ] **Step 4: Runtime wiring in `freecam/steam_runtime.lua`**

In the options call pass `pose_groups=deps.pose_editor and deps.pose_editor.GROUPS`, and the six action closures. `bone_angle_change`: if `self.bone_sync` return; else `self.pose_editor.set_angle(selected_node,axis,value)`. `bone_select_change`: recompute the selected node from the two dropdowns (clamping `bone`), `self.pose_editor.select(node)`, then `self.bone_sync=true; handle.set_many{bone_bend=…,bone_swing=…,bone_twist=…}; self.bone_sync=false`, refresh `controls.bone.choices` and `choices_revision`. `subject_action`: add the `apply_frame` branch per spec §2. `settle_pose`: when `wanted.frame`, call `subject_action('apply_frame',wanted.frame,true)`. `load_subject`: after the controller passes its method check (add `apply_frame`,`target_frame`,`current_frame`), create `self.pose_editor=deps.pose_editor.new()`. Tick, next to `settle_pose`: a method `self.tick_pose_editor()` that (a) rebases when `subject_status.pose` is a catalogue id different from the editor's last seen key, (b) when the editor is dirty and the rows are enabled, ensures a base (`target_frame()` when posed else `current_frame()`), composes, and calls `subject_action('apply_frame',frame)`; refusals go to `notice` once per reason. `sync_subject`: enabled rules and `texts.bone_status`. `subject_pose_stop`, subject refresh/select, and `self.close`: `self.pose_editor.clear()` plus a guarded slider sync to zero.

- [ ] **Step 5: Run the new fixture and the whole suite.** Expected: both pass. If `steam_runtime.lua` fails to load with "too many local variables" or "upvalues", move the offending state onto `self`.

- [ ] **Step 6: Commit**

```bash
git add freecam/photo_options.lua freecam/steam_runtime.lua freecam/steam51.lua freecam/steam_subject_runtime_tests.lua freecam/pose_editor_runtime_tests.lua tools/test_steam_port.py
git commit -m "Pose editor rows: edits apply through the subject lease once per update"
```

---

### Task 5: Saved poses rows and file actions

**Files:**
- Modify: `freecam/photo_options.lua` (group `'Saved poses'`), `freecam/steam_runtime.lua`, `freecam/steam51.lua` (`deps.pose_files=mod.require('src/pose_files.lua')`)
- Test: `freecam/pose_editor_runtime_tests.lua` (append)

**Interfaces:**
- Consumes: Task 2 `storage`, Task 4 editor lifecycle.
- Produces: rows `pose_file` (choice), `pose_load`, `pose_save_new`, `pose_overwrite`, `pose_delete`, `pose_rescan` (buttons), `pose_files_status`, `pose_files_hint` (text). Runtime field `self.pose_store=deps.pose_files and deps.pose_files.storage(host.config_dir)`; fixtures inject `deps.pose_files={storage=function()return fake end}`. Actions `pose_load`, `pose_save_new`, `pose_overwrite`, `pose_delete`, `pose_rescan`. `controls.pose_file.choices=self.pose_store.labels()` after every action and on open.

- [ ] **Step 1: Append failing cases**

```lua
do -- save, load, overwrite, delete through an injected store; save needs true zero
 local F=dofile('freecam/pose_files.lua');local files={}
 local fs={open=function(p,m)if m=='rb'then local c=files[p];if c==nil then return nil end;return{read=function()return c end,close=function()end}end;local b={};return{write=function(_,s)b[#b+1]=s;return true end,close=function()files[p]=table.concat(b);return true end}end,
  rename=function(a,b)files[b]=files[a];files[a]=nil;return true end,remove=function(p)files[p]=nil;return true end}
 local f=fixture(function(f,deps)deps.pose_files={storage=function(folder)assert(folder==f.config_dir or folder);return F.storage('C:/cfg',fs)end}end)
 f.enable();f.select();elbow(f)
 assert(f.runtime.handle.set('freeze_player',false));f.step(.016,1)
 assert(select(2,f.action('pose_save_new'))=='Freeze Action first','save needs true zero')
 assert(f.runtime.handle.set('freeze_player',true));for _=1,3 do f.step(.016,1)end
 assert(f.action('pose_save_new'));assert(files['C:/cfg/wj-pose-01.txt']and F.decode(files['C:/cfg/wj-pose-01.txt']).label=='Snapshot')
 assert(f.controls.pose_file.choices[1]=='01 — Snapshot')
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle()
 assert(f.action('pose_save_new'));assert(F.decode(files['C:/cfg/wj-pose-02.txt']).label=='Snapshot edits')
 assert(f.action('subject_pose_stop'));f.restored()
 assert(f.runtime.handle.set('pose_file',2));assert(f.action('pose_load'));f.settle()
 assert(f.subject.status().pose=='edited'and near(f.b.nodes[70].q,E.compose(f.original_b[70].q,30,0,0)),'Loaded pose is applied')
 assert(f.runtime.handle.get('bone_bend')==0,'Loaded pose is the new base')
 assert(f.action('pose_overwrite')and F.decode(files['C:/cfg/wj-pose-02.txt']).label=='Snapshot edits')
 assert(f.action('pose_delete')and files['C:/cfg/wj-pose-02.txt']==nil and #f.controls.pose_file.choices==1)
 assert(f.action('subject_pose_stop'));f.restored()
end
```

- [ ] **Step 2: Run to verify it fails.** Expected: `pose_save_new` unknown.

- [ ] **Step 3: Implement rows and actions.** `pose_save_new`: frame = editor `compose_frame()` when it has a base, else `subject.current_frame()` (which refuses when not frozen; map that refusal to `'Freeze Action first'`); meta label per spec §4; on success rescan, set `pose_file` to the new number's index (guarded). `pose_load`: decode via store, `subject_action('apply_frame',frame,nil)`, then `self.pose_editor.rebase(frame,label)` and slider sync. `pose_overwrite`, `pose_delete`, `pose_rescan` straightforward; status text in `texts.pose_files_status`.

- [ ] **Step 4: Run the fixture and the suite.** Expected: pass.

- [ ] **Step 5: Commit** — `git commit -m "Saved poses: numbered files load, save, overwrite and delete from the Subject tab"`.

---

### Task 6: Generic drag handle and the bone handle

**Files:**
- Modify: `freecam/photo_menu.lua` (handle recognition, `camera_drag` → `handle_drag`, `camera_values` → descriptor-driven `handle_values`)
- Modify: `freecam/photo_options.lua` (`M.handycam_drag`, `M.bone_drag` descriptors; `handycam_position_handle` gets `drag=M.handycam_drag`)
- Modify: `freecam/steam_runtime.lua` (`bone_adjust` action; `handycam_adjust` unchanged)
- Test: `freecam/photo_menu_interaction_tests.lua` (existing camera handle block gains `drag=` on its `ctl`; new bone handle block), `freecam/pose_editor_runtime_tests.lua` (preview discarded on bone change)

**Interfaces:**
- Descriptor: `drag={action='handycam_adjust',x={id='handycam_right_cm',scale=.1,limit=30},y={id='handycam_up_cm',scale=.1,limit=30},wheel={id='handycam_forward_cm',step=.5,limit=30},middle={x={id='handycam_yaw_deg',scale=-.2,limit=180},y={id='handycam_pitch_deg',scale=.2,limit=89}}}`; bone: `drag={action='bone_adjust',x={id='bone_bend',scale=.2,limit=180},y={id='bone_swing',scale=.2,limit=180},wheel={id='bone_twist',step=1,limit=180},middle={x={id='bone_twist',scale=.2,limit=180}}}`.
- Menu: a row with `drag` renders the handle glyph and starts a drag on left click (`rotate=false`) or middle press (`rotate=true`); deltas become `values[id]=clamp(current+delta*scale*fine/scale_factor)` rounded to 2 decimals, `wheel` adds `±step*fine`; `actions[drag.action](values)` previews, `actions[drag.action](nil,commit)` finishes.
- Runtime `bone_adjust(values,finish)`: with values, `self.bone_preview` accumulates the three ids and the editor takes the angles immediately (`set_angle` for each id present, marking dirty); with nil and `finish`, `handle.set_many(self.bone_preview)` under `self.bone_sync` then clears it; with nil and not finish, restores the editor's angles from the handle values and marks dirty. Changing the bone selection while `self.bone_preview` exists discards the preview the same way.

- [ ] **Step 1: Write the failing menu case** (new block after the camera handle block)

```lua
do -- Bone handle: left-drag Bend/Swing, wheel and MMB Twist, Shift fine, single commit
 local saved={bone_bend=0,bone_swing=0,bone_twist=0};local preview;local commits,updates=0,0;local cmds;local keys={}
 local drag={action='bone_adjust',x={id='bone_bend',scale=.2,limit=180},y={id='bone_swing',scale=.2,limit=180},wheel={id='bone_twist',step=1,limit=180},middle={x={id='bone_twist',scale=.2,limit=180}}}
 local ctl={id='bone_drag_handle',type='button',label='Drag to rotate bone',button_label='Drag to rotate bone',drag=drag}
 local function get(id)return preview and preview[id]~=nil and preview[id]or saved[id]end
 local m=dofile(root..'photo_menu.lua').new({draw=function(c)cmds=c end,release=function()end,measure=measure},{focus=function()end,hide=function()end,exit=function()end,
  bone_adjust=function(v,commit)if v then updates=updates+1;preview=preview or{};for k,n in pairs(v)do preview[k]=n end else if commit and preview then commits=commits+1;for k,n in pairs(preview)do saved[k]=n end end;preview=nil end;return true end})
 m.bind({get=get,set=function()error('Gesture must not write directly')end},{{name='Subject',controls={ctl}}})
 local function draw(focus)m.draw(1920,1080,focus~=false,false,{focus='TAB',hide='H'})end
 local function tick(x,y,left,wheel)m.tick({x=x,y=y,click=left==true,wheel=wheel or 0},function(k)return keys[k]or false end)end
 draw();local b;for _,c in ipairs(cmds)do if c.ui_role=='field'and c.control_id==ctl.id then b=c end end;assert(b)
 local x,y=b.x+b.w/2,b.y+b.h/2
 tick(x,y,false);tick(x,y,true);tick(x+10,y+20,true);assert(get('bone_bend')==2 and get('bone_swing')==4 and commits==0)
 tick(x+10,y+20,false);assert(commits==1 and saved.bone_bend==2)
 tick(x,y,false,120);assert(saved.bone_twist==1,'Wheel over the handle twists');keys[16]=true;tick(x,y,false,120);assert(math.abs(saved.bone_twist-1.1)<1e-9);keys[16]=false
 keys[4]=true;tick(x,y,false);tick(x+10,y,false);assert(get('bone_twist')>1.1,'MMB drag twists');keys[4]=false;tick(x+10,y,false)
 tick(x,y,true);tick(x+10,y,true);assert(preview);draw(false);assert(not preview,'Focus loss cancels')
 m.close()
end
print('Bone handle: drag Bend/Swing, wheel and MMB Twist, fine steps and single commit passed')
```

Also add `drag={action='handycam_adjust',…}` (the descriptor above) to the camera handle block's `ctl` so that block keeps passing through the generic path.

- [ ] **Step 2: Run `photo_menu_interaction_tests.lua` to verify the new block fails.** Expected: no field for `bone_drag_handle` drag (assert on `get('bone_bend')==2`).

- [ ] **Step 3: Implement the descriptor path in `photo_menu.lua`** replacing the three id checks (render at the `camera_handle` branch, left click at the hit branch, middle/wheel at the hits loop) with `c.drag~=nil`, and `camera_values` with a descriptor-driven function. Keep the `camera_drag_handle` ui_role name for the glyph.

- [ ] **Step 4: Runtime `bone_adjust` and the preview-discard case** (append to `pose_editor_runtime_tests.lua`):

```lua
do -- preview discarded on bone change
 local f=fixture();f.enable();f.select();elbow(f)
 f.runtime.handle.set('bone_bend',10);f.step(.016,1);f.settle()
 assert(f.runtime.actions.bone_adjust({bone_bend=40}));assert(f.runtime.handle.set('bone',4))
 f.step(.016,1);assert(near(f.b.nodes[70].q,E.compose(f.original_b[70].q,10,0,0)),'Preview never reached the old bone after the change')
 assert(f.runtime.handle.get('bone_bend')==0);assert(f.action('subject_pose_stop'));f.restored()
end
```

(Expose the action table as `f.runtime.actions` if the base fixture does not already; `steam_runtime` keeps it as `self.actions` for the HUD legend — check and reuse.)

- [ ] **Step 5: Run both fixtures and the suite.** Expected: pass.

- [ ] **Step 6: Commit** — `git commit -m "Menu drag handles: one descriptor path for the Handycam and the bone editor"`.

---

### Task 7: Bone marker

**Files:**
- Create: `freecam/pose_marker.lua`
- Modify: `freecam/photo_menu.lua` (call `self.prepare_bone_marker` beside `prepare_light_gizmos`; `self.bone_marker.draw(commands)` beside `light_gizmos.draw`)
- Modify: `freecam/steam_runtime.lua` (`menu.bone_marker`, `menu.prepare_bone_marker` next to the light gizmo block), `freecam/steam51.lua` (`deps.pose_marker`)
- Test: `freecam/pose_marker_tests.lua`, `freecam/pose_editor_runtime_tests.lua` (marker hides on failed read)

**Interfaces:**
- `pose_marker.new(project)` where `project` is `photo_light_gizmos.project`; `update(frame,fov,w,h,bone_position,parent_position,shown)`, `draw(commands)` appends rects: ring (`ui_role='bone_marker'`, layer 330, gold border) at the bone and a 6-px dot (`ui_role='bone_parent'`) at the parent; `visible()`.
- Runtime: `prepare_bone_marker(w,h,focused,hidden)` reads `handle.get('bone_marker')`, the editor's selected node, `subject.node_position(node)` and `subject.node_position(rig parent)`; any `nil` → `update(nil,…,false)`.

- [ ] **Step 1: Failing marker fixture**: with the gizmo module's `project` and a camera frame looking down +Y from the origin, `update(frame,math.rad(60),1920,1080,{0,5,0},{0,5,-.3},true)` yields `visible()==true`, `draw` appends a `bone_marker` rect centred at (960,540) within 1 px and a `bone_parent` rect below it; `update(nil,…,false)` → `visible()==false` and `draw` appends nothing; a position behind the camera → not visible.
- [ ] **Step 2: Run to verify it fails.** Expected: cannot open `pose_marker.lua`.
- [ ] **Step 3: Implement `pose_marker.lua`, the menu hooks and the runtime prepare.**
- [ ] **Step 4: Runtime case "marker hides on failed read"**: after an edit is held, set `f.b.alive=false`, step once with a render, assert no `bone_marker` command in `f.commands` (the base fixture's last draw) and no error notice. With `f.b.alive` true and `bone_marker` on, assert one `bone_marker` command exists; set `handle.set('bone_marker',false)` → none.
- [ ] **Step 5: Register `pose_marker_tests.lua`, run the suite.** Expected: pass.
- [ ] **Step 6: Commit** — `git commit -m "Bone marker: ring at the selected bone, dot at its parent"`.

---

### Task 8: Build graph, player page, dev package

**Files:**
- Modify: `tools/build_steam_candidate.py` (`MODULES+=('pose_editor.lua','pose_files.lua','pose_marker.lua')`)
- Create: `docs/POSE-FILES.md` (where the files live, the numbered names, the label line, copying a friend's pose, that renaming means editing the label line)
- Modify: `docs/KNOWN-ISSUES.md` only if a limitation is confirmed live (left to the release session otherwise)

- [ ] **Step 1: Add the modules to `MODULES`; run `…/venv/bin/python tools/build_steam_candidate.py --output dist/review/bone-posing-dev.1`.** Expected: the candidate folder contains `src/pose_editor.lua`, `src/pose_files.lua`, `src/pose_marker.lua` and the build reports the module count up by three.
- [ ] **Step 2: Run `tools/build_steam_archive.py --help`, then build the BML archive from that candidate to `dist/review/bone-posing-dev.1.zip`** (exact flags from `--help`; development build, not `--release`). Record the zip's sha256 in the commit message.
- [ ] **Step 3: Stage into Arsenal** as a development entry under `~/.config/hd2arsenal/mods/War-Journalist-1.3.4-bone-posing-dev.1`, following `[[arsenal-always-update-metadata]]` (label, description, version in `hd2a_data.json`) and `[[arsenal-open-edits]]` (profile rows only while Arsenal is closed; back up `hd2a_data.json` first to `repair-backups/`). Switch the profile row from the released 1.3.4 to the dev entry.
- [ ] **Step 4: Write `docs/POSE-FILES.md` in the release-copy voice** (`[[wj-release-copy-voice]]`: "I", plain, no tech detail beyond the file name and label line).
- [ ] **Step 5: Run the whole suite one more time; commit** — `git commit -m "Bone posing dev.1: module graph, pose file page, development package"`.

---

### Task 9: Live calibration (manual, with the user)

**Files:** none until a fix is needed.

- [ ] **Step 1: Calibration.** Freeze Action on, Subject → Pose editor → Right arm / Elbow, Bend 45. Expected: the forearm folds toward the upper arm. If it swings sideways, set `BONE_FRAME_SIDE='left'` in `pose_editor.lua`, update the pinned composition assertion in `pose_editor_tests.lua`, rebuild dev.2.
- [ ] **Step 2: Shoulder Twist, Head, Fingers, Cape bone, Body root.** Expected: Twist spins the arm around its length; children follow; cape bones move and the cape mesh follows on the next maintain; Reset pose restores all.
- [ ] **Step 3: Drag cost.** Hold a slider drag for five seconds; read `war_journalist` log lines for the subject apply timing. Expected: no visible hitch; log the per-apply milliseconds in the commit that closes this task.
- [ ] **Step 4: Teammate subject, save/restart/load, overwrite, delete, copied-in file after Rescan, corrupt file, unfreeze then Apply edits, leave Photo Mode edited, marker on/off.** Expected per spec §5.
- [ ] **Step 5: Record outcomes** in `docs/superpowers/plans/2026-10-31-custom-bone-posing.md` under a "Live results" heading and commit.

## Live results
- 2026-11-01 (Proton line, bone-posing-dev.4 under LLL): the left drag on a ring read as inverted (down went up): menu space grows upward while `pose_marker` negated dy. The user asked for the drag to rotate the bone rather than move it in space ("respect IK/FK") and for lines between bones. Fixed on `claude/wj-proton-bone-posing` as 2b70a92 and cherry-picked here as 595e813 (BML dev.6): a left drag aims the bone at the pointer (its parent turns, length kept), the wheel aims deeper or nearer, every ring draws its bone as a thin line (white for the selected bone), and the translation gesture is gone. Kept as designed there: only a parent inside the current group turns, so the first ring of a group selects but does not drag; the right drag still uses -dy. Not yet live on BML: the dev.4 and dev.5 reload requests never landed (log stops 00:54), so the Lua5.1 profile needs a fresh Deploy of the dev.6 Arsenal entry.

- 2026-11-01 00:29–00:31, Proton, dev.1: **Elbow Bend 45 folded the forearm; Shoulder Twist spun the arm along its length** (user: "Folded correctly"). `BONE_FRAME_SIDE='right'` stands.
- The first edit after freezing went pending with "Subject body changed; recover without overwriting it" and needed Recover twice. Cause: the Freeze skeleton hold's transfer lease reports `posed` under the key `freeze-bone-trial`, so the editor applied directly instead of taking the reset-and-settle path, and `tick_pose_editor` treated that key as a catalogue pose. Fixed in dev.2 (`self.pose_held()`, catalogue-only rebase), with fixture coverage.
- `Authored pose cape placement: writes=0` was logged once per frame while dragging (about 90 lines a second). Now logged only when something was written.
- Marker drag added at the user's request ("Let me grab the anchor to move it"): the ring previews Bend (x) and Swing (y), the wheel twists, release commits once.

### Proton live results

The LuaJIT/LLL build (branch `claude/wj-proton-bone-posing`, merged from this
branch; Arsenal profile "LuaJIT Proton", folder install in the LLL Mods folder).

- 2026-11-01 06:30 UTC: dev.5 (13c31aa) merged as 58a760f. Suite green under
  lupa Lua 5.1 with the four pose fixtures. `tools/build_proton_candidate.py`
  built `bone-posing-dev.1`: 77 modules (the 74 of 15c649b plus the three pose
  modules), version 1.3.4-proton. Proton keeps `node_frame`/`node_position` on
  the native adapter's `Unit.world_pose` matrix path; no FFI bone read was
  needed. dev.1 was never installed: the Mods folder held the Handycam
  ADS-entry build, which had to be kept.
- 2026-11-01 06:37-06:55 UTC: `claude/wj-handycam-ads-entry` merged, b68267b
  as 89975f0 and then its head ddcc613 as 114056b (b68267b alone never fired
  in game; a9bdecf and ddcc613 fix the guard and poll the ADS buttons).
  `bone-posing-dev.2` and `bone-posing-dev.3` were built but not installed:
  the game-exit watcher matched its own command line and never fired.
- 2026-11-02 04:11 UTC: `claude/wj-proton-slick` 9613fcf (Photo menu HUD font
  through the main bridge) merged as 3fc60e7, because the live folder carried
  that fix as an overlay. `bone-posing-dev.4` built: 77 modules, version
  1.3.4-proton, build 20261102.0411-3fc60e7, package sha256 cfd78957...;
  `font.lua`, `windows_handycam_ads.lua` and `windows_camera_signals.lua`
  byte-identical to the live overlay.
- 2026-11-02 04:12 UTC: dev.4 installed in the LLL Mods folder with the game
  closed (`dist/review/proton/INSTALL-RECEIPT-folder-3fc60e7-bone-posing-dev.4.json`).
  Previous folder moved to `Port-Candidate-Backups/war-journalist-proton-1.3.3-
  ddcc613-ads-entry-before-bone-posing-20261102T041244Z`; module audit passed
  77/77; `Settings/dbf_freecam` untouched. That previous folder also carried the
  uncommitted `wj-proton-aim-field` Handycam aim smoothing
  (`windows_aim_field.lua`, in no branch); it lives on only in that backup and
  in its worktree, so the aim lock is back to the committed 15c649b behaviour.
- 2026-11-02 04:25-04:46 UTC, user's dev.4 run: the Pose editor worked (rings,
  select, edits applied: "Freeze skeleton hold: released ... apply_frame" in the
  LLL log, no errors), but the left drag read as inverted, and the user asked
  for the drag to rotate the bone ("does not respect IK/FK") and for lines
  between the bones. Root cause of the inversion: menu space grows upward
  (steam_input flips the pointer, gizmos.project adds along camera up) while
  the marker negated dy. Change (2b70a92, shared modules, to be cherry-picked
  onto `claude/wj-bone-posing`): the left drag aims the bone at the pointer,
  turning the ring's parent bone by the smallest rotation (pose_editor.aim,
  decompose inverts compose), length kept; the wheel aims the ring deeper;
  every ring draws its bone as a thin quad to its parent (white for the
  selected one); only a parent inside the current group turns (the first ring
  of a group selects but never drags the body). Built as `bone-posing-dev.5`
  (77 modules, build 20261102.0447-2b70a92, package sha256 947e9aa9...).
  Installed 2026-11-02 05:08 UTC with the game closed
  (`INSTALL-RECEIPT-folder-1bf17de-bone-posing-dev.5.json`; previous folder at
  `Port-Candidate-Backups/war-journalist-proton-1.3.4-3fc60e7-before-bone-posing-dev.5-20261102T050828Z`;
  audit 77/77; Settings untouched). The Lua 5.1 line has the same change as
  595e813 (BML dev.6). Live acceptance of the new drag: pending the user's run.
