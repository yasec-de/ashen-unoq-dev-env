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
- `zeroize/` — our fast tamper-response RAM zeroization (kernel patches in
  `linux/` + a freestanding kdump capture/wipe payload). See "Fast tamper-response
  zeroization" below and `zeroize/README.md`.

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

## External JTAG debug: blocked by TrustZone debug policy

Goal was halt-mode JTAG debug of the QRB2210 application cores (kernel hang
debugging) via Glasgow (`jtag-openocd` applet) + OpenOCD. Full account in
`TASK.md`; the findings:

- Both TAPs enumerate: `auto0.tap` 0x5ba00477 (ARM DAP), `auto1.tap`
  0x001c80e1 (Qualcomm).
- `dap init` originally hung polling DP CTRL/STAT — `CDBGPWRUPACK` asserts,
  `CSYSPWRUPACK` never does (timeout, error -5). This is a **non-conformant
  power handshake, not the real blocker**: OpenOCD's `dap create ...
  -ignore-syspwrupack` skips that wait and `dap init` completes.
  (`openocd.cfg` carries the flag.)
- With it, the MEM-AP enumerates: AP IDR `0x14770004` (Qualcomm AXI3/4
  MEM-AP), CSW `0x30800042` (writable). DP `ABORT`
  (`auto0.dap dpreg 0x0 0x1F`) clears the JTAG-DP sticky errors that
  otherwise block every probe — needed between transactions.
- **But every AXI read through the AP returns `0x00000000`, no fault, clean
  CTRL/STAT** — DDR `0x80000000`, boot ROM `0x0`, GCC `0x01400000`, TCSR,
  IMEM all zero. GCC is never all-zero on a running SoC. The AP completes
  transactions; the secure access controller silently zero-fills all
  debug-AP reads.
- That is the definitive signature of **TrustZone debug policy gating the
  APSS debug AP** (DBGEN/NIDEN/SPIDEN deasserted by the secure boot chain).
  `BASE`=`0x2` / "No ROM table" / failed CoreSight autodiscovery are all
  downstream of the same gate. Enforced in secure firmware, invisible to
  Linux — not a DT or OpenOCD issue.

Reproduce: `openocd -f openocd.cfg` (Glasgow on `/tmp/jtag.sock`, TCK B0/TMS
B3/TDI B1/TDO B2/TRST B4, `-f 100`), then on tcl port 6666:
`auto0.dap dpreg 0x0 0x1F; auto0.dap apreg 0 0x4 0x01400000; auto0.dap apreg 0 0xC`
→ `0x00000000`.

Only JTAG-unlock route left touches secure firmware — see `TASK.md`.

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

## DTB: which copy is live, and how to override per-kernel (TODO)

The kernel-loaded DTB is the **ESP file** `/boot/efi/dtb/qcom/qrb2210-arduino-imola.dtb`
(U-Boot→systemd-boot path), NOT the `dtb_a`/`dtb_b` FAT partitions (p17/p18,
`combined-dtb.dtb`). Verified 2026-06-23: editing p17 had no effect on the live
DT; editing the ESP file did (and a bad DTB there = kernel hang → watchdog
reset, systemd-boot still runs fine).

BLS entries currently have **no `devicetree` line**, so every entry shares the
one ESP DTB. **TODO: give the modified (coresight) kernel its own DTB** by
adding a per-entry `devicetree /path.dtb` line (systemd-boot honors it here),
e.g. ship `qrb2210-arduino-imola-coresight.dtb` alongside the stock one and
point only the `-dirty`/experimental entry at it. Then a bad experimental DTB
can't brick boot — just select the stock entry. The coresight overlay source is
`coresight-imola.dtso`; merge with `fdtoverlay` onto the stock ESP DTB.

### Recovery from a bad ESP DTB (used 2026-06-23)
EDL (shunt the two JCTL pins furthest from USB, power on → `05c6:9008`), then:
```sh
cd qcom-deb-images/flash_qrb2210-arduino-imola_emmc
echo '5-2:1.0' | sudo tee /sys/bus/usb/drivers/qcserial/unbind   # NOTES gotcha
sudo ../../qdl/build/qdl -s emmc prog_firehose_ddr.elf rawprogram-restore.xml
```
`rawprogram-restore.xml` flashes only stock `dtb_a`,`dtb_b`,`efi` (efi from
`../disk-sdcard.img1`, the from-scratch flash image — its ESP DTB is stock/good).
Key flags that made it work: **`-s emmc`** (without it: "failed to setup
programming"), and unbinding `qcserial` first. No `patch0.xml` needed — that's
GPT-repartition only, irrelevant when writing into existing partitions.
This reverts BLS entries to the image's state; just re-run install-kernel.sh
after.

### Full flash (with GPT patches)
For a complete flash that repartitions, include `patch0.xml`:
```sh
cd qcom-deb-images/flash_qrb2210-arduino-imola_emmc
../../qdl/build/qdl -s emmc -l prog_firehose_ddr.elf rawprogram0.xml patch0.xml
```

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

### Wi-Fi (ath10k_snoc / WCN3990): QRTR deadlock + warm-reboot flakiness

Chip is WCN3990 at `c800000.wifi` (`qcom,wcn3990-wifi`), driven by
`ath10k_snoc`. It talks to firmware over QMI on QRTR (`AF_QIPCRTR`, PF=42).

**Deadlock when QRTR stack is `=m`:** at boot nothing opens a PF_QIPCRTR
socket and no `IPCRTR` rpmsg channel exists yet, so neither `qrtr` (alias
`net-pf-42`) nor `qrtr-smd` (alias `rpmsg:IPCRTR`) autoloads. But the
remoteprocs' `qmi_handle_init()` fails immediately without qrtr loaded →
modem/ADSP never boot → no IPCRTR channel → qrtr-smd never loads.
Chicken-and-egg. Symptoms: `failed to initialize qmi handle` (q6v5_pas),
`failed to register wlfw qmi client: -517` (ath10k), `deferred probe
pending`, no `wlan0`. Fix: force `CONFIG_QRTR=y` + `QRTR_SMD=y` (and the
remoteproc/glink stack) built-in so they probe during kernel init. Userspace
half (`rmtfs`, `tqftpserv`, `wireless-regdb`) was already present and fine.

**Warm-reboot flakiness:** after a plain `# reboot`, Wi-Fi sometimes does NOT
come back (ath10k stuck, WCN remoteproc recovery wedged — `kworker
rproc_recovery_wq` in D-state). A cold power-cycle via `./reset-target.sh`
(re-powers the board) always brings it up cleanly. So: to test Wi-Fi, reset
the board with `reset-target.sh`, don't rely on `reboot`.

**Do NOT debug this stack with `modprobe -r ath10k_snoc` / driver rebind:**
the WCN remoteproc recovery doesn't survive it and wedges (ath10k_snoc then
won't unload, "Device or resource busy"). Reboot/power-cycle to retest.

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

## Fast tamper-response zeroization (`zeroize/`)

Two-tier secret erase. Tier 1 runs in the dying kernel's crash path (highest
value, fastest); tier 2 is a freestanding capture kernel that erases all of RAM.
Build/deploy/test details in `zeroize/README.md`; this is the design + the
bring-up findings.

**Trigger / transport.** Tamper → `echo c > /proc/sysrq-trigger` (or in-kernel
`panic()`). No trigger module: the wipe runs on the normal crash-kexec path, and
the wipe payload is just the kdump capture image (`kexec -p`). So we *use* the
kdump machinery, not patch it.

**Tier 1 — crash-path zeroize (patches in `linux/`, branch `ashen`).** Hooked at
the end of `machine_crash_shutdown()` (after `crash_smp_send_stop()`), so it runs
single-CPU with the old kernel's mappings still live. Order = crown jewels first:
keyring (`user`/`logon` payloads) → `memfd_secret` pages → QCE key registers.
Gated by `crash_zeroize.armed` (off by default; HSM arms at runtime). New file
`kernel/crash_zeroize.c` + `CONFIG_CRASH_ZEROIZE` (`zeroize.config`).

**Tier 2 — capture/wipe payload (`zeroize/`).** Freestanding aarch64 Image; reads
`/memory`, `/reserved-memory` (no-map), `/chosen` `linux,usable-memory-range`,
`/cpus` from the crash DTB; identity-maps RAM, brings up all 4 cores via PSCI,
wipes in 4 slices, `PSCI SYSTEM_OFF`.

**Non-obvious findings (the parts that bite):**

- **Crash-path code must be lock-free.** Other CPUs are halted; taking
  `key_serial_lock`/page-cache locks could deadlock against a CPU that holds one.
  We walk `key_serial_tree` and the secretmem superblock's `s_inodes` without
  locks. This is also why there are *no timeouts* — single CPU, pure memory
  writes, nothing to stall.
- **No secretmem registry needed.** `secretmem_mnt->mnt_sb->s_inodes` already
  enumerates every live secret folio; the free-path primitive
  (`set_direct_map_default_noflush()` + zero) is reused as-is. Zero fast-path
  changes.
- **QCE key wipe reuses the driver's own `qce_clear_array()`** on
  `REG_ENCR_KEY0`/`REG_ENCR_XTS_KEY0`/`REG_AUTH_KEY0`/`REG_AUTH_IV0`. The driver
  has no reset line; clocks are held on for the device lifetime
  (`devm_clk_get_optional_enabled`) so the registers are reachable from the crash
  path. QCE is `=m`, so it registers a callback into built-in `crash_zeroize`.
- **`/proc/sysrq-trigger` bypasses the `kernel.sysrq` mask** and is root-only
  (`__handle_sysrq(c, false)`), so only `CONFIG_MAGIC_SYSRQ=y` is needed —
  `kernel.sysrq` can stay 0 (keyboard/serial sysrq disabled).
- **Wipe-set is mapped Normal Non-Cacheable**, not cacheable + DC ZVA: zeros land
  in DRAM immediately (no writeback worry for a secure erase) and there's no
  read-for-ownership. Secure (`no-map`) carveouts are left **unmapped** —
  writing them from EL1 faults an xPU. Rounding no-map out to 2 MB leaves ≤2 MB
  slack per carveout edge (firmware regions, no HSM secrets).
- **crashkernel base is pinned** (`crashkernel=64M@0x80000000` in the image
  cmdline) so the payload can be linked to its load address (`PAYLOAD_BASE`); no
  PIC. `usable-memory-range` is always inserted into the crash DTB by the kernel,
  so the payload trusts it for the "don't wipe our own code" region (and powers
  off if it's somehow absent rather than self-wiping).
- **EL handling.** `start.S` drops EL2→EL1 if needed (PSCI may bring secondaries
  up at EL2). 4× Cortex-A53; core count comes from `/cpus`, not assumed.

**Status:** kernel + payload build clean (`Image`, `qcrypto.ko`, symbols verified;
payload is a valid arm64 Image, magic at 0x38). Not yet validated on hardware —
that's destructive (wipes RAM, powers off). Open items: crashkernel base actually
free (`/proc/iomem`), `kexec -p -s` accepting the raw Image, entry EL. debos
install wiring (copy to `/usr/lib/zeroize/`, enable service, add `kexec-tools`)
still to do.

## JTAG halt-mode debug of the A53 cores: WORKING (2026-06-24)

External JTAG halt/inspect/resume of the QRB2210 A53 application cores works.
The long-held "JTAG impossible / TZ-fuse-gated" verdict was **wrong twice over**
(see [JTAG.md](JTAG.md) for the full history). Two real findings:

1. **Not security-gated.** Debug is permitted (Secure Boot off, OEM debug fuses
   unblown). Proven decisively: the RPM Cortex-M3 debug (AHB-AP, AP3) is wide
   open. A global TZ DBGEN gate could not leave that open.
2. **The blocker was a wrong dbgbase, not a power gate.** The A53s are behind
   the APB-AP (AP1, BASE 0x80000000). OpenOCD's ROM-table autodiscovery there
   faults ("core might be turned off") — but the per-core debug block is
   directly readable at a fixed address. The "CSYSPWRUPACK never asserts" thing
   was a red herring: it stays low, yet the cores debug fine once you point
   OpenOCD at the right base.

**The magic numbers** (from the QCS6490 OpenOCD patch, same APSS layout:
<https://sourceforge.net/p/openocd/mailman/message/59116199/>):
- core0 debug base **0x87010000**, its CTI **0x87020000**
- target: `aarch64 -ap-num 1 -coreid 0 -dbgbase 0x87010000 -cti <cti@0x87020000>`
- aarch64 halt REQUIRES the CTI object (`cti create ... -baseaddr 0x87020000`).

Confirmed live on our device: MIDR=0x410fd034 (Cortex-A53 r0p4),
EDDEVARCH=0x47706a15 (ARMv8-A debug). Halted core0, debug_reason=debug-request,
read coherent PC/SP/X0/X30 (caught it in a userspace spinner: pc=0xaaaa...,
sp=0xffff...), then resumed cleanly back to running. Config in `openocd.cfg`.

### Operational quirks (important)
- **Cores power-collapse their debug in idle.** A core only reads its debug regs
  (non-zero MIDR/EDPRSR) while it's *running*; idle cores read 0 at their debug
  base (cpuidle/PSCI power-collapse). This kernel exposes **no cpuidle sysfs**,
  so to keep a core debuggable, pin a busy loop on it (`taskset -c N sh -c
  'while :; do :; done'`). That's how we caught core0.
- **adb access drops while any core is halted, and recovers after resume.**
  A halted CPU stalls whatever runs on it (adbd, the shell). Don't panic if adb
  hangs during a halt — `resume` brings it back. (Bit us: an `adb pkill` issued
  right after a halt hung for 2 min until resume.)
- **All 4 cores now mapped + SMP working (2026-06-24).** Per-core stride is
  **0x100000**; each core's 0x40000 block = debug(+0)/CTI(+0x10000)/PMU(+0x20000)/
  ETM(+0x30000). Mapped by a DEVTYPE(+0xFCC) scan: debug=0x15, CTI=0x14,
  PMU=0x16, ETM=0x13. Bases:
  | core | debug      | CTI        |
  |------|------------|------------|
  | 0    | 0x87010000 | 0x87020000 |
  | 1    | 0x87110000 | 0x87120000 |
  | 2    | 0x87210000 | 0x87220000 |
  | 3    | 0x87310000 | 0x87320000 |
  `target smp` groups them: one `halt`/`resume` acts on the whole cluster and
  dumps per-core cpsr/pc/EL/MMU state. Confirmed all 4 halt+resume cleanly,
  MMU/caches enabled, coherent PCs (mix of EL0t userspace and EL1 kernel).
- **How to map debug/CTI bases (the method that worked):** raw `apreg` reads
  collide with OpenOCD's target polling and return 0. Fix: `poll off` first,
  re-arm the AP (`apreg 1 0x0 0x80000042`), then scan DEVTYPE/MIDR; `poll on`
  after. A half-broken target (examined but bad CTI) spews
  `{auto0.a53.N get_reg} pc` errors into the tcl stream — remove bad targets
  from the config and restart before scanning.
- **tcl-port command syntax:** use `arp_halt` / top-level `resume` / `get_reg` /
  `read_memory` — NOT `<target> halt` / `<target> reg` (those print subcommand
  help, look like errors but aren't).
- The CoreSight DT overlay work (CTI/ETM nodes) turned out **not** to be needed
  for JTAG — it powers the QDSS trace clock, orthogonal to the dbgbase fix. It's
  still installed in the `-test` BLS entry and boots fine.

## KVM / EL2: blocked by QHEE, custom-hyp path validated (2026-08-26)

`/dev/kvm` is absent. `dmesg`: `CPU: All CPU(s) started at EL1` +
`kvm [1]: HYP mode not available`. The kernel side is complete (`CONFIG_KVM=y`,
GICv3 maintenance PPI, arch-timer PPIs all present) — the only blocker is that
**EL2 is owned by QHEE**, Qualcomm's proprietary hypervisor, loaded by XBL from
the `hyp_a`/`hyp_b` partitions into the `hyp@45700000` carveout. QHEE boots the
HLOS at EL1 and exposes no VM API (ABL logs `VM Hyp calls not present` — it is
not Gunyah). The only route to KVM is to stop QHEE occupying EL2.

**Partition geometry (LIVE GPT — use this, not the flash dir):** hyp_a =
`/dev/mmcblk0p9` @ sector 164352, hyp_b = `/dev/mmcblk0p10` @ 165376, **1024
sectors / 512 KiB each**. This matches `unoq-bootloader-emmc-linux-251020/`'s
`rawprogram0.xml`. It does **NOT** match
`qcom-deb-images/flash_qrb2210-arduino-imola_emmc/rawprogram0.xml`, which
describes an 8 MiB layout at different offsets — restoring with that XML would
clobber neighbouring partitions.

**Blank-zeros does NOT work — QHEE is mandatory to XBL.** `dd`ing zeros over
both hyp slots makes XBL walk its A/B fallback and give up:
`Using boot chain :: Primary` → *"...corrupted..."* → recovery → *"Both Primary
and Recovery chains are corrupted. Entering EDL mode"* (seen on the Glasgow UART
console). XBL fails at **format-parse** (no valid ELF/MBN header), before auth.
Board drops to EDL — recoverable, but no boot.

**XBL accepts a qtestsign-signed custom hyp — PROVEN (secure boot off).** Took
the stock `hyp.mbn`, re-signed it with `qtestsign -v6 hyp` (dummy cert chain,
stub signature), flashed to both hyp slots over EDL → **board booted normally to
login**, modem/adsp `running`, wlan0 up. This confirms the whole custom-hyp
pipeline: XBL checks the hash-segment format + segment hashes but skips signature
verification when secure boot is off (matches `SecureBoot=0`, empty
`/boot/efi/loader/keys/`). Still EL1, because the *content* is stock QHEE.

- **Signing:** MBN **version 6**, SHA384, `hyp` sw_id `0x15`. Determined by
  decoding the stock hash-segment header (`version=6`, `hash_size=0xc0`=4×48B for
  the 4 phdrs, two `0xffffffff` unused-addr fields) — a perfect
  `qtestsign/mbn/hashseg.py:HashSegmentV6` match. `qtestsign -v6` is correct; no
  guessing.
- **QHEE load/entry:** ELF `EXEC`, entry + code LOAD at `0x45740000` (offset
  0x40000 into the 6 MiB `0x45700000` carveout), ~359 KiB.
- **TZ→hyp handoff (from disassembling the QHEE entry):** TZ enters hyp **at
  EL2** (first real insn writes `vbar_el2`). All cores funnel through the same
  entry, picking a per-core stack via `vmpidr_el2` (0x2000/core). Entry preserves
  `x0→x21, x1→x22, x2→x20` — i.e. TZ passes **x0 = next-stage (EL1) entry,
  x1 = exec-state, x2/x3 = args**, the same register contract MSM8916 qhypstub
  relies on. So the qhypstub approach is architecturally applicable here.

**Remaining step to actually get KVM: a QCM2290 qhypstub port.** qhypstub
(`github.com/msm8916-mainline/qhypstub`, ~280 lines aarch64 asm) is a minimal
EL2 stub that replaces QHEE and returns the next stage to **EL2** instead of EL1,
leaving EL2 for the kernel's hyp stub → KVM. Officially MSM8916/MSM8939 only;
porting needs: HYP base → `0x45740000` (known); the RPM-reset workaround is
likely N/A here (XBL already brings up RPM); **unknown/empirical:** whether
QCM2290 TZ re-forces EL1 on the state switch (the MSM8916 "stage-2 ping-pong"
workaround) and whether its secondary-core state-switch SMCs
(`0x2000010F`, `0x86004242`) exist — discoverable via the UART+EDL loop, since
all cores re-enter the hyp entry on PSCI `CPU_ON`. Sign with `qtestsign -v6 hyp`,
flash to both slots. **This is unshipped firmware dev with brick/recover cycles,
not a config flag** — approached but not yet done.

**Recovery tooling (`hyp-backup/`):**
- `hyp_a.bin` / `hyp_b.bin` — byte-exact backups of stock hyp (= stock
  `hyp.mbn` zero-padded to 512 KiB; sha256 verified).
- `restore-hyp.sh` — reboots to EDL (`enter-qdl.sh`), unbinds qcserial, flashes
  stock `hyp.mbn` back to both slots via `qdl` + `rawprogram-hyp.xml`.
- `rawprogram-hyp.xml` — minimal firehose XML, correct 1024-sector geometry,
  stock `hyp.mbn`. `rawprogram-hyp-testsigned.xml` — same but the re-signed
  image (what's on the board now). Both dry-run + real-flash verified.
- If the board still boots Linux, skip EDL: just `dd` the backups back over
  `/dev/mmcblk0p9`/`p10` via adb.

**Note:** the board currently runs the qtestsign-re-signed *stock* QHEE (still
EL1, fully functional) — the enabling-test image, not the untouched original.
A full `build-image.sh` + `flash.sh` reflash writes stock `hyp.mbn` back and
reverts this.

**Also out of scope for a kernel rebuild (flagged):** once EL2 is freed, the
now-unused `hyp_mem` 6 MiB carveout and the bogus `GIC_PPI 0` hyp-timer entry in
`agatti.dtsi` could be reclaimed/fixed.

## Demo board state (2026-10-26, Phase 0 of demo integration — see demo/)

- SSH: `demo/bssh` (root@192.168.1.199 wired USB-Ethernet `enx6c1ff7bc45b1`; .209 = wlan0).
- Kernel `7.2.0-rc5-next-20260730-test-tpm-…-dirty` (ashen-drv-tpm build, Oct 7). Cmdline has
  `crashkernel=64M@0x80000000 qcom_scm.download_mode=full crash_memaction=secret`; the latter is
  "Unknown" — this kernel has no CRASH_MEMACTION. `kexec_crash_loaded`=0.
- **KVM works**: `Hyp nVHE mode initialized successfully`, `/dev/kvm` present → kvm-hvc-poc firmware is flashed.
- ashen-tamper bound to `serial0-0` (so no `/dev/ttyHS1`), but **handshake times out every 10 s**;
  `status: connected 0`. No `/dev/tpm*`. MCU flash vector table: SP=0x200c0000, reset=0x08000239.
- arduino-router + arduino-app-cli still enabled. Router's generated drop-in (`10-imola.conf`) drives
  MCU GPIOs on gpiochip1: 37=0 before start (likely BOOT0), 70=1 "ready"; on stop it sets 70=0 and
  pulses 38 (likely MCU NRST) → **stopping the router (e.g. at shutdown) resets the MCU** = TPM loss.
- Display: msm/anx7625 loaded as modules. Tools present: kexec, cryptsetup, podman, arduino-debug (OpenOCD
  over gpiod SWD, tcl port 6666). Not present: tpm2-tools, crun.
- Rootfs 20G (7.1G free), ESP 488M (147M free), RAM 3.6G.

### MCU link: SoC TX does not reach MCU RX (2026-10-26)
- Schematic ABX00162 (p9 + p19): direct 1.8 V link, no level shifter: SoC GPIO_71 (SE2 TX) -> R2504 0R -> PG8
  (LPUART1_RX); PG7 -> R2503 -> GPIO_80; GPIO_6/7 <-> PG6/PG5 (CTS/RTS). GPIO_37/38 = MCU BOOT0/NRST via
  TXS0104 U1101 (also SWD); GPIO_70 = MCU_SPI3_RDY (PG13), not a UART enable.
- Measured: TLMM gpio71 func1/oe=1, pad IN=1 (SoC drives idle-high). MCU PG8 (AF8, no pull) reads 0, follows
  internal pull-up/-down when enabled => floating: open between GPIO_71 and PG8 (R2504?). MCU RX DMA never
  receives a byte; GENI SE2 TX completes normally. MCU->SoC (PG7->GPIO_80) reads high as expected.
- Schematic re-read from rendered drawings (p9 + p19 of ABX00162-schematics.pdf), confirms GPIO_71 -> R2504 -> PG8.
- Wire tests with /dev/mem (TLMM) + gdb (MCU GPIO), both directions, all restored afterwards:
  PG7 -> GPIO_80 OK; GPIO_7 -> PG5 OK (held low); SPI3 -> PG9/PG13 OK.
  GPIO_71 (GPIO mode, driven 0/1) -> PG8 (pull-up and pull-down): no change; no MCU pin on A-I follows.
  PG8 (output 0/1) -> GPIO_71 (input, pull-up): no change.  => no continuity GPIO_71 <-> PG8 as seen from both ends.
- Root cause: R2504 bad (seen under microscope), replaced with a wire link 2026-10-27; link handshakes since.
  Re-test any time with demo/wiretest.py (copy to board, run as root).

### ADSP (remoteproc1) fails with -22 since the QHEE teardown? (2026-10-27, fixed on branch adsp-q6ss)
- `qcom_q6v5_pas ab00000.remoteproc: error -22 initializing firmware qcom/qcm2290/adsp.mbn`: the PAS
  INIT_IMAGE SCM call (`qcom_scm_pas_init_image`) fails; the ELF/mdt header itself is accepted.
- ADSP came up on every captured 7.0 (Arduino tree) boot (May-Jul logs: "adsp is now up"); it fails on
  both linux-next kernels tried (next-20260730, the Oct 7 kernel; next-20260922, the demo kernel), which
  both ran *after* kvm-hvc-poc (patched QHEE tears itself down, Linux at EL2) was flashed on Aug 27.
- Arduino's branches (incl. qcom-v7.2.11-arduino) carry no remoteproc/SCM/SoC driver patches missing from
  next; upstream comment in qcom_scm.c: "For PIL calls the hypervisor creates SHM Bridges for the blob
  buffers on behalf of Linux" -> hypothesis: ADSP PIL needs QHEE services that the teardown removed (the
  modem's PIL still works). Same firmware blob (Debian backports adsp.mbn is byte-identical).
- Test pending: boot slot B (stock QHEE + U-Boot) once. `qbootctl -s b` FAILED ("Failed to set active")
  and the board did not come back from that reboot. Use `fastboot set_active b` (see A/B notes) instead.
- Stock QHEE (hyp_b) strings confirm QHEE implements PIL for HLOS: pil_init_image_api_ns ->
  pil_init_image_to_tz, PILSubsys_memAssign, SHM bridge create/delete around auth, and per-subsystem
  assign handlers only for LPASS (pil_lpass_mem_assign) and video (pil_video_mem_assign) -- exactly the
  two subsystems that fail with -22 (adsp, venus), while the modem (no QHEE handler) boots.
- Upstream supports this case (Linux at EL2, no QHEE/Gunyah): 5c720260e840 "remoteproc: qcom: pas: Enable
  Secure PAS support with IOMMU managed by Linux" + b019925838bc "qcom_scm: Add SHM bridge handling for
  PAS when running without QHEE". Enabled by an `iommus` property on the remoteproc node (see the
  *-el2.dtso overlays). Fix candidate (linux-demo a74da2ae): `&remoteproc_adsp { iommus = <&apps_smmu
  0x1c0 0x0>; }` -- 0x1c0 = base of agatti's LPASS SID block (q6asm 0x1c1, fastrpc CBs 0x1c3+), by
  analogy with lemans/monaco/talos where the PIL SID is the DSP block base.
- With the iommus fix INIT_IMAGE passes; next failure: GET_RSCTABLE unsupported (TZ without QHEE) ->
  linux-demo 4715c21e treats -EOPNOTSUPP as "use the firmware's table". Then auth_and_reset succeeds but
  "start timed out" (-110): smp2p-adsp IRQ count 0, no SMMU global/context faults ever (GFSR 0, CB4 FSR 0,
  SID 0x1c0 -> CB4 with the carveout mapped IOVA=PA), so the Q6 either never runs or stalls before DDR.
- Stock QHEE pil_lpass_mem_assign (0x4574f314): walks the ELF segments and pil_map_memory()s them to
  {VMID 6 ADSP_Q6_ELF, 0x16 LPASS} (RW/RWX; RO segments to 6 only), i.e. QHEE stage-2 + xPU via its "AC"
  layer (/ac/autosmmuconfig, TZ secure channels, "ADSP Table"). Re-doing that from Linux with
  qcom_scm_assign_mem (branch adsp-assign-test, param assign_vmids) succeeds (TZ ret 0) but changes nothing.
  Careful: that param leaked to the modem's recovery once (modem carveout went to VMID 6; reboot hung).
- gcc_lpass_aggre_tbu_clk (QHEE clock table) is already on; qcm2290 has no LPASS TBU GDSC.
- Not needed for the demo: linux-demo 5e1d1502 disables &remoteproc_adsp. Left: RE of QHEE's AC/SMMU
  static config for LPASS SIDs, or TZ's PIL/xPU log.
- Modem DOG crash: unrelated to the ADSP, see the qrtr HELLO race below.
- 2026-10-27, round 2. QHEE's leftover SMMU state, dumped before arm-smmu resets it (branch
  smmu-dump-test): QHEE programs stage-2-only context banks for the subsystems. SID 0x1c0 -> CB61 VMID 6
  (ADSP_Q6), SIDs 0xe5 + 0x8a/0x11 -> CB60 VMID 0x16 (LPASS), others on CB51-58. The VMID 6 stage 2 maps
  70 ranges besides the firmware: Q6/LPASS MMIO (0xab0xxxx...), 0xe000000 (16 MB), SMEM 0x46000000-
  0x4614efff + 0x461cd000-0x461fffff, one non-identity page (IPA 0x1b21000 -> PA 0x1b12000). Tables at
  0x7da08000+, which is plain System RAM to Linux, so QHEE's contexts can't simply be kept.
- Reproduced all three QHEE behaviours (branch adsp-static-map): qcom,iommu-static-map in the ADSP's
  IOMMU domain (/workspace/cache/adsp-s2-ranges.dtsi), qcom,iommu-vmid = <6> on its stage-1 context
  (CBAR.VMID; Linux otherwise leaves 0 on S1 contexts), and the carveout assigned to VMIDs 6+0x16.
  Still "start timed out"; no SMMU global or context faults. So the Q6 never runs, or is blocked
  silently downstream (TZ names an LPASS_Q6_MPU xPU).
- Next: find TZ's diag log (tz.mbn has TZ_DIAG / diag strings; the location isn't a fixed DT address),
  or boot stock slot b once for comparison (needs fastboot from a USB host). Careful: a blind
  /dev/mem read of IMEM candidates (0x0c1x0000 / 0x146x0000) stalled the bus -> watchdog reset.
  Reboot hangs seen around it: see the zeroize payload UART timeout + watchdog backstop (ca0a070).
- 2026-10-27, round 3: SOLVED (by hand). TZ's diag log: shared IMEM 0xc125720 holds its address
  (0xc116000, 0x3000 bytes, tzdbg_t v9, plain text; demo/tzdiag.sh). It logs nothing for the ADSP and
  its XPU/VMIDMT/NOC/SMMU-CB interrupt counters stay 0. After a failed start the carveout equals the
  loaded image and all bss is still zero: the Q6 never ran. Cause: in stock QHEE, pil_auth_reset_api_ns
  calls a per-subsystem bringUp after TZ's auth_reset; LPASS's (hyp.mbn 0x4574f294) clocks and starts
  the Q6 itself: GCC 0x143a00c/0x143a008 (branches, not in gcc-qcm2290), LPASS 0xa78901c/0xa789020,
  0xa783090 |= 0xf000, QDSP6SS (0xa400000) XO/SLEEP/CORE CBCR, 0xa955018/20 |= 4 (poll bit 0),
  EVB 0xa95b000 = 1 / 0xa95b004 = entry >> 4, then CORE_START/BOOT_CMD and BOOT_STATUS (as in
  qcom_q6v5_adsp.c). demo/adsp-qhee-boot.py replays it via /dev/mem while pas waits for the ready IRQ:
  "remote processor adsp is now up", apr_audio_svc/fastrpc/IPCRTR glink channels appear, no faults.
- Kernel version: linux-demo branch `adsp-q6ss` (on ashen-demo): pas maps qcom,iommu-static-map
  (QHEE's stage 2 for SID 0x1c0) and runs QHEE's bringUp after auth_and_reset and its teardown
  (0x45762970: Q6 clocks off, LPASS BCR pulse, AXI halt 0x362000, GCC BCR 0x14c0000) after shutdown;
  regions via reg-names on the ADSP node. Autostart at boot, stop/start cycles and Galene all fine.
  Needed: static map (without it the board resets on start). Not needed: VMID 6 on the S1 context,
  hyp-assigning the carveout. Pitfalls: pas mem_reloc is the *link* address for relocatable images
  (boot address = mem_phys + e_entry - mem_reloc), rproc->bootaddr is 0 for pas; a bad boot address
  resets the board silently ~5 s later. Not in the demo kernel (ADSP stays disabled there).

### fwTPM lost on plain reboots = board power loss via the USB-C dock (2026-10-27)
- MCU RCC_CSR after a plain `systemctl reboot` (flags cleared first): BORRST|PINRST = brown-out.
- PM4125 PON_REASON1 (0x808) = 0x03 = HARD_RESET|SMPL ("sudden momentary power loss") on 3/3 reboots.
- UART: every such reboot runs XBL twice; the first run dies ~0.6 s in (right after "OEM_MISC Image
  Loaded", at the PMIC init) and restarts from power-on. The one reboot with a single XBL run kept the
  TPM ("volume unlocked: existing VM image and TLS key reused").
- Schematic (ABX00162): MCU VDD = PWR_3P3V <- TPS62A02 <- PWR_3P8V <- TPS62A02 <- 5V_SYS, which is
  diode-ORed from 5V_USB_VBUS (USB-C) and 5V_BUCK_OUT (DC_IN 6-24 V via LMR51440). No SoC-controlled enable.
  MCU VBAT = PMIC VCOIN (also on JMISC); nothing on it, so the STM32 backup domain dies too.
- USB-C CC is handled by the ANX7625, powered from SoC PMIC rails (L11A/L15A) + SoC GPIO reset. The SoC
  reset drops those rails -> Rd disappears -> the dock (Type-C sink, default power, no PD contract)
  sees a detach and removes VBUS (tVBUSOFF <= 650 ms) -> everything browns out.
- TZ PSCI has no SYSTEM_RESET2, so no warm-reset workaround. Fix is power: feed 5V_SYS from DC_IN/VIN
  (or the 5V pin) so a VBUS drop no longer matters; or a coin cell/supercap on VCOIN + backup-SRAM seeds.
- On VIN (2026-10-27): plain reboot -> MCU RCC_CSR no flags, volume unlocked with the TPM. PON_REASON1
  still 0x03, so that flag alone does not mean the MCU lost power.
- VIN alone cannot power the dock: 5V_USB_VBUS only feeds 5V_SYS through D2801. Q2801 switches 5V_SYS
  to the PMIC/ANX USB_VBUS_IN, not to the connector. Arduino confirms the port is PD sink only
  (forum.arduino.cc/t/1411831). With the unpowered dock: no typec partner, DP-1 disconnected, no USB.
  The 5V pin is on 5V_USB_VBUS and does back-feed the port, but the ANX7625 is sink-only (Rd), so an
  unpowered dock (also Rd) never attaches: no host role, no PD, no DP alt mode/HDMI.
- Working setup: dock on its PD supply + board on VIN. The dock's VBUS drop at reset is now harmless.

### Demo power and dock: host-only USB brings up Ethernet and HDMI (2026-10-27)
- Power: 9 V -> VIN -> board 5 V regulation -> board 5 V out -> USB-A -> dock's PD power input. The dock
  powers itself; the board's USB-C port only carries data/DP.
- Even with the dock powered, the ANX7625 reads CC1=Rd, CC2=Ra (0x7e:0x46 = 0x21) and no VBUS: no
  attach, no interrupt, and at probe anx7625_typec_register() sets the role switch to device.
- Runtime `echo host > /sys/class/usb_role/4e00000.usb-role-switch/role` enumerated the dock
  (Genesys hub, AX88179B, card reader) and br0 got its lease.
- Persisted in the DTB (linux-demo 7deec2ec): overlay sets dwc3 dr_mode = "host", and build.sh runs
  `fdtput -d` on usb-role-switch. Overlays can't delete properties, and without that deletion
  anx7625 would defer forever waiting for a role switch that host-only dwc3 never registers. After a
  reboot: USB 3 hub + AX88179B on the SS bus, DP-1 connected at 1280x720, console on HDMI. Device
  mode (gadget/adb over USB-C) is gone with this DTB.
- VM DHCP: the office server sometimes answers once and then ignores the client. The guest now runs
  `udhcpc -b -t 3 -T 2 -A 3`: Galene starts without a lease, udhcpc keeps retrying every few seconds
  and then renews. The hook announces a late lease through /dev/console, which the host forwarder
  strips of libkrun's `[.. ERROR init_or_kernel]` prefix.
  Tested with the dock uplink down for 30 s: lease 3 s after the link came back.
- ashen-demo now re-extracts the staged guest tarball over the volume's rootfs when the tarball is
  newer (stamp rootfs/.image). Before, guest updates only landed after a re-provision.
- Static DHCP mappings (office router): br0 6c:1f:f7:bc:45:b1 -> .17, wlan0 14:b5:cd:ea:b6:db -> .18,
  Galene VM 02:a5:4e:00:00:01 (krunwipe default) -> .21. The tap and the Wi-Fi scan MACs are random
  per start but never request a lease.
- libkrun pitfall: taking the VM's tap down wedges virtio-net (guest "TX timeout" every 5 s, no
  recovery after the tap is back up). Don't use that as a test.
- build-guest.sh is currently blocked: the galene outputs are gone from the buildns store, and
  rebuilding Go fails with "home directory '/homeless-shelter' exists". The tarball in cache/out was
  repacked by hand with the new init/udhcpc.script (prev in galene-rootfs.tar.gz.prev).

### Modem "DOG detects stalled initialization" ~40 s after boot = qrtr HELLO race (2026-10-27, fixed)
- Modem announces svc 43/66, then never queries the PD mapper (svc 64): it never learned it exists.
- ns.c announce_servers() on the modem's HELLO: first send -EAGAIN (qrtr_node_enqueue drops everything
  while !hello_sent; our HELLO is sent from a work item since next's 544d85de) -> returns, rest unsent.
- linux-demo 45ba3c7f: flush the pending say_hello work before a non-HELLO send. 4/4 boots clean
  (was ~10 of 12 crashing). Upstream candidate (Fixes: 544d85de).

### Reproducible demo image (2026-10-27)
- demo/image/build-image.sh: inputs from source -> Arduino boot-binaries zip (hash-pinned) + kvm-hvc-poc
  hyp/boot (slot a only) -> mmdebstrap trixie from snapshot.debian.org 20261026T000000Z on an arm64
  builder (this VM has no binfmt_misc; default builder = the board, /home/arduino, ~4 min) ->
  rootless mke2fs -d tarball / mkfs.vfat+mtools -> qdl flash dir with rawprogram0.xml rewritten.
- Two builds from the same inputs: bit-identical esp/rootfs/userdata images and package manifest.
- Arduino bits taken: arduino-unoq-radio-firmware 0.7.0-1 (Wi-Fi BDF override, initramfs hook; pinned
  by SHA-512 from apt-repo.arduino.cc) and /opt/openocd from arduino-deb-images e7713f1.
- Not yet boot-tested from eMMC: needs EDL + qdl from a USB host. After flashing, the MCU must be
  erased once (new host Noise key).
- Wipe payload is now position-independent; crashkernel=64M unpinned. With physical KASLR the EFI
  stub put the kernel at 0x80f50000, inside the old fixed 0x80000000 window, in 1 of 3 tampers.
