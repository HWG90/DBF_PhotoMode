-- Read-only diagnostics for hosts where the subject and hover-pause bridges fail (Boot Mod
-- Loader): which of the game pages those features read the bridge can read, and where the
-- engine bindings they check point. Reads only; calls no engine function it inspects.
local M={}
-- The pages subject/hover/scene read first, as offsets into their module.
M.probes={{'exe','header',0},{'exe','text',0x1000},{'exe','set_mesh_visibility',0x3f4c80},{'exe','mesh_layout',0x51fe50},
 {'exe','unit_registry',0xa06b0},{'exe','save_render_target',0x3da140},
 {'game','header',0},{'game','hover_control',0x9c6420},{'game','hover_jump',0x9c6942},{'game','hover_height',0x9c6a97}}
M.bindings={{'Unit','set_mesh_visibility',0x3f4c80},{'World','units'},{'Application','time_since_launch'},{'Application','save_render_target',0x3da140}}
local function hex(n)return type(n)=='number'and string.format('0x%X',n)or tostring(n)end
local function word64(s)
 if type(s)~='string'or#s<8 then return nil end
 local n=0;for i=8,1,-1 do n=n*256+s:byte(i)end;return n
end
-- The gameplay HUD as the HUD lease sees it (scene 3 is the ship, 4 a mission), for finding
-- what the game's own Toggle HUD key changes. Reads only.
function M.hud(bridge)
 local game=bridge.module_base('game.dll')
 local function read(at,n)local ok,s=pcall(bridge.read_memory,at,n);if ok and type(s)=='string'and#s==n then return s end end
 local function word(at)local s=read(at,4);return s and s:byte(1)+s:byte(2)*256+s:byte(3)*65536+s:byte(4)*16777216 end
 local function ptr(at)local s=read(at,8);local v=s and word64(s);return v and v>=65536 and v<2^47 and v or nil end
 local state=type(game)=='number'and ptr(game+0x2ce1508);local root=type(game)=='number'and ptr(game+0x2e28788)
 if not root then return'scene '..tostring(state and word(state+0xac29c))..', HUD root unreadable'end
 local widget,panel=root+0x820,root+0x24e340+0x146940
 local flags,panel_flags,near=word(widget),word(panel),read(root+0x24e330,16)
 return string.format('scene %s, hud flag %s, tree %s, widget flags %s (visible %s), panel flags %s (visible %s), root+0x24E330 %s',
  tostring(state and word(state+0xac29c)),near and tostring(near:byte(5))or'?',ptr(widget+0xf0)==root+0x258 and ptr(panel+0xf0)==widget and'ok'or'differs',
  hex(flags),flags and tostring(math.floor(flags/16)%2)or'?',hex(panel_flags),panel_flags and tostring(math.floor(panel_flags/16)%2)or'?',
  near and(near:gsub('.',function(c)return string.format('%02X',c:byte())end))or'unreadable')
end
-- A Lua 5.1 function's GC object address, as tostring prints it.
function M.closure(f)local s=tostring(f):match('^function: ?(%x+)$')or tostring(f):match('^function: 0x(%x+)$');return s and tonumber(s,16)end
function M.run(sr,host_native,log,label)
 local opened,bridge=pcall(host_native.open)
 if not opened then log('Native diagnostics ('..label..'): bridge unavailable: '..tostring(bridge));return end
 local bases={}
 for _,name in ipairs({'exe','game'})do
  local ok,base=pcall(bridge.module_base,name=='exe'and'helldivers2.exe'or'game.dll');bases[name]=ok and type(base)=='number'and base or nil
 end
 local function read(at,n)
  if type(at)~='number'then return nil,'no address'end
  local ok,s=pcall(bridge.read_memory,at,n);if ok and type(s)=='string'and#s==n then return s end
  return nil,tostring(s)
 end
 local pages={}
 for _,p in ipairs(M.probes)do
  local s=bases[p[1]]and read(bases[p[1]]+p[3],8)
  pages[#pages+1]=p[1]..'.'..p[2]..(s and'=ok'or'=refused')
 end
 log('Native diagnostics ('..label..'): exe '..hex(bases.exe)..', game '..hex(bases.game)..'; '..table.concat(pages,' '))
 for _,b in ipairs(M.bindings)do
  local t=sr[b[1]];local f=type(t)=='table'and t[b[2]]
  local parts={b[1]..'.'..b[2]..': '..type(f)}
  if type(f)=='function'then
   local info=debug and debug.getinfo and debug.getinfo(f,'S');parts[#parts+1]='what='..tostring(info and info.what)
   local closure=M.closure(f);local entry=closure and word64((read(closure+0x20,8)))
   parts[#parts+1]='closure='..hex(closure)
   if entry and entry>=65536 then
    local rva=bases.exe and entry>=bases.exe and entry<bases.exe+0x10000000 and entry-bases.exe
    parts[#parts+1]='entry='..(rva and('exe+'..hex(rva))or hex(entry))..(b[3]and(rva==b[3]and' (expected)'or' (expected exe+'..hex(b[3])..')')or'')
    parts[#parts+1]='entry page '..(read(entry,8)and'readable'or'refused')
   else parts[#parts+1]='entry unreadable' end
   local ok,address=pcall(bridge.function_address,f)
   parts[#parts+1]='function_address '..(ok and('= '..hex(address))or('failed: '..tostring(address)))
  end
  log('Native diagnostics ('..label..'): '..table.concat(parts,', '))
 end
end
return M
