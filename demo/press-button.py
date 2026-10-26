# Simulate pressing the D10 tamper button without halting the MCU (a halt would itself trip the
# heartbeat): drive PB9 low as an output via SWD while the firmware runs; its EXTI sees the low level
# exactly as from the button. The MCU then wipes and resets, which restores PB9 to its input config.
import socket, subprocess, time
ocd = subprocess.Popen(["/opt/openocd/bin/openocd", "-s", "/opt/openocd", "-f", "openocd_gpiod.cfg", "-c", "init"],
                       cwd="/opt/openocd", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.5)
s = socket.create_connection(("127.0.0.1", 6666))
def tcl(cmd):
    s.sendall(cmd.encode() + b"\x1a"); buf = b""
    while not buf.endswith(b"\x1a"): buf += s.recv(4096)
    return buf[:-1].decode().strip()
GPIOB_MODER, GPIOB_BRR = 0x42020400, 0x42020428
moder = int(tcl(f"lindex [read_memory {GPIOB_MODER:#x} 32 1] 0"), 0)
tcl(f"write_memory {GPIOB_BRR:#x} 32 {1 << 9:#x}")                        # PB9 output latch = 0
tcl(f"write_memory {GPIOB_MODER:#x} 32 {(moder & ~(3 << 18)) | (1 << 18):#x}")  # PB9 -> output
print("PB9 driven low at", time.strftime("%T"), flush=True)
s.close(); ocd.terminate(); ocd.wait()
