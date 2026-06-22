# UNO Q board bring-up notes

Working notes from reverse-engineering the Arduino UNO Q image/flash/boot
pipeline, gathered across `arduino-flasher-cli/`, `linux/`, `qdl/`,
`qcom-deb-images/`, and a stock board connected via `adb`.

## Repo map

- `arduino-flasher-cli/` — end-user CLI/daemon that downloads or accepts a
  local Debian image and flashes it via an embedded `qdl` binary. Does not
  build images; only consumes a `flash`/`flash_UnoQ` directory
  (`rawprogram*.xml`, `gpt_main0.bin`, `patch0.xml`, `prog_firehose_ddr.elf`).
- `linux/` — kernel source. Has Arduino's own remote (`arduino`,
  `https://github.com/arduino/linux-qcom`), checked out at branch
  `qcom-v7.0.0-unoq`. Contains DTS for **two different boards**, easy to
  confuse:
  - `qrb2210-arduino-imola*.dts` — **this is the actual UNO Q** (QCM2290/QRB2210
    silicon).
  - `monaco-arduino-monza.dts` — a different, separate Arduino board ("Monza",
    QCS8300/Monaco silicon). Not the UNO Q.
- `qdl/` — just the EDL/Firehose flashing client + GPT parsing. No image
  build capability.
- `qcom-deb-images/` (https://github.com/qualcomm-linux/qcom-deb-images) —
  **the actual build pipeline**, missing from the other three repos. debos
  recipes that build the Debian rootfs, kernel package, disk image, and
  flash assets. This is what you need to build a custom image/kernel.
- `unoq-bootloader-emmc-linux-251020/` — extracted contents of Arduino's
  bootloader zip (see below).
- `u-boot/` — not yet investigated in depth; see "U-Boot source" below for
  where the actual running U-Boot comes from instead.

## Board identity: UNO Q = `qrb2210-arduino-imola`

In `qcom-deb-images/debos-recipes/qualcomm-linux-debian-flash.yaml`, the
board entry named `qrb2210-arduino-imola` (silicon family `qcm2290`,
`ptool_platforms: qrb2210-unoq/emmc-16GB`) is explicitly labeled "UNO Q boot
binaries". This is distinct from:
- `qrb2210-rb1` — the Linaro/Qualcomm QRB2210 devkit (different bootloader
  source, gated behind `build_rb1`/`u_boot_rb1` since it needs U-Boot).
- `monaco-arduino-monza` — unrelated newer Arduino board, different silicon.

## Bootloader blob bundle (`unoq-bootloader-emmc-linux-251020.zip`)

Source: `https://downloads.arduino.cc/debian-im/unoq-bootloader-emmc-linux-251020.zip`,
pinned by sha256 in the flash recipe ([line 232](qcom-deb-images/debos-recipes/qualcomm-linux-debian-flash.yaml#L232)).
Added once in repo history, never bumped since — versioning is just the
embedded date in the filename (`251020` = 2025-10-20), no semantic version.

Unlike every other board in that recipe (which pull Qualcomm boot binaries
from `softwarecenter.qualcomm.com` + a separate CDT zip from
`artifacts.codelinaro.org`), the UNO Q bundle is repackaged by Arduino
directly into one zip, with no separate CDT download.

`LICENSE.arduino` inside the zip states it's derived from Linaro's RB1
rescue image (`releases.linaro.org/96boards/rb1/linaro/rescue/23.12/...`).

File-by-file identification (from `flashall` script + `rawprogram0.xml`
labels + sizes/headers):
- `xbl.elf`, `xbl_feature_config.elf`, `tz.mbn`, `hyp.mbn`, `rpm.mbn`,
  `devcfg.mbn`, `imagefv.elf`, `uefi_sec.mbn`, `km4.mbn`, `qupv3fw.elf`,
  `featenabler.mbn`, `storsec.mbn`, `multi_image.mbn` — Qualcomm SoC boot
  chain firmware (XBL/TrustZone/hypervisor/RPM/etc), A/B partitioned.
  **Closed, proprietary, no public source** — confirmed via web research,
  not even available through Linaro/CodeLinaro as source, only as prebuilt
  signed binaries. Modifying XBL in practice means patching/re-signing the
  stock binary with `xbltools`/`qtestsign` (works because secure boot is
  off — see below), not rebuilding from source.
- `NON-HLOS.bin` — modem firmware. `BTFM.bin` — BT/FM firmware. `dspso.bin`
  — DSP firmware (uncertain which core exactly).
- `boot.img` — confirmed via hex dump (`ANDROID!` magic) to be a real
  Android boot image. **Important correction**: this is NOT the Linux
  kernel — it's **U-Boot itself**, packaged in Android boot-image format
  (same mechanism `qcom-deb-images`' `u_boot_rb1` option uses for RB1, except
  here it's the default path, not opt-in). ABL boots this → U-Boot → UEFI →
  `systemd-bootaa64.efi` → real kernel+initrd as plain files on the ESP.
- `boot-erase.img` — all-zero filler, for wiping the boot partition.
- `gpt_main0/1/2.bin`, `gpt_backup0/1/2.bin`, `gpt_both0.bin`,
  `gpt_empty0.bin` — GPT tables for eMMC LUNs 0/1/2, main+backup+combined
  variants.
- `rawprogram0.xml` / `rawprogram0.nouser.xml` — firehose programming
  scripts; `.nouser` skips the `userdata` partition (powers
  `arduino-flasher-cli --preserve-user`).
- `patch0.xml` — firehose post-program GPT patch step.
- `cdt.bin` — Customer/Chip Definition Table (board hardware-config
  descriptor), 24 bytes, magic `CDT.`. Exact field layout uncertain.
- `flashall` — alternate `fastboot`-based flash path, not used by
  `qdl`/`arduino-flasher-cli` (which use firehose/`rawprogram0.xml`).

## Real boot chain on stock hardware (confirmed via `adb`)

ABL → `boot.img` (= U-Boot in Android boot-image format) → U-Boot UEFI →
`/boot/efi/EFI/systemd/systemd-bootaa64.efi` → Boot Loader Spec entry in
`/boot/efi/loader/entries/*.conf` → real kernel + initrd as plain files at
`/boot/efi/<machine-id>/<kernel-version>/{linux,initrd.img-*}`.

Root filesystem: plain mutable ext4 (`mmcblk0p68`, 10G,
`/`) plus a separate `/home` partition (`mmcblk0p69`, 18.2G). Default user
`arduino` (uid 1000) has `sudo` group membership.

ESP is `mmcblk0p67`, FAT32, mounted rw at `/boot/efi`.

## Secure boot: present as capability, OFF by default

- UEFI `SecureBoot`/`SetupMode` NVRAM variables exist (U-Boot's UEFI layer
  supports it), but `SecureBoot` reads back as `0` (disabled) on the stock
  unit checked, and `/boot/efi/loader/keys/` (systemd-boot's key-enrollment
  slot) is empty.
- No `dm-verity`, no `androidboot.verifiedbootstate` anywhere in
  `/proc/cmdline` — OS-level verified boot is not active.
- Per public reporting, Arduino plans to extend FoundriesFactory in early
  2026 to let users *opt in* to secure boot for production deployments with
  their own keys — consistent with it shipping open by default.
- Practical implication: a custom kernel/initrd can be dropped onto the ESP
  and added as a new BLS entry with no signing step required, since nothing
  in the chain currently enforces signatures past U-Boot itself.

## U-Boot source

Running version on stock hardware: `2026.01-rc3-g572d34ccadb9` (read from
`/proc/device-tree/chosen/u-boot,version`). This is `git describe` output:
nearest tag `v2026.01-rc3` (upstream U-Boot's own pre-release tag) + short
hash of an Arduino-authored fixup commit.

Source: `https://github.com/arduino/u-boot`, branch
`qcom-denx-mainline-emmc` (only branch whose HEAD contains that commit).
Default branch of the fork is `qcom-mainline` — it tracks upstream DENX
U-Boot mainline plus Arduino/Qualcomm patches on top, not a from-scratch
vendor tree.

## Kernel config

No single committed "board config" file. Reconstructed at build time by
`qcom-deb-images/scripts/build-linux-deb.py`:
1. `make defconfig` from `linux/arch/arm64/configs/defconfig` (base).
2. Merge fragments from `qcom-deb-images/kernel-configs/*.config` via
   `scripts/kconfig/merge_config.sh`, then `make olddefconfig`.

README's documented invocation merges *all* fragments:
`scripts/build-linux-deb.py kernel-configs/*.config`. Confirmed real overlap
between fragments and the actual running config (pulled from device at
`/boot/config-6.16.7-g0dd6551ae96b`): `monza.config`'s
`CONFIG_SENSORS_INA2XX`, `systemd-boot.config`'s `CONFIG_EFI_ZBOOT`,
`docker.config`'s namespace options all present on the live board.

Ground truth for the exact running config is always
`/boot/config-<uname -r>` on the device itself, not any file in these
repos.

## DTB provenance

`qcom/qrb2210-arduino-imola.dtb` traces back to
`linux/arch/arm64/boot/dts/qcom/qrb2210-arduino-imola.dts` in the
`arduino`-remote kernel checkout. In the default `qcom-deb-images` rootfs
build, the DTB isn't compiled locally — it comes from installing the
`linux-image-arm64` package from Qualcomm's own APT overlay
(`qsc-deb-releases` at `qartifactory-edge.qualcomm.com`), whose kernel
package installs DTBs to `/usr/lib/linux-image-*/`. The rootfs recipe tars
that whole directory into `dtbs.tar.gz`
(`qualcomm-linux-debian-rootfs.yaml:650-669`); the flash recipe later
extracts the board-specific `.dtb` from it by path.

For a custom kernel: use `kernelpackage:none` +
`localdebs:local-debs/` debos options, with your own kernel `.deb`
installing DTBs to the same `/usr/lib/linux-image-*/` convention.

## Path to a custom-kernel image (current best understanding)

1. Build kernel from `linux/` (`qcom-v7.0.0-unoq` branch) using
   `defconfig` + `qcom-deb-images/kernel-configs/*.config`, package as
   `.deb`.
2. `EXTRA_DEBOS_OPTS="-t localdebs:local-debs/ -t kernelpackage:none" make rootfs.tar`
3. `make disk-ufs.img` (or `disk-sdcard.img`)
4. `EXTRA_DEBOS_OPTS="-t target_boards:qrb2210-arduino-imola" make flash`
   — **not verified yet** whether this board name actually appears in the
   accepted `target_boards` list / whether its DTB ships in the default
   `dtbs.tar.gz`.
5. Flash via `qdl` or point `arduino-flasher-cli flash` at the resulting
   `flash_qrb2210-arduino-imola_emmc/` directory.

Likely-faster shortcut for just testing a custom kernel (not yet tried):
skip the whole EDL/flash cycle, drop the new kernel+initrd directly onto
the live board's ESP (`/boot/efi/<machine-id>/<version>/`) and add a BLS
entry in `/boot/efi/loader/entries/`, since secure boot is off and the ESP
is writable.

## Reproducing and testing the running kernel (done)

`build-kernel.sh` + `flake.nix` + `test-on-board.sh` in repo root implement
the above. Summary of what actually worked:

### Exact source commit

The running kernel's `g0dd6551ae96b` build-id is a real commit hash, not
just a `git describe` artifact: `0dd6551ae96b78024086e72339fefbef6fcc604b`
on `remotes/arduino/qcom-v6.16.7-unoq` ("arm64: qrb2210: support Arduino
UNO Q"). That branch HEAD *is* the exact tree that produced the running
`/boot/vmlinuz`/`/boot/config-*`.

### Build

`qcom-deb-images/scripts/build-linux-deb.py` is the documented build
entrypoint, but two things make it unusable as-is:
- It calls `make bindeb-pkg`, which needs `debhelper` -- not packaged in
  nixpkgs at all (checked: no `debhelper` attribute, no `dh-*` equivalent).
- Its `merge_config.sh` invocation hardcodes `cwd="linux"`, breaking
  `--local-dir` unless the local tree happens to be a directory literally
  named `linux` directly under the invocation cwd.

Lazier fix: skip the .deb packaging step entirely. `build-kernel.sh`
replicates only the parts that matter (`defconfig` + merge
`qcom-deb-images/kernel-configs/*.config` fragments via `merge_config.sh`
+ `olddefconfig`), then builds the kernel tree directly with `make all dtbs
modules`. Because the running config has `CONFIG_EFI_ZBOOT=y` (from
`systemd-boot.config`), plain `make all` already produces
`arch/arm64/boot/vmlinuz.efi` (gzip-compressed ARM64 EFI zboot image) --
no separate packaging step needed for a bootable artifact.

Build environment: `flake.nix` provides a `nix develop` shell with the
cross toolchain + the same build-dependency list `build-linux-deb.py`
checks for (`crossbuild-essential-arm64` equivalent, flex, bison, bc,
etc.), built via `pkgsCross.aarch64-multiplatform`. One wrinkle: nixpkgs'
cross gcc prefixes binaries `aarch64-unknown-linux-gnu-`, but the kernel
build hardcodes `CROSS_COMPILE=aarch64-linux-gnu-`; the flake's
`shellHook` symlinks the toolchain into a tmpdir under the expected prefix
and prepends it to `$PATH`.

Same defconfig base, same fragment set, same source commit as the stock
build -- not byte-identical (different host toolchain version than
whatever qsc-deb-releases used to build the shipped kernel), but same
config and source.

### Testing on hardware: kexec, not a new boot entry

Originally planned to drop the new kernel onto the ESP and add a BLS
entry, using `bootctl set-oneshot` for a safe one-time test boot. Doesn't
work on this board: `dmesg` shows `Firmware does not support
SetVariableRT. Can not remount with rw` -- U-Boot's UEFI implementation
only supports `GetVariable`, not `SetVariable`, at runtime, so `efivarfs`
is permanently read-only and `LoaderEntryOneShot` can never be written.
No persistent one-shot mechanism is possible on stock firmware.

Used `kexec` instead (`apt-get install kexec-tools`, not installed by
default; works once `apt-get update` has run -- the mirror occasionally
404s on stale Recommends like `libxen*`, harmless since they're not hard
deps). `kexec -l <Image> --dtb=<dtb> --initrd=<existing initrd path>
--command-line=<cmdline minus initrd=>` loads the new kernel from the
*running* system; `kexec -e` jumps straight to it, skipping
U-Boot/systemd-boot entirely. This means:
- The on-disk boot config is never touched -- a failed/hung kexec just
  needs a power cycle to fall back to the untouched stock entry.
- No persistent EFI variable writes needed, so the firmware limitation
  above doesn't matter.
- The existing initrd can be reused as-is: eMMC storage
  (`CONFIG_MMC_SDHCI_MSM`) and UFS (`CONFIG_SCSI_UFSHCD_PLATFORM`) are
  built in (`=y`), not modules, so the new kernel doesn't need its own
  `/lib/modules/<version>/` populated on the rootfs just to mount root.

ESP detail learned along the way: it's FAT32, so BLS entries can't use
symlinks for shared initrds -- just point the `initrd` line in a new
`.conf` at the existing file path directly (this is what `test-on-board.sh`
would need if it ever switches back to the BLS-entry approach).

No live boot console is available over adb (adbd only starts once Linux
userspace is up), so verification is before/after: note
`/proc/sys/kernel/random/boot_id`, `kexec -e`, `adb wait-for-device`, then
diff `boot_id` and check `uname -r`/`journalctl -b -k`.

Result: kexec boot of the freshly built kernel succeeded on the stock
board.

## Custom-kernel Debian image: built, flashed, booted to login (this session)

The "Path to a custom-kernel image" plan above now works end to end. The
full image flashes via `qdl` and boots the stock Debian rootfs with a
custom kernel to a serial login. Three real bugs had to be fixed first;
all are committed in this repo.

### Bug 1 — dtb partition FAT sector size (U-Boot can't read the dtb)

`qualcomm-linux-debian-flash.yaml` formatted the `dtb-combineddtb.bin` FAT
with `mkfs.vfat -S 4096`, hardcoded with a comment assuming UFS. The UNO Q
is **emmc (512-byte logical sectors)**, so U-Boot rejected the FAT with
`FAT sector size mismatch (fs=4096, dev=512)` and couldn't load the board
devicetree → boot failed at U-Boot. Fixed: sector size now follows
`disk_type` (`512` for emmc/sdcard, `4096` for ufs). The ESP itself
(`disk-sdcard.img1`) was already 512 and fine — only the dtb partition was
wrong.

### Bug 2 — no `console=` in the kernel cmdline (kernel boots mute)

The BLS entry's `options` had no `console=`, so systemd-boot launched the
kernel and it ran with no serial console — looks exactly like a hang.
Added `console=ttyMSM0,115200n8` to `append-kernel-cmdline` in
`qualcomm-linux-debian-image.yaml`. (ttyMSM0 is the qcm2290 geni debug
UART.)

### Bug 3 — RPM bring-up stack built `=m`, the actual no-boot cause

The big one. arm64 `defconfig` builds the Qualcomm RPM stack as **modules**:
`QCOM_SMEM`, `QCOM_SMD_RPM`, `QCOM_CLK_SMD_RPM`, `QCOM_RPMPD`,
`QCOM_APCS_IPC`, `RPMSG_QCOM_SMD/GLINK`, `QCM_GCC_2290`. On qcm2290 the RPM
SMD clock + power-domain controllers are the **root suppliers** for GCC,
the geni UART, SMMU, SPMI and the CPU PM domains. As modules they don't
come up in dependency order from the generic Debian initramfs, so every
consumer defers forever and root never mounts. Symptoms: endless
`CPUidle PSCI: failed to create CPU PM domains ret=-517` storm, and
`deferred probe pending: ... wait for supplier
/remoteproc/glink-edge/rpm-requests/clock-controller`. **Not** a dtb issue
(both the combined-dtb and the full Linux dtb fail identically; the dtb has
the right nodes), and **not** missing modules (they're in the initramfs).

Fix: `qcom-deb-images/kernel-configs/qcom-rpm-builtin.config` forces the
RPM stack + GCC + pinctrl + RPM regulator/interconnect, plus EXT4 + SDHCI,
to `=y`. Built-in, they probe during kernel init and the whole tree
resolves. With storage also `=y` the kernel mounts root with no initramfs
at all. Validated: full systemd boot to `debian login:` on ttyMSM0,
NetworkManager/ModemManager/adbd all up.

### Building the kernel `.deb` (must be in the Debian container, not nix)

`make bindeb-pkg` cannot run on the nix host: the kernel's `debian/rules`
uses `dh_listpackages` (debhelper), which is not in nixpkgs, and
`bindeb-pkg` (binary build) runs `dpkg-checkbuilddeps` which fails with no
dpkg package DB. Build it in the debos container instead:

    podman run --rm --entrypoint bash -v "$PWD":/work -w /work/linux \
      ghcr.io/go-debos/debos:latest -c '
        dpkg --add-architecture arm64; apt-get update
        apt-get install -y --no-install-recommends debhelper dpkg-dev \
          build-essential crossbuild-essential-arm64 bc bison flex \
          libdw-dev libelf-dev libssl-dev libssl-dev:arm64 kmod python3 rsync
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
        scripts/kconfig/merge_config.sh -m -r .config ../qcom-deb-images/kernel-configs/*.config
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
        make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- DPKG_FLAGS=-d bindeb-pkg'

- `--entrypoint bash` is required (the debos image's entrypoint is `debos`,
  which otherwise eats the args).
- Default rootless userns (root-in-container) so `apt` works; files in the
  bind mount still come out owned by the host user.
- `DPKG_FLAGS=-d` = `dpkg-buildpackage --no-check-builddeps` (harmless once
  deps are installed; needed if they aren't).
- **`mrproper` first is mandatory.** A tree previously built on the nix host
  has host tools (`scripts/kconfig/conf`, fixdep, modpost) linked against
  the nix loader; they fail with `No such file or directory` (ENOENT on the
  missing interpreter) inside the container. So the container build can't
  reuse nix-built objects — it's a full from-scratch compile.

Then: drop the `linux-image-*.deb` into `qcom-deb-images/local-debs/` and
build the rootfs with `-t kernelpackage:none -t localdebs:local-debs/`
(rootfs recipe overlays it to `/root/` and `apt-get install`s it).

### A/B slot retry exhaustion → drops to fastboot

ABL boots `boot_a` with a retry counter (starts ~7, visible as
`slot-retry-count:a`). Each boot that the OS doesn't confirm "successful"
(via `qbootctl`/the boot-success path) decrements it. After enough
unconfirmed boots the slot is flagged unbootable
(`Slot _a is unbootable, trying alternate slot` → `Launching fastboot`)
and ABL falls back to **fastboot** (USB `18d1:d00d`). This is the same
ABL-served fastboot that `flashall` targets. Re-arm the slot with:

    nix shell nixpkgs#android-tools -c fastboot set_active a
    nix shell nixpkgs#android-tools -c fastboot reboot

(`fastboot` is not on PATH; android-tools is in nixpkgs but its default
app name is wrong, so call the `fastboot` binary explicitly as above.)

### Serial console for boot debugging: Glasgow as 1V8 UART

The board's UART is 1.8V-only. `glasgow-console.sh` (repo root) runs the
nixpkgs glasgow UART applet at 1.8V: `A0` = Glasgow TX → board RX, `A1` =
Glasgow RX ← board TX. Note the Linux console (ttyMSM0) is the
**RPM-clocked geni UART**, so the full tty only registers once RPM is up;
`earlycon` shows kernel printk earlier (reusing the bootloader-left-on
clock), but userspace `/dev/console` needs the real driver — which is why a
kernel that fails RPM bring-up looks totally silent after the U-Boot stage.
Run it inside `tmux` (session `uart`) so a second tool can `capture-pane`
/`send-keys` the same console.

### Fast kernel-iteration trick (no rootfs rebuild)

Because a fully-`=y` kernel needs no matching initramfs, you can test a new
kernel without rebuilding the 2.9G rootfs: `mcopy` the new `Image` over
`::/<machine-id>/<ver>/linux` in `disk-sdcard.img1`, edit the BLS entry's
`options` with `mtype`/`mcopy`, then `qdl` only the efi partition with a
one-line `rawprogram-efionly.xml` (filter `label="efi"` from
`rawprogram0.xml`). Same trick for the dtb partition
(`rawprogram-dtbonly.xml`, `label="dtb_a"`/`dtb_b`). Each is seconds, vs a
full reflash. Inspect/modify the built ESP and rootfs images offline with
`mtools` (FAT) and `debugfs -R 'cat /path' disk-sdcard.img2` (ext4) — no
mount/root needed.

## Entering EDL mode

This board has no dedicated BOOT button. `reboot edl` from userspace does
*not* work either -- confirmed the board's devicetree
(`qrb2210-arduino-imola.dts` and includes) defines no `reboot-mode`/`mode-*`
properties, so there's no software hook for a reboot-reason string to land
on; it just performs a normal reboot.

EDL entry is purely hardware: shunt the two pins **furthest from the USB
connector** on the JCTL pin header with a jumper, then power on the board.
Confirmed via `lsusb` showing `05c6:9008 Qualcomm, Inc. ... (QDL mode)`.

## qdl hangs silently if `qcserial` claims the EDL device first

Once in EDL mode, the host kernel's `qcserial` driver auto-binds to the
`05c6:9008` device's interface (it looks like a generic Qualcomm modem to
the kernel). `qdl` then can't claim the USB interface itself, but instead
of failing loudly it sits in a silent retry loop (`hrtimer_nanosleep`,
process state `S`) -- `/proc/<pid>/io` shows `rchar` slowly climbing (it's
just re-reading the local image files on each retry), so it looks like
forward progress when checked superficially, but `usbmon`/Wireshark shows
*zero* actual USB traffic. Confirmed by checking
`/sys/bus/usb/devices/<bus>-<port>/<bus>-<port>:1.0/driver` -- symlinked to
`qcserial`.

Fix: unbind it before running qdl:

    echo '<bus>-<port>:1.0' | sudo tee /sys/bus/usb/drivers/qcserial/unbind

(find `<bus>-<port>` via `lsusb -t` or by grepping
`/sys/bus/usb/devices/*/idVendor` for `05c6`). Kill and restart `qdl`
afterwards -- it does not recover from being launched while the interface
was unavailable.
