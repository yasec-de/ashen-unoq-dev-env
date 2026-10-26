#!/bin/sh
# Copy demo/rootfs/ onto the board (files only, existing config in /etc/default/ashen is kept)
# and reload systemd. Usage: install-rootfs.sh
set -e
cd "$(dirname "$0")/rootfs"
tar -cf - --owner=0 --group=0 --exclude=./etc/default/ashen . |
	/workspace/demo/bssh 'tar -C / --keep-directory-symlink --no-overwrite-dir -xf - && systemctl daemon-reload'
/workspace/demo/bssh 'test -e /etc/default/ashen' || tar -cf - --owner=0 --group=0 ./etc/default/ashen |
	/workspace/demo/bssh 'tar -C / --keep-directory-symlink --no-overwrite-dir -xf -'
# Wipe payload (crash kernel) and its staging unit, from zeroize/ and its build output
B=/workspace/demo/bssh
$B 'install -d /usr/lib/zeroize'
scp -q -i /workspace/id_ed25519_claude_vm /workspace/cache/out/zeroize/Image \
	/workspace/zeroize/service/zeroize-stage.sh root@"$($B --host)":/usr/lib/zeroize/
scp -q -i /workspace/id_ed25519_claude_vm /workspace/zeroize/service/zeroize-stage.service \
	root@"$($B --host)":/etc/systemd/system/
scp -q -i /workspace/id_ed25519_claude_vm /workspace/zeroize/service/90-zeroize-display.rules \
	root@"$($B --host)":/etc/udev/rules.d/
$B 'chmod 755 /usr/lib/zeroize/zeroize-stage.sh && chmod 644 /etc/systemd/system/zeroize-stage.service /etc/udev/rules.d/90-zeroize-display.rules && systemctl daemon-reload && udevadm control --reload'
# Galene VM image and the krun launcher (cross-built in cache/out)
$B 'install -d /usr/local/share/ashen /usr/local/lib/ashen'
[ -f /workspace/cache/out/galene-rootfs.tar.gz ] && scp -q -i /workspace/id_ed25519_claude_vm \
	/workspace/cache/out/galene-rootfs.tar.gz root@"$($B --host)":/usr/local/share/ashen/
# upload next to the target and rename: the running VM keeps the old binary open
scp -q -i /workspace/id_ed25519_claude_vm /workspace/cache/out/krun/libkrun.so.2 \
	root@"$($B --host)":/usr/local/lib/ashen/libkrun.so.2.new
scp -q -i /workspace/id_ed25519_claude_vm /workspace/cache/out/krun/krunwipe \
	root@"$($B --host)":/usr/local/lib/ashen/krunwipe.new
$B 'cd /usr/local/lib/ashen && mv libkrun.so.2.new libkrun.so.2 && mv krunwipe.new krunwipe'
echo installed
