#!/usr/bin/env bash
# Build the demo kernel: committed HEAD of /workspace/linux-demo (branch ashen-demo), config =
# running board config (linux/.config) + ashen-demo.config. Source and build tree live in the
# buildns tmpfs (virtiofs can't take kernel-tree inode counts); only artifacts are exported to
# /workspace/cache/out/kernel: Image, dtbs, modules.tar.gz, config, kernelrelease.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mountpoint -q /dev/shm/ns || exec "$HERE/../buildns" run "$HERE/build.sh" "$@"
if [[ -z "${IN_NIX_SHELL:-}" ]]; then
	exec "$HERE/../nix" develop "path:$HERE" -c "$HERE/build.sh" "$@"
fi
REPO=/workspace/linux-demo
SRC=/dev/shm/ns/linux-demo
OUT=/dev/shm/ns/kbuild
EXPORT=/workspace/cache/out/kernel

rev=$(git -C "$REPO" rev-parse HEAD)
if [[ "$(cat "$SRC/.rev" 2>/dev/null)" != "$rev" ]]; then
	echo "updating $SRC to $rev"
	mkdir -p "$SRC"
	# Private index: only files that differ from the last build are rewritten (and files gone from
	# the tree removed), so make stays incremental across commits.
	GIT_INDEX_FILE=/dev/shm/ns/linux-demo.index git -C "$REPO" --work-tree="$SRC" read-tree -u --reset "$rev"
	echo "$rev" > "$SRC/.rev"
fi
mkdir -p "$OUT"
MAKE=(make -C "$SRC" O="$OUT" -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)
# Test builds (KTEST=name): separate kernelrelease and export dir, so their modules never
# overwrite the demo kernel's on the board. Booted with kexec only (see test-kexec.sh).
if [[ -n "${KTEST:-}" ]]; then
	MAKE+=(LOCALVERSION="-$KTEST")
	EXPORT=/workspace/cache/out/kernel-test
fi
if [[ ! -f "$OUT/.config" || "$HERE/ashen-demo.config" -nt "$OUT/.config" ]]; then
	cp /workspace/linux/.config "$OUT/.config"
	"$SRC/scripts/kconfig/merge_config.sh" -O "$OUT" -m "$OUT/.config" "$HERE/ashen-demo.config"
	"${MAKE[@]}" olddefconfig
	# report symbols from our fragment that didn't stick
	while IFS= read -r line; do
		[[ $line =~ ^(CONFIG_[A-Z0-9_]+)=(.*)$ ]] || continue
		grep -qxF "$line" "$OUT/.config" || echo "WARNING: $line did not stick: $(grep "^${BASH_REMATCH[1]}=" "$OUT/.config" || echo unset)"
	done < "$HERE/ashen-demo.config"
fi
"${MAKE[@]}" Image modules qcom/qrb2210-arduino-imola-ashen-tamper.dtbo
# The upstream Makefile composes this DTB from Arduino-tree blobs that have no source here;
# use the prebuilt ones (see dtb/README) and apply our overlay on top.
DTB="$OUT/qrb2210-arduino-imola-ashen-demo.dtb"
fdtoverlay -i "$HERE/dtb/qrb2210-arduino-imola-base.dtb" -o "$DTB" \
	"$HERE/dtb/qrb2210-arduino-imola-video_sound-usbc.dtbo" \
	"$OUT/arch/arm64/boot/dts/qcom/qrb2210-arduino-imola-ashen-tamper.dtbo"
# host-only USB (see the overlay); overlays can't delete properties
fdtput -d "$DTB" /soc@0/usb@4ef8800/usb@4e00000 usb-role-switch
krel=$("${MAKE[@]}" -s kernelrelease)

rm -rf "$OUT/modinst"
"${MAKE[@]}" INSTALL_MOD_PATH="$OUT/modinst" INSTALL_MOD_STRIP=1 modules_install >/dev/null
mkdir -p "$EXPORT"
cp "$OUT/arch/arm64/boot/Image" "$OUT/.config" "$OUT/System.map" "$EXPORT/"
cp "$DTB" "$EXPORT/"
tar -C "$OUT/modinst" -czf "$EXPORT/modules.tar.gz" lib
echo "$krel" > "$EXPORT/kernelrelease"
echo "kernelrelease: $krel ($rev) -> $EXPORT"
