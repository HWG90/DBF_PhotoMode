-- Session-local numeric bookmark. Identity is the rendered camera attachment;
-- no player discovery, engine vectors, or native pointers are retained here.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e8 end
local function vec(v)return type(v)=='table'and finite(v[1])and finite(v[2])and finite(v[3])end
local function distance(a,b)local n=0;for i=1,3 do n=n+(a[i]-b[i])^2 end;return math.sqrt(n)end
function M.new()
 local self={};local saved;local reason;local meters
 function self.clear(why)saved=nil;meters=nil;reason=why;return true end
 function self.save(context,photo,options,radius)
  if not context or not context.world or not context.unit or not vec(context.position)or not photo or not vec(photo.pos)or not vec(photo.forward)or not vec(photo.right)then return false,'Start Photo Mode and place the camera first'end
  if not finite(radius)or radius<=0 or not options or not finite(options.roll)or not finite(options.fov)then return false,'Invalid camera bookmark settings'end
  local d=distance(context.position,photo.pos)
  if d>radius then return false,'Camera is outside the saved-camera radius'end
  local function copy(v)return{v[1],v[2],v[3]}end
  saved={world=context.world,unit=context.unit,pos=copy(photo.pos),forward=copy(photo.forward),right=copy(photo.right),roll=options.roll,fov=options.fov}
  reason=nil;meters=d;return true
 end
 function self.restore(context,radius,handle)
  if not saved then return end
  if not context or not vec(context.position)then return nil,'Camera attachment unavailable'end
  if context.world~=saved.world or context.unit~=saved.unit then self.clear('camera or scene changed');return end
  meters=distance(context.position,saved.pos)
  if not finite(radius)or radius<=0 or meters>radius then self.clear('outside retention radius');return end
  local ok,why=handle.set_many({roll=saved.roll,fov=saved.fov})
  if ok==false then return nil,why or'Saved lens settings refused'end
  local function copy(v)return{v[1],v[2],v[3]}end
  return{pos=copy(saved.pos),forward=copy(saved.forward),right=copy(saved.right)}
 end
 function self.status()
  if saved then return string.format('Saved camera: %.1f m',meters)end
  return reason and'Saved camera cleared: '..reason or'Saved camera: none'
 end
 return self
end
return M
