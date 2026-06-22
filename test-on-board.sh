#!/usr/bin/env bash
# Builds the kernel (build-kernel.sh, inside `nix develop`) and boots it on
# the attached UNO Q board via kexec, bypassing U-Boot/systemd-boot entirely.
# This is the fast iterate-on-the-kernel path; to build and flash a full
# image permanently, use build-image.sh + flash.sh instead.
#
# Why kexec and not a new bootloader-spec entry: the board's U-Boot UEFI
# implementation doesn't support runtime SetVariable (confirmed via dmesg:
# "Firmware does not support SetVariableRT"), so `bootctl set-oneshot` can't
# schedule a one-time boot -- there is no safe automatic revert if a new
# default entry fails to boot. kexec instead loads the new kernel from
# the *running* system and jumps to it directly; the on-disk boot config is
# never touched, so a hung/failed kexec just needs a power cycle to fall
# back to the untouched stock kernel.
set -euo pipefail
cd "$(dirname "$0")"

nix develop --command ./build-kernel.sh

IMAGE=linux/arch/arm64/boot/Image
DTB=linux/arch/arm64/boot/dts/qcom/qrb2210-arduino-imola.dtb

adb get-state >/dev/null

MACHINE_ID=$(adb shell cat /etc/machine-id | tr -d '\r\n')
RUNNING_REL=$(adb shell uname -r | tr -d '\r\n')
INITRD=$(adb shell cat /proc/cmdline | tr ' ' '\n' | sed -n 's/^initrd=//p' | tr '\\' '/' | tr -d '\r\n')
INITRD_PATH="/boot/efi${INITRD}"
CMDLINE=$(adb shell cat /proc/cmdline | tr -d '\r\n' | sed -E 's/initrd=[^ ]+ ?//')

echo "machine-id:   $MACHINE_ID"
echo "running rel:  $RUNNING_REL"
echo "initrd:       $INITRD_PATH"
echo "cmdline:      $CMDLINE"

adb shell "which kexec >/dev/null 2>&1" || \
  adb shell "echo arduino | sudo -S apt-get install -y kexec-tools"

adb push "$IMAGE" /tmp/rebuild-Image
adb push "$DTB" /tmp/rebuild.dtb

adb shell "echo arduino | sudo -S kexec -l /tmp/rebuild-Image --dtb=/tmp/rebuild.dtb --initrd=$INITRD_PATH --command-line='$CMDLINE'"

echo "Kernel loaded into kexec. Boot id before switch:"
adb shell cat /proc/sys/kernel/random/boot_id

read -r -p "Run 'kexec -e' now and switch into the new kernel? [y/N] " ans
if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
  echo "Not executing. Kernel stays loaded; run manually with:"
  echo "  adb shell \"echo arduino | sudo -S kexec -e\""
  exit 0
fi

adb shell "echo arduino | sudo -S kexec -e" || true

echo "Waiting for board to come back..."
adb wait-for-device shell true
adb shell uname -a
adb shell cat /proc/sys/kernel/random/boot_id
