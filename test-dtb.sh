#!/usr/bin/env bash
# Requires loader entry created by test-kernel-via-boot.sh to exist
#
# USER CREATED - NOT TO BE EDITED BY CLAUDE / LLM
#

set -euo pipefail
cd "$(dirname "$0")"

DTB=${1:-}
[[ -z "$DTB" || -f "$DTB" ]] || { echo "dtb not found: $DTB" >&2; exit 1; }

VERSION=$(make -sC linux kernelrelease)
ENTRY=$(adb shell "bootctl list" | grep -oE '[^ ]+'"$VERSION-test"'[^ ]*\.conf' | head -1)
[[ -n "$ENTRY" ]] || { echo "couldn't find BLS entry for $VERSION in bootctl list" >&2; exit 1; }

DTB_LOCATION=$(adb shell cat /boot/efi/loader/entries/$ENTRY | grep devicetree | cut -d' ' -f2)
adb push $DTB /boot/efi/$DTB_LOCATION
adb shell reboot
sleep 2
./reset-target.sh
