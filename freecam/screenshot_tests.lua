local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local module=dofile(root..'screenshot.lua');local base=os.tmpname();os.remove(base)
local captures=0;local s=module.new({capture=function(path)captures=captures+1;local f=assert(io.open(path,'wb'));f:write('DDS ');f:close();return true end},function(_,png)local f=assert(io.open(png,'wb'));f:write('\137PNG\r\n\26\n');f:close();return true end,'.')
assert(s.request()and s.active());assert(not s.request());for _=1,11 do s.tick()end;assert(captures==0);assert(s.tick()and not s.active()and captures==1);os.remove(s.last_path)
assert(s.request());s.cancel();s.tick();assert(captures==1 and not s.active())
local failed=module.new({capture=function()return false,'Unsupported game build'end},function()error('Must not convert after failed capture')end,'.')
assert(failed.request());for _=1,11 do failed.tick()end;assert(failed.tick()==false and not failed.active())
print('Screenshots: clean frame delay, duplicate requests, cancellation, PNG signature and failure restore passed')
