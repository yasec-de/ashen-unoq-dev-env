
adb shell mount -o remount,rw /boot/efi
VERSION=$(make -sC linux kernelrelease)
ENTRY=$(adb shell "bootctl list" | grep -oE '[^ ]+'"$VERSION"'[^ ]*\.conf' | head -1)
[[ -n "$ENTRY" ]] || { echo "couldn't find BLS entry for $VERSION in bootctl list" >&2; exit 1; }
adb shell "sed -i '/^default/d' /boot/efi/loader/loader.conf"
adb shell "echo \"default $ENTRY\" >> /boot/efi/loader/loader.conf"
adb shell "grep -e '^console-mode' /boot/efi/loader/loader.conf || sh -c 'echo console-mode keep >> /boot/efi/loader/loader.conf'"
adb shell "grep -e '^timeout' /boot/efi/loader/loader.conf || sh -c 'echo timeout 3 >> /boot/efi/loader/loader.conf'"
