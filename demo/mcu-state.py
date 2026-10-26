# Print MCU core state over SWD (OpenOCD on the board): PC/xPSR, fault status, LED, without reset.
import socket, subprocess, time
ocd = subprocess.Popen(["/opt/openocd/bin/openocd", "-s", "/opt/openocd", "-f", "openocd_gpiod.cfg", "-c", "init"],
                       cwd="/opt/openocd", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.5)
s = socket.create_connection(("127.0.0.1", 6666))
def tcl(cmd):
    s.sendall(cmd.encode() + b"\x1a"); buf = b""
    while not buf.endswith(b"\x1a"): buf += s.recv(4096)
    return buf[:-1].decode().strip()
def rd(a): return int(tcl(f"lindex [read_memory {a:#x} 32 1] 0"), 0)
try:
    for i in range(3):
        tcl("halt")
        print("pc", tcl("reg pc"), "| xpsr", tcl("reg xpsr"), "| sp", tcl("reg sp"), "| lr", tcl("reg lr"))
        tcl("resume"); time.sleep(0.3)
    print("CFSR %#010x HFSR %#010x MMFAR %#010x BFAR %#010x SHCSR %#010x" %
          tuple(rd(a) for a in (0xE000ED28, 0xE000ED2C, 0xE000ED34, 0xE000ED38, 0xE000ED24)))
    print("GPIOH ODR (LED PH10):", hex(rd(0x42021C14)))
finally:
    s.close(); ocd.terminate(); ocd.wait()
