#!/bin/sh

set -eu

adb push zeroize/Image /tmp/zeroize-image
adb shell 'sudo kexec -p -s /tmp/zeroize-image'
sleep 0.5
adb shell 'echo c | sudo tee /proc/sysrq-trigger'
