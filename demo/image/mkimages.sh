#!/usr/bin/env bash
# rootfs.tar/esp.tar -> rootfs.img (ext4), esp.img (vfat), userdata.img (empty ext4), rootless and
# reproducible (fixed UUIDs, hash seed and timestamps from SOURCE_DATE_EPOCH).
#   mkimages.sh STAGE_DIR FLASH_DIR
set -euo pipefail
S=$1 F=$2
: "${SOURCE_DATE_EPOCH:?}"
export E2FSPROGS_FAKE_TIME=$SOURCE_DATE_EPOCH

# The rootfs partition is ~10 GiB; the image holds the content plus headroom and
# x-systemd.growfs (fstab) grows it to the partition on first boot.
used=$(tar -tvf "$S/rootfs.tar" | awk '{s += $3} END {print int(s / 1048576)}')
size=$(( (used * 13 / 10 + 512) / 64 * 64 ))M
rm -f "$F/rootfs.img"
mke2fs -q -t ext4 -L rootfs -U 9b1c6a4e-ad3e-4c3a-9a51-a5e0de300001 \
	-E hash_seed=9b1c6a4e-ad3e-4c3a-9a51-a5e0de300002,root_owner=0:0 \
	-d "$S/rootfs.tar" "$F/rootfs.img" "$size"
e2fsck -fn "$F/rootfs.img" >/dev/null

# ESP: vfat doesn't grow, so it fills the 512 MiB efi partition.
rm -f "$F/esp.img"
mkfs.vfat -C -n EFI -i a5e0de30 -S 512 "$F/esp.img" 524288 >/dev/null
E=$(mktemp -d)
tar -C "$E" -xf "$S/esp.tar"
# mtools takes file times from the files; pin them
find "$E" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(cd "$E" && for d in $(find . -mindepth 1 -type d | sort); do mmd -i "$F/esp.img" "::${d#.}"; done
 find . -type f | sort | while read -r f; do mcopy -m -i "$F/esp.img" "$f" "::${f#.}"; done)
rm -rf "$E"
fsck.vfat -n "$F/esp.img" >/dev/null

# userdata (Arduino's /home) is unused by the demo; give it a small empty filesystem.
rm -f "$F/userdata.img"
mke2fs -q -t ext4 -L userdata -U 9b1c6a4e-ad3e-4c3a-9a51-a5e0de300003 \
	-E hash_seed=9b1c6a4e-ad3e-4c3a-9a51-a5e0de300004 "$F/userdata.img" 64M
ls -l "$F"/{rootfs,esp,userdata}.img
