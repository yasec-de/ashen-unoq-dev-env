# UNO Q board bring-up notes

Reverse-engineering the Arduino UNO Q image/flash/boot pipeline, across
`arduino-flasher-cli/`, `linux/`, `qdl/`, `qcom-deb-images/`, plus a stock
board over `adb`.

## Repo map

- `arduino-flasher-cli/` — end-user CLI/daemon, flashes a Debian image via
  embedded `qdl`. Consumes a `flash`/`flash_UnoQ` dir (`rawprogram*.xml`,
  `gpt_main0.bin`, `patch0.xml`, `prog_firehose_ddr.elf`). Doesn't build images.
- `linux/` — kernel source, Arduino remote (`arduino`,
  `https://github.com/arduino/linux-qcom`), branch `qcom-v7.0.0-unoq`. Two
  boards in here, don't confuse:
  - `qrb2210-arduino-imola*.dts` — **the actual UNO Q** (QCM2290/QRB2210).
  - `monaco-arduino-monza.dts` — different board ("Monza", QCS8300/Monaco). Not UNO Q.
- `qdl/` — EDL/Firehose flashing client + GPT parsing only. No image build.
- `qcom-deb-images/` (https://github.com/qualcomm-linux/qcom-deb-images) —
  **the actual build pipeline**. debos recipes for rootfs, kernel package,
  disk image, flash assets. Needed to build a custom image/kernel.
- `unoq-bootloader-emmc-linux-251020/` — extracted Arduino bootloader zip (see below).
- `u-boot/` — not investigated; see "U-Boot source" for where the real running U-Boot comes from.

## Scripts (repo root)

- `build-image.sh` — build a complete flashable image with our fixed kernel:
  kernel `.deb` (in the go-debos container) → rootfs → disk image → flash dir.
  The one command to go from source to `qcom-deb-images/flash_*/`.
- `flash.sh` — flash that image over EDL with `qdl` (waits for the device,
  unbinds `qcserial`). Put the board in EDL first (JCTL jumper, see below).
- `build-kernel.sh` — build just the kernel `Image`+dtbs (nix, no `.deb`) for
  the fast kexec test path.
- `test-on-board.sh` — kexec the freshly built kernel on the running board via
  adb (no flash). Fast kernel iteration.
- `glasgow-console.sh` — 1.8V serial console to the board's UART via a Glasgow.
- `Dockerfile.debos` — go-debos image + kernel cross-build toolchain +
  mtools/dtc, used for both the kernel-deb and flash stages of build-image.sh
  (built on demand).
- `udev/` — `60-qdl.rules` (EDL `uaccess`) and `70-glasgow.rules`.

## Board identity: UNO Q = `qrb2210-arduino-imola`

In `qcom-deb-images/debos-recipes/qualcomm-linux-debian-flash.yaml`, board
entry `qrb2210-arduino-imola` (silicon `qcm2290`, `ptool_platforms:
qrb2210-unoq/emmc-16GB`) is labeled "UNO Q boot binaries". Distinct from:
- `qrb2210-rb1` — Linaro/Qualcomm devkit, different bootloader, gated behind `build_rb1`/`u_boot_rb1`.
- `monaco-arduino-monza` — unrelated newer Arduino board, different silicon.

## Bootloader blob bundle (`unoq-bootloader-emmc-linux-251020.zip`)

- Source: `https://downloads.arduino.cc/debian-im/unoq-bootloader-emmc-linux-251020.zip`,
  pinned by sha256 ([line 232](qcom-deb-images/debos-recipes/qualcomm-linux-debian-flash.yaml#L232)).
- Added once, never bumped; version = embedded date `251020` (2025-10-20), no semver.
- Unlike other boards (which pull Qualcomm boot bins from
  `softwarecenter.qualcomm.com` + CDT zip from `artifacts.codelinaro.org`),
  Arduino repackages UNO Q into one zip, no separate CDT download.
- `LICENSE.arduino`: derived from Linaro's RB1 rescue image
  (`releases.linaro.org/96boards/rb1/linaro/rescue/23.12/...`).

File-by-file (from `flashall` + `rawprogram0.xml` labels + sizes/headers):
- `xbl.elf`, `xbl_feature_config.elf`, `tz.mbn`, `hyp.mbn`, `rpm.mbn`,
  `devcfg.mbn`, `imagefv.elf`, `uefi_sec.mbn`, `km4.mbn`, `qupv3fw.elf`,
  `featenabler.mbn`, `storsec.mbn`, `multi_image.mbn` — Qualcomm SoC boot
  chain firmware (XBL/TrustZone/hypervisor/RPM/etc), A/B partitioned.
  **Closed, proprietary, no public source** even via Linaro/CodeLinaro —
  only prebuilt signed binaries. Modifying XBL in practice = patch/re-sign
  stock binary with `xbltools`/`qtestsign` (works, secure boot is off).
- `NON-HLOS.bin` — modem firmware. `BTFM.bin` — BT/FM firmware. `dspso.bin` — DSP firmware (which core: uncertain).
- `boot.img` — confirmed via hex dump (`ANDROID!` magic) to be a real
  Android boot image, but **not the Linux kernel** — it's **U-Boot itself**
  in Android boot-image format (same mechanism `u_boot_rb1` uses for RB1,
  default here not opt-in). Chain: ABL → this → U-Boot → UEFI →
  `systemd-bootaa64.efi` → real kernel+initrd as plain ESP files.
- `boot-erase.img` — all-zero filler, wipes boot partition.
- `gpt_main0/1/2.bin`, `gpt_backup0/1/2.bin`, `gpt_both0.bin`, `gpt_empty0.bin` — GPT tables, eMMC LUNs 0/1/2.
- `rawprogram0.xml` / `.nouser.xml` — firehose programming scripts;
  `.nouser` skips `userdata` (powers `arduino-flasher-cli --preserve-user`).
- `patch0.xml` — firehose post-program GPT patch step.
- `cdt.bin` — Customer/Chip Definition Table, 24 bytes, magic `CDT.`. Field layout uncertain.
- `flashall` — alternate `fastboot`-based flash path, not used by `qdl`/`arduino-flasher-cli`.

## Real boot chain on stock hardware (confirmed via `adb`)

ABL → `boot.img` (U-Boot, Android boot-image format) → U-Boot UEFI →
`/boot/efi/EFI/systemd/systemd-bootaa64.efi` → BLS entry in
`/boot/efi/loader/entries/*.conf` → kernel+initrd as plain files at
`/boot/efi/<machine-id>/<kernel-version>/{linux,initrd.img-*}`.

- Root: plain mutable ext4 (`mmcblk0p68`, 10G, `/`); separate `/home` (`mmcblk0p69`, 18.2G).
- Default user `arduino` (uid 1000), sudo group.
- ESP: `mmcblk0p67`, FAT32, rw at `/boot/efi`.

## Secure boot: present as capability, OFF by default

- UEFI `SecureBoot`/`SetupMode` vars exist (U-Boot UEFI supports it), but
  `SecureBoot=0` on stock unit; `/boot/efi/loader/keys/` empty.
- No `dm-verity`, no `androidboot.verifiedbootstate` in `/proc/cmdline` — no OS-level verified boot.
- Public reporting: Arduino plans FoundriesFactory secure-boot opt-in for production in early 2026.
- Practical implication: custom kernel/initrd can be dropped on the ESP +
  new BLS entry, no signing required.

## U-Boot source

- Running version: `2026.01-rc3-g572d34ccadb9` (from
  `/proc/device-tree/chosen/u-boot,version`) = `git describe`: tag
  `v2026.01-rc3` + short hash of an Arduino fixup commit.
- Source: `https://github.com/arduino/u-boot`, branch
  `qcom-denx-mainline-emmc` (only branch with that commit). Default branch
  `qcom-mainline` tracks upstream DENX mainline + Arduino/Qualcomm patches.

## Kernel config

No single committed board config; reconstructed at build time by `qcom-deb-images/scripts/build-linux-deb.py`:
1. `make defconfig` from `linux/arch/arm64/configs/defconfig`.
2. Merge `qcom-deb-images/kernel-configs/*.config` via `merge_config.sh`, then `make olddefconfig`.

README's invocation merges *all* fragments:
`scripts/build-linux-deb.py kernel-configs/*.config`. Confirmed overlap with
live config (`/boot/config-6.16.7-g0dd6551ae96b`): `monza.config`'s
`CONFIG_SENSORS_INA2XX`, `systemd-boot.config`'s `CONFIG_EFI_ZBOOT`,
`docker.config`'s namespace options all present on device.

Ground truth for exact running config: always `/boot/config-<uname -r>` on
the device, not any file in these repos.

## DTB provenance

`qcom/qrb2210-arduino-imola.dtb` ← `linux/arch/arm64/boot/dts/qcom/qrb2210-arduino-imola.dts`
in the `arduino`-remote checkout. Default `qcom-deb-images` rootfs build
doesn't compile the DTB locally — installs `linux-image-arm64` from
Qualcomm's APT overlay (`qsc-deb-releases` at
`qartifactory-edge.qualcomm.com`), which installs DTBs to
`/usr/lib/linux-image-*/`. Rootfs recipe tars that dir into `dtbs.tar.gz`
(`qualcomm-linux-debian-rootfs.yaml:650-669`); flash recipe extracts the
board-specific `.dtb` by path.

For a custom kernel: `kernelpackage:none` + `localdebs:local-debs/` debos
options, own kernel `.deb` installing DTBs to the same path convention.

## Path to a custom-kernel image

**Verified end to end** — see "Custom-kernel Debian image" section below
for the full procedure + three bugs fixed. Outline (original plan,
confirmed correct: `target_boards:qrb2210-arduino-imola` accepted, DTB ships
in default `dtbs.tar.gz`):

1. Build kernel from `linux/` (`qcom-v7.0.0-unoq`) with `defconfig` +
   `qcom-deb-images/kernel-configs/*.config`, package as `.deb`.
2. `EXTRA_DEBOS_OPTS="-t localdebs:local-debs/ -t kernelpackage:none" make rootfs.tar`
3. `make disk-ufs.img` (or `disk-sdcard.img`)
4. `EXTRA_DEBOS_OPTS="-t target_boards:qrb2210-arduino-imola" make flash`
5. Flash via `qdl` or `arduino-flasher-cli flash` against `flash_qrb2210-arduino-imola_emmc/`.

Untried faster shortcut for testing a kernel only: skip EDL/flash, drop
kernel+initrd onto the live ESP (`/boot/efi/<machine-id>/<version>/`) + new
BLS entry — secure boot off, ESP writable.

## Reproducing and testing the running kernel (done)

`build-kernel.sh` + `flake.nix` + `test-on-board.sh` in repo root.

### Exact source commit

Running kernel's `g0dd6551ae96b` build-id is a real commit:
`0dd6551ae96b78024086e72339fefbef6fcc604b` on
`remotes/arduino/qcom-v6.16.7-unoq` ("arm64: qrb2210: support Arduino UNO
Q"). That HEAD = exact tree behind running `/boot/vmlinuz`/`/boot/config-*`.

### Build

`build-linux-deb.py` is the documented entrypoint but unusable as-is:
- Calls `make bindeb-pkg`, needs `debhelper` — not in nixpkgs at all.
- `merge_config.sh` invocation hardcodes `cwd="linux"`, breaks `--local-dir`
  unless local tree is literally named `linux` under invocation cwd.

`build-kernel.sh` instead: skip `.deb` packaging, replicate `defconfig` +
merge `kernel-configs/*.config` + `olddefconfig`, then `make all dtbs
modules` directly. `CONFIG_EFI_ZBOOT=y` (from `systemd-boot.config`) means
plain `make all` already produces `arch/arm64/boot/vmlinuz.efi` (gzip ARM64
EFI zboot) — no packaging step needed.

Build env: `flake.nix` → `nix develop` shell, cross toolchain via
`pkgsCross.aarch64-multiplatform` (matches `build-linux-deb.py`'s dep list:
flex, bison, bc, etc). nixpkgs cross gcc prefixes
`aarch64-unknown-linux-gnu-`, kernel build hardcodes
`CROSS_COMPILE=aarch64-linux-gnu-` — `shellHook` symlinks toolchain into a
tmpdir under the expected prefix, prepends to `$PATH`.

Same defconfig, fragments, source commit as stock build — not
byte-identical (different host toolchain), same config/source.

### Testing on hardware: kexec, not a new boot entry

Plan A (BLS entry + `bootctl set-oneshot`) doesn't work: `dmesg` shows
`Firmware does not support SetVariableRT` — U-Boot's UEFI only supports
`GetVariable` at runtime, `efivarfs` permanently read-only,
`LoaderEntryOneShot` can never be written. No persistent one-shot possible.

Used `kexec` instead (`apt-get install kexec-tools`; mirror sometimes 404s
on stale Recommends like `libxen*`, harmless). `kexec -l <Image>
--dtb=<dtb> --initrd=<existing initrd> --command-line=<cmdline minus
initrd=>` then `kexec -e` jumps straight to the new kernel from the running
system, skipping U-Boot/systemd-boot. Implications:
- On-disk boot config never touched — failed/hung kexec just needs a power cycle.
- No persistent EFI var writes needed.
- Existing initrd reusable as-is: eMMC (`CONFIG_MMC_SDHCI_MSM`) + UFS
  (`CONFIG_SCSI_UFSHCD_PLATFORM`) built in (`=y`), no new
  `/lib/modules/<version>/` needed just to mount root.

ESP is FAT32 — no symlinks for shared initrds; BLS `.conf` must point
`initrd` directly at the existing file path.

No live boot console over adb (adbd starts only once userspace is up) —
verify before/after: note `/proc/sys/kernel/random/boot_id`, `kexec -e`,
`adb wait-for-device`, diff `boot_id`, check `uname -r`/`journalctl -b -k`.

Result: kexec boot of freshly built kernel succeeded on stock board.

## Custom-kernel Debian image: built, flashed, booted to login (this session)

Full image flashes via `qdl`, boots stock Debian rootfs with custom kernel
to serial login. Three bugs fixed, all committed.

### Bug 1 — dtb partition FAT sector size (U-Boot can't read the dtb)

`qualcomm-linux-debian-flash.yaml` formatted `dtb-combineddtb.bin` FAT with
hardcoded `mkfs.vfat -S 4096` (comment assumed UFS). UNO Q is **emmc
(512-byte sectors)** → U-Boot: `FAT sector size mismatch (fs=4096,
dev=512)`, couldn't load board devicetree, boot failed at U-Boot. Fix:
sector size follows `disk_type` (512 emmc/sdcard, 4096 ufs). ESP itself
(`disk-sdcard.img1`) was already 512 and fine.

### Bug 2 — no `console=` in kernel cmdline (boots mute)

BLS entry `options` had no `console=` → kernel ran with no serial console,
looked like a hang. Fix: added `console=ttyMSM0,115200n8` to
`append-kernel-cmdline` in `qualcomm-linux-debian-image.yaml` (ttyMSM0 = qcm2290 geni debug UART).

### Bug 3 — RPM bring-up stack built `=m`, the actual no-boot cause

arm64 `defconfig` builds Qualcomm RPM stack as **modules**: `QCOM_SMEM`,
`QCOM_SMD_RPM`, `QCOM_CLK_SMD_RPM`, `QCOM_RPMPD`, `QCOM_APCS_IPC`,
`RPMSG_QCOM_SMD/GLINK`, `QCM_GCC_2290`. On qcm2290 these are root suppliers
for GCC, geni UART, SMMU, SPMI, CPU PM domains. As modules they don't load
in dependency order from the generic initramfs → every consumer defers
forever, root never mounts. Symptoms: `CPUidle PSCI: failed to create CPU
PM domains ret=-517` storm, `deferred probe pending: ... wait for supplier
/remoteproc/glink-edge/rpm-requests/clock-controller`. Not a dtb issue (both
combined-dtb and full dtb fail identically, right nodes present). Not
missing modules (present in initramfs).

Fix: `qcom-deb-images/kernel-configs/qcom-rpm-builtin.config` forces RPM
stack + GCC + pinctrl + RPM regulator/interconnect + EXT4 + SDHCI to `=y`.
Built-in → probe during kernel init, tree resolves. With storage also `=y`,
kernel mounts root with no initramfs at all. Validated: full systemd boot
to `debian login:` on ttyMSM0, NetworkManager/ModemManager/adbd up.

### Building the kernel `.deb` (must be in Debian container, not nix)

`make bindeb-pkg` can't run on nix host: `debian/rules` uses
`dh_listpackages` (debhelper, not in nixpkgs); `bindeb-pkg` runs
`dpkg-checkbuilddeps`, fails with no dpkg DB. Build in debos container instead:

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

- `--entrypoint bash` required (image's entrypoint is `debos`, eats args).
- Default rootless userns (root-in-container) for `apt`; bind-mount files still come out host-owned.
- `DPKG_FLAGS=-d` = `dpkg-buildpackage --no-check-builddeps`.
- **`mrproper` first is mandatory** — a tree built on nix host has host
  tools (`scripts/kconfig/conf`, fixdep, modpost) linked against the nix
  loader, fail with ENOENT in container. Container build can't reuse
  nix-built objects, full rebuild needed.

Then: drop `linux-image-*.deb` into `qcom-deb-images/local-debs/`, build
rootfs with `-t kernelpackage:none -t localdebs:local-debs/` (recipe
overlays to `/root/`, `apt-get install`s it).

### A/B slot retry exhaustion → drops to fastboot

ABL boots `boot_a` with retry counter (starts ~7, `slot-retry-count:a`).
Each unconfirmed boot (no `qbootctl` boot-success) decrements it. Exhausted
→ `Slot _a is unbootable, trying alternate slot` → fastboot (USB
`18d1:d00d`), same ABL fastboot `flashall` targets. Re-arm:

    nix shell nixpkgs#android-tools -c fastboot set_active a
    nix shell nixpkgs#android-tools -c fastboot reboot

(`fastboot` not on PATH by default app name; call binary explicitly as above.)

### Serial console for boot debugging: Glasgow as 1V8 UART

Board UART is 1.8V-only. `glasgow-console.sh` (repo root): nixpkgs glasgow
UART applet at 1.8V, `A0` = Glasgow TX → board RX, `A1` = Glasgow RX ←
board TX. Linux console (ttyMSM0) is RPM-clocked geni UART — full tty
registers only once RPM is up; `earlycon` shows printk earlier (reuses
bootloader-left-on clock), but userspace `/dev/console` needs the real
driver — why a kernel failing RPM bring-up looks silent after U-Boot. Run
inside `tmux` (session `uart`) so a second tool can `capture-pane`/`send-keys`.

### Fast kernel-iteration trick (no rootfs rebuild)

Fully-`=y` kernel needs no matching initramfs → test without rebuilding the
2.9G rootfs: `mcopy` new `Image` over `::/<machine-id>/<ver>/linux` in
`disk-sdcard.img1`, edit BLS `options`, `qdl` only the efi partition with a
one-line `rawprogram-efionly.xml` (filter `label="efi"` from
`rawprogram0.xml`). Same for dtb partition (`rawprogram-dtbonly.xml`,
`label="dtb_a"`/`dtb_b`). Each takes seconds vs full reflash. Inspect/modify
images offline with `mtools` (FAT) and `debugfs -R 'cat /path'
disk-sdcard.img2` (ext4) — no mount/root needed.

## Entering EDL mode

No dedicated BOOT button. `reboot edl` from userspace doesn't work either —
devicetree (`qrb2210-arduino-imola.dts` + includes) defines no
`reboot-mode`/`mode-*` properties, no software hook for a reboot-reason
string; just does a normal reboot.

EDL entry is purely hardware: shunt the two pins **furthest from the USB
connector** on the JCTL header with a jumper, power on. Confirmed via
`lsusb` → `05c6:9008 Qualcomm, Inc. ... (QDL mode)`.

## qdl hangs silently if `qcserial` claims the EDL device first

Host kernel's `qcserial` auto-binds to the `05c6:9008` device (looks like a
generic Qualcomm modem). `qdl` then can't claim the USB interface — instead
of failing loudly it silently retry-loops (`hrtimer_nanosleep`, state `S`);
`/proc/<pid>/io` `rchar` slowly climbs (just re-reading local image files),
looks like progress but `usbmon`/Wireshark shows zero USB traffic. Confirm
via `/sys/bus/usb/devices/<bus>-<port>/<bus>-<port>:1.0/driver` symlinked to `qcserial`.

Fix: unbind before running qdl:

    echo '<bus>-<port>:1.0' | sudo tee /sys/bus/usb/drivers/qcserial/unbind

(find `<bus>-<port>` via `lsusb -t` or grep `idVendor` for `05c6`). Kill and
restart `qdl` after — it doesn't recover from launching while unavailable.
