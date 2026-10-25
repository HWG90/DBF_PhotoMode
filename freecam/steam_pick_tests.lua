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
   assert(index==1 and u.alive and u.items>0,'Transform read must follow alive and scene-graph checks')
   transform_reads=transform_reads+1;return vec(u.pos)
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
-- Far Helldiver slightly right of centre: x offset .2 at 20 m.
units={unit('Helldiver',20,-.2,-.9,{resource='helldiver'})}
local sx=960+(.2/20)/1*540
hit=assert(picker.pick(camera,sx,540,1920,1080,48))
assert(hit.helldiver and hit.label=='Helldiver'and hit.unit==units[1])
assert(not picker.pick(camera,100,100,1920,1080,48),'A click away from every character picks nothing')
units={unit('#ID[ef3a4136b21592cb]',10,0,-.9)}
assert(assert(picker.pick(camera,960,540,1920,1080,48)).label=='Character','Hashed debug names fall back to a plain label')
type=real_type
print('Scene picking: guarded unit reads, projection, nearest choice, Helldiver detection and empty clicks passed')
