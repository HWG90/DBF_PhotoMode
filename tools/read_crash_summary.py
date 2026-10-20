"""Read exception/module information from an existing dump without process access."""
import struct
import sys
from pathlib import Path
with Path(sys.argv[1]).open('rb') as f:
    header=f.read(32)
    assert header[:4]==b'MDMP'
    count,rva=struct.unpack_from('<II',header,8)
    f.seek(rva)
    streams={kind:(size,at) for kind,size,at in struct.iter_unpack('<III',f.read(count*12))}
    size,at=streams[6];f.seek(at);exception=f.read(size)
    code=struct.unpack_from('<I',exception,8)[0]
    fault=struct.unpack_from('<Q',exception,24)[0]
    print('Exception:',hex(code),'address:',hex(fault),'parameters:',struct.unpack_from('<3Q',exception,40))
    size,at=streams[4];f.seek(at);data=f.read(size)
    modules=[]
    for i in range(struct.unpack_from('<I',data)[0]):
        offset=4+i*108
        base,length=struct.unpack_from('<QI',data,offset)
        name_rva=struct.unpack_from('<I',data,offset+20)[0]
        f.seek(name_rva);name_size=struct.unpack('<I',f.read(4))[0]
        name=f.read(name_size).decode('utf-16-le')
        modules.append((base,length,name))
        if base<=fault<base+length:print('Fault module:',Path(name).name,'offset:',hex(fault-base))
    context_size,context_rva=struct.unpack_from('<II',exception,160)
    f.seek(context_rva);context=f.read(context_size)
    print('RIP:',hex(struct.unpack_from('<Q',context,248)[0]),'RSP:',hex(struct.unpack_from('<Q',context,152)[0]))
    ranges=[]
    if 9 in streams:
        size,at=streams[9];f.seek(at);data=f.read(size)
        count,physical=struct.unpack_from('<QQ',data)
        for i in range(count):
            start,length=struct.unpack_from('<QQ',data,16+i*16)
            ranges.append((start,length,physical));physical+=length
    elif 5 in streams:
        size,at=streams[5];f.seek(at);data=f.read(size)
        for i in range(struct.unpack_from('<I',data)[0]):
            start,length,physical=struct.unpack_from('<QII',data,4+i*16)
            ranges.append((start,length,physical))
    def read(address,length):
        for start,size,physical in ranges:
            if start<=address and address+length<=start+size:
                f.seek(physical+address-start);return f.read(length)
        return b''
    stack=read(struct.unpack_from('<Q',context,152)[0],512)
    for offset in range(0,len(stack),8):
        value=struct.unpack_from('<Q',stack,offset)[0]
        for base,size,name in modules:
            if base<=value<base+size:print('Stack',hex(offset),Path(name).name,hex(value-base))
    code=read(fault-32,96)
    if code:
        from capstone import Cs,CS_ARCH_X86,CS_MODE_64
        for instruction in Cs(CS_ARCH_X86,CS_MODE_64).disasm(read(fault-45,109),fault-45):
            print(hex(instruction.address),instruction.mnemonic,instruction.op_str)
        engine=next(base for base,size,name in modules if name.lower().endswith('helldivers2.exe'))
        for offset in (0x99a980,):
            print('Caller',hex(offset))
            for instruction in Cs(CS_ARCH_X86,CS_MODE_64).disasm(read(engine+offset,128),engine+offset):
                print(hex(instruction.address-engine),instruction.mnemonic,instruction.op_str)
