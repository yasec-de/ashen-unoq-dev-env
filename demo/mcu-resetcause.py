# Read (and with --clear, clear) the MCU's reset-cause flags (RCC_CSR) over SWD without halting it.
import socket, subprocess, time
ocd = subprocess.Popen(["/opt/openocd/bin/openocd", "-s", "/opt/openocd", "-f", "openocd_gpiod.cfg", "-c", "init"],
                       cwd="/opt/openocd", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.5)
s = socket.create_connection(("127.0.0.1", 6666))
def tcl(cmd):
    s.sendall(cmd.encode() + b"\x1a"); buf = b""
    while not buf.endswith(b"\x1a"): buf += s.recv(4096)
    return buf[:-1].decode().strip()
import sys
csr = int(tcl("lindex [read_memory 0x46020cf4 32 1] 0"), 0)
flags = {25: "OBLRST", 26: "PINRST (NRST pin)", 27: "BORRST (power-on/brown-out)", 28: "SFTRST (software: tamper reset)",
         29: "IWDGRST", 30: "WWDGRST", 31: "LPWRRST"}
print("RCC_CSR %#010x:" % csr, ", ".join(n for b, n in flags.items() if csr >> b & 1) or "no flags")
if "--clear" in sys.argv:
    tcl("write_memory 0x46020cf4 32 %#x" % (csr | 1 << 23))   # RMVF: clear the reset flags
    print("cleared; now %#010x" % int(tcl("lindex [read_memory 0x46020cf4 32 1] 0"), 0))
s.close(); ocd.terminate(); ocd.wait()
