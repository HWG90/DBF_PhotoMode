-- Screenshots from the engine's own back-buffer writer, for hosts with neither LLL's capture
-- service nor the Linux host worker (Boot Mod Loader, native Windows included). No native
-- code: the engine writes DDS, so the file stays DDS. Its writer labels SDR BGRA bytes as
-- DXGI 28 (RGBA) and HDR RGB10A2 as 0; the header is corrected to 87 or 24 when the size
-- proves the layout. Not natively verified: call it only while Photo Mode renders a world.
local M={}
local function integer(s,o)local a,b,c,d=s:byte(o+1,o+4);if not d then return nil end;return a+b*256+c*65536+d*16777216 end
local function le32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
-- The pixel format this header should carry, or nil when it already reads right.
function M.corrected(header,size,hdr)
 if type(header)~='string'or#header<148 or header:sub(1,4)~='DDS 'or integer(header,4)~=124 or header:sub(85,88)~='DX10'then return nil,'Engine screenshot is not a DX10 DDS'end
 local width,height,format=integer(header,16),integer(header,12),integer(header,128)
 if not(width and width>0 and width<=16384 and height and height>0 and height<=16384)then return nil,'Engine screenshot dimensions invalid'end
 if size~=148+width*height*4 or integer(header,20)~=width*4 then return nil end
 if format==28 and hdr==false then return 87 end
 if format==0 and hdr==true then return 24 end
 return nil
end
function M.new(sr,output,fs)
 fs=fs or{open=io.open}
 if type(output)~='string'or output==''or type(sr.Application)~='table'or type(sr.Application.save_render_target)~='function'then return nil end
 output=output:gsub('[/\\]+$','')
 local self={version=1,output_directory=output,extension='dds',
  capabilities={async=true,game_window=false,format='dds',color_space='game',max_jobs=1}}
 local issued,current,count=nil,nil,0
 local function record(state,why)
  return{job_token=current.job_token,output_token=current.output_token,output_path=current.output_path,state=state,reason=why}
 end
 function self.new_job_token()count=count+1;issued='engine-shot:'..count;return issued end
 function self.request(intent)
  if type(intent)~='table'or not issued or intent.job_token~=issued then return nil,'Latest unused screenshot token required'end
  local name=intent.output_token
  if type(name)~='string'or#name>128 or not name:match('^War%-Journalist%-%w[%w_-]*%.dds$')or intent.output_path~=output..'/'..name then return nil,'Screenshot output identity differs'end
  local existing=fs.open(intent.output_path,'rb');if existing then existing:close();return nil,'Screenshot output already exists'end
  current={job_token=issued,output_token=name,output_path=intent.output_path};issued=nil
  -- Synchronous: the coordinator has already hidden our UI for its clean frames.
  local saved,why=pcall(sr.Application.save_render_target,'back_buffer',intent.output_path)
  if not saved then current.state,current.reason='failed',tostring(why);return record('failed',current.reason)end
  local file=fs.open(intent.output_path,'rb')
  if not file then current.state,current.reason='failed','The engine did not write the screenshot';return record('failed',current.reason)end
  local size=file:seek('end');file:seek('set',0);local header=file:read(148);file:close()
  local hdr_ok,hdr=pcall(sr.Application.render_setting,'hdr_enabled')
  local format,problem=M.corrected(header,size,hdr_ok and hdr)
  if problem then current.state,current.reason='failed',problem;return record('failed',problem)end
  if format then
   local patch=fs.open(intent.output_path,'r+b')
   if patch then patch:seek('set',128);patch:write(le32(format));patch:close()end
  end
  current.state='succeeded';return record('succeeded')
 end
 function self.status(job,output_token)
  assert(current and current.job_token==job and current.output_token==output_token,'Screenshot job identity differs')
  return record(current.state,current.reason)
 end
 function self.cancel(job,output_token)return true,self.status(job,output_token)end
 return self
end
return M
