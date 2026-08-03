#!/bin/sh

set -euo pipefail

adb push zeroize/Image /tmp/zeroize-image
adb shell 'kexec -p -s /tmp/zeroize-image'
adb push reproduce-crash-hang.sh /tmp/repro.sh
#adb shell 'sh /tmp/repro.sh'
#adb shell 'exec 3>/dev/watchdog0; printf V >&3; exec 3>&-'
#echo '=== disabling wdt ==='
#adb shell 'echo 1 > /sys/bus/platform/devices/f017000.watchdog/disable'
#adb shell 'dmesg | grep -iE "qcom.*wdt|secure watchdog|watchdog" | tail -50'
#adb shell 'busybox devmem 0x0f017008 32'
#echo '=== done ==='

adb shell 'echo c > /proc/sysrq-trigger'
#sleep 5
#adb shell rmmod qcom_wdt || true
#adb shell reboot
