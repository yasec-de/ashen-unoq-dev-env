#!/bin/sh

set -eu

adb push zeroize/Image /tmp/zeroize-image
adb shell 'kexec -p -s /tmp/zeroize-image'
sleep 0.5
adb shell 'echo c > /proc/sysrq-trigger'
