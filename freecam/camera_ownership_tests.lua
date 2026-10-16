-- Photo owns only its local lifecycle lease; foreign mods are never inspected.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local function forbidden()error('Photo inspected or invoked an unrelated camera provider')end
local foreign=setmetatable({}, {__index=forbidden,__newindex=forbidden,__call=forbidden})
local update,render=function()error('Foreign update called')end,function()error('Foreign render called')end
local G=setmetatable({
 ActionCamCamera=foreign,update=update,render=render,
 package={loaded={['mods/actioncam/actioncam']=foreign}},
 debug={getupvalue=forbidden,setupvalue=forbidden},
}, {__index=forbidden,__newindex=forbidden})
-- Detect raw table reads as well as ordinary foreign field/callback access.
local env=setmetatable({
 rawget=function(t,k)if t==G then forbidden()end;return rawget(t,k)end,
 rawset=function(t,k,v)if t==G then forbidden()end;return rawset(t,k,v)end,
 pairs=function(t)if t==G then forbidden()end;return pairs(t)end,
 next=function(t,k)if t==G then forbidden()end;return next(t,k)end,
}, {__index=_G})
local factory=setfenv(assert(loadfile(root..'camera_ownership.lua')),env)()
local owner=factory.new(G,forbidden,forbidden)
assert(owner.available==true and owner.held==false and owner.refresh()==true)
assert(owner.wrap_update==nil and owner.set_priority==nil and owner.set_input_blocked==nil,
 'A local camera lease must expose no foreign callback or binding adapter')
assert(owner.acquire()==true and owner.held==true)
assert(owner.acquire()==true and owner.held==true,'Acquisition must be idempotent')
assert(owner.refresh()==true and owner.held==true)
assert(owner.dispose()==false and owner.held==true and owner.available==true,
 'Disposal must retain an active lease until its controller has cleaned up')
assert(owner.release()==true and owner.held==false)
assert(owner.release()==true and owner.held==false,'Release must be idempotent')
assert(owner.dispose()==true and owner.available==false and owner.held==false)
assert(owner.refresh()==false and owner.acquire()==false and owner.held==false,
 'A disposed owner cannot grant a new session')
assert(owner.release()==true and owner.dispose()==true,'Disposed cleanup must remain idempotent')
assert(rawget(G,'update')==update and rawget(G,'render')==render and rawget(G,'ActionCamCamera')==foreign,
 'A Photo lease must not mutate foreign globals or callbacks')

-- Neither load order nor an unavailable/malformed foreign API changes Photo.
for _,advertisement in ipairs({false,true,{api=999},foreign})do
 local environment=setmetatable({ActionCamCamera=advertisement},{__index=forbidden,__newindex=forbidden})
 local local_owner=factory.new(environment,forbidden)
 assert(local_owner.refresh()and local_owner.acquire()and local_owner.held)
 assert(local_owner.release()and local_owner.dispose())
end
local untouched=setmetatable({}, {__index=forbidden,__newindex=forbidden})
local first,second=factory.new(untouched),factory.new(untouched)
assert(first.acquire()and not second.held and second.available)
assert(second.acquire()and first.release()and second.held and not first.held)
assert(first.dispose()and second.refresh()and second.held,'Independent Photo lifetimes must remain independent')
assert(second.release()and second.dispose())
print('Local Photo camera lease: foreign globals/callbacks untouched, idempotent ownership, cleanup-before-dispose and independent lifetimes passed')
