local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local module=dofile(root..'screenshot.lua');local base=os.tmpname();os.remove(base)
local captures=0;local s=module.new({capture=function(path)captures=captures+1;local f=assert(io.open(path,'wb'));f:write('DDS ');f:close();return true,{color_encoding='hdr10-pq-bt2020',white_nits=203}end},function(_,png,metadata)assert(metadata.color_encoding=='hdr10-pq-bt2020'and metadata.white_nits==203,'Verified capture color metadata must reach the converter');local f=assert(io.open(png,'wb'));f:write('\137PNG\r\n\26\n');f:close();return true end,'.')
assert(s.request()and s.active());assert(not s.request());for _=1,11 do s.tick()end;assert(captures==0);assert(s.tick()and not s.active()and captures==1);os.remove(s.last_path)
assert(s.request());s.cancel();s.tick();assert(captures==1 and not s.active())
local failed=module.new({capture=function()return false,'Unsupported game build'end},function()error('Must not convert after failed capture')end,'.')
assert(failed.request());for _=1,11 do failed.tick()end;assert(failed.tick()==false and not failed.active())
-- Exercise the production native-converter routing without loading a DLL.
local previous_ffi=package.loaded.ffi;local conversions={}
local kernel={MultiByteToWideChar=function(_,_,value,_,out)return #value+1 end,CreateDirectoryW=function()return 1 end,GetLastError=function()return 0 end}
local native={PhotoDDSConvertColor=function(_,_,encoding,white)conversions[#conversions+1]={encoding,white};return 1 end}
package.loaded.ffi={cdef=function()end,new=function()return {}end,load=function(path)return path=='kernel32'and kernel or native end}
local convert=module.native_converter('fixture.dll','fixture-folder')
assert(convert('a.dds','a.png',{color_encoding='hdr10-pq-bt2020',white_nits=203}))
assert(convert('b.dds','b.png',{color_encoding='sdr'}));assert(convert('c.dds','c.png',nil))
assert(convert('d.dds','d.png',{color_encoding='sdr-bgra-engine'}))
package.loaded.ffi=previous_ffi
assert(conversions[1][1]==2 and conversions[1][2]==0,'Verified HDR10 must use fixed native SDR display conversion')
assert(conversions[2][1]==0 and conversions[3][1]==0,'SDR and absent metadata must retain original byte interpretation')
assert(conversions[4][1]==3 and conversions[4][2]==0,'Verified engine BGRA capture must use the narrow channel-order profile')
print('Screenshots: clean frame delay, duplicate requests, cancellation, PNG signature, failure restore and explicit native HDR/SDR converter routing passed')
