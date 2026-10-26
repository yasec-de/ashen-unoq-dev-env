# Hold the GPIO_71 <-> PG8 net (SoC UART TX -> MCU LPUART1 RX, via R2504) in a known state for
# probing, until Enter is pressed; then restore everything. Run on the board as root:
#   python3 wirehold.py soc-low | soc-high | mcu-low | mcu-high
# soc-*: SoC GPIO_71 drives the level (GPIO mode), MCU PG8 is a plain input (no pull).
# mcu-*: MCU PG8 drives the level (MCU halted), SoC GPIO_71 is a plain input (no pull).
import mmap, os, socket, struct, subprocess, sys, time

mode = sys.argv[1]
lvl = 1 if mode.endswith("high") else 0
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
t71 = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x500000 + 0x1000 * 71)
c71, i71 = struct.unpack_from("<II", t71, 0)

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
GM, GPU, GODR = 0x42021800, 0x4202180C, 0x42021814
tcl("halt")
moder, pupdr, odr = rd(GM), rd(GPU), rd(GODR)
try:
    if mode.startswith("soc"):
        wr(GM, moder & ~(3 << 16)); wr(GPU, pupdr & ~(3 << 16))          # PG8 input, no pull
        struct.pack_into("<I", t71, 4, lvl << 1); struct.pack_into("<I", t71, 0, 0x200 | (7 << 6))  # 16 mA
    else:
        struct.pack_into("<I", t71, 0, 0x000)                            # GPIO_71 input, no pull
        wr(GODR, (odr & ~(1 << 8)) | (lvl << 8)); wr(GM, (moder & ~(3 << 16)) | (1 << 16))
    input(f"holding {mode}; GPIO_71 pad reads {struct.unpack_from('<I', t71, 4)[0] & 1}. Enter to restore: ")
finally:
    struct.pack_into("<I", t71, 0, c71); struct.pack_into("<I", t71, 4, i71)
    wr(GM, moder); wr(GPU, pupdr); wr(GODR, odr)
    tcl("resume"); s.close(); ocd.terminate(); ocd.wait()
    print("restored")
