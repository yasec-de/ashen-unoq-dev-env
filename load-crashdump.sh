#!/usr/bin/env bash
# Load a Qualcomm QDL ramdump into the crash utility.
# Usage: ./load-crashdump.sh [DUMPDIR] [extra crash args...]
# DUMPDIR defaults to the dump this was set up against.
#
# DDR physical bases come from the dump's load.cmm (Trace32 script):
#   DDRCS0_0.BIN @ 0x40000000   DDRCS1_0.BIN @ 0xc0000000
#
# The vmlinux must have full debug info (CONFIG_DEBUG_INFO_REDUCED=n);
# the reduced vmlinux originally shipped in the dump makes crash abort with
# "no debugging data available".
#
# Two machdep overrides are required:
#   vabits_actual=48  - the kernel is CONFIG_ARM64_VA_BITS_52 but runs with a
#                       48-bit VA at runtime (no LPA2 on this SoC). crash's
#                       TCR_EL1-from-dump guess is stale, so we force it.
#   phys_offset=0x40000000 - true physical DDR base. crash otherwise picks the
#                       KASLR-biased memstart_addr (0xfff1000040000000) and the
#                       linear-map translation lands outside the dump.
#
# ponytail: values hard-coded from this dump's load.cmm + memstart analysis;
# for a different dump, regenerate addresses from its load.cmm and re-derive
# phys_offset/vabits if the SoC or kernel config differs.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
crash="$here/crash/crash"
dump="${1:-$here/crashdumps/qdl-ramdump-20260630-121143}"
shift || true
dump="$(cd "$dump" && pwd)"   # absolutise before we cd into it

vmlinux="$dump/vmlinux"

cd "$dump"
exec "$crash" --no_panic \
    --machdep vabits_actual=48 \
    --machdep phys_offset=0x40000000 \
    "$@" "$vmlinux" \
    "DDRCS0_0.BIN@0x40000000,DDRCS1_0.BIN@0xc0000000"
