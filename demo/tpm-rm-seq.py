# Replay the kernel resource manager's sequence on /dev/tpm0 with raw commands and timings:
# CreatePrimary -> ContextSave(obj) -> FlushContext(obj) -> ContextLoad(blob) -> ReadPublic(new handle).
import os, struct, time, signal
fd = os.open("/dev/tpm0", os.O_RDWR)
def tx(name, cc, handles=b"", auth=None, params=b""):
    tag = 0x8002 if auth is not None else 0x8001
    body = handles + ((struct.pack(">I", len(auth)) + auth) if auth is not None else b"") + params
    t0 = time.time(); os.write(fd, struct.pack(">HII", tag, 10 + len(body), cc) + body)
    signal.alarm(20); r = os.read(fd, 8192); signal.alarm(0)
    rc = struct.unpack_from(">I", r, 6)[0]
    print(f"{name:14s} rc={rc:#x} len={len(r)} {time.time()-t0:.2f}s")
    return r
pw = struct.pack(">IHBH", 0x40000009, 0, 0, 0)
pub = struct.pack(">HHI", 0x0023, 0x000B, 0x00030472) + struct.pack(">H", 0) + \
      struct.pack(">HHHHHHH", 0x0006, 128, 0x0043, 0x0010, 0x0003, 0x0010, 0x0010) + struct.pack(">HH", 0, 0)
r = tx("CreatePrimary", 0x131, struct.pack(">I", 0x40000001), pw,
       struct.pack(">HHH", 4, 0, 0) + struct.pack(">H", len(pub)) + pub + struct.pack(">H", 0) + struct.pack(">I", 0))
h = struct.unpack_from(">I", r, 10)[0]
r = tx("ContextSave", 0x162, struct.pack(">I", h))
blob = r[10:]
tx("FlushContext", 0x165, params=struct.pack(">I", h))
r = tx("ContextLoad", 0x161, params=blob)
h2 = struct.unpack_from(">I", r, 10)[0]
tx("ReadPublic", 0x173, struct.pack(">I", h2))
tx("FlushContext", 0x165, params=struct.pack(">I", h2))
