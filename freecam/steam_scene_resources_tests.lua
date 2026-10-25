local M=dofile('freecam/steam_scene_resources.lua');local bytes={};local calls=0
local exe=0x140000000;local app,renderer,backend,array,resource_rows,cache_rows,manager,templates,settings,schema=0x100000,0x200000,0x300000,0x400000,0x500000,0x600000,0x700000,0x800000,0x900000,0xa00000
local resources={0xb00000,0xb00100,0xb00200};local backing={0xc00000,0xc00100,0xc00200};local hashes={0x9b8038e0,0xa68c78a4,0x2b269c03}
local function raw(at,s)for i=1,#s do bytes[at+i-1]=s:byte(i)end end
local function number(at,n,size)local s={};for i=1,size do s[i]=string.char(n%256);n=math.floor(n/256)end;raw(at,table.concat(s))end
local function zero(at,n)raw(at,string.rep('\0',n))end
local function ptr(at,n)number(at,n,8)end
local function word(at,n)number(at,n,4)end
word(exe+60,128);word(exe+128+8,0x6ad78c0d);ptr(exe+0x24099e8,app);ptr(app+0x338,renderer)
raw(exe+0x103d4d,'\139\133\144\004\000\000');raw(exe+0x103d5c,'\072\139\133\128\004\000\000');raw(exe+0x3d417a,'\072\139\013\063\055\110\001')
word(renderer+0x1790,3);ptr(renderer+0x1798,resource_rows);ptr(renderer+0x1168,backend);ptr(backend+0x480,array);word(backend+0x490,0);word(array,3);ptr(array+8,cache_rows)
for i=1,3 do
 local a=resource_rows+(i-1)*32;zero(a,32);word(a,hashes[i]);ptr(a+8,resources[i]);word(a+24,0x7fffffff)
 a=cache_rows+(i-1)*24;zero(a,24);ptr(a,resources[i]);ptr(a+8,backing[i]);word(a+16,0x7fffffff)
 a=backing[i];zero(a,36);word(a,(i==3 and 4 or 2)*16777216+i);word(a+8,({1,19,0})[i]);word(a+20,1920);word(a+24,1080);word(a+28,1);word(a+32,1)
end
ptr(renderer+0x1208,manager);word(manager+0x100,2);word(manager+0x104,2);word(manager+0x11c,1);ptr(manager+0x108,templates)
zero(templates,64);word(templates,0x9fcfe126);ptr(templates+8,0xd00000);word(templates+24,1);word(templates+32,0x217cc71f);ptr(templates+40,0xd00100);word(templates+56,0x7fffffff)
ptr(exe+0x1ab78c0,settings);word(settings,2);ptr(settings+8,schema);zero(schema,48);word(schema,4);word(schema+16,0xbf7ef641);word(schema+24,1);word(schema+40,0x3f5fea89)
local sr={Renderer={resource=function(name)assert(name=='linear_depth');calls=calls+1;return resources[1]end},Application={render_setting=function(name)return name=='hdr_enabled'and false or 200 end}}
-- The boolean setting must preserve false, without Lua's and/or conversion.
sr.Application.render_setting=function(name)if name=='hdr_enabled'then return false end;return 200 end
local memory={exe=exe,read=function(at,n)local s={};for i=0,n-1 do local value=assert(bytes[at+i],'Unreadable test memory');s[#s+1]=string.char(value)end;return table.concat(s)end,
 function_address=function(f)if f==sr.Renderer.resource then return exe+0x3f9450 end;return exe+0x3d43b0 end}
local r=M.new(sr,memory,{userdata_address=function(v)return v end})
assert(r.registered());local ok,color=r.color();assert(ok and color.format==19 and color.hdr_enabled==false and color.ui_brightness==200)
assert(r.depth.get()==resources[1]and calls==1)
word(resource_rows+24,0xfffffffe);assert(not r.depth.available());assert(not pcall(r.depth.get)and calls==1,'Missing resource called inserting SDK getter');word(resource_rows+24,0x7fffffff)
ptr(cache_rows+24+8,backing[3]);assert(not pcall(r.color),'Scene color accepted display alias');ptr(cache_rows+24+8,backing[2])
bytes[cache_rows]=nil;assert(not r.depth.available(),'Unknown cache read accepted')
print('Ordinary Lua renderer guards: registered surfaces, false HDR schema, no missing-target insertion, display alias refusal and unknown-read refusal passed')
