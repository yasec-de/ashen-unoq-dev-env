#!/bin/sh
# Dump TrustZone's diag area (tzdbg_t) to stdout. Shared IMEM 0xc125720 holds its physical
# address (downstream qcom,tz-log); the area is 0x3000 bytes. Only these two reads are safe:
# other IMEM addresses can stall the bus.
exec python3 -c '
import mmap,os,sys
f=os.open("/dev/mem",os.O_RDONLY|os.O_SYNC)
def rd(pa,n):
    b=pa&~0xfff; m=mmap.mmap(f,(pa-b+n+0xfff)&~0xfff,mmap.MAP_SHARED,mmap.PROT_READ,offset=b)
    w=memoryview(m).cast("I"); o=(pa-b)//4
    return b"".join(w[o+i].to_bytes(4,"little") for i in range(n//4))
diag=int.from_bytes(rd(0xc125720,4),"little")
assert diag==0xc116000, hex(diag)
sys.stdout.buffer.write(rd(diag,0x3000))'
