#!/bin/bash
# Runs as root on an arm64 Debian builder (see build-image.sh). Builds the demo rootfs with
# mmdebstrap from a pinned snapshot.debian.org timestamp and splits it into rootfs.tar and
# esp.tar (the /boot/efi contents).
#   SNAPSHOT=YYYYMMDDTHHMMSSZ rootfs-build.sh WORKDIR
set -euo pipefail
W=$1
cd "$W"
# mmdebstrap builds the chroot under TMPDIR; keep it on disk, not in RAM
export TMPDIR=$W
: "${SNAPSHOT:?}"
export SOURCE_DATE_EPOCH=$(date -u -d "${SNAPSHOT:0:8} ${SNAPSHOT:9:2}:${SNAPSHOT:11:2}:${SNAPSHOT:13:2}" +%s)
command -v mmdebstrap >/dev/null || { apt-get update -qq && apt-get install -y -qq mmdebstrap; }

COMP="main contrib non-free non-free-firmware"
D=http://snapshot.debian.org/archive
pkgs=$(grep -vE '^\s*(#|$)' packages | tr '\n' ',' | sed 's/,$//')

# Downloaded .debs persist next to the work dir between builds (the image's own apt cache is
# still emptied by mmdebstrap's cleanup, so this doesn't change the output).
CACHE=${APT_CACHE:-$W/../ashen-image-apt-cache}
mkdir -p "$CACHE"
mmdebstrap --variant=important --include="$pkgs" \
	--skip=download/empty --skip=essential/unlink \
	--setup-hook='mkdir -p "$1"/var/cache/apt/archives/' \
	--setup-hook="sync-in $CACHE /var/cache/apt/archives/" \
	--customize-hook="sync-out /var/cache/apt/archives $CACHE" \
	--aptopt='Acquire::Check-Valid-Until "false"' --aptopt='Acquire::Retries "5"' \
	--essential-hook='echo uno-q > "$1/etc/hostname"' \
	--customize-hook="$W/customize.sh \"\$1\" $W" \
	--skip=cleanup/apt/lists \
	trixie "$W/full.tar" \
	"deb $D/debian/$SNAPSHOT trixie $COMP" \
	"deb $D/debian/$SNAPSHOT trixie-updates $COMP" \
	"deb $D/debian-security/$SNAPSHOT trixie-security $COMP"

echo "$(date +%T) splitting ESP from rootfs"
# split: the ESP goes to its own partition, the rootfs keeps an empty mount point
rm -rf esp; mkdir esp
tar -C esp -xf full.tar --strip-components=3 ./boot/efi
tar -C esp -cf esp.tar --owner=0 --group=0 --sort=name --mtime="@$SOURCE_DATE_EPOCH" .
tar --delete -f full.tar --wildcards './boot/efi/?*'
mv full.tar rootfs.tar
rm -rf esp
ls -l rootfs.tar esp.tar
