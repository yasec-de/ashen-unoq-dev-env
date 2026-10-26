# Raw session context round trip on /dev/tpm0: StartAuthSession(HMAC, unsalted, unbound) ->
# ContextSave -> ContextLoad -> FlushContext, with sizes and timings.
import os, struct, time, signal
fd = os.open("/dev/tpm0", os.O_RDWR)
def tx(name, cc, handles=b"", params=b""):
    body = handles + params
    t0 = time.time(); os.write(fd, struct.pack(">HII", 0x8001, 10 + len(body), cc) + body)
    signal.alarm(20); r = os.read(fd, 8192); signal.alarm(0)
    rc = struct.unpack_from(">I", r, 6)[0]
    print(f"{name:16s} cmd={10+len(body):5d}B rsp={len(r):5d}B rc={rc:#x} {time.time()-t0:.2f}s")
    return r
nonce = os.urandom(32)
r = tx("StartAuthSession", 0x176, struct.pack(">II", 0x40000007, 0x40000007),
       struct.pack(">H", 32) + nonce + struct.pack(">H", 0) + struct.pack(">BHH", 0x00, 0x0010, 0x000B))
h = struct.unpack_from(">I", r, 10)[0]; print("session handle %#x" % h)
r = tx("ContextSave", 0x162, struct.pack(">I", h)); blob = r[10:]
r = tx("ContextLoad", 0x161, params=blob)
h2 = struct.unpack_from(">I", r, 10)[0] if len(r) > 10 else h
tx("FlushContext", 0x165, params=struct.pack(">I", h2))
