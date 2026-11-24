#!/usr/bin/env bash
# Load a Qualcomm QDL ramdump into the crash utility.
# Usage: ./load-crashdump.sh [DUMPDIR] [extra crash args...]
# DUMPDIR defaults to the newest dump under crash-wipe-exercise/ramdumps.
#
# Everything that varies per dump is derived by derive-kaslr.py: the DDR images
# and their physical bases from load.cmm, and - because CONFIG_RANDOMIZE_BASE=y
# - kimage_voffset and the KASLR offset, read out of the dumped kernel image
# after locating it in DDR. That script also asserts memstart_addr matches the
# phys_offset we pass, so a dump that breaks these assumptions fails loudly.
#
# The vmlinux must have full debug info (CONFIG_DEBUG_INFO_REDUCED=n);
# a reduced vmlinux makes crash abort with "no debugging data available".
#
# One machdep override stays hard-coded:
#   vabits_actual=48  - the kernel is CONFIG_ARM64_VA_BITS_52 but runs with a
#                       48-bit VA at runtime (no LPA2 on this SoC). crash's
#                       TCR_EL1-from-dump guess is stale, so we force it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
crash="$here/crash/crash"
if [[ -d ${1:-} ]]; then
    dump="$1"; shift
else
    dump="$(ls -d "$here"/crash-wipe-exercise/ramdumps/qdl-ramdump-* | tail -1)"
fi
dump="$(cd "$dump" && pwd)"   # absolutise before we cd into it

vmlinux="$dump/vmlinux"

# sets ddr_arg, phys_offset, kimage_voffset, kaslr
eval "$("$here/derive-kaslr.py" "$dump")"

kaslr_arg=()
[[ $kaslr != 0x0 ]] && kaslr_arg=(--kaslr="$kaslr")

cd "$dump"
exec "$crash" --no_panic \
    --machdep vabits_actual=48 \
    --machdep phys_offset="$phys_offset" \
    --machdep kimage_voffset="$kimage_voffset" \
    "${kaslr_arg[@]}" \
    "$@" "$vmlinux" \
    "$ddr_arg"
