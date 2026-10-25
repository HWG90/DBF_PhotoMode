// In-game keyboard lease for hosts without LLL's helper process (Boot Mod Loader). It is
// LLL's RegisterHotKey reservation (lll/native/steam_keyboard.c), run on our own thread
// with a message-only window: keys it holds never reach the game, and their physical
// state is read with GetAsyncKeyState. It arms only once none of them is held, ends when
// the foreground window changes, and lapses 2 s after the last sample, so a stalled
// caller can never leave the keyboard reserved. No hooks into the game, no injected input.
// Included by nativeinfo.cc.
enum {WJ_KB_ARMING=1,WJ_KB_ACTIVE=2,WJ_KB_REVOKED=3,WJ_KB_CLOSING=4,WJ_KB_FAILED=5};
static const uint32_t wj_kb_allowed[8]={0x081f3300u,0x03ffe1ffu,0x27fffffeu,0xf7ffffffu,0x000300ffu,0xfc00003fu,0xf8000001u,0x00000004u};
static const DWORD wj_kb_arm_ms=2000,wj_kb_register_ms=1000,wj_kb_ttl_ms=2000;
struct WjKeyboard{HANDLE thread,stop;HWND target,window;HWINEVENTHOOK hook;uint32_t mask[8],state,terminal,generation;ULONGLONG started,heartbeat;int ids[2048];unsigned count;bool unclean;};
static WjKeyboard wj_kb={};static SRWLOCK wj_kb_lock=SRWLOCK_INIT;static uint32_t wj_kb_generations=0;
static bool wj_kb_bit(const uint32_t m[8],unsigned key){return (m[key>>5]>>(key&31))&1u;}
// The same tuples LLL reserves: side modifiers alias the generic key, and the OS's own
// Alt+Tab/Esc/F4/Enter/Space, Ctrl+Esc and Ctrl+Alt+Delete combinations stay free.
static bool wj_kb_tuple(unsigned key,unsigned mods){
 if(key>=160&&key<=165)return false;
 if((mods&MOD_ALT)&&(key==VK_TAB||key==VK_ESCAPE||key==VK_F4||key==VK_RETURN||key==VK_SPACE))return false;
 if((mods&MOD_CONTROL)&&key==VK_ESCAPE)return false;
 if((mods&(MOD_CONTROL|MOD_ALT))==(MOD_CONTROL|MOD_ALT)&&key==VK_DELETE)return false;
 return true;
}
static unsigned wj_kb_mods(unsigned i){return ((i&1)?MOD_SHIFT:0u)|((i&2)?MOD_CONTROL:0u)|((i&4)?MOD_ALT:0u);}
static bool wj_kb_mask_valid(const uint32_t m[8]){
 uint32_t any=0;static const unsigned groups[3][3]={{16,160,161},{17,162,163},{18,164,165}};
 for(int i=0;i<8;i++){if(m[i]&~wj_kb_allowed[i])return false;any|=m[i];}
 if(!any)return false;
 for(auto &g:groups){int bits=wj_kb_bit(m,g[0])+wj_kb_bit(m,g[1])+wj_kb_bit(m,g[2]);if(bits&&bits!=3)return false;}
 return true;
}
static bool wj_kb_held(){for(unsigned k=0;k<256;k++)if(wj_kb_bit(wj_kb.mask,k)&&(GetAsyncKeyState(static_cast<int>(k))&0x8000))return true;return false;}
static bool wj_kb_foreground(HWND target){
 HWND window=GetForegroundWindow();DWORD pid=0;
 if(!window||window!=target||!IsWindowVisible(window))return false;
 GetWindowThreadProcessId(window,&pid);return pid==GetCurrentProcessId();
}
static uint32_t wj_kb_state(){AcquireSRWLockShared(&wj_kb_lock);const uint32_t s=wj_kb.state;ReleaseSRWLockShared(&wj_kb_lock);return s;}
static void wj_kb_stop(uint32_t terminal){
 AcquireSRWLockExclusive(&wj_kb_lock);
 if(wj_kb.state==WJ_KB_ARMING||wj_kb.state==WJ_KB_ACTIVE){wj_kb.state=WJ_KB_CLOSING;wj_kb.terminal=terminal;}
 ReleaseSRWLockExclusive(&wj_kb_lock);
 if(wj_kb.stop)SetEvent(wj_kb.stop);
}
static LRESULT CALLBACK wj_kb_proc(HWND window,UINT message,WPARAM wp,LPARAM lp){
 if(message==WM_HOTKEY)return 0;
 return DefWindowProcW(window,message,wp,lp);
}
static void CALLBACK wj_kb_foreground_event(HWINEVENTHOOK,DWORD event,HWND window,LONG,LONG,DWORD,DWORD){
 if(event==EVENT_SYSTEM_FOREGROUND&&window!=wj_kb.target)wj_kb_stop(WJ_KB_REVOKED);
}
static bool wj_kb_pump(){
 MSG message;
 for(int i=0;i<64&&PeekMessageW(&message,nullptr,0,0,PM_REMOVE);i++){if(message.message==WM_QUIT)return false;TranslateMessage(&message);DispatchMessageW(&message);}
 return true;
}
static bool wj_kb_register(){
 const ULONGLONG started=GetTickCount64();
 for(unsigned key=0;key<256;key++){
  if(!wj_kb_bit(wj_kb.mask,key))continue;
  for(unsigned variant=0;variant<8;variant++){
   const unsigned mods=wj_kb_mods(variant);
   if(!wj_kb_tuple(key,mods))continue;
   // A bounded transition: the foreground notification is dispatched between tuples.
   if(!wj_kb_pump()||wj_kb_state()!=WJ_KB_ARMING||!wj_kb_foreground(wj_kb.target)){wj_kb_stop(WJ_KB_REVOKED);return false;}
   if(GetTickCount64()-started>=wj_kb_register_ms||wj_kb.count>=2048){wj_kb_stop(WJ_KB_FAILED);return false;}
   const int id=1+static_cast<int>(key*8+variant);
   if(!RegisterHotKey(wj_kb.window,id,mods|MOD_NOREPEAT,key)){wj_kb_stop(WJ_KB_FAILED);return false;}
   wj_kb.ids[wj_kb.count++]=id;
  }
 }
 // The reservation is not atomic: a key pressed meanwhile may already be held by the game.
 if(wj_kb_held()){wj_kb_stop(WJ_KB_FAILED);return false;}
 AcquireSRWLockExclusive(&wj_kb_lock);
 if(wj_kb.state==WJ_KB_ARMING){wj_kb.state=WJ_KB_ACTIVE;wj_kb.heartbeat=GetTickCount64();}
 const bool active=wj_kb.state==WJ_KB_ACTIVE;
 ReleaseSRWLockExclusive(&wj_kb_lock);
 return active;
}
static DWORD WINAPI wj_kb_thread(void *){
 HINSTANCE instance=GetModuleHandleW(nullptr);WNDCLASSW type={};
 type.lpfnWndProc=wj_kb_proc;type.hInstance=instance;type.lpszClassName=L"WarJournalistKeyboardLease";
 const bool owns_class=RegisterClassW(&type)!=0;
 if(owns_class)wj_kb.window=CreateWindowExW(0,type.lpszClassName,L"",0,0,0,0,0,HWND_MESSAGE,nullptr,instance,nullptr);
 if(wj_kb.window)wj_kb.hook=SetWinEventHook(EVENT_SYSTEM_FOREGROUND,EVENT_SYSTEM_FOREGROUND,nullptr,wj_kb_foreground_event,0,0,WINEVENT_OUTOFCONTEXT);
 if(!wj_kb.hook)wj_kb_stop(WJ_KB_FAILED);
 for(;;){
  const uint32_t state=wj_kb_state();const ULONGLONG now=GetTickCount64();DWORD timeout=16;
  if(state==WJ_KB_ARMING){
   if(!wj_kb_foreground(wj_kb.target)){wj_kb_stop(WJ_KB_REVOKED);break;}
   if(now-wj_kb.started>=wj_kb_arm_ms){wj_kb_stop(WJ_KB_FAILED);break;}
   if(!wj_kb_held()){if(!wj_kb_register())break;continue;}
  }else if(state==WJ_KB_ACTIVE){
   AcquireSRWLockExclusive(&wj_kb_lock);
   const ULONGLONG elapsed=now-wj_kb.heartbeat;
   if(elapsed>=wj_kb_ttl_ms&&wj_kb.state==WJ_KB_ACTIVE){wj_kb.state=WJ_KB_CLOSING;wj_kb.terminal=WJ_KB_REVOKED;}
   ReleaseSRWLockExclusive(&wj_kb_lock);
   if(elapsed>=wj_kb_ttl_ms)break;
   timeout=static_cast<DWORD>(wj_kb_ttl_ms-elapsed);
  }else break;
  const DWORD result=MsgWaitForMultipleObjectsEx(1,&wj_kb.stop,timeout,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
  if(result==WAIT_OBJECT_0)break;
  if(result==WAIT_OBJECT_0+1&&!wj_kb_pump()){wj_kb_stop(WJ_KB_REVOKED);break;}
  if(result==WAIT_FAILED){wj_kb_stop(WJ_KB_FAILED);break;}
 }
 bool clean=true;
 while(wj_kb.count)if(!UnregisterHotKey(wj_kb.window,wj_kb.ids[--wj_kb.count]))clean=false;
 if(wj_kb.hook&&!UnhookWinEvent(wj_kb.hook))clean=false;
 wj_kb.hook=nullptr;
 if(wj_kb.window)DestroyWindow(wj_kb.window);
 wj_kb.window=nullptr;
 if(owns_class)UnregisterClassW(type.lpszClassName,instance);
 AcquireSRWLockExclusive(&wj_kb_lock);
 wj_kb.state=wj_kb.terminal?wj_kb.terminal:WJ_KB_REVOKED;wj_kb.unclean=!clean;
 ReleaseSRWLockExclusive(&wj_kb_lock);
 return 0;
}
// A finished worker's handles are closed here; a live one is never touched.
static bool wj_kb_reap(DWORD timeout){
 if(!wj_kb.thread)return true;
 if(WaitForSingleObject(wj_kb.thread,timeout)!=WAIT_OBJECT_0)return false;
 CloseHandle(wj_kb.thread);CloseHandle(wj_kb.stop);wj_kb.thread=wj_kb.stop=nullptr;return true;
}
// keyboard_acquire(mask): a 32-byte virtual-key mask inside LLL's whitelist. Returns the
// lease generation; the game window must be the foreground window.
static int native_keyboard_acquire(lua_State *L){
 size_t size=0;const char *bytes=native_api.luaL_checklstring(L,1,&size);
 uint32_t mask[8]={};if(size!=32)return native_api.luaL_error(L,"Keyboard mask must be 32 bytes");
 std::memcpy(mask,bytes,32);if(!wj_kb_mask_valid(mask))return native_api.luaL_error(L,"Keyboard mask is outside the lease whitelist");
 if(!wj_kb_reap(0)||wj_kb.unclean)return native_api.luaL_error(L,"Keyboard lease already owned or restoring");
 HWND target=GetForegroundWindow();
 if(!wj_kb_foreground(target))return native_api.luaL_error(L,"Keyboard lease needs the game window in front");
 HANDLE stop=CreateEventW(nullptr,TRUE,FALSE,nullptr);if(!stop)return native_api.luaL_error(L,"Keyboard lease event unavailable");
 AcquireSRWLockExclusive(&wj_kb_lock);
 const uint32_t generation=++wj_kb_generations;
 wj_kb.stop=stop;wj_kb.target=target;wj_kb.window=nullptr;wj_kb.hook=nullptr;std::memcpy(wj_kb.mask,mask,32);
 wj_kb.state=WJ_KB_ARMING;wj_kb.terminal=0;wj_kb.generation=generation;wj_kb.started=wj_kb.heartbeat=GetTickCount64();wj_kb.count=0;
 ReleaseSRWLockExclusive(&wj_kb_lock);
 wj_kb.thread=CreateThread(nullptr,0,wj_kb_thread,nullptr,0,nullptr);
 if(!wj_kb.thread){CloseHandle(stop);wj_kb.stop=nullptr;AcquireSRWLockExclusive(&wj_kb_lock);wj_kb.state=WJ_KB_FAILED;ReleaseSRWLockExclusive(&wj_kb_lock);return native_api.luaL_error(L,"Keyboard lease thread unavailable");}
 native_api.lua_pushnumber(L,generation);return 1;
}
// keyboard_sample(): state, the held keys of the mask as 32 bytes (active only), generation.
// Sampling an active lease renews it.
static int native_keyboard_sample(lua_State *L){
 AcquireSRWLockExclusive(&wj_kb_lock);
 const uint32_t state=wj_kb.state,generation=wj_kb.generation;
 if(state==WJ_KB_ACTIVE)wj_kb.heartbeat=GetTickCount64();
 ReleaseSRWLockExclusive(&wj_kb_lock);
 uint32_t keys[8]={};
 if(state==WJ_KB_ACTIVE)for(unsigned k=0;k<256;k++)if(wj_kb_bit(wj_kb.mask,k)&&(GetAsyncKeyState(static_cast<int>(k))&0x8000))keys[k>>5]|=1u<<(k&31);
 native_api.lua_pushinteger(L,state);native_api.lua_pushlstring(L,reinterpret_cast<const char*>(keys),32);native_api.lua_pushnumber(L,generation);return 3;
}
// keyboard_release(): true once the worker has retired and every hotkey is free.
static int native_keyboard_release(lua_State *L){
 if(wj_kb.thread)wj_kb_stop(WJ_KB_REVOKED);
 const bool retired=wj_kb_reap(250);
 native_api.lua_pushboolean(L,retired&&!wj_kb.unclean?1:0);
 if(!retired||wj_kb.unclean){native_api.lua_pushstring(L,retired?"Keyboard hotkeys were not all released":"Keyboard lease is still retiring");return 2;}
 return 1;
}
