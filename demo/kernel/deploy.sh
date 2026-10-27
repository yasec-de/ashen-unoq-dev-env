#!/usr/bin/env bash
# Install the demo kernel from /workspace/cache/out/kernel on the board over SSH and make it
# the default boot entry. Counterpart of test-kernel-via-boot.sh (adb), with the demo cmdline:
# console on the monitor (tty0 last = /dev/console), quiet console loglevel, crashkernel for
# the wipe payload, crash_memaction=secret, and NO qcom_scm.download_mode (reset must reboot).
# Older entries stay installed and selectable in systemd-boot.
#   [K=dir] deploy.sh [--reboot]   (K=/workspace/cache/out/kernel-test for KTEST builds)
set -euo pipefail
B=/workspace/demo/bssh
K=${K:-/workspace/cache/out/kernel}
krel=$(cat "$K/kernelrelease")
dtb=qrb2210-arduino-imola-ashen-demo.dtb
cmdline_extra="console=ttyMSM0,115200n8 console=tty0 fbcon=font:TER16x32 loglevel=6 systemd.show_status=error printk.devkmsg=on crashkernel=64M@0x80000000 crash_memaction=secret"
echo "deploying $krel"

# a fresh install needs room for Image + initrd; a reinstall of the same version replaces them
$B "test -d /boot/efi/\$(cat /etc/machine-id)/$krel || df --output=avail -k /boot/efi | tail -1" |
	{ read -r kb || true; [ -z "$kb" ] || [ "$kb" -gt 70000 ] || { echo "only ${kb}k free on ESP" >&2; exit 1; }; }
scp -q -i /workspace/id_ed25519_claude_vm "$K/Image" "$K/modules.tar.gz" \
	"$K/$dtb" root@"$($B --host)":/var/tmp/

# ssh joins its arguments into one shell string, so quote them for the remote shell
$B "bash -s -- $(printf '%q ' "$krel" "$dtb" "$cmdline_extra")" <<'REMOTE'
set -euo pipefail
krel=$1 dtb=$2 extra=$3
rm -rf "/usr/lib/modules/$krel"
# Debian is merged-/usr: /lib is a symlink. Extract under /usr and never let tar replace a
# directory symlink (GNU tar does by default: that deleted /lib -> usr/lib once, see WORKLOG).
tar -C /usr --keep-directory-symlink -xzf /var/tmp/modules.tar.gz
depmod "$krel"
install -D -m 644 /var/tmp/$dtb "/usr/lib/modules/$krel/dtb/$dtb"
install -D -m 644 /var/tmp/$dtb "/boot/efi/dtb/$dtb"
update-initramfs -c -k "$krel" >/dev/null
kernel-install add "$krel" /var/tmp/Image
entry=$(ls /boot/efi/loader/entries/ | grep -F -- "-$krel.conf" | grep -v -- '-no-ma' | head -1)
[ -n "$entry" ] || { echo "no BLS entry for $krel" >&2; exit 1; }
f=/boot/efi/loader/entries/$entry
# strip options we manage, then append the demo set
opts=$(sed -n 's/^options[[:space:]]\+//p' "$f" | tr ' ' '\n' |
	grep -vE '^(console|fbcon|loglevel|systemd\.show_status|printk\.devkmsg|crashkernel|crash_memaction|crash_kexec_post_notifiers|qcom_scm\.download_mode)(=|$)' | tr '\n' ' ')
sed -i -e '/^options/d' -e '/^devicetree/d' -e 's/^title.*/title Ashen demo ('"$krel"')/' "$f"
echo "options ${opts}${extra}" >> "$f"
echo "devicetree /dtb/$dtb" >> "$f"
sed -i '/^default/d' /boot/efi/loader/loader.conf
echo "default $entry" >> /boot/efi/loader/loader.conf
sync
echo "installed entry $entry:"; cat "$f"
REMOTE
[[ "${1:-}" == --reboot ]] && { $B systemctl reboot || true; echo "rebooting"; }
