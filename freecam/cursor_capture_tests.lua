local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local B=dofile(root..'cursor_capture_backend.lua');local C=dofile(root..'cursor_capture.lua')
local function copy(r)return r and{r[1],r[2],r[3],r[4]}end
local desktop={-1920,0,3840,2160};local clipped=copy(desktop);local current=101;local process=77;local owners={[101]=77,[202]=88,[303]=77};local live={[101]=true,[202]=true,[303]=true}
local clients={[101]={0,0,1280,720},[303]={0,0,640,480}};local origins={[101]={100,50},[303]={-1900,100}}
local writes={};local client_reads=0;local fail_pid=false;local fail_clip=false;local fail_set=false;local fail_after=false;local race=false
local api={current_pid=function()return process end,foreground=function()return current end,
 valid_window=function(h)return live[h]==true end,pid=function(h)if fail_pid then error('PID read failed')end;return owners[h]end,
 client=function(h)client_reads=client_reads+1;assert(owners[h]==process,'Queried another app client');return copy(clients[h])end,
 to_screen=function(h,x,y)return x+origins[h][1],y+origins[h][2]end,
 get_clip=function()if fail_clip then error('Clip read failed')end;if race then race=false;clipped={1,2,301,402}end;return copy(clipped)end,
 set_clip=function(r)if fail_set then return false end;writes[#writes+1]=r and copy(r)or false;clipped=r and copy(r)or copy(desktop);if fail_after then fail_after=false;fail_clip=true end;return true end}
local backend=B.new(api);local capture=C.new(backend)
assert(capture.tick(false)and#writes==0,'Inactive instance touched shared clipping')
current=202;local before=client_reads;assert(capture.tick(true)and#writes==0 and client_reads==before,'Another process was captured or queried')
current=101;assert(capture.tick(true));assert(B.equal(clipped,{100,50,1380,770})and capture.active and#writes==1,'Client-to-screen confinement incorrect')
local state=capture.state();assert(B.equal(state.prior,desktop));state.prior[1]=999;assert(capture.state().prior[1]==desktop[1],'State getter leaked the clip lease')
local count=#writes;assert(capture.tick(true)and#writes==count,'Stable rectangle was rewritten each frame')
clients[101]={0,0,1600,900};assert(capture.tick(true)and B.equal(clipped,{100,50,1700,950})and#writes==count+1,'Resize did not update confinement')
-- A Core setter can already apply the freshly resized client rectangle.
clients[101]={0,0,1500,800};clipped={100,50,1600,850};count=#writes
assert(capture.tick(true)and capture.active and#writes==count,'Coordinated Core resize was treated as a foreign writer')
assert(capture.tick(false)and B.equal(clipped,desktop),'Photo exit did not restore prior rectangle')
assert(capture.tick(true));count=#writes;current=202;before=client_reads
assert(capture.tick(true)and not capture.active and B.equal(clipped,desktop)and writes[#writes]==false and#writes==count+1 and client_reads==before,'AltTab kept confinement or queried another app')
current=101;assert(capture.tick(true));local foreign={300,200,700,600};clipped=copy(foreign);count=#writes
assert(not capture.tick(true)and capture.state().yielded and#writes==count,'Foreign clip was overwritten')
assert(capture.tick(true)and#writes==count,'Yielded capture fought the foreign writer')
assert(capture.tick(false)and B.equal(clipped,foreign)and#writes==count,'Inactive cleanup changed foreign clipping')
-- Explicit cooperative handoff releases first, then captures a fresh baseline.
assert(capture.tick(true));assert(capture.suspend());assert(B.equal(clipped,foreign));clipped=copy(desktop);count=#writes
assert(capture.tick(true)and#writes==count,'Suspended capture wrote during handoff')
assert(capture.resume()and capture.tick(true));assert(capture.tick(false)and B.equal(clipped,desktop))
assert(capture.tick(true));count=#writes;fail_pid=true
assert(not capture.tick(true)and#writes==count and capture.state().window==101,'Uncertain window error wrote or abandoned the lease')
assert(not capture.release()and#writes==count and capture.pending,'Window read error released another app or lost retry state');fail_pid=false
fail_clip=true;assert(not capture.release()and capture.pending and#writes==count,'Clip read error wrote shared state');fail_clip=false
fail_set=true;assert(not capture.release()and capture.pending and#writes==count,'Restore failure lost ownership');fail_set=false
assert(capture.release()and B.equal(clipped,desktop))
-- A rejected initial write never owns the prior (possibly foreign) rectangle.
clipped=copy(foreign);fail_set=true;count=#writes;assert(not capture.tick(true)and capture.state().window==nil);current=202
assert(capture.release()and#writes==count and B.equal(clipped,foreign),'Failed acquisition released an unowned clip');fail_set=false;current=101;clipped=copy(desktop)
assert(capture.tick(true));fail_after=true;assert(not capture.release()and capture.pending,'Committed restoration/readback failure lost retry state')
count=#writes;fail_clip=false;assert(capture.release()and#writes==count and not capture.pending and B.equal(clipped,desktop),'Committed restoration was not acknowledged without another write')
-- No capture survives its window, including a foreground replacement window.
assert(capture.tick(true));live[101]=false;count=#writes
assert(capture.tick(true)and not capture.active and writes[#writes]==false and#writes==count+1,'Retired window kept capture');live[101]=true
assert(capture.tick(true));current=303;assert(capture.tick(true)and capture.state().window==303 and B.equal(clipped,{-1900,100,-1260,580}),'Own-process replacement window was not revalidated')
assert(capture.release());current=101;clipped=copy(desktop)
local candidate=assert(backend.window());race=true;count=#writes
assert(not backend.write(candidate.rect,desktop,candidate.window)and#writes==count and B.equal(clipped,{1,2,301,402}),'Clip compare/write race overwrote a foreign writer')
-- Initial confinement already supplied by Core is still claimed exactly once.
clipped=copy(candidate.rect);assert(capture.tick(true));count=#writes;assert(capture.tick(true)and#writes==count);current=202
assert(capture.tick(true)and writes[#writes]==false and B.equal(clipped,desktop),'Preexisting client confinement trapped another app after focus loss')
assert(not B.valid({0,0,0,10})and not B.valid({0/0,0,100,100})and not B.valid({0,0,100.5,100}),'Malformed clip rectangle accepted')
print('Photo cursor: same-process foreground client bounds, one lease/readback, resize/Core adoption, AltTab/retirement, foreign writers, explicit handoff, conditional restoration/retry, failed acquisition, committed-readback and compare/write races passed; no cursor warp or native calls')
