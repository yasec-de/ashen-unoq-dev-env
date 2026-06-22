#!/usr/bin/env bash
# Rebuilds the exact kernel image running on the stock UNO Q board.
#
# Source commit and config fragments identified in NOTES.md: the running
# kernel (6.16.7-g0dd6551ae96b) is built from arduino/linux-qcom commit
# 0dd6551ae96b ("arm64: qrb2210: support Arduino UNO Q"), defconfig + all
# fragments in qcom-deb-images/kernel-configs/ (same set used by
# qcom-deb-images/scripts/build-linux-deb.py's documented invocation).
#
# CONFIG_EFI_ZBOOT=y (from systemd-boot.config) means the bootable artifact
# is arch/arm64/boot/vmlinuz.efi, not a bare Image -- ponytail: building
# straight from the kernel tree instead of a .deb skips debhelper, which
# isn't packaged in nixpkgs.
#
# Run inside `nix develop` (see flake.nix) for the build toolchain.
set -euo pipefail
cd "$(dirname "$0")"

KERNEL_COMMIT=0dd6551ae96b78024086e72339fefbef6fcc604b
LINUX_DIR=linux
CONFIGS_DIR=qcom-deb-images/kernel-configs

git -C "$LINUX_DIR" checkout "$KERNEL_COMMIT"

MAKE=(make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)

"${MAKE[@]}" -C "$LINUX_DIR" defconfig
"$LINUX_DIR/scripts/kconfig/merge_config.sh" -O "$LINUX_DIR" -m -r "$LINUX_DIR/.config" "$CONFIGS_DIR"/*.config
"${MAKE[@]}" -C "$LINUX_DIR" olddefconfig
"${MAKE[@]}" -C "$LINUX_DIR" all dtbs modules

echo "Done."
echo "  kernel:  $LINUX_DIR/arch/arm64/boot/vmlinuz.efi"
echo "  dtb:     $LINUX_DIR/arch/arm64/boot/dts/qcom/qrb2210-arduino-imola.dtb"
