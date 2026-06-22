#!/usr/bin/env bash
# Build our UNO Q kernel as a bare Image + dtbs for quick kexec testing
# (test-on-board.sh), skipping the full image/flash cycle.
#
# Same source + config as the flashable image: linux/ branch qcom-v7.0.0-unoq,
# defconfig + every qcom-deb-images/kernel-configs/*.config fragment -- notably
# qcom-rpm-builtin.config, which builds the Qualcomm RPM clock/power stack (and
# ext4/sdhci) =y so the board actually boots and needs no matching initramfs
# (see NOTES.md). The flashable image builds this kernel as a .deb instead;
# see build-image.sh.
#
# Run inside `nix develop` (flake.nix) for the cross toolchain.
set -euo pipefail
cd "$(dirname "$0")"

KERNEL_BRANCH=qcom-v7.0.0-unoq
LINUX_DIR=linux
CONFIGS_DIR=qcom-deb-images/kernel-configs

git -C "$LINUX_DIR" checkout "$KERNEL_BRANCH"

MAKE=(make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)

"${MAKE[@]}" -C "$LINUX_DIR" defconfig
"$LINUX_DIR/scripts/kconfig/merge_config.sh" -O "$LINUX_DIR" -m -r "$LINUX_DIR/.config" "$CONFIGS_DIR"/*.config
"${MAKE[@]}" -C "$LINUX_DIR" olddefconfig
"${MAKE[@]}" -C "$LINUX_DIR" Image dtbs

echo "Done."
echo "  kernel:  $LINUX_DIR/arch/arm64/boot/Image"
echo "  dtb:     $LINUX_DIR/arch/arm64/boot/dts/qcom/qrb2210-arduino-imola.dtb"
