#!/usr/bin/env bash
# Requires loader entry created by test-kernel-via-boot.sh to exist
#
# USER CREATED - NOT TO BE EDITED BY CLAUDE / LLM
#

set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${1:-linux/arch/arm64/boot/Image}
[[ -z "$IMAGE" || -f "$IMAGE" ]] || { echo "kernel image not found: $IMAGE" >&2; exit 1; }

VERSION=$(make -sC linux kernelrelease)
ENTRY=$(adb shell "bootctl list" | grep -oE '[^ ]+'"$VERSION-test"'[^ ]*\.conf' | head -1)
[[ -n "$ENTRY" ]] || { echo "couldn't find BLS entry for $VERSION in bootctl list" >&2; exit 1; }

IMAGE_LOCATION=$(adb shell cat /boot/efi/loader/entries/$ENTRY | grep '^linux' | sed 's/linux *//')
adb push $IMAGE /boot/efi$IMAGE_LOCATION
adb shell reboot
