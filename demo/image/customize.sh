#!/bin/bash
# mmdebstrap customize hook (runs natively on the arm64 builder): install the demo into the new
# root. Mirrors what install-rootfs.sh and kernel/deploy.sh do on a live board.
#   customize.sh ROOT WORKDIR
set -euo pipefail
R=$1 W=$2
krel=$(cat "$W/kernelrelease")
dtb=qrb2210-arduino-imola-ashen-demo.dtb
chrun() { chroot "$R" "$@"; }

# --- kernel, modules, DTB, initrd -----------------------------------------------------------
# merged /usr: never let tar replace the /lib symlink
tar -C "$R/usr" --keep-directory-symlink -xzf "$W/modules.tar.gz"
install -D -m 644 "$W/$dtb" "$R/usr/lib/modules/$krel/dtb/$dtb"
install -m 644 "$W/Image" "$R/boot/vmlinuz-$krel"
chrun depmod "$krel"

# --- ESP: systemd-boot with one fixed entry ("ashen" token instead of a machine-id) ----------
E=$R/boot/efi
install -D -m 644 "$R/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$E/EFI/BOOT/BOOTAA64.EFI"
install -D -m 644 "$R/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$E/EFI/systemd/systemd-bootaa64.efi"
install -D -m 644 "$W/Image" "$E/ashen/$krel/linux"
install -D -m 644 "$W/$dtb" "$E/dtb/$dtb"
mkdir -p "$E/loader/entries"
printf 'timeout 3\ndefault ashen-%s.conf\n' "$krel" > "$E/loader/loader.conf"
cat > "$E/loader/entries/ashen-$krel.conf" <<EOF
title      Ashen demo ($krel)
version    $krel
linux      /ashen/$krel/linux
initrd     /ashen/$krel/initrd
devicetree /dtb/$dtb
options    root=PARTLABEL=rootfs rw clk_ignore_unused pd_ignore_unused audit=0 deferred_probe_timeout=30 console=ttyMSM0,115200n8 console=tty0 fbcon=font:TER16x32 loglevel=6 systemd.show_status=error printk.devkmsg=on crashkernel=64M crash_memaction=secret
EOF
# later kernel-install runs (deploy.sh) use the same layout
echo ashen > "$R/etc/kernel/entry-token"

# --- demo services, payload, VM -------------------------------------------------------------
tar -C "$R" --keep-directory-symlink --no-overwrite-dir -xf "$W/demo-rootfs.tar"
tar -C "$R" --keep-directory-symlink --no-overwrite-dir -xf "$W/image-files.tar"
chmod 700 "$R/root/.ssh"; chmod 600 "$R/root/.ssh/authorized_keys"
install -D -m 644 "$W/zeroize-Image" "$R/usr/lib/zeroize/Image"
install -m 755 "$W/zeroize-stage.sh" "$R/usr/lib/zeroize/"
install -m 644 "$W/zeroize-stage.service" "$R/etc/systemd/system/"
install -m 644 "$W/90-zeroize-display.rules" "$R/etc/udev/rules.d/"
install -D -m 755 "$W/krunwipe" "$R/usr/local/lib/ashen/krunwipe"
install -m 644 "$W/libkrun.so.2" "$R/usr/local/lib/ashen/"
install -D -m 644 "$W/galene-rootfs.tar.gz" "$R/usr/local/share/ashen/galene-rootfs.tar.gz"
install -m 644 "$W/ashen-fw.elf" "$R/usr/local/share/ashen/"
# Arduino: Wi-Fi/BT board-data override (before the initramfs is rebuilt below) and OpenOCD
cp "$W/arduino-unoq-radio-firmware.deb" "$R/tmp/"
chrun dpkg -i /tmp/arduino-unoq-radio-firmware.deb
rm "$R/tmp/arduino-unoq-radio-firmware.deb"
tar -C "$R/opt" -xf "$W/openocd.tar"
if [[ -f "$W/wifi.nmconnection" ]]; then
	install -m 600 "$W/wifi.nmconnection" "$R/etc/NetworkManager/system-connections/"
fi
chmod 600 "$R"/etc/NetworkManager/system-connections/* 2>/dev/null || true
chrun systemctl enable zeroize-stage.service ashen-pair.service ashen-demo.service \
	ashen-turn.service ashen-galene-vm.service qbootctl.service 2>/dev/null ||
	chrun systemctl enable zeroize-stage.service ashen-pair.service ashen-demo.service \
	ashen-turn.service ashen-galene-vm.service
# ashen-turn runs its own coturn instance; Debian's would hold port 3478
chrun systemctl mask coturn.service

# initramfs last, so it carries the radio firmware hook; systemd-boot's initramfs hook must not
# run kernel-install (the ESP entry is written by hand)
KERNEL_INSTALL_BYPASS=1 chrun update-initramfs -c -k "$krel"
install -D -m 644 "$R/boot/initrd.img-$krel" "$R/boot/efi/ashen/$krel/initrd"

# --- identity -------------------------------------------------------------------------------
sed -i '/127.0.1.1/d' "$R/etc/hosts"; sed -i '1i 127.0.1.1\tuno-q' "$R/etc/hosts"
# fresh machine-id and SSH host keys on first boot (sshd -t fails without keys, so make them first)
: > "$R/etc/machine-id"
rm -f "$R"/etc/ssh/ssh_host_*
mkdir -p "$R/etc/systemd/system/ssh.service.d"
printf '[Service]\nExecStartPre=\nExecStartPre=/usr/bin/ssh-keygen -A\nExecStartPre=/usr/sbin/sshd -t\n' \
	> "$R/etc/systemd/system/ssh.service.d/keygen.conf"
echo en_US.UTF-8 UTF-8 > "$R/etc/locale.gen"; chrun locale-gen >/dev/null

# --- manifest -------------------------------------------------------------------------------
chrun dpkg-query -W -f '${Package} ${Version}\n' > "$W/manifest"
