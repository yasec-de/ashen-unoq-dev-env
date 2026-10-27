#!/usr/bin/env bash
# Build the complete, flashable demo image: /workspace/cache/out/image/flash/ (qdl rawprogram set).
#
#   build-image.sh            build all inputs from source, then the image
#   SKIP_INPUTS=1 build-image.sh   reuse the inputs already in /workspace/cache/out
#
# Stages:
#  1. inputs from source: demo kernel + DTB, wipe payload, libkrun + launcher, Galene guest, MCU fw
#  2. boot firmware: Arduino's boot-binaries (hash-pinned) + kvm-hvc-poc (patched QHEE, EL2 U-Boot)
#  3. rootfs + ESP: mmdebstrap on an arm64 Debian builder (BUILDER, default: the demo board), pinned
#     to snapshot.debian.org $SNAPSHOT. This VM has no binfmt_misc, so arm64 package scripts can't
#     run here; the builder only needs mmdebstrap and ~6 GB free in $BUILD_DIR.
#  4. ext4/vfat images (rootless: mke2fs -d takes the tarball with its ownership) + flash dir
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEMO=$(cd "$HERE/.." && pwd)
mountpoint -q /dev/shm/ns || exec "$DEMO/buildns" run "$HERE/build-image.sh" "$@"

OUT=/workspace/cache/out
IMG=$OUT/image
SNAPSHOT=${SNAPSHOT:-20261026T000000Z}
BUILDER=${BUILDER:-root@$("$DEMO/bssh" --host)}
BUILD_DIR=${BUILD_DIR:-/home/arduino/ashen-image}
KEY=/workspace/id_ed25519_claude_vm
SSH=(ssh -i "$KEY" -o BatchMode=yes "$BUILDER")
STORE=/dev/shm/ns/.nix-portable
nixout() { "$DEMO/nix" build --no-link --print-out-paths "$@"; }
say() { echo "== $(date +%T) $*"; }

# --- 1. inputs ---------------------------------------------------------------------------------
if [[ -z "${SKIP_INPUTS:-}" ]]; then
	say "building inputs from source"
	"$DEMO/kernel/build.sh"
	"$DEMO/build-payload.sh"
	"$DEMO/vm/build-krun.sh"
	"$DEMO/vm/build-guest.sh"
	"$DEMO/fw-build.sh"
fi
K=$OUT/kernel
krel=$(cat "$K/kernelrelease")
for f in "$K/Image" "$K/modules.tar.gz" "$K/qrb2210-arduino-imola-ashen-demo.dtb" \
	"$OUT/zeroize/Image" "$OUT/krun/libkrun.so.2" "$OUT/krun/krunwipe" \
	"$OUT/galene-rootfs.tar.gz" "$OUT/ashen-fw.elf"; do
	[[ -f "$f" ]] || { echo "missing input $f" >&2; exit 1; }
done

# --- 2. boot firmware --------------------------------------------------------------------------
say "boot firmware"
rm -rf "$IMG"; mkdir -p "$IMG/flash" "$IMG/stage"
zip=$("$DEMO/nix" store prefetch-file --json \
	--expected-hash sha256-xgbpXQEH+MWNDdlJTgBiTR23xDYcyiBRO8eO8CyijdE= \
	https://downloads.arduino.cc/debian-im/unoq-bootloader-emmc-linux-251020.zip |
	python3 -c 'import json,sys; print(json.load(sys.stdin)["storePath"])')
"$DEMO/nix" shell nixpkgs#unzip -c unzip -q -j "$STORE$zip" -d "$IMG/flash"
qhee=$(nixout "path:/workspace/kvm-hvc-poc#qhee")
uboot=$(nixout "path:/workspace/kvm-hvc-poc#uboot")
install -m 644 "$STORE$qhee/hyp-hvc.mbn" "$IMG/flash/hyp-hvc.mbn"
install -m 644 "$STORE$uboot/boot-el2.img" "$IMG/flash/boot-el2.img"

# Arduino board bits the demo needs: the Wi-Fi/BT board-data override (initramfs hook) and the
# OpenOCD build that flashes the MCU over the SoC's GPIOs (precompiled in Arduino's image repo).
radio=$("$DEMO/nix" store prefetch-file --json --hash-type sha512 \
	--expected-hash sha512-bv/U/5fspvhk6KWrvM6uvU0Fsj7qcQAS/QlW2uRb5eMtrPkTafAnY3Skhr8jzd2Y9Ij9atmjp8oZr8PR4CGrSA== \
	https://apt-repo.arduino.cc/pool/main/a/arduino-unoq-radio-firmware/arduino-unoq-radio-firmware_0.7.0-1_arm64.deb |
	python3 -c 'import json,sys; print(json.load(sys.stdin)["storePath"])')
ADI=/workspace/arduino-deb-images
ADI_REV=e7713f1
[[ "$(git -C "$ADI" rev-parse --short=7 HEAD)" == "$ADI_REV" ]] || { echo "$ADI not at $ADI_REV" >&2; exit 1; }

# --- 3. rootfs + ESP on the builder ------------------------------------------------------------
say "rootfs on $BUILDER ($SNAPSHOT)"
S=$IMG/stage
cp "$K/Image" "$K/modules.tar.gz" "$K/qrb2210-arduino-imola-ashen-demo.dtb" "$S/"
echo "$krel" > "$S/kernelrelease"
cp "$OUT/zeroize/Image" "$S/zeroize-Image"
cp /workspace/zeroize/service/{zeroize-stage.sh,zeroize-stage.service,90-zeroize-display.rules} "$S/"
cp "$OUT/krun/libkrun.so.2" "$OUT/krun/krunwipe" "$OUT/galene-rootfs.tar.gz" "$OUT/ashen-fw.elf" "$S/"
tar -C "$DEMO/rootfs" -cf "$S/demo-rootfs.tar" --owner=0 --group=0 --sort=name .
tar -C "$HERE/files" -cf "$S/image-files.tar" --owner=0 --group=0 --sort=name .
cp "$HERE/packages" "$HERE/rootfs-build.sh" "$HERE/customize.sh" "$S/"
cp "$STORE$radio" "$S/arduino-unoq-radio-firmware.deb"
tar -C "$ADI/debos-recipes/overlays/arduino-unoq-releases/opt" -cf "$S/openocd.tar" \
	--owner=0 --group=0 --sort=name openocd
# Wi-Fi credentials are not in git: WIFI_PROFILE=path/to/x.nmconnection adds one.
[[ -n "${WIFI_PROFILE:-}" ]] && cp "$WIFI_PROFILE" "$S/wifi.nmconnection"
"${SSH[@]}" "rm -rf $BUILD_DIR && mkdir -p $BUILD_DIR"
tar -C "$S" -cf - . | "${SSH[@]}" "tar -C $BUILD_DIR -xf -"
"${SSH[@]}" "SNAPSHOT=$SNAPSHOT $BUILD_DIR/rootfs-build.sh $BUILD_DIR"
say "fetching rootfs"
"${SSH[@]}" "cat $BUILD_DIR/rootfs.tar" > "$S/rootfs.tar"
"${SSH[@]}" "cat $BUILD_DIR/esp.tar" > "$S/esp.tar"
"${SSH[@]}" "cat $BUILD_DIR/manifest" > "$IMG/manifest"
"${SSH[@]}" "rm -rf $BUILD_DIR"

# --- 4. filesystem images + flash dir ----------------------------------------------------------
say "filesystem images"
export SOURCE_DATE_EPOCH=$(date -u -d "${SNAPSHOT:0:8} ${SNAPSHOT:9:2}:${SNAPSHOT:11:2}:${SNAPSHOT:13:2}" +%s)
"$DEMO/nix" shell nixpkgs#e2fsprogs nixpkgs#dosfstools nixpkgs#mtools -c \
	"$HERE/mkimages.sh" "$S" "$IMG/flash"
python3 -I "$HERE/rawprogram.py" "$IMG/flash"
rm -rf "$S"
say "flash dir"
(cd "$IMG/flash" && sha256sum hyp-hvc.mbn boot-el2.img esp.img rootfs.img userdata.img > SHA256SUMS)
say "done: $IMG/flash (kernel $krel, Debian snapshot $SNAPSHOT)"
cat "$IMG/flash/SHA256SUMS"
