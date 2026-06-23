#!/usr/bin/env bash
# Build the out-of-tree module (cross toolchain via nix develop) and load it on
# the attached UNO Q over adb: push, rmmod-if-loaded, insmod, show dmesg.
# Pass a module name as $1 (default: hello). Non-destructive -- just insmod.
set -euo pipefail
cd "$(dirname "$0")"

MOD=${1:-hello}

nix develop ../ --command make

adb get-state >/dev/null
adb push "$MOD.ko" "/tmp/$MOD.ko"

# rmmod first so re-loading an edited module works; ignore "not loaded".
adb shell "rmmod $MOD 2>/dev/null || true"
adb shell "insmod /tmp/$MOD.ko"

echo "--- lsmod ---"
adb shell "lsmod | grep -E '^$MOD ' || echo '($MOD not in lsmod)'"
echo "--- dmesg tail ---"
adb shell "dmesg | grep '$MOD:' | tail -5"
