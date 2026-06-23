#!/bin/sh
# Stage the tamper-response wipe payload as the kdump capture image, so a tamper
# panic (`echo c > /proc/sysrq-trigger`, or an in-kernel panic) jumps straight
# to it. Also warn, to the kernel log, about swap/hibernate that could leak
# plaintext secrets to eMMC.
set -eu

DIR=$(dirname "$0")
IMG=${ZEROIZE_IMAGE:-$DIR/Image}

# --- swap / hibernate audit (warn-only) ---
swapon --show=NAME --noheadings 2>/dev/null | while read -r dev; do
	case "$dev" in
	/dev/dm-* | /dev/mapper/*) : ;;	# assume dm-crypt
	*) echo "zeroize: WARNING unencrypted swap on $dev (secrets may reach eMMC)" >/dev/kmsg ;;
	esac
done
resume=$(cat /sys/power/resume 2>/dev/null || echo 0:0)
if [ -n "$resume" ] && [ "$resume" != "0:0" ]; then
	echo "zeroize: WARNING hibernate resume configured ($resume)" >/dev/kmsg
fi

# --- stage the capture image (kexec_file_load into the crashkernel region) ---
if [ ! -f "$IMG" ]; then
	echo "zeroize: ERROR capture image $IMG missing" >/dev/kmsg
	exit 1
fi
kexec -p -s "$IMG"
echo "zeroize: wipe payload staged as capture image ($IMG)" >/dev/kmsg
