#!/usr/bin/env bash
# Copy the built kernel (and optionally a custom dtb) to the board, install it
# via kernel-install (BLS), make that entry the default in loader.conf, and
# reboot. This is install-kernel.sh + set-default + reboot for a one-shot
# "deploy and boot into it" flow.
#
# Usage: ./test-kernel-via-boot.sh [custom.dtb]
#   custom.dtb  optional; replaces the shared board dtb on the ESP.
#
# USER MODIFIED - NOT TO BE EDITED BY CLAUDE / LLM
#
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=linux/arch/arm64/boot/Image
DTB=${1:-linux/arch/arm64/boot/dts/qcom/qrb2210-arduino-imola-ashen-tamper.dtb}
DTB_DEST=qrb2210-arduino-imola-ashen-tamper.dtb

[[ -f "$IMAGE" ]] || { echo "missing $IMAGE, build the kernel first" >&2; exit 1; }
[[ -z "$DTB" || -f "$DTB" ]] || { echo "dtb not found: $DTB" >&2; exit 1; }

VERSION=$(make -sC linux LOCALVERSION=-test kernelrelease)
echo "version:  $VERSION"

adb shell sudo mount -o remount,rw /boot/efi
[ $(adb shell df /boot/efi | tail -n1 | awk "{print \$4}") -lt 50000 ] && { echo "Too little space left on /boot/efi"; exit 1; }

echo "Installing modules..."
rm -rf modules
mkdir modules
make -C linux INSTALL_MOD_PATH=$(realpath modules) modules_install
adb shell sudo rm -rf /lib/modules/$VERSION
adb push modules/lib/modules/$VERSION /tmp/modules
adb shell sudo mv /tmp/modules /lib/modules/$VERSION

echo "Installing devicetree..."
adb shell sudo mkdir -p /lib/modules/$VERSION/dtb
adb push "$DTB" /tmp/dtb
adb shell sudo cp /tmp/dtb /lib/modules/$VERSION/dtb/$DTB_DEST
adb shell sudo cp /tmp/dtb /boot/efi/dtb/$DTB_DEST

echo "Building initrd..."
adb shell sudo update-initramfs -k $VERSION -c

echo "Installing kernel image..."
adb push "$IMAGE" /tmp/Image
adb shell "sudo kernel-install add $VERSION /tmp/Image"

echo "Updating bootloader config..."
# Find the BLS entry id kernel-install just wrote (matches the version) and set
# it as the default in loader.conf. bootctl set-default writes loader.conf.
ENTRY=$(adb shell "sudo bootctl list" | grep -oE '[^ ]+'"$VERSION"'[^ ]*\.conf' | head -1)
[[ -n "$ENTRY" ]] || { echo "couldn't find BLS entry for $VERSION in bootctl list" >&2; exit 1; }
# We can't use "bootctl set-default" since that uses EFI vars, not loader.conf.
# Our platform doesn't have (working) EFI vars.
adb shell "sudo sed -i '/^default/d' /boot/efi/loader/loader.conf"
adb shell "sudo sh -c 'echo \"default $ENTRY\" >> /boot/efi/loader/loader.conf'"
adb shell "sudo grep -e '^console-mode' /boot/efi/loader/loader.conf || sudo sh -c 'echo console-mode keep >> /boot/efi/loader/loader.conf'"
adb shell "sudo grep -e '^timeout' /boot/efi/loader/loader.conf || sudo sh -c 'echo timeout 3 >> /boot/efi/loader/loader.conf'"
adb shell "sudo sed -i '/^devicetree/d' /boot/efi/loader/entries/$ENTRY"
adb shell "sudo sh -c 'echo devicetree /dtb/$DTB_DEST >> /boot/efi/loader/entries/$ENTRY'"

echo "Disabling systemd watchdog use..."
#adb shell "sudo sed -i -E 's/^[#[:space:]]*RuntimeWatchdogSec=.*/RuntimeWatchdogSec=0/' /etc/systemd/system.conf"
#adb shell "sudo grep -q '^RuntimeWatchdogSec=' /etc/systemd/system.conf || echo 'RuntimeWatchdogSec=0' >> /etc/systemd/system.conf"
#adb shell "sudo sed -i -E 's/^[#[:space:]]*RebootWatchdogSec=.*/RebootWatchdogSec=0/' /etc/systemd/system.conf"
#adb shell "sudo grep -q '^RebootWatchdogSec=' /etc/systemd/system.conf || echo 'RebootWatchdogSec=0' >> /etc/systemd/system.conf"
#adb shell "sudo sed -i -E 's/^[#[:space:]]*KExecWatchdogSec=.*/KExecWatchdogSec=0/' /etc/systemd/system.conf"
#adb shell "sudo grep -q '^KExecWatchdogSec=' /etc/systemd/system.conf || echo 'KExecWatchdogSec=0' >> /etc/systemd/system.conf"

echo "Rebooting target..."
adb shell sudo sync
adb shell sudo mount -o remount,ro /boot/efi
adb shell sudo reboot
#./reset-target.sh
