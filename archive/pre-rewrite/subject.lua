-- Renderer-only subject visibility. Backends must prove exact local ownership
-- and expose the actual mesh pass mask before any proper engine setter runs.
local M={}
function M.new(backend,log,reuse)
 if reuse then assert(type(reuse)=='table'and type(reuse.count)=='function'and reuse.count()==0 and not reuse.pending,'Subject refresh requires restored, idle ownership')end
 local self=reuse or{};self.status='Subject controls are waiting for a verified player';self.capabilities={};self.pending=false;self.available=false
 local owned={};local last_context;local identity;local queued;local desired;local refresh_elapsed=.5;local hold_elapsed=0
 log=log or function()end
 local function restore(record)
  local valid,why=backend.valid(record.part,record.mesh)
  if valid==false then return true end
  assert(valid==true,why or'Subject restore owner unavailable')
  local current=backend.read(record.part,record.mesh)
  if current~=record.written then return true end -- A different visibility writer owns its mask.
  backend.write(record.part,record.mesh,record.before~=0)
  assert(backend.read(record.part,record.mesh)==record.before,'Subject visibility restore readback failed')
  return true
 end
 function self.release()
  desired=nil;queued=nil;self.pending=false;hold_elapsed=0
  local failed={};local reason
  for key,record in pairs(owned)do
   local ok,why=pcall(restore,record)
   if not ok then failed[key]=record;reason=tostring(why)end
  end
  owned=failed
  if next(failed)then self.status='Subject restoration pending: '..reason;return false,reason end
  identity=nil;last_context=nil;return true
 end
 function self.ready()
  self.capabilities={}
  if not backend then return false,'Subject renderer backend unavailable' end
  local ok,context,why=pcall(backend.resolve)
  if not ok or not context then self.status=tostring(ok and why or context or 'Local subject unavailable');return false,self.status end
  assert(context.local_owner==true and context.identity and type(context.groups)=='table','Subject ownership proof required')
  for name,parts in pairs(context.groups)do
   local available=type(parts)=='table'and #parts>0;local total=0
   if available then
    for _,part in ipairs(parts)do
     if not backend.valid(part)then available=false;break end
     local count=part.mesh_count
     if type(count)~='number'or count<0 or count>512 or count%1~=0 then available=false;break end
     total=total+count
     for mesh=1,count do
      local mask=backend.read(part,mesh)
      if mask~=0 and mask~=255 then available=false;break end
     end
     if not available then break end
    end
   end
   self.capabilities[name]=available and total>0
  end
  last_context=context;self.status='Subject visibility ready';return true,self.status,self.capabilities,context
 end
 local function unchanged()
  if not last_context or not backend or type(backend.unchanged)~='function'then return false end
  local ok,value=pcall(backend.unchanged,last_context);return ok and value==true
 end
 function self.refresh(dt)
  refresh_elapsed=refresh_elapsed+math.max(.001,math.min(.1,tonumber(dt)or 0))
  if refresh_elapsed<.5 then return self.available,self.status,self.capabilities end
  refresh_elapsed=0
  if unchanged()then return self.available,self.status,self.capabilities end
  local called,ready,why,caps=pcall(self.ready)
  self.available=called and ready==true
  if not called then self.status='Subject controls unavailable: '..tostring(ready);self.capabilities={}
  elseif not ready then self.status=why end
  return self.available,self.status,caps or self.capabilities
 end
 function self.apply(options)
  local ok,_,_,context=self.ready();if not ok then return false,self.status end
  if identity and identity~=context.identity then local done,why=self.release();if not done then return false,why end end
  identity=context.identity
  local wanted={}
  for name,parts in pairs(context.groups)do
   if options[name]==true and self.capabilities[name]then
    for _,part in ipairs(parts)do
     for mesh=1,part.mesh_count do wanted[part.identity..':'..tostring(part.mesh_objects and part.mesh_objects[mesh]or mesh)]={part=part,mesh=mesh}end
    end
   end
  end
  -- Restore rows removed by a group change before hiding any newly selected rows.
  for key,record in pairs(owned)do
   if not wanted[key]then
    local done,why=pcall(restore,record);if not done then self.status='Subject restoration pending: '..tostring(why);return false,self.status end
    owned[key]=nil
   end
  end
  for key,row in pairs(wanted)do
   if not backend.valid(row.part)then return false,'Subject ownership changed' end
   if backend.owned and not backend.owned(row.part)then return false,'Subject attachment ownership changed'end
   local current=backend.read(row.part,row.mesh);local previous=owned[key]
   if previous then
    if current~=previous.written then return false,'Subject visibility changed by another owner' end
    previous.part=row.part;previous.mesh=row.mesh
   elseif current==255 then
    local record={part=row.part,mesh=row.mesh,before=current,written=0};owned[key]=record
    local done,why=pcall(backend.write,row.part,row.mesh,false)
    if not done then self.status='Subject visibility refused: '..tostring(why);return false,self.status end
    if backend.read(row.part,row.mesh)~=0 then self.status='Subject visibility readback failed';return false,self.status end
   end -- Already invisible meshes keep their original owner and are never made visible.
  end
  self.status=next(owned)and 'Selected subject parts hidden'or'Subject visibility restored';return true
 end
 function self.queue(options)
  if options~=nil and type(options)~='table'then return false,'Invalid subject visibility options'end
  queued={};for key,value in pairs(options or{})do queued[key]=value==true end
  if options==nil then queued.release=true end
  self.pending=true;return true
 end
 function self.flush(dt)
  -- SDK mesh setters run from the owning update hook, never the menu callback.
  if self.pending then
   local request=queued;queued=nil;self.pending=false
   if request.release then desired=nil;return self.release()end
   refresh_elapsed=.5;hold_elapsed=0;local ok,why=self.apply(request);desired=request;return ok,why
  end
  local hiding=false;for _,value in pairs(desired or{})do if value==true then hiding=true;break end end
  if hiding then
   -- Capability polling must not reset the update-time attachment refresh.
   -- A new mesh can appear even when every original mesh was already hidden.
   hold_elapsed=hold_elapsed+math.max(.001,math.min(.1,tonumber(dt)or 0))
   if hold_elapsed>=.5 then hold_elapsed=0;if unchanged()then return true end;local request=desired;local ok,why=self.apply(request);desired=request;return ok,why end
  end
  return true
 end
 function self.count()local count=0;for _ in pairs(owned)do count=count+1 end;return count end
 return self
end
return M
