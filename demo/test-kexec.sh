#!/bin/sh
# Boot a kernel/DTB once via kexec without touching the ESP or boot entries; any reboot (or a hang
# plus watchdog reset) returns to the installed default. Uses the running kernel's initrd and
# cmdline. `systemctl kexec` shuts down orderly, so the tamper heartbeat is disarmed first.
#   test-kexec.sh [IMAGE [DTB]]   (defaults: cache/out/kernel/{Image,qrb2210-arduino-imola-ashen-demo.dtb})
set -e
K=/workspace/cache/out/kernel
IMG=${1:-$K/Image}
DTB=${2:-$K/qrb2210-arduino-imola-ashen-demo.dtb}
B=/workspace/demo/bssh
scp -q -i /workspace/id_ed25519_claude_vm "$IMG" root@"$($B --host)":/var/tmp/test-Image
scp -q -i /workspace/id_ed25519_claude_vm "$DTB" root@"$($B --host)":/var/tmp/test.dtb
$B 'set -e
initrd=/boot/efi/$(cat /etc/machine-id)/$(uname -r)/initrd.img-$(uname -r)
cmdline=$(sed -E "s/(^| )initrd=[^ ]*//" /proc/cmdline)
kexec -l /var/tmp/test-Image --dtb=/var/tmp/test.dtb --initrd="$initrd" --command-line="$cmdline"
echo "kexec loaded, switching"; systemctl kexec'
