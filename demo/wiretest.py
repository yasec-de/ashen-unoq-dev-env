# Board-side SoC<->MCU wire test: TLMM via /dev/mem, MCU GPIO via OpenOCD Tcl (port 6666).
# Every register touched is restored. Usage: python3 wiretest.py
import mmap, os, socket, struct, subprocess, time

ocd = subprocess.Popen(["/opt/openocd/bin/openocd", "-s", "/opt/openocd", "-f", "openocd_gpiod.cfg", "-c", "init"],
                       cwd="/opt/openocd", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.5)
s = socket.create_connection(("127.0.0.1", 6666))
def tcl(cmd):
    s.sendall(cmd.encode() + b"\x1a"); buf = b""
    while not buf.endswith(b"\x1a"): buf += s.recv(4096)
    return buf[:-1].decode().strip()
def rd(a): return int(tcl(f"lindex [read_memory {a:#x} 32 1] 0"), 0)
def wr(a, v): tcl(f"write_memory {a:#x} 32 {v:#x}")

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
def tlmm(g): return mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x500000 + 0x1000 * g)
def tin(m): return struct.unpack_from("<I", m, 4)[0] & 1

GM, GPU, GIDR, GODR = 0x42021800, 0x4202180C, 0x42021810, 0x42021814
tcl("halt")
moder, pupdr, odr = rd(GM), rd(GPU), rd(GODR)
t71, t80 = tlmm(71), tlmm(80)
c71, i71 = struct.unpack_from("<II", t71, 0)
c80, i80 = struct.unpack_from("<II", t80, 0)
try:
    # A: SoC GPIO_71 drives 0/1, MCU PG8 input with pull-up / pull-down
    struct.pack_into("<I", t71, 0, 0x200)
    for pull, name in ((1, "pull-up"), (2, "pull-down")):
        wr(GM, moder & ~(3 << 16)); wr(GPU, (pupdr & ~(3 << 16)) | (pull << 16))
        res = []
        for lvl in (0, 1, 0, 1):
            struct.pack_into("<I", t71, 4, lvl << 1); time.sleep(0.05)
            res.append(f"{lvl}->{(rd(GIDR) >> 8) & 1}")
        print(f"A GPIO_71 -> PG8 ({name}):", " ".join(res))
    struct.pack_into("<I", t71, 0, c71); struct.pack_into("<I", t71, 4, i71)
    wr(GM, moder); wr(GPU, pupdr)
    # B: MCU PG8 drives 0/1, SoC GPIO_71 input with pull-up / pull-down
    for pull, name in ((3, "pull-up"), (1, "pull-down")):
        struct.pack_into("<I", t71, 0, pull)
        wr(GM, (moder & ~(3 << 16)) | (1 << 16)); res = []
        for lvl in (0, 1, 0, 1):
            wr(GODR, (odr & ~(1 << 8)) | (lvl << 8)); time.sleep(0.05)
            res.append(f"{lvl}->{tin(t71)}")
        print(f"B PG8 -> GPIO_71 ({name}):", " ".join(res))
    struct.pack_into("<I", t71, 0, c71); struct.pack_into("<I", t71, 4, i71)
    wr(GM, moder); wr(GODR, odr)
    # Control: MCU PG7 drives 0/1, SoC GPIO_80 (left as-is, input)
    wr(GM, (moder & ~(3 << 14)) | (1 << 14)); res = []
    for lvl in (0, 1, 0, 1):
        wr(GODR, (odr & ~(1 << 7)) | (lvl << 7)); time.sleep(0.05)
        res.append(f"{lvl}->{tin(t80)}")
    print("C PG7 -> GPIO_80 (control):", " ".join(res))
finally:
    struct.pack_into("<I", t71, 0, c71); struct.pack_into("<I", t71, 4, i71)
    struct.pack_into("<I", t80, 0, c80)
    wr(GM, moder); wr(GPU, pupdr); wr(GODR, odr)
    ok = (rd(GM), rd(GPU), rd(GODR)) == (moder, pupdr, odr) and struct.unpack_from("<I", t71, 0)[0] == c71
    print("restored:", "OK" if ok else "MISMATCH")
    tcl("resume"); s.close(); ocd.terminate(); ocd.wait()
