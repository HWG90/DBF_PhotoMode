// Build-specific normal Lua module bootstrap. No hooks or target code writes.
#include "host_api.hh"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <cstring>
#include <cstdint>
static const char *boot_status = "not attempted";
static bool fail(const char *why) { boot_status=why; OutputDebugStringA(why); return false; }
HD2_EXPORT const char *hd2_cffi_bootstrap_status() { return boot_status; }
static bool readable(const void *ptr, size_t count, bool code=false) {
    MEMORY_BASIC_INFORMATION m = {};
    if (!ptr || !count || !VirtualQuery(ptr,&m,sizeof(m))) return false;
    uintptr_t low=reinterpret_cast<uintptr_t>(ptr),end=low+count;
    if (end<low || end>reinterpret_cast<uintptr_t>(m.BaseAddress)+m.RegionSize) return false;
    if (m.State!=MEM_COMMIT || (m.Protect&(PAGE_NOACCESS|PAGE_GUARD))) return false;
    DWORD p=m.Protect&0xff;
    if (code) return p==PAGE_EXECUTE_READ || p==PAGE_EXECUTE_READWRITE || p==PAGE_EXECUTE_WRITECOPY;
    return p==PAGE_READONLY || p==PAGE_READWRITE || p==PAGE_WRITECOPY || p==PAGE_EXECUTE_READ || p==PAGE_EXECUTE_READWRITE || p==PAGE_EXECUTE_WRITECOPY;
}
static bool expected_file() {
    wchar_t path[32768];
    DWORD length=GetModuleFileNameW(nullptr,path,32768);
    if (!length || length>=32768) return fail("Cannot resolve host executable path");
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,0,nullptr);
    if (file==INVALID_HANDLE_VALUE) return fail("Cannot read host executable");
    BCRYPT_ALG_HANDLE algorithm=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;
    unsigned char buffer[65536],digest[32];DWORD count;bool ok=false;
    if (BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)>=0 && BCryptCreateHash(algorithm,&hash,nullptr,0,nullptr,0,0)>=0) {
        ok=true;
        for (;;) {
            if (!ReadFile(file,buffer,sizeof(buffer),&count,nullptr)) {ok=false;break;}
            if (!count) break;
            if (BCryptHashData(hash,buffer,count,0)<0) {ok=false;break;}
        }
        if (ok) ok=BCryptFinishHash(hash,digest,32,0)>=0;
    }
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm,0);
    CloseHandle(file);
    const unsigned char expected[32]={0x0a,0xcc,0x07,0xde,0xbe,0x04,0x71,0x4a,0xe0,0x42,0x81,0xe1,0xa6,0x6b,0xd2,0xeb,0x9d,0x3d,0x85,0x23,0x29,0x53,0xe3,0x2a,0x93,0xc8,0xa3,0xdd,0x08,0x74,0xea,0xbe};
    return (ok && !std::memcmp(digest,expected,32)) || fail("Unsupported host executable; expected Helldivers 2 build 26088801");
}

static Hd2LuaApi native_api={};
static bool accept_native_api(const Hd2LuaApi *api) {
 if(native_api.abi_version && std::memcmp(&native_api,api,sizeof(*api))) return false;
 native_api=*api;return true;
}
static bool read_exact(const void *from,void *to,size_t n) {
 SIZE_T count=0;return ReadProcessMemory(GetCurrentProcess(),from,to,n,&count)&&count==n;
}
static int native_address(lua_State *L) {
 if(native_api.lua_type(L,1)!=LUA_TFUNCTION)return native_api.luaL_error(L,"Native function required");
 uintptr_t slot=0,closure=0,entry=0;unsigned char value[16]={},header[40]={};
 if(!read_exact(reinterpret_cast<unsigned char *>(L)+0x18,&slot,8) ||
    !read_exact(reinterpret_cast<void *>(slot),value,sizeof(value)))
  return native_api.luaL_error(L,"Unreadable Lua argument slot");
 std::memcpy(&closure,value,8);int tag=0;std::memcpy(&tag,value+8,4);
 if(tag!=LUA_TFUNCTION || !read_exact(reinterpret_cast<void *>(closure),header,sizeof(header)) || header[8]!=6 || header[10]!=1)
  return native_api.luaL_error(L,"Lua 5.1 x64 CClosure ABI differs, or function is a Lua closure");
 std::memcpy(&entry,header+0x20,8);
 if(!readable(reinterpret_cast<void *>(entry),1,true))return native_api.luaL_error(L,"Native binding is not executable");
 native_api.lua_pushnumber(L,static_cast<lua_Number>(entry));return 1;
}
static int native_userdata_address(lua_State *L) {
 const int tag=native_api.lua_type(L,1);
 if(tag!=LUA_TLIGHTUSERDATA && tag!=LUA_TUSERDATA)
  return native_api.luaL_error(L,"Engine userdata required");
 const auto address=reinterpret_cast<uintptr_t>(native_api.lua_touserdata(L,1));
 if(address>=UINT64_C(1)<<47)
  return native_api.luaL_error(L,"Engine userdata address outside supported range");
 native_api.lua_pushnumber(L,static_cast<lua_Number>(address));
 return 1;
}
static int native_read_memory(lua_State *L) {
 const lua_Number value=native_api.luaL_checknumber(L,1);
 const lua_Integer count=native_api.luaL_checkinteger(L,2);
 if(!(value>=65536 && value<140737488355328.0) || count<1 || count>4096)
  return native_api.luaL_error(L,"Protected read bounds invalid");
 const uintptr_t address=static_cast<uintptr_t>(value);
 if(static_cast<lua_Number>(address)!=value)
  return native_api.luaL_error(L,"Protected read address must be integral");
 char buffer[4096];
 if(!read_exact(reinterpret_cast<const void *>(address),buffer,static_cast<size_t>(count)))
  return native_api.luaL_error(L,"Protected native read failed");
 native_api.lua_pushlstring(L,buffer,static_cast<size_t>(count));return 1;
}
static int native_module_base(lua_State *L) {
 size_t length=0;const char *name=native_api.luaL_checklstring(L,1,&length);
 const bool game=length==8 && !std::memcmp(name,"game.dll",8);
 const bool exe=length==15 && !std::memcmp(name,"helldivers2.exe",15);
 if(!game && !exe)return native_api.luaL_error(L,"Unsupported engine module");
 const auto address=reinterpret_cast<uintptr_t>(GetModuleHandleA(game?"game.dll":nullptr));
 if(!address)return native_api.luaL_error(L,"Engine module unavailable");
 native_api.lua_pushnumber(L,static_cast<lua_Number>(address));return 1;
}
#pragma once
#include <cstdint>
#include <cstring>
struct HoverSpan {uintptr_t address;size_t size;unsigned char before[280],after[280];};
// 0 committed, 1 refused/rolled back, 2 unresolved rollback. No callbacks/yields.
template<class Read,class Write,class Writable>
static int hover_transaction(HoverSpan *spans,size_t count,Read read,Write write,Writable writable) {
 unsigned char current[280];
 for(size_t i=0;i<count;i++)if(!spans[i].size||spans[i].size>280||!writable(spans[i].address,spans[i].size)||!read(spans[i].address,current,spans[i].size)||std::memcmp(current,spans[i].before,spans[i].size))return 1;
 for(size_t i=0;i<count;i++) {
  auto &s=spans[i];bool attempted=false;
  bool ok=read(s.address,current,s.size)&&!std::memcmp(current,s.before,s.size);
  if(ok){attempted=true;ok=write(s.address,s.after,s.size)&&read(s.address,current,s.size)&&!std::memcmp(current,s.after,s.size);}
  if(ok)continue;
  size_t undo=i+(attempted?1:0);bool unresolved=false;
  while(undo){size_t j=--undo;auto &u=spans[j];
   if(!read(u.address,current,u.size)){unresolved=true;continue;}
   if(!std::memcmp(current,u.before,u.size))continue;
   bool ours=!std::memcmp(current,u.after,u.size);
   // A failed process write can commit a prefix. Only that failed destination
   // permits a prefix; completed earlier destinations require exact ownership.
   if(!ours&&attempted&&j==i)for(size_t split=0;split<=u.size&&!ours;split++)ours=!std::memcmp(current,u.after,split)&&!std::memcmp(current+split,u.before+split,u.size-split);
   if(!ours){unresolved=true;continue;}
   if(!writable(u.address,u.size)||!write(u.address,u.before,u.size)||!read(u.address,current,u.size)||std::memcmp(current,u.before,u.size))unresolved=true;
  }
  return unresolved?2:1;
 }
 return 0;
}

static int native_profile_float(lua_State *L) {
 auto fail=[&](const char *s)->int{return native_api.luaL_error(L,s);};
 if(native_api.lua_type(L,1)!=LUA_TLIGHTUSERDATA && native_api.lua_type(L,1)!=LUA_TUSERDATA)return fail("World userdata required");
 uintptr_t world=0,provider=0,vt=0;
 auto world_handle=native_api.lua_touserdata(L,1);
 if(!read_exact(world_handle,&world,8)||!read_exact(reinterpret_cast<void*>(world+0x230b58),&provider,8)||!read_exact(reinterpret_cast<void*>(provider),&vt,8))return fail("Lens world unavailable");
 const auto exe=reinterpret_cast<uintptr_t>(GetModuleHandleA(nullptr));
 const auto game=reinterpret_cast<uintptr_t>(GetModuleHandleA("game.dll"));
 uint32_t pe=0,stamp=0;
 for(int i=0;i<2;i++) {auto base=i?exe:game;
  if(!read_exact(reinterpret_cast<void*>(base+60),&pe,4)||pe<64||pe>1048576||!read_exact(reinterpret_cast<void*>(base+pe+8),&stamp,4)||stamp!=(i?0x6ad78c0d:0x6ad7c05d))return fail("Lens build differs");
 }
 uintptr_t setter=0,getter=0;
 if(!read_exact(reinterpret_cast<void*>(vt+0x28),&setter,8)||setter!=exe+0x2ad310||!read_exact(reinterpret_cast<void*>(vt+0x30),&getter,8)||getter!=exe+0x2ad520)return fail("Lens provider methods differ");
 const unsigned char prefix[]={0x40,0x53,0x55,0x41,0x55,0x41,0x57,0x48,0x83,0xec,0x58,0x48,0x8b,0x81,0xe8,0,0,0,0x4c,0x8b,0xf9,0x44,0x8b,0xea,0x49,0x8b,0xe9,0x4a,0x8b,0x0c,0xe8,0x41};
 unsigned char code[sizeof(prefix)]={};if(!read_exact(reinterpret_cast<void*>(setter),code,sizeof(code))||std::memcmp(code,prefix,sizeof(code)))return fail("Lens setter witness differs");
 uint32_t args[4];for(int i=0;i<4;i++){const auto n=native_api.luaL_checknumber(L,i+2);if(!(n>=0&&n<=4294967295.0))return fail("Lens identifier invalid");args[i]=static_cast<uint32_t>(n);if(n!=args[i])return fail("Lens identifier must be integral");}
 const uint32_t index=args[0],entity=args[1],instance=args[2],key=args[3];
 const uint32_t allowed[]={0xf617a000,0x1ed5746a,0xf2cba64d,0x594c123a,0xd8108f78,0xb18edf0c,0xa7990477,0xf07fc12e,0x834c73c0,0xa5fecfc7,0xa3b92674,0xf90f260e,0xbcb7968f,0x32af31e5,0x0db64441,0x209f72cf};
 bool found=false;for(auto k:allowed)if(k==key)found=true;if(!found)return fail("Unsupported photographic lens field");
 const double expected=native_api.luaL_checknumber(L,6),value=native_api.luaL_checknumber(L,7);
 if(!(expected>=0&&expected<=20000&&value>=0&&value<=20000))return fail("Lens value outside supported range");
 uint32_t count=0,capacity=0;uintptr_t entities=0,classes=0,instances=0,blobs=0,blob=0;
 auto rd=[&](uintptr_t at,void *to,size_t size)->bool{return at>=65536&&at<UINT64_C(1)<<47&&read_exact(reinterpret_cast<void*>(at),to,size);};
 if(!rd(provider+0xb8,&count,4)||!rd(provider+0xbc,&capacity,4)||count>capacity||capacity>4096||index>=count||!rd(provider+0xc8,&entities,8)||!rd(provider+0xd0,&classes,8)||!rd(provider+0xd8,&instances,8)||!rd(provider+0xe8,&blobs,8)||!rd(blobs+index*8,&blob,8))return fail("Lens profile bounds differ");
 uint32_t e=0,c=0,n=0;if(!rd(entities+index*4,&e,4)||e!=entity||!rd(classes+index*4,&c,4)||c!=0xf7a3101f||!rd(instances+index*4,&n,4)||n!=instance)return fail("Lens profile owner differs");
 uint32_t fields=0;if(!rd(blob+4,&fields,4)||fields==0||fields>512)return fail("Lens profile fields differ");
 uintptr_t address=0;
 for(uint32_t i=0;i<fields;i++){uint32_t k=0;if(!rd(blob+0x10+i*4,&k,4))return fail("Lens keys unreadable");if(k==key){uint32_t tag=0;auto at=blob+0x10+fields*4+i*16;if(address||!rd(at,&tag,4)||tag!=2)return fail("Lens field type differs");address=at+8;}}
 float current=0;if(!address||!rd(address,&current,4)||static_cast<double>(current)!=expected)return fail("Lens field changed by another writer");
 const float target=static_cast<float>(value);if(current!=target){alignas(8) unsigned char variant[24]={};const uint32_t tag=2;std::memcpy(variant,&tag,4);std::memcpy(variant+8,&target,4);
  reinterpret_cast<void(*)(void*,uint32_t,uint32_t,const void*)>(setter)(reinterpret_cast<void*>(provider),index,key,variant);
  if(!rd(address,&current,4)||current!=target)return fail("Lens write readback failed");
 }
 native_api.lua_pushnumber(L,current);return 1;
}
static int native_hud_visible(lua_State *L) {
 const auto target=native_api.luaL_checknumber(L,1);const auto value=native_api.luaL_checkinteger(L,2);
 if(!(target>=65536&&target<140737488355328.0)||(value!=0&&value!=1))return native_api.luaL_error(L,"HUD arguments invalid");
 const uintptr_t game=reinterpret_cast<uintptr_t>(GetModuleHandleA("game.dll")),widget=static_cast<uintptr_t>(target);
 if(static_cast<lua_Number>(widget)!=target)return native_api.luaL_error(L,"HUD pointer must be integral");
 auto rd=[&](uintptr_t at,void *to,size_t n)->bool{return at>=65536&&at<(UINT64_C(1)<<47)&&read_exact(reinterpret_cast<void*>(at),to,n);};
 uint32_t pe=0,stamp=0,size=0;
 if(!rd(game+60,&pe,4)||pe<64||pe>1048576||!rd(game+pe+8,&stamp,4)||stamp!=0x6ad7c05d||!rd(game+pe+80,&size,4)||size!=0x3382000)return native_api.luaL_error(L,"HUD build differs");
 const unsigned char prefix[]={0x48,0x83,0xec,0x28,0x44,0x8b,0x01,0x4c,0x8b,0xd1,0x41,0x8b,0xc0,0x45,0x8b,0xc8,0x83,0xe0,0xef,0x41,0x83,0xc9,0x10,0x84,0xd2,0x44,0x0f,0x44,0xc8,0x44,0x89,0x09};
 unsigned char actual[sizeof(prefix)]={};if(!rd(game+0x12e4cc0,actual,sizeof(actual))||std::memcmp(actual,prefix,sizeof(actual)))return native_api.luaL_error(L,"HUD setter witness differs");
 uintptr_t state=0,root=0,parent=0,panel_parent=0;uint32_t scene=0;unsigned char initialized=0;
 // Scene 4 is a mission. Scene 3 is the ship: the same widget, and no mission panel there.
 if(!rd(game+0x2ce1508,&state,8)||!rd(state+0xac29c,&scene,4)||(scene!=4&&scene!=3)||!rd(game+0x2e28788,&root,8)||widget!=root+0x820||!rd(root+0x24e334,&initialized,1)||initialized!=1||!rd(widget+0xf0,&parent,8)||parent!=root+0x258||(scene==4&&(!rd(root+0x24e340+0x146940+0xf0,&panel_parent,8)||panel_parent!=widget)))return native_api.luaL_error(L,"Gameplay HUD ownership differs");
 reinterpret_cast<void(*)(uintptr_t,uint8_t)>(game+0x12e4cc0)(widget,static_cast<uint8_t>(value));
 uint32_t flags=0;if(!rd(widget,&flags,4)||((flags>>4)&1)!=static_cast<uint32_t>(value))return native_api.luaL_error(L,"HUD visibility acknowledgement differs");
 native_api.lua_pushboolean(L,1);return 1;
}

// Narrow current-build data accessor. No hooks or executable writes.
static int native_hover_height(lua_State *L) {
 auto fail=[&](const char *s)->int{return native_api.luaL_error(L,s);};
 const auto game=reinterpret_cast<uintptr_t>(GetModuleHandleA("game.dll"));
 const auto exe=reinterpret_cast<uintptr_t>(GetModuleHandleA(nullptr));
 auto rd=[&](uintptr_t at,void *to,size_t n)->bool{return at>=65536&&at<(UINT64_C(1)<<47)&&read_exact(reinterpret_cast<void*>(at),to,n);};
 auto u32=[&](uintptr_t at,uint32_t &v)->bool{return rd(at,&v,4);};
 auto ptr=[&](uintptr_t at,uintptr_t &v)->bool{return rd(at,&v,8)&&v>=65536&&v<(UINT64_C(1)<<47);};
 for(int i=0;i<2;i++){uintptr_t base=i?exe:game;uint32_t pe=0,stamp=0;
  if(!u32(base+60,pe)||pe<64||pe>1048576||!u32(base+pe+8,stamp)||stamp!=(i?0x6ad78c0d:0x6ad7c05d))return fail("Hover build differs");
 }
 const unsigned char height_code[]={0xf3,0x41,0x0f,0x10,0x84,0x24,0x9c,0,0,0};
 unsigned char code[sizeof(height_code)]={};
 if(!rd(game+0x9c6942,code,sizeof(code))||std::memcmp(code,height_code,sizeof(code)))return fail("Hover height consumer differs");
 const double pack_number=native_api.luaL_checknumber(L,1),ref_number=native_api.luaL_checknumber(L,2);
 if(!(pack_number>0&&pack_number<4294967295.0&&ref_number>0&&ref_number<4294967295.0))return fail("Hover entity arguments invalid");
 const uint32_t pack=static_cast<uint32_t>(pack_number),ref=static_cast<uint32_t>(ref_number);
 if(pack_number!=pack||ref_number!=ref)return fail("Hover entity arguments must be integral");
 const double expected=native_api.luaL_checknumber(L,3),value=native_api.luaL_checknumber(L,4);
 if(!(expected>=0&&expected<=1000000&&value>=0&&value<=1000000)||(value!=0&&expected!=0&&value!=expected))return fail("Hover write is outside pause/restore contract");
 // Native open-addressed maps use a uint32 product, not floating arithmetic.
 auto lookup=[&](uintptr_t header,uint32_t key,uint32_t &index)->bool{
  uintptr_t data=0;uint32_t cap=0,empty=0,seed=0;
  if(!ptr(header,data)||!u32(header+8,cap)||!cap||cap>4194304||(cap&(cap-1))||!u32(header+12,empty)||!u32(header+16,seed)||key==empty)return false;
  const uint32_t hash=key*seed;
  for(uint32_t i=0;i<cap&&i<64;i++){uint32_t row[2]={};if(!rd(data+((hash+i)%cap)*8,row,8))return false;
   if(row[0]==key){index=row[1];return index!=UINT32_MAX;}if(row[0]==empty)return false;
  }return false;
 };
 uintptr_t world=0,manager=0,players=0,inventory=0;uint32_t entity_index=0;
 if(!ptr(game+0x2ce41b8,world)||!ptr(game+0x2ce1d78,manager)||!lookup(world+0xf1c978,pack,entity_index)||entity_index>=4194304)return fail("Hover entity unavailable");
 unsigned char record[24]={};
 if(!rd(world+0xf349e0+entity_index*24,record,24))return fail("Hover record unreadable");
 const unsigned char resource[]={0xcf,0x66,0xdb,0x1c,0x4f,0x0f,0xc8,0x5e};uint32_t entity=0,unit_ref=0;
 std::memcpy(&entity,record+8,4);std::memcpy(&unit_ref,record+12,4);
 if(std::memcmp(record,resource,8)||entity!=pack||unit_ref!=ref||!(record[20]&1))return fail("Hover pack lifetime differs");
 uintptr_t registry=0,generations=0;uint32_t units=0;unsigned char generation=0;
 if(!ptr(exe+0x1ab76f8,registry)||!u32(registry+0x98,units)||ref%4194304>=units||!ptr(registry+0xa0,generations)||!rd(generations+ref%4194304,&generation,1)||generation!=ref/4194304)return fail("Hover Unit generation retired");
 uint32_t row=0,count=0;if(!lookup(manager+0x20,pack,row)||!u32(manager+12,count)||row>=count||count>4096)return fail("Hover component unavailable");
 uintptr_t descriptors=0,descriptor=0;unsigned char component_record[24]={};
 if(!ptr(manager+0x38,descriptors)||!ptr(descriptors+row*8,descriptor)||!rd(descriptor,component_record,24)||std::memcmp(record,component_record,20)||!(component_record[20]&1))return fail("Hover component owner differs");
 uint32_t index=0,private_count=0,capacity=0,reverse=0;uintptr_t definitions=0;
 if(!u32(manager+4,capacity)||!capacity||capacity>256||!u32(manager+0x98,private_count)||private_count>capacity||!lookup(manager+0x60,pack,index)||index>=private_count||!lookup(manager+0x80,index,reverse)||reverse!=pack||!ptr(manager+0xa0,definitions))return fail("Entity-owned hover definition unavailable");
 // Acquiring zero is limited to the current local equipped pack. Restoration
 // may resolve the same living old pack after it has been unequipped.
 if(value==0&&expected!=0){uint32_t root=0,avatar_index=0,avatar=0,inventory_index=0,equipped=0;uintptr_t items=0;
  if(!ptr(game+0x2ce1618,players)||!u32(players+0x3a8,root)||!lookup(world+0xf24990,root,avatar_index)||avatar_index>=4194304||!u32(world+0xf349e0+avatar_index*24+8,avatar)||!ptr(game+0x2ce18e8,inventory)||!lookup(inventory+40,avatar,inventory_index)||inventory_index>=4194304||!ptr(inventory+80,items)||!u32(items+inventory_index*48+12,equipped)||equipped!=pack)return fail("Hover pack is no longer equipped locally");
 }
 uintptr_t address=definitions+index*280+0x9c;float current=0;
 if(!rd(address,&current,4)||static_cast<double>(current)!=expected)return fail("Hover field changed by another writer");
 const float target=static_cast<float>(value);
 if(current!=target){MEMORY_BASIC_INFORMATION m={};
  if(!VirtualQuery(reinterpret_cast<void*>(address),&m,sizeof(m))||m.State!=MEM_COMMIT||(m.Protect!=PAGE_READWRITE&&m.Protect!=PAGE_WRITECOPY)||address+4>reinterpret_cast<uintptr_t>(m.BaseAddress)+m.RegionSize)return fail("Hover field is not writable data");
  SIZE_T written=0;if(!WriteProcessMemory(GetCurrentProcess(),reinterpret_cast<void*>(address),&target,4,&written)||written!=4||!rd(address,&current,4)||current!=target)return fail("Hover write acknowledgement failed");
 }
 native_api.lua_pushnumber(L,current);return 1;
}
static int native_gamepads_absent(lua_State *L) {
 static HMODULE library=nullptr;static bool attempted=false;
 if(!attempted){attempted=true;library=LoadLibraryExA("xinput1_4.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);if(!library)library=LoadLibraryExA("xinput9_1_0.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);}
 if(!library){native_api.lua_pushnil(L);native_api.lua_pushstring(L,"XInput presence unavailable");return 2;}
 auto query=reinterpret_cast<DWORD(WINAPI*)(DWORD,void*)>(GetProcAddress(library,"XInputGetState"));
 if(!query){native_api.lua_pushnil(L);native_api.lua_pushstring(L,"XInput state unavailable");return 2;}
 alignas(16) unsigned char state[16]={};
 for(DWORD i=0;i<4;i++){const DWORD status=query(i,state);
  if(status==ERROR_SUCCESS){native_api.lua_pushboolean(L,0);native_api.lua_pushstring(L,"XInput controller present");return 2;}
  if(status!=ERROR_DEVICE_NOT_CONNECTED){native_api.lua_pushnil(L);native_api.lua_pushstring(L,"XInput presence uncertain");return 2;}
 }
 native_api.lua_pushboolean(L,1);return 1;
}

static int native_hover_ensure(lua_State *L) {
 auto fail=[&](const char *s)->int{return native_api.luaL_error(L,s);};
 auto rd=[](uintptr_t a,void *p,size_t n)->bool{return a>=65536&&a<(UINT64_C(1)<<47)&&read_exact(reinterpret_cast<void*>(a),p,n);};
 auto u=[&](uintptr_t a,uint32_t &v){return rd(a,&v,4);};
 auto p=[&](uintptr_t a,uintptr_t &v){return rd(a,&v,8)&&v>=65536&&v<(UINT64_C(1)<<47);};
 auto game=reinterpret_cast<uintptr_t>(GetModuleHandleA("game.dll"));auto exe=reinterpret_cast<uintptr_t>(GetModuleHandleA(nullptr));
 for(int i=0;i<2;i++){uintptr_t b=i?exe:game;uint32_t pe=0,stamp=0;if(!u(b+60,pe)||pe<64||pe>1048576||!u(b+pe+8,stamp)||stamp!=(i?0x6ad78c0d:0x6ad7c05d))return fail("Hover copy build differs");}
 const unsigned char witness[]={0x48,0x69,0xc0,0x18,0x01,0,0,0x49,0x03,0x83,0xa0,0,0,0};unsigned char code[sizeof(witness)]={};
 if(!rd(game+0x515eb2,code,sizeof(code))||std::memcmp(code,witness,sizeof(code)))return fail("Hover definition consumer differs");
 double a=native_api.luaL_checknumber(L,1),b=native_api.luaL_checknumber(L,2);
 if(!(a>0&&a<4294967295.0&&b>0&&b<4294967295.0))return fail("Hover copy arguments invalid");uint32_t pack=static_cast<uint32_t>(a),ref=static_cast<uint32_t>(b);
 if(a!=pack||b!=ref)return fail("Hover copy arguments must be integral");
 struct Slot{uintptr_t address=0;uint32_t key=0,index=0,empty=0;};
 auto slot=[&](uintptr_t h,uint32_t key,Slot &s)->bool{
  uintptr_t data=0;uint32_t cap=0,seed=0,empty=0;if(!p(h,data)||!u(h+8,cap)||!cap||cap>4194304||(cap&(cap-1))||!u(h+12,empty)||!u(h+16,seed)||key==empty)return false;
  uint32_t hash=key*seed;
  for(uint32_t i=0;i<cap&&i<64;i++){uint32_t r[2]={};uintptr_t at=data+((hash+i)%cap)*8;if(!rd(at,r,8))return false;if(r[0]==key||r[0]==empty){s.address=at;s.key=r[0];s.index=r[1];s.empty=empty;return true;}}return false;
 };
 auto lookup=[&](uintptr_t h,uint32_t key,uint32_t &index){Slot s;if(!slot(h,key,s)||s.key!=key||s.index==UINT32_MAX)return false;index=s.index;return true;};
 uintptr_t world=0,manager=0,registry=0,generations=0;uint32_t ei=0,count=0;unsigned char record[24]={},generation=0;
 const unsigned char type[]={0xcf,0x66,0xdb,0x1c,0x4f,0x0f,0xc8,0x5e};
 if(!p(game+0x2ce41b8,world)||!p(game+0x2ce1d78,manager)||!lookup(world+0xf1c978,pack,ei)||ei>=4194304||!rd(world+0xf349e0+ei*24,record,24))return fail("Hover copy entity unavailable");
 uint32_t re=0,rr=0;std::memcpy(&re,record+8,4);std::memcpy(&rr,record+12,4);
 if(std::memcmp(record,type,8)||re!=pack||rr!=ref||!(record[20]&1)||!p(exe+0x1ab76f8,registry)||!u(registry+0x98,count)||ref%4194304>=count||!p(registry+0xa0,generations)||!rd(generations+ref%4194304,&generation,1)||generation!=ref/4194304)return fail("Hover copy lifetime differs");
 uintptr_t players=0,inventory=0,items=0;uint32_t root=0,ai=0,avatar=0,ii=0,equipped=0;
 if(!p(game+0x2ce1618,players)||!u(players+0x3a8,root)||!lookup(world+0xf24990,root,ai)||ai>=4194304||!u(world+0xf349e0+ai*24+8,avatar)||!p(game+0x2ce18e8,inventory)||!lookup(inventory+40,avatar,ii)||ii>=4194304||!p(inventory+80,items)||!u(items+ii*48+12,equipped)||equipped!=pack)return fail("Hover copy requires current local pack");
 uintptr_t list=0,descriptor=0;uint32_t row=0;unsigned char identity[24]={};
 if(!lookup(manager+0x20,pack,row)||!u(manager+12,count)||count>4096||row>=count||!p(manager+0x38,list)||!p(list+row*8,descriptor)||!rd(descriptor,identity,24)||std::memcmp(record,identity,20)||!(identity[20]&1))return fail("Hover copy component differs");
 uint32_t capacity=0,n=0;uintptr_t data=0;Slot forward,reverse;
 if(!u(manager+4,capacity)||!capacity||capacity>256||!u(manager+0x98,n)||n>capacity||!p(manager+0xa0,data)||!slot(manager+0x60,pack,forward))return fail("Hover private storage differs");
 if(forward.key==pack&&forward.index!=UINT32_MAX){uint32_t owner=0;if(forward.index>=n||!lookup(manager+0x80,forward.index,owner)||owner!=pack)return fail("Hover existing private owner differs");native_api.lua_pushboolean(L,1);return 1;}
 if(n>=capacity||!slot(manager+0x80,n,reverse)||(reverse.key==n&&reverse.index!=UINT32_MAX))return fail("Hover private storage full or owned");
 uintptr_t pool=0;unsigned char headers[96]={},resource[280]={};bool found=false;
 if(!p(world+0xf14780,pool)||!rd(pool,headers,sizeof(headers)))return fail("Hover resource defaults unavailable");
 for(int i=0;i<6;i++)if(!std::memcmp(headers+i*16,type,8)){uint32_t index=0;std::memcpy(&index,headers+i*16+8,4);if(found||index>=3||!rd(pool+96+index*280,resource,280))return fail("Hover resource defaults differ");found=true;}
 float height=0;std::memcpy(&height,resource+0x9c,4);if(!found||resource[0x99]!=1||resource[0x9a]>1||!(height>=0&&height<=1000000))return fail("Hover resource mode differs");
 HoverSpan spans[4]={};spans[0].address=data+n*280;spans[0].size=280;std::memcpy(spans[0].after,resource,280);
 spans[1].address=reverse.address;spans[1].size=8;std::memcpy(spans[1].after,&n,4);std::memcpy(spans[1].after+4,&pack,4);
 spans[2].address=manager+0x98;spans[2].size=4;uint32_t next=n+1;std::memcpy(spans[2].after,&next,4);
 spans[3].address=forward.address;spans[3].size=8;std::memcpy(spans[3].after,&pack,4);std::memcpy(spans[3].after+4,&n,4);
 for(auto &s:spans)if(!rd(s.address,s.before,s.size))return fail("Hover copy destinations unreadable");
 auto writable=[](uintptr_t at,size_t size){MEMORY_BASIC_INFORMATION m={};return VirtualQuery(reinterpret_cast<void*>(at),&m,sizeof(m))&&m.State==MEM_COMMIT&&(m.Protect==PAGE_READWRITE||m.Protect==PAGE_WRITECOPY)&&at+size>=at&&at+size<=reinterpret_cast<uintptr_t>(m.BaseAddress)+m.RegionSize;};
 auto write=[](uintptr_t at,const void *bytes,size_t size){SIZE_T n=0;return WriteProcessMemory(GetCurrentProcess(),reinterpret_cast<void*>(at),bytes,size,&n)&&n==size;};
 int result=hover_transaction(spans,4,rd,write,writable);
 if(result)return fail(result==2?"Hover copy rollback pending; preserve owner":"Hover copy refused and rolled back");
 native_api.lua_pushboolean(L,1);return 1;
}

static int open_nativeinfo(lua_State *L) {
 native_api.lua_createtable(L,0,9);
 native_api.lua_pushcclosure(L,native_profile_float,0);
 native_api.lua_setfield(L,-2,"profile_float");
 native_api.lua_pushcclosure(L,native_hud_visible,0);
 native_api.lua_setfield(L,-2,"hud_visible");
 native_api.lua_pushcclosure(L,native_hover_height,0);
 native_api.lua_setfield(L,-2,"hover_height");
 native_api.lua_pushcclosure(L,native_gamepads_absent,0);
 native_api.lua_setfield(L,-2,"gamepads_absent");
 native_api.lua_pushcclosure(L,native_hover_ensure,0);
 native_api.lua_setfield(L,-2,"hover_ensure");


 native_api.lua_pushcclosure(L,native_address,0);
 native_api.lua_setfield(L,-2,"function_address");
 native_api.lua_pushcclosure(L,native_userdata_address,0);
 native_api.lua_setfield(L,-2,"userdata_address");
 native_api.lua_pushcclosure(L,native_read_memory,0);
 native_api.lua_setfield(L,-2,"read_memory");
 native_api.lua_pushcclosure(L,native_module_base,0);
 native_api.lua_setfield(L,-2,"module_base");return 1;
}

static bool bind_current_host() {
    if (!expected_file()) return false;
    auto base=reinterpret_cast<unsigned char *>(GetModuleHandleW(nullptr));
    if (!readable(base,sizeof(IMAGE_DOS_HEADER))) return fail("Unreadable host header");
    auto dos=reinterpret_cast<const IMAGE_DOS_HEADER *>(base);
    if (dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<0 || dos->e_lfanew>0x100000) return fail("Invalid host DOS header");
    auto nt=reinterpret_cast<const IMAGE_NT_HEADERS64 *>(base+dos->e_lfanew);
    if (!readable(nt,sizeof(*nt)) || nt->Signature!=IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC) return fail("Invalid host PE header");
    constexpr uintptr_t table_rva=0x286f710;
    if (nt->OptionalHeader.SizeOfImage<table_rva+115*sizeof(void *)) return fail("Host image too small for LuaApi");
    auto table=reinterpret_cast<void *const *>(base+table_rva);
    if (!readable(table,115*sizeof(void *))) return fail("Unreadable host LuaApi table");
    Hd2LuaApi api={};api.abi_version=1;api.struct_size=sizeof(api);
    { // luaL_argerror, SDK member lib_argerror
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x81,0xec,0xf0,0x00};
        auto expected=base+0x792af0;
        if (table[91]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_argerror");
        api.luaL_argerror=reinterpret_cast<decltype(api.luaL_argerror)>(table[91]);
    }
    { // luaL_checkany, SDK member lib_checkany
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0x44,0x8b,0xd2,0x4c,0x8b,0xd9,0xe8,0x21,0x34,0x00,0x00,0x48};
        auto expected=base+0x7931b0;
        if (table[100]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_checkany");
        api.luaL_checkany=reinterpret_cast<decltype(api.luaL_checkany)>(table[100]);
    }
    { // luaL_checkinteger, SDK member lib_checkinteger
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xec,0x30,0x8b};
        auto expected=base+0x7934c0;
        if (table[96]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_checkinteger");
        api.luaL_checkinteger=reinterpret_cast<decltype(api.luaL_checkinteger)>(table[96]);
    }
    { // luaL_checklstring, SDK member lib_checklstring
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57};
        auto expected=base+0x7931f0;
        if (table[92]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_checklstring");
        api.luaL_checklstring=reinterpret_cast<decltype(api.luaL_checklstring)>(table[92]);
    }
    { // luaL_checknumber, SDK member lib_checknumber
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x40,0x0f,0x29,0x74,0x24,0x30,0x8b};
        auto expected=base+0x793370;
        if (table[94]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_checknumber");
        api.luaL_checknumber=reinterpret_cast<decltype(api.luaL_checknumber)>(table[94]);
    }
    { // luaL_checktype, SDK member lib_checktype
        const unsigned char prefix[16]={0x40,0x53,0x48,0x83,0xec,0x20,0x45,0x8b,0xd0,0x44,0x8b,0xda,0x48,0x8b,0xd9,0xe8};
        auto expected=base+0x793160;
        if (table[99]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_checktype");
        api.luaL_checktype=reinterpret_cast<decltype(api.luaL_checktype)>(table[99]);
    }
    { // luaL_checkudata, SDK member lib_checkudata
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57};
        auto expected=base+0x793060;
        if (table[102]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_checkudata");
        api.luaL_checkudata=reinterpret_cast<decltype(api.luaL_checkudata)>(table[102]);
    }
    { // luaL_error, SDK member lib_error
        const unsigned char prefix[16]={0x48,0x89,0x54,0x24,0x10,0x4c,0x89,0x44,0x24,0x18,0x4c,0x89,0x4c,0x24,0x20,0x53};
        auto expected=base+0x792e10;
        if (table[104]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_error");
        api.luaL_error=reinterpret_cast<decltype(api.luaL_error)>(table[104]);
    }
    { // luaL_newmetatable, SDK member lib_newmetatable
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xec,0x20,0x48};
        auto expected=base+0x792f90;
        if (table[101]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_newmetatable");
        api.luaL_newmetatable=reinterpret_cast<decltype(api.luaL_newmetatable)>(table[101]);
    }
    { // luaL_optinteger, SDK member lib_optinteger
        const unsigned char prefix[16]={0x40,0x53,0x48,0x83,0xec,0x20,0x4d,0x8b,0xd0,0x44,0x8b,0xda,0x48,0x8b,0xd9,0xe8};
        auto expected=base+0x7935c0;
        if (table[97]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_optinteger");
        api.luaL_optinteger=reinterpret_cast<decltype(api.luaL_optinteger)>(table[97]);
    }
    { // luaL_ref, SDK member lib_ref
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x10,0x56,0x48,0x83,0xec,0x30,0x8d,0x82,0x0f,0x27,0x00,0x00};
        auto expected=base+0x7942d0;
        if (table[106]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_ref");
        api.luaL_ref=reinterpret_cast<decltype(api.luaL_ref)>(table[106]);
    }
    { // luaL_register, SDK member lib_register
        const unsigned char prefix[16]={0x45,0x33,0xc9,0xe9,0x28,0x00,0x00,0x00,0x41,0x54,0x48,0x83,0xec,0x60,0x33,0xd0};
        auto expected=base+0x7937a0;
        if (table[87]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_register");
        api.luaL_register=reinterpret_cast<decltype(api.luaL_register)>(table[87]);
    }
    { // luaL_unref, SDK member lib_unref
        const unsigned char prefix[16]={0x45,0x85,0xc0,0x0f,0x88,0x9f,0x00,0x00,0x00,0x48,0x89,0x5c,0x24,0x08,0x48,0x89};
        auto expected=base+0x794410;
        if (table[107]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_unref");
        api.luaL_unref=reinterpret_cast<decltype(api.luaL_unref)>(table[107]);
    }
    { // luaL_where, SDK member lib_where
        const unsigned char prefix[16]={0x40,0x57,0x48,0x81,0xec,0xe0,0x00,0x00,0x00,0x4c,0x8b,0x41,0x28,0x48,0x8b,0xf9};
        auto expected=base+0x792cf0;
        if (table[103]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: luaL_where");
        api.luaL_where=reinterpret_cast<decltype(api.luaL_where)>(table[103]);
    }
    { // lua_call, SDK member call
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0x8d,0x42,0x01,0x41,0x8b,0xd8};
        auto expected=base+0x797a30;
        if (table[64]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_call");
        api.lua_call=reinterpret_cast<decltype(api.lua_call)>(table[64]);
    }
    { // lua_concat, SDK member concat
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0x48,0x63,0xda,0x48,0x8b,0xf9};
        auto expected=base+0x797fd0;
        if (table[75]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_concat");
        api.lua_concat=reinterpret_cast<decltype(api.lua_concat)>(table[75]);
    }
    { // lua_createtable, SDK member createtable
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57};
        auto expected=base+0x797510;
        if (table[54]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_createtable");
        api.lua_createtable=reinterpret_cast<decltype(api.lua_createtable)>(table[54]);
    }
    { // lua_error, SDK member error
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0xe8,0xe7,0xe4,0xff,0xff,0x33,0xc0,0x48,0x83,0xc4,0x28,0xc3};
        auto expected=base+0x797f80;
        if (table[73]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_error");
        api.lua_error=reinterpret_cast<decltype(api.lua_error)>(table[73]);
    }
    { // lua_getfield, SDK member getfield
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x30,0x4d,0x8b,0xd0,0x48,0x8b,0xd9};
        auto expected=base+0x797420;
        if (table[51]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_getfield");
        api.lua_getfield=reinterpret_cast<decltype(api.lua_getfield)>(table[51]);
    }
    { // lua_getmetatable, SDK member getmetatable
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0x4c,0x8b,0xd1,0xe8,0x54,0xf0,0xff,0xff,0x48,0x63,0x48,0x08};
        auto expected=base+0x797580;
        if (table[56]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_getmetatable");
        api.lua_getmetatable=reinterpret_cast<decltype(api.lua_getmetatable)>(table[56]);
    }
    { // lua_gettable, SDK member gettable
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0x4c,0x8b,0xd1,0xe8,0xe4,0xf1,0xff,0xff,0x4d,0x8b,0x42,0x10};
        auto expected=base+0x7973f0;
        if (table[50]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_gettable");
        api.lua_gettable=reinterpret_cast<decltype(api.lua_gettable)>(table[50]);
    }
    { // lua_gettop, SDK member gettop
        const unsigned char prefix[16]={0x48,0x8b,0x41,0x10,0x48,0x2b,0x41,0x18,0x48,0xc1,0xf8,0x04,0xc3,0x41,0x56,0x57};
        auto expected=base+0x796950;
        if (table[13]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_gettop");
        api.lua_gettop=reinterpret_cast<decltype(api.lua_gettop)>(table[13]);
    }
    { // lua_insert, SDK member insert
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0x4c,0x8b,0xd9,0xe8,0xc4,0xfb,0xff,0xff,0x49,0x8b,0x53,0x10};
        auto expected=base+0x796a10;
        if (table[17]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_insert");
        api.lua_insert=reinterpret_cast<decltype(api.lua_insert)>(table[17]);
    }
    { // lua_isnumber, SDK member isnumber
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0xe8,0x87,0xf9,0xff,0xff,0x8b,0x48,0x08,0x83,0xf9,0x03,0x74};
        auto expected=base+0x796c50;
        if (table[21]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_isnumber");
        api.lua_isnumber=reinterpret_cast<decltype(api.lua_isnumber)>(table[21]);
    }
    { // lua_isstring, SDK member isstring
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0xe8,0x47,0xf9,0xff,0xff,0x48,0x8d,0x0d,0x40,0x2b,0xf6,0x00};
        auto expected=base+0x796c90;
        if (table[22]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_isstring");
        api.lua_isstring=reinterpret_cast<decltype(api.lua_isstring)>(table[22]);
    }
    { // lua_isuserdata, SDK member isuserdata
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0xe8,0x07,0xf9,0xff,0xff,0x8b,0x48,0x08,0x83,0xf9,0x07,0x74};
        auto expected=base+0x796cd0;
        if (table[24]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_isuserdata");
        api.lua_isuserdata=reinterpret_cast<decltype(api.lua_isuserdata)>(table[24]);
    }
    { // lua_newuserdata, SDK member newuserdata
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57};
        auto expected=base+0x7980a0;
        if (table[55]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_newuserdata");
        api.lua_newuserdata=reinterpret_cast<decltype(api.lua_newuserdata)>(table[55]);
    }
    { // lua_objlen, SDK member objlen
        const unsigned char prefix[16]={0x40,0x53,0x48,0x83,0xec,0x20,0x4c,0x8b,0xd1,0xe8,0x42,0xf6,0xff,0xff,0x48,0x8b};
        auto expected=base+0x796f90;
        if (table[34]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_objlen");
        api.lua_objlen=reinterpret_cast<decltype(api.lua_objlen)>(table[34]);
    }
    { // lua_pcall, SDK member pcall
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x40,0x41,0x8b,0xf8,0x44,0x8b,0xda};
        auto expected=base+0x797a90;
        if (table[65]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pcall");
        api.lua_pcall=reinterpret_cast<decltype(api.lua_pcall)>(table[65]);
    }
    { // lua_pushboolean, SDK member pushboolean
        const unsigned char prefix[16]={0x4c,0x8b,0x41,0x10,0x33,0xc0,0x85,0xd2,0x0f,0x95,0xc0,0x41,0x89,0x00,0x41,0xc7};
        auto expected=base+0x797380;
        if (table[47]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushboolean");
        api.lua_pushboolean=reinterpret_cast<decltype(api.lua_pushboolean)>(table[47]);
    }
    { // lua_pushcclosure, SDK member pushcclosure
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xec,0x20,0x4c};
        auto expected=base+0x7972b0;
        if (table[46]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushcclosure");
        api.lua_pushcclosure=reinterpret_cast<decltype(api.lua_pushcclosure)>(table[46]);
    }
    { // lua_pushfstring, SDK member pushfstring
        const unsigned char prefix[16]={0x48,0x89,0x54,0x24,0x10,0x4c,0x89,0x44,0x24,0x18,0x4c,0x89,0x4c,0x24,0x20,0x53};
        auto expected=base+0x797260;
        if (table[45]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushfstring");
        api.lua_pushfstring=reinterpret_cast<decltype(api.lua_pushfstring)>(table[45]);
    }
    { // lua_pushinteger, SDK member pushinteger
        const unsigned char prefix[16]={0x48,0x8b,0x41,0x10,0x0f,0x57,0xc0,0xf2,0x48,0x0f,0x2a,0xc2,0xc7,0x40,0x08,0x03};
        auto expected=base+0x797150;
        if (table[41]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushinteger");
        api.lua_pushinteger=reinterpret_cast<decltype(api.lua_pushinteger)>(table[41]);
    }
    { // lua_pushlightuserdata, SDK member pushlightuserdata
        const unsigned char prefix[16]={0x48,0x8b,0x41,0x10,0x48,0x89,0x10,0xc7,0x40,0x08,0x02,0x00,0x00,0x00,0x48,0x83};
        auto expected=base+0x7973a0;
        if (table[48]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushlightuserdata");
        api.lua_pushlightuserdata=reinterpret_cast<decltype(api.lua_pushlightuserdata)>(table[48]);
    }
    { // lua_pushlstring, SDK member pushlstring
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57};
        auto expected=base+0x797170;
        if (table[42]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushlstring");
        api.lua_pushlstring=reinterpret_cast<decltype(api.lua_pushlstring)>(table[42]);
    }
    { // lua_pushnil, SDK member pushnil
        const unsigned char prefix[16]={0x48,0x8b,0x41,0x10,0xc7,0x40,0x08,0x00,0x00,0x00,0x00,0x48,0x83,0x41,0x10,0x10};
        auto expected=base+0x797110;
        if (table[39]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushnil");
        api.lua_pushnil=reinterpret_cast<decltype(api.lua_pushnil)>(table[39]);
    }
    { // lua_pushnumber, SDK member pushnumber
        const unsigned char prefix[16]={0x48,0x8b,0x41,0x10,0xf2,0x0f,0x11,0x08,0xc7,0x40,0x08,0x03,0x00,0x00,0x00,0x48};
        auto expected=base+0x797130;
        if (table[40]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushnumber");
        api.lua_pushnumber=reinterpret_cast<decltype(api.lua_pushnumber)>(table[40]);
    }
    { // lua_pushstring, SDK member pushstring
        const unsigned char prefix[16]={0x48,0x85,0xd2,0x75,0x0d,0x48,0x8b,0x41,0x10,0x89,0x50,0x08,0x48,0x83,0x41,0x10};
        auto expected=base+0x7971e0;
        if (table[43]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushstring");
        api.lua_pushstring=reinterpret_cast<decltype(api.lua_pushstring)>(table[43]);
    }
    { // lua_pushvalue, SDK member pushvalue
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0x4c,0x8b,0xd1,0xe8,0x34,0xfa,0xff,0xff,0x4d,0x8b,0x42,0x10};
        auto expected=base+0x796ba0;
        if (table[15]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_pushvalue");
        api.lua_pushvalue=reinterpret_cast<decltype(api.lua_pushvalue)>(table[15]);
    }
    { // lua_rawequal, SDK member rawequal
        const unsigned char prefix[16]={0x40,0x53,0x48,0x83,0xec,0x20,0x45,0x8b,0xd8,0x4c,0x8b,0xd1,0xe8,0xcf,0xf8,0xff};
        auto expected=base+0x796d00;
        if (table[28]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_rawequal");
        api.lua_rawequal=reinterpret_cast<decltype(api.lua_rawequal)>(table[28]);
    }
    { // lua_rawget, SDK member rawget
        const unsigned char prefix[16]={0x40,0x53,0x48,0x83,0xec,0x20,0x4c,0x8b,0xd1,0xe8,0x42,0xf1,0xff,0xff,0x49,0x8b};
        auto expected=base+0x797490;
        if (table[52]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_rawget");
        api.lua_rawget=reinterpret_cast<decltype(api.lua_rawget)>(table[52]);
    }
    { // lua_rawgeti, SDK member rawgeti
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0x45,0x8b,0xd0,0x4c,0x8b,0xd9,0xe8,0x01,0xf1,0xff,0xff,0x41};
        auto expected=base+0x7974d0;
        if (table[53]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_rawgeti");
        api.lua_rawgeti=reinterpret_cast<decltype(api.lua_rawgeti)>(table[53]);
    }
    { // lua_replace, SDK member replace
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0x8b,0xfa,0x48,0x8b,0xd9,0x81};
        auto expected=base+0x796a60;
        if (table[18]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_replace");
        api.lua_replace=reinterpret_cast<decltype(api.lua_replace)>(table[18]);
    }
    { // lua_setfield, SDK member setfield
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x30,0x4d,0x8b,0xd0,0x48,0x8b,0xd9};
        auto expected=base+0x797690;
        if (table[59]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_setfield");
        api.lua_setfield=reinterpret_cast<decltype(api.lua_setfield)>(table[59]);
    }
    { // lua_setmetatable, SDK member setmetatable
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0x4c,0x8b,0xd1,0xe8,0x64,0xed,0xff,0xff,0x49,0x8b,0x52,0x10};
        auto expected=base+0x797870;
        if (table[62]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_setmetatable");
        api.lua_setmetatable=reinterpret_cast<decltype(api.lua_setmetatable)>(table[62]);
    }
    { // lua_settop, SDK member settop
        const unsigned char prefix[16]={0x85,0xd2,0x78,0x40,0x4c,0x63,0xc2,0x48,0x8b,0x51,0x18,0x4d,0x03,0xc0,0x4a,0x8d};
        auto expected=base+0x796960;
        if (table[14]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_settop");
        api.lua_settop=reinterpret_cast<decltype(api.lua_settop)>(table[14]);
    }
    { // lua_toboolean, SDK member toboolean
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0xe8,0x17,0xf7,0xff,0xff,0x8b,0x48,0x08,0x85,0xc9,0x74,0x14};
        auto expected=base+0x796ec0;
        if (table[32]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_toboolean");
        api.lua_toboolean=reinterpret_cast<decltype(api.lua_toboolean)>(table[32]);
    }
    { // lua_tointeger, SDK member tointeger
        const unsigned char prefix[16]={0x48,0x83,0xec,0x38,0xe8,0x77,0xf7,0xff,0xff,0x8b,0x48,0x08,0x83,0xf9,0x03,0x74};
        auto expected=base+0x796e60;
        if (table[31]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_tointeger");
        api.lua_tointeger=reinterpret_cast<decltype(api.lua_tointeger)>(table[31]);
    }
    { // lua_tolstring, SDK member tolstring
        const unsigned char prefix[16]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xec,0x20,0x49};
        auto expected=base+0x796ef0;
        if (table[33]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_tolstring");
        api.lua_tolstring=reinterpret_cast<decltype(api.lua_tolstring)>(table[33]);
    }
    { // lua_tonumber, SDK member tonumber
        const unsigned char prefix[16]={0x48,0x83,0xec,0x38,0xe8,0xd7,0xf7,0xff,0xff,0x8b,0x48,0x08,0x83,0xf9,0x03,0x74};
        auto expected=base+0x796e00;
        if (table[30]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_tonumber");
        api.lua_tonumber=reinterpret_cast<decltype(api.lua_tonumber)>(table[30]);
    }
    { // lua_touserdata, SDK member touserdata
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0xe8,0x97,0xf5,0xff,0xff,0x8b,0x48,0x08,0x83,0xf9,0x02,0x74};
        auto expected=base+0x797040;
        if (table[36]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_touserdata");
        api.lua_touserdata=reinterpret_cast<decltype(api.lua_touserdata)>(table[36]);
    }
    { // lua_type, SDK member type
        const unsigned char prefix[16]={0x48,0x83,0xec,0x28,0xe8,0x07,0xfa,0xff,0xff,0x48,0x8d,0x0d,0x00,0x2c,0xf6,0x00};
        auto expected=base+0x796bd0;
        if (table[25]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_type");
        api.lua_type=reinterpret_cast<decltype(api.lua_type)>(table[25]);
    }
    { // lua_typename, SDK member lua_typename
        const unsigned char prefix[16]={0x83,0xfa,0xff,0x75,0x08,0x48,0x8d,0x05,0x74,0x0d,0xfa,0x00,0xc3,0x48,0x63,0xc2};
        auto expected=base+0x796c00;
        if (table[26]!=expected || !readable(expected,16,true) || std::memcmp(expected,prefix,16))
            return fail("LuaApi validation failed: lua_typename");
        api.lua_typename=reinterpret_cast<decltype(api.lua_typename)>(table[26]);
    }
    if (!accept_native_api(&api)) return fail("Host API binding rejected");
    boot_status="validated build 26088801 and all 53 LuaApi slots";
    return true;
}
HD2_EXPORT int luaopen_hd2_nativeinfo(lua_State *L) {
    if (!L) {fail("Null Lua state");return 0;}
    if (!bind_current_host()) return 0;
    return open_nativeinfo(L);
}
