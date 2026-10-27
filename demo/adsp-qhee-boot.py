# TEST: replay stock QHEE's LPASS PILSubsys_bringUp (hyp.mbn 0x4574f294) from userspace while
# qcom_q6v5_pas waits for the ADSP after auth_and_reset, and its teardown (0x45762970) after a stop.
# Run as root: adsp-qhee-boot.py ENTRY | stop
import mmap, os, sys, time
f = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
maps = {}
def reg(a):
    pg = a & ~0xfff
    if pg not in maps:
        maps[pg] = memoryview(mmap.mmap(f, 0x1000, mmap.MAP_SHARED,
                                        mmap.PROT_READ | mmap.PROT_WRITE, offset=pg)).cast("I")
    return maps[pg], (a & 0xfff) // 4
def r(a):
    m, i = reg(a); return m[i]
def w(a, v):
    m, i = reg(a); m[i] = v & 0xffffffff
def orr(a, b):
    w(a, r(a) | b)
def poll(a, ok, n, what):
    for _ in range(n):
        v = r(a)
        if ok(v):
            print(f"{what}: {a:#x} = {v:#010x}"); return True
        time.sleep(0.001)
    print(f"{what}: TIMEOUT {a:#x} = {v:#010x}"); return False
def stop():
    orr(0xa40001c, 1)
    w(0xa789090, r(0xa789090) & ~1)
    if not poll(0xa789090, lambda v: v >> 31, 50, "lpass 9090 off"):
        return
    orr(0xa78908c, 1); poll(0xa78908c, lambda v: v & 1, 50, "lpass 908c")
    time.sleep(0.001); w(0xa78908c, r(0xa78908c) & ~1); time.sleep(0.001)
    for a in (0xa5403e8, 0xa540000):
        for b in (1, 2, 4):
            w(a, r(a) & ~b)
    orr(0xa789090, 1); poll(0xa789090, lambda v: not v >> 31, 50, "lpass 9090 on")
    if not r(0xa796090) >> 31:
        w(0xa796090, r(0xa796090) & ~1)
        poll(0xa796090, lambda v: v >> 31, 50, "lpass 6090 off")
        poll(0xa79609c, lambda v: v & 1, 50, "lpass 609c")
        poll(0xac02004, lambda v: not v >> 31, 50, "ac02004")
    w(0x362000, 1); poll(0x362004, lambda v: v & 1, 1000, "halt ack")
    print(f"idle {r(0x362008):#x}")
    orr(0x14c0000, 1); time.sleep(0.001); w(0x14c0000, 0); w(0x362000, 0); time.sleep(0.001)
    print("stopped")
if sys.argv[1] == "stop":
    stop(); sys.exit()
entry = int(sys.argv[1], 0)
orr(0x143a00c, 1); poll(0x143a00c, lambda v: not v >> 31, 50, "gcc 3a00c")
orr(0xa78901c, 1); poll(0xa78901c, lambda v: not v >> 31, 50, "lpass 901c")
orr(0xa789020, 1); poll(0xa789020, lambda v: not v >> 31, 50, "lpass 9020")
save = r(0xa400018); print(f"q6ss 0x18 = {save:#x}")
orr(0xa783090, 0xf000)
orr(0x143a008, 1); poll(0x143a008, lambda v: not v >> 31, 50, "gcc 3a008")
orr(0xa400038, 1); orr(0xa40003c, 1); orr(0xa400020, 1)
w(0xa400018, save)
if save:
    orr(0xa78a00c, 1); orr(0xa78a014, 1)
orr(0xa955018, 4); orr(0xa955020, 4)
poll(0xa955020, lambda v: v & 1, 1000, "a955020")
w(0xa95b000, 1)
w(0xa95b004, ((entry >> 4) & 0xffffff0) | (r(0xa95b004) & 0xf))
print(f"evb {r(0xa95b000):#x} {r(0xa95b004):#x}")
orr(0xa400400, 1); w(0xa400404, 1)
poll(0xa400408, lambda v: v != 0, 2000, "boot status")
