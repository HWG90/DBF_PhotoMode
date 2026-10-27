-- Scene picking: guard order, projection, nearest/closest choice. No game access.
local M=dofile('freecam/steam_pick.lua')
local transform_reads=0
local function unit(name,x,y,z,opts)
 opts=opts or{};return{name=name,pos={x,y,z},alive=opts.alive~=false,items=opts.items or 40,animated=opts.animated~=false,resource=opts.resource or'enemy'}
end
local units={}
local function vec(p)return{p=p}end
local sr={Application={main_world=function()return'world'end},
 World={units=function(world)assert(world=='world');local out={};for i,u in ipairs(units)do out[i]=u end;return out end},
 Unit={alive=function(u)return u.alive end,num_scene_graph_items=function(u)assert(u.alive,'Scene graph read on a dead unit');return u.items end,
  has_animation_state_machine=function(u)assert(u.items>0);return u.animated end,
  world_position=function(u,index)
   assert(u.alive and index>=1 and index<=u.items and(index==1 or u.nodes and u.nodes[index]),'Transform read must follow alive, scene-graph and named-node checks')
   transform_reads=transform_reads+1;return vec(index==1 and u.pos or u.nodes[index])
  end,
  resource_name=function(u)return u.resource end,debug_name=function(u)return u.name end},
 IdString64={from_hex=function(hex)return hex=='4d1c334d294dfa97'and'helldiver'or hex end,equal=function(a,b)return a==b end},
 Vector3={x=function(v)return v.p[1]end,y=function(v)return v.p[2]end,z=function(v)return v.p[3]end}}
-- The picker only accepts userdata handles; fixture tables stand in for them.
local real_type=type
type=function(v)if real_type(v)=='table'and v.pos then return'userdata'end;return real_type(v)end
local picker=M.new(sr)
-- Camera at the origin looking along +x, z up; 90 degree vertical FOV.
local camera={pos={0,0,0},forward={1,0,0},up={0,0,1},fov=math.pi/2}
units={unit('Charger',10,0,-.9),unit('Corpse',10,1,-.9,{items=0}),unit('Gone',10,0,-.9,{alive=false}),
 unit('Prop',10,0,-.9,{animated=false}),unit('Behind',-10,0,0),unit('Helldiver',20,-.2,-.9,{resource='helldiver'})}
-- Screen centre of 1920x1080 maps to straight ahead; the waist point of the
-- Charger (z=0) projects there.
local hit=assert(picker.pick(camera,960,540,1920,1080,48))
assert(hit.label=='Charger'and not hit.helldiver and math.abs(hit.distance-10)<.01,'Nearest centred character wins')
assert(transform_reads==3,'Only alive, scene-graph, animated units are read: '..transform_reads)
local audit={};hit=assert(picker.pick(camera,960,540,1920,1080,48,10,audit))
assert(audit.candidates==1 and audit.geometry=='upright-capsule'and audit.resource=='enemy')
assert(audit.surface[1]==10 and audit.center[1]==10 and audit.score==0,'Audit records the actual selected geometry without another scene scan')
-- Far Helldiver slightly right of centre: x offset .2 at 20 m.
units={unit('Helldiver',20,-.2,-.9,{resource='helldiver'})}
local sx=960+(.2/20)/1*540
hit=assert(picker.pick(camera,sx,540,1920,1080,48))
assert(hit.helldiver and hit.label=='Helldiver'and hit.unit==units[1])
assert(not picker.pick(camera,100,100,1920,1080,48),'A click away from every character picks nothing')
units={unit('#ID[ef3a4136b21592cb]',10,0,-.9)}
assert(assert(picker.pick(camera,960,540,1920,1080,48)).label=='Character','Hashed debug names fall back to a plain label')

-- A centered distant root must not beat the actual clicked surface.
units={unit('Far',3000,0,-.9),unit('Near',1.2,-.15,-.9,{resource='helldiver'})}
hit=assert(picker.pick(camera,960,540,1920,1080,48,.708))
assert(hit.unit==units[2]and hit.distance==.708,'Use visible surface depth, not a 3 km projected root')
units={unit('Occluded',20,0,-.9)}
assert(not picker.pick(camera,960,540,1920,1080,48,2),'Foreground surface excludes a hidden character')
assert(not picker.pick(camera,960,540,1920,1080,48,0/0),'Invalid depth must refuse selection')
-- Continuous torso segments remove gaps between feet/waist/head samples.
units={unit('Near torso',1,0,0,{resource='helldiver'})}
hit=assert(picker.pick(camera,960,540+.45*540,1920,1080,24,.8))
assert(hit.unit==units[1],'Torso between old sample points is clickable')
-- Exercise actual authored names/indices rather than an invented second rig.
local rig=dofile('freecam/assets/subject_pose_frames.lua').rig
assert(rig.resource=='4d1c334d294dfa97'and rig.node_count==107)
local indices={};for index,node in pairs(rig.nodes)do if node.name then indices[node.name]=index end end
local posed=unit('Prone Helldiver',10,0,0,{items=107,resource='helldiver'});posed.nodes={}
local positions={hips={10,.8,0},chest={10,1.4,0},head={10,1.9,0},
 l_shoulder={10,1.4,.2},l_elbow={10,1.9,.3},l_hand={10,2.5,.4},
 r_shoulder={10,1.4,-.2},r_elbow={10,1.9,-.3},r_hand={10,2.5,-.4},
 l_thigh={10,.7,.2},l_knee={10,.3,.2},l_foot={10,-.1,.2},
 r_thigh={10,.7,-.2},r_knee={10,.3,-.2},r_foot={10,-.1,-.2}}
local joint_count=0;for name,point in pairs(positions)do assert(indices[name],name);posed.nodes[indices[name]]=point;joint_count=joint_count+1 end
assert(joint_count==15)
local missing,invalid,throwing
sr.Unit.has_node=function(u,name)assert(u.alive and u.items==107);return name~=missing and indices[name]~=nil end
sr.Unit.node=function(u,name)assert(u.alive and name~=missing);if name==throwing then error('Retired joint')end;return name==invalid and 108 or indices[name]end
units={posed}
local function at(y,z,depth)return picker.pick(camera,960-y/10*540,540+z/10*540,1920,1080,24,depth or 10)end
local before_reads=transform_reads
hit=assert(at(1.9,0));assert(hit.unit==posed and hit.helldiver,'Prone head outside the upright proxy must be selectable')
assert(transform_reads-before_reads==16,'One click reads only the root and fifteen current body joints')
audit={};assert(picker.pick(camera,960-1.9/10*540,540,1920,1080,24,10,audit))
assert(audit.geometry=='body-joints'and audit.candidates==1 and audit.resource=='helldiver')
-- An animated attachment's upright proxy can be perfectly centered while
-- the clicked surface is slightly off a body joint. The precise body must
-- win in either enumeration order, even without diagnostic collection.
local proxy=unit('Animated render part',10,1.9,-.8)
units={proxy,posed}
hit=assert(at(1.9,.1));assert(hit.unit==posed,'A centered generic proxy must not steal a confirmed body hit')
units={posed,proxy}
hit=assert(at(1.9,.1));assert(hit.unit==posed,'Body preference must not depend on enumeration order')
audit={};assert(picker.pick(camera,960-1.9/10*540,540+.1/10*540,1920,1080,24,10,audit))
assert(audit.candidates==2 and #audit.hits==2 and audit.geometry=='body-joints','Record both competing hit geometries in the one-shot audit')
proxy.pos={5,.95,-.85}
hit=assert(at(1.9,.1,5));assert(hit.unit==proxy,'A foreground character still wins when depth excludes the Helldiver')
units={posed}
assert(assert(at(2.3,.36)).unit==posed,'Extended forearm between joints must be selectable')
assert(not at(0,.9),'Empty space in the former upright torso must not select a prone body')
assert(not at(1.9,0,5),'Foreground depth must exclude a posed character behind it')
for _,point in pairs(posed.nodes)do point[2]=point[2]+4 end
assert(not at(1.9,0),'A later click must not reuse an earlier pose')
assert(assert(at(5.9,0)).unit==posed,'Fresh joint positions must follow the changed pose')
missing='head';assert(not at(5.9,0),'Incomplete known rig refuses instead of reviving the upright proxy');missing=nil
invalid='head';assert(not at(5.9,0),'Out-of-range named index refuses before transform access');invalid=nil
throwing='head';assert(not at(5.9,0),'Retired node getter remains a refused selection');throwing=nil
posed.alive=false;before_reads=transform_reads;assert(not at(5.9,0)and transform_reads==before_reads,'Dead posed units perform no transform reads')

type=real_type
print('Scene picking: guarded unit reads, projection, nearest choice, Helldiver detection and empty clicks passed')
