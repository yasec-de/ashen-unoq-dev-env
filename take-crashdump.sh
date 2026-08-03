#!/bin/bash
# take-crashdump.sh — capture a forensic crash dump of the hung QRB2210 via JTAG.
#
# The bottleneck is NOT the JTAG link, it's the per-word core-MMU read handshake
# (~8 KB/s, one debug-register transaction per 4 bytes). So we do NOT dump all
# 4 GB of DRAM (that would be ~140 h). We dump everything forensically useful:
# both halted cores' register state + kernel stacks, and the kernel static image
# (code + all globals + per-cpu + bss), which holds every structure the analysis
# relies on (cpu masks, csd_data, rcu_state, console_*, runqueues, panic_cpu).
#
# Usage:
#   ./take-crashdump.sh            # targeted forensic dump (~1.5 h, default)
#   ./take-crashdump.sh --full     # ALSO dump all 4 GB physical DRAM (~140 h!)
#
# Prereqs: openocd running with the repo openocd.cfg (telnet :4444, gdb :3333/:3335),
# cores 0 and 2 online (the hang signature), 1 and 3 in reset.

set -u
GDB=${GDB:-gdb}
VMLINUX=linux/vmlinux
TELNET="ncat 127.0.0.1 4444"
OUT="crashdumps/$(date +%Y%m%d-%H%M%S)"
# Per-core gdb ports from openocd.cfg. cores 1,3 are in reset (unreadable).
declare -A PORT=( [0]=3333 [2]=3335 )

mkdir -p "$OUT"
echo "crashdump -> $OUT"

oocd() { printf '%b' "$1\nexit\n" | $TELNET 2>/dev/null | tr -d '\357\277\275'; }

# 1. Halt the two online cores cleanly. dbginit re-inits the debug/CTI block;
#    without it a crash-wedged core refuses to halt (reads back as AArch32).
echo "[1/4] halting online cores (0,2) with dbginit ..."
oocd 'targets auto0.a53.0\naarch64 dbginit\nhalt\ntargets auto0.a53.2\naarch64 dbginit\nhalt\ntargets' \
  | sed -n '/TargetName/,$p' | tee "$OUT/core-states.txt"

# 2. Full register dump per online core (x0-x30, sp, pc, cpsr, v0-v31, fpscr).
echo "[2/4] dumping CPU registers ..."
for c in 0 2; do
  oocd "targets auto0.a53.$c\nreg" \
    | sed -n '/Aarch64 registers/,/^>/p' | sed '/^>/d' \
    > "$OUT/cpu$c-registers.txt"
  echo "  cpu$c: $(grep -c ':' "$OUT/cpu$c-registers.txt") register lines"
done
for c in 1 3; do
  printf 'CPU %s: STATE=reset (PSCI CPU_OFF / crash-stopped secondary).\n' "$c" > "$OUT/cpu$c-registers.txt"
  printf 'Powered down; debug logic off. Registers NOT readable via JTAG.\n' >> "$OUT/cpu$c-registers.txt"
done

# 3. Kernel stacks of the two halted cores (16 KB THREAD_SIZE, aligned down from sp).
#    Read via the core's own gdb (VA, through its MMU).
echo "[3/4] dumping kernel stacks (16 KB each) ..."
for c in 0 2; do
  sp=$(awk -F'[():]' '/\) sp /{gsub(/ /,"",$NF); print $NF}' "$OUT/cpu$c-registers.txt" | head -1)
  if [ -z "$sp" ]; then echo "  cpu$c: no sp, skipping"; continue; fi
  base=$(printf '0x%x' $(( sp & ~0x3fff )))           # THREAD_SIZE=16K aligned
  top=$(printf '0x%x'  $(( (sp & ~0x3fff) + 0x4000 )))
  echo "  cpu$c: sp=$sp stack $base..$top"
  $GDB --batch -nx -ex 'set pagination off' -ex 'set architecture aarch64' \
    -ex 'set remotetimeout 120' -ex "file $VMLINUX" -ex "target extended-remote :${PORT[$c]}" \
    -ex "dump binary memory $OUT/cpu$c-stack.bin $base $top" \
    >/dev/null 2>&1
  ls -l "$OUT/cpu$c-stack.bin" 2>/dev/null | awk '{print "    -> "$5" bytes"}'
done

# 4. Kernel static image: _text..ALIGN(_end). Holds code + all globals + per-cpu
#    + bss. ~41 MB at ~8 KB/s -> ~1.4 h. Read via core 2 gdb (stable stub).
echo "[4/4] dumping kernel static image (_text.._end, ~41 MB, ~1.4 h) ..."
TEXT=$($GDB --batch -nx -ex "file $VMLINUX" -ex 'p/x _text' 2>/dev/null | awk '/\$1/{print $NF}')
END=$($GDB  --batch -nx -ex "file $VMLINUX" -ex 'p/x _end'  2>/dev/null | awk '/\$1/{print $NF}')
echo "  range $TEXT .. $END"
time $GDB --batch -nx -ex 'set pagination off' -ex 'set architecture aarch64' \
  -ex 'set remotetimeout 600' -ex "file $VMLINUX" -ex 'target extended-remote :3335' \
  -ex "dump binary memory $OUT/kernel-image.bin $TEXT $END" \
  2>&1 | grep -iE 'real|error|cannot'
ls -l "$OUT/kernel-image.bin" 2>/dev/null | awk '{print "  -> "$5" bytes"}'

# Optional: full physical DRAM (4 GB: phys 0x40000000..0x140000000). ~140 h.
if [ "${1:-}" = "--full" ]; then
  echo "[+] FULL DRAM dump requested: 4 GB @ ~8 KB/s ~= 140 HOURS. Reading phys via core 2 VA..."
  # Linear map: VA = phys - PHYS_OFFSET + PAGE_OFFSET. Simpler: dump the linear-map
  # window the kernel uses. We dump by physical address through the core MMU's
  # linear mapping. PAGE_OFFSET for the lm region:
  $GDB --batch -nx -ex 'set pagination off' -ex 'set architecture aarch64' \
    -ex 'set remotetimeout 3600' -ex "file $VMLINUX" -ex 'target extended-remote :3335' \
    -ex "dump binary memory $OUT/dram-linear.bin (long)__va(0x40000000) (long)__va(0x140000000)" \
    2>&1 | grep -iE 'real|error|cannot'
fi

echo
echo "DONE. crashdump in: $OUT"
ls -l "$OUT"
