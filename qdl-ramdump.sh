#!/bin/sh
set -euo pipefail

fn=crashdumps/qdl-ramdump-$(date -u +%Y%m%d-%H%M%S)
mkdir -p $fn
qdl/build/qdl ramdump -o $fn
cp linux/vmlinux linux/vmlinux.symvers linux/System.map $fn/
cp linux/.config $fn/KERNEL_CONFIG
./capture-last-boot.sh
cp last-boot.log $fn/
