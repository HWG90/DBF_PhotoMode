// Scoped client confinement for an existing WJ input lease; no input injection.
static HWND wj_clip_owner=nullptr;
static RECT wj_clip_before={},wj_clip_applied={};
static bool wj_clip_owned=false;
static bool wj_release_clip() {
 if(!wj_clip_owned)return true;
 RECT current;if(!GetClipCursor(&current))return false;
 if(EqualRect(&current,&wj_clip_applied)) {
  const RECT *restore=GetForegroundWindow()==wj_clip_owner?&wj_clip_before:nullptr;
  if(!ClipCursor(restore))return false;
 }
 wj_clip_owned=false;wj_clip_owner=nullptr;return true;
}
static int native_pointer_clip(lua_State *L) {
 const int active=(int)native_api.luaL_checkinteger(L,1);
 if(active!=0 && active!=1)return native_api.luaL_error(L,"Pointer confinement flag must be zero or one");
 if(!active){native_api.lua_pushboolean(L,wj_release_clip());return 1;}
 HWND owner=GetForegroundWindow();DWORD pid=0;
 if(owner)GetWindowThreadProcessId(owner,&pid);
 if(!owner || pid!=GetCurrentProcessId()) {
  wj_release_clip();native_api.lua_pushboolean(L,0);return 1;
 }
 RECT client,current;POINT a,b;
 if(!GetClientRect(owner,&client)||client.right<=client.left||client.bottom<=client.top||!GetClipCursor(&current)) {
  native_api.lua_pushboolean(L,0);return 1;
 }
 a={client.left,client.top};b={client.right,client.bottom};
 if(!ClientToScreen(owner,&a)||!ClientToScreen(owner,&b)){native_api.lua_pushboolean(L,0);return 1;}
 RECT target={a.x,a.y,b.x,b.y};
 if(wj_clip_owned && owner!=wj_clip_owner && !wj_release_clip()){native_api.lua_pushboolean(L,0);return 1;}
 if(!wj_clip_owned)wj_clip_before=current;
 if(!EqualRect(&current,&target) && !ClipCursor(&target)){native_api.lua_pushboolean(L,0);return 1;}
 wj_clip_owner=owner;wj_clip_applied=target;wj_clip_owned=true;
 RECT observed;native_api.lua_pushboolean(L,GetClipCursor(&observed)&&EqualRect(&observed,&target));return 1;
}
