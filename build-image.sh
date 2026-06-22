#!/usr/bin/env bash
# Build a complete flashable UNO Q Debian image with our fixed kernel.
# Output: qcom-deb-images/flash_qrb2210-arduino-imola_emmc/ (feed to ./flash.sh).
#
# Three stages, each long but cheap to redo:
#   1. kernel .deb  -- built in the go-debos (Debian) container. debhelper
#      isn't in nixpkgs, and a nix-built tree won't relink in the container,
#      so this is a clean from-scratch build (mrproper). See NOTES.md.
#   2. rootfs.tar + dtbs.tar.gz  -- kernelpackage:none + our local kernel deb.
#   3. disk-sdcard.img + flash dir.
#
# The fixes that make the result actually boot live in the kernel config
# fragment qcom-deb-images/kernel-configs/qcom-rpm-builtin.config and the
# image/flash recipes -- this script just drives the build.
#
# Needs: podman. The flash stage needs an mtools+dtc image, auto-built from
# Dockerfile.debos-mtools if missing.
set -euo pipefail
cd "$(dirname "$0")"

KERNEL_BRANCH=qcom-v7.0.0-unoq
LINUX_DIR=linux
REPO=qcom-deb-images
DEBOS_IMAGE=ghcr.io/go-debos/debos:latest
MTOOLS_IMAGE=localhost/debos-mtools:latest
BOARD=qrb2210-arduino-imola

# debos under podman wants a tty; `script` gives it one in non-interactive use.
mk() { ( cd "$REPO" && script -qec "EXTRA_DEBOS_OPTS=\"$1\" CONTAINER_IMAGE=\"$2\" make USE_CONTAINER=yes CONTAINER_ENGINE=podman $3" /dev/null ); }

echo "== 1/3: kernel .deb (container build of $KERNEL_BRANCH) =="
git -C "$LINUX_DIR" checkout "$KERNEL_BRANCH"
rm -f "$REPO"/debos-recipes/local-debs/*.deb
podman run --rm --entrypoint bash -v "$PWD":/work -w "/work/$LINUX_DIR" "$DEBOS_IMAGE" -c '
  set -eux; export DEBIAN_FRONTEND=noninteractive
  dpkg --add-architecture arm64; apt-get update -qq
  apt-get install -y --no-install-recommends debhelper dpkg-dev build-essential \
    crossbuild-essential-arm64 bc bison flex libdw-dev libelf-dev libssl-dev \
    libssl-dev:arm64 kmod python3 rsync >/dev/null
  M=(make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)
  "${M[@]}" mrproper
  "${M[@]}" defconfig
  scripts/kconfig/merge_config.sh -m -r .config ../'"$REPO"'/kernel-configs/*.config
  "${M[@]}" olddefconfig
  "${M[@]}" DPKG_FLAGS=-d bindeb-pkg'
# only the linux-image deb feeds the rootfs (not headers/dbg/libc-dev)
IMG_DEB=$(ls -t linux-image-*.deb | grep -v -- -dbg | head -1)
cp -v "$IMG_DEB" "$REPO/debos-recipes/local-debs/"

echo "== 2/3: rootfs + dtbs =="
rm -f "$REPO"/rootfs.tar "$REPO"/dtbs.tar.gz
mk "-t localdebs:local-debs/ -t kernelpackage:none" "$DEBOS_IMAGE" "rootfs.tar"

echo "== 3/3: disk image + flash dir =="
podman image exists "$MTOOLS_IMAGE" || podman build -t debos-mtools -f Dockerfile.debos-mtools .
rm -f "$REPO"/disk-sdcard.img "$REPO"/disk-sdcard.img1 "$REPO"/disk-sdcard.img2
mk "" "$DEBOS_IMAGE" "disk-sdcard.img"
mk "-t target_boards:$BOARD -t build_qcs615:false -t build_qcm6490:false -t build_qcs8300:false -t build_qcs9100:false" \
   "$MTOOLS_IMAGE" "flash"

echo
echo "Done -> $REPO/flash_${BOARD}_emmc/   (flash with ./flash.sh)"
