#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <vector>
#include <cstring>
#include <cstdint>
#include <cstdlib>
struct Blob {void**v;};
static void* data(Blob*b){return reinterpret_cast<void*(*)(Blob*)>(b->v[3])(b);}
static size_t size(Blob*b){return reinterpret_cast<size_t(*)(Blob*)>(b->v[4])(b);}
static bool save(const char*p,Blob*b){FILE*f=fopen(p,"wb");if(!f)return false;bool ok=fwrite(data(b),1,size(b),f)==size(b);fclose(f);return ok;}
int main(int argc,char**argv){
 if(argc!=6)return 2;
 HMODULE h=LoadLibraryA(argv[1]);if(!h){fprintf(stderr,"load %lu\n",GetLastError());return 3;}
 FILE*f=fopen(argv[3],"rb");if(!f)return 4;fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);std::vector<char>s(n);fread(s.data(),1,n,f);fclose(f);Blob*out=nullptr,*error=nullptr;HRESULT status=E_FAIL;
 if(!strcmp(argv[2],"compile")){
  auto fn=reinterpret_cast<HRESULT(*)(const void*,size_t,const char*,const void*,void*,const char*,const char*,UINT,UINT,Blob**,Blob**)>(GetProcAddress(h,"D3DCompile"));
  status=fn(s.data(),s.size(),"wj-sdr.hlsl",nullptr,nullptr,"photo_resolved_v2","ps_5_0",1<<15,0,&out,&error);
 }else if(!strcmp(argv[2],"listing")){
  auto fn=reinterpret_cast<HRESULT(*)(const void*,size_t,UINT,const char*,Blob**)>(GetProcAddress(h,"D3DDisassemble"));status=fn(s.data(),s.size(),0,nullptr,&out);
 }else if(!strncmp(argv[2],"pad",3)){
  auto fn=reinterpret_cast<HRESULT(*)(const void*,size_t,int,UINT,const void*,size_t,Blob**)>(GetProcAddress(h,"D3DSetBlobPart"));std::vector<char>p(4);Blob*first=nullptr;
  status=fn(s.data(),s.size(),10,0,p.data(),p.size(),&first);if(status<0)return 5;size_t window=((size(first)+15)/16)*16;if(window<7152)window=7152;window+=strtoul(argv[2]+3,nullptr,10)%16;p.resize(window-size(first)+4);status=fn(s.data(),s.size(),10,0,p.data(),p.size(),&out);
 }
 if(error){fwrite(data(error),1,size(error),stderr);save(argv[5],error);}if(status<0||!out){fprintf(stderr,"HRESULT %lx\n",static_cast<unsigned long>(status));return 6;}return save(argv[4],out)?0:7;
}
