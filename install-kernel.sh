#!/usr/bin/env bash
# Properly install a freshly built kernel onto the board's ESP via
# kernel-install/bootctl (BLS), instead of hand-copying files like
# test-on-board.sh's kexec path does. Use this when the kexec fast-iterate
# loop isn't enough and you want a real, persistent, rebootable bootloader
# entry -- e.g. to test a kernel that needs a *cold* boot (crashkernel=
# reservation only happens on a non-kexec'd boot).
#
# Why kernel-install and not hand-built BLS entries: a previous manual copy
# left a 0-byte initrd in the per-kernel ESP dir (no /init ever ran -> eMMC
# never probed -> panic mounting root). kernel-install's initramfs-tools
# hook regenerates the initrd in place, so this can't happen.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=linux/arch/arm64/boot/Image

[[ -f "$IMAGE" ]] || { echo "missing $IMAGE, build the kernel first" >&2; exit 1; }

adb get-state >/dev/null

set +o pipefail
VERSION=$(strings "$IMAGE" | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-g[0-9a-f]+(-dirty)?')
set -o pipefail
[[ -n "$VERSION" ]] || { echo "couldn't extract version string from $IMAGE" >&2; exit 1; }

echo "version:  $VERSION"

adb shell "which kernel-install >/dev/null 2>&1" || { echo "kernel-install not found on device" >&2; exit 1; }

adb push "$IMAGE" /tmp/install-Image

# kernel-install add <version> <vmlinuz> runs the configured plugins
# (zz-systemd-boot, initramfs-tools): builds the initrd fresh (in-place,
# unlike a hand copy) and writes the BLS entry. The board's dtb is a single
# shared /boot/efi/dtb/qcom/qrb2210-arduino-imola.dtb, not per-kernel-version,
# so it's untouched here.
adb shell "kernel-install add $VERSION /tmp/install-Image"

echo "Installed. Loader entries:"
adb shell "bootctl list" || true
