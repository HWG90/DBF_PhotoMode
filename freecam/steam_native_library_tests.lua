-- Bridge paths: folder installs load from port51/, the archive build from its native folder.
local saved=mod
mod={dir='C:/Mods/dbf_freecam_lua51'}
local host=dofile('freecam/host_native.lua')
assert(host.library('hd2_nativeinfo_x.dll')=='C:/Mods/dbf_freecam_lua51/port51/hd2_nativeinfo_x.dll','Folder installs load bridges from port51/')
mod={native_dir='C:/LLL/Helldivers2/Native'}
assert(host.library('hd2_nativeinfo_x.dll')=='C:/LLL/Helldivers2/Native/hd2_nativeinfo_x.dll','The archive build loads bridges from its native folder')
mod=saved
print('Native bridge paths: folder port51/ and archive native folder passed')
