# Ashen demo — architecture

Status (2026-10-27): all parts run on the board; `image/build-image.sh` builds a reproducible eMMC image.

## What the demo shows

An Arduino UNO Q runs Galene (video conference server) inside a krun microVM. Two laptops on a wired
switch hold a call. Pressing the tamper button destroys the VM's memory and the TPM's keys, and the board
resets. It comes back up, finds itself uninitialized, provisions again and serves Galene with **new**
TLS keys. The monitor shows the kernel console throughout.

## Hardware

| Part | Role |
|---|---|
| QRB2210 (4× A53, Debian 13) | Linux host, KVM via patched QHEE + EL2 U-Boot (`kvm-hvc-poc/`); ADSP, GPU, venus, audio off |
| STM32U585 MCU (`ashen-fw/`) | Tamper monitor + firmware TPM 2.0; 4 Mbaud LPUART1 (PG7/PG8) to SoC SE2 (GPIO_71/80) |
| Button on D10 = PB9 | Tamper sensor, external pull-up; pressed = low |
| USB Ethernet + switch | Demo network, one laptop provides DHCP/internet |
| Monitor (USB-C DP via anx7625) | Kernel console (`console=tty0`) |
| Power: 9 V → VIN; board 5 V out → USB-A → dock PD input | VIN keeps the MCU (and its TPM) up across SoC resets; the USB-C port cannot source VBUS |
| USB-C dock (hub, AX88179B GbE, HDMI) | dwc3 forced host-only in the DTB: the self-powered dock never attaches as a Type-C partner |

## Components

- **ashen-tamper** (kernel, `drivers/misc/ashen-tamper/`): serdev driver for the MCU link. Noise XX
  session, Echo heartbeat (50 ms) with 100 ms timeout → `panic()`; a `Tamper` message panics at once. Exposes the MCU TPM via
  **tpm_ashen** as `/dev/tpmrm0`.
- **crash memaction** (kernel): `MADV_CRASH_SECRET` tags memory; kernel passes a page bitmap to
  the crash kernel as an ELF note `MEMACTION`.
- **zeroize payload** (`zeroize/`, repo `ashen-kexec-zeroizer`): the kdump "crash kernel". Wipes tagged pages, then all RAM,
  resets; solid red on the display meanwhile.
- **ashen-fw**: Noise responder, TOFU pairing, volatile fwTPM (seeds in masked RAM). On tamper:
  wipe SRAM, go silent, self-reset (PB9, done).
- **libkrun + krunwipe**: run the Galene VM (guest kernel = the host's demo Image); libkrun tags all guest
  RAM with `MADV_CRASH_SECRET`.
- **systemd units** (`demo/rootfs/`): `zeroize-stage` (stage payload) → `ashen-pair` (host key, TOFU
  pairing, TPM, arm heartbeat) → `ashen-demo` (unlock or provision the LUKS volume) → `ashen-galene-vm`.
  Every step is narrated on the console via `/dev/kmsg` (KERN_NOTICE, console loglevel 6).
- **Network**: USB Ethernet is enslaved to bridge `br0`, which holds the board's DHCP lease. The VM's tap is
  a private /30 (host 10.21.0.1, guest 10.21.0.2, static); nftables DNATs the board's :8443 to Galene and
  masquerades the guest. WebRTC media goes through coturn on the board (`ashen-turn`, :3478, per-boot
  shared secret handed to Galene as `ice-servers.json`); its relay sockets live on the board's LAN address.

## Alarm sequence

1. Button → MCU sends a `Tamper` message (between frames, ≤5 ms), wipes all SRAM (TPM seeds/NV, keys)
   and resets itself.
2. Linux panics on that message at once (`panic("TAMPER ALARM: …")`; fallback: heartbeat lost, ≤100 ms)
   → straight into kexec. There's no
   `crash_kexec_post_notifiers` because panic notifiers can hang on this SoC; the payload draws the red screen.
3. kexec into the wipe payload: halt and reset the USB controller (its DMA into wiped rings otherwise
   wedges the bus and the board ends in a watchdog reset that leaves HDMI dead), wipe tagged pages (VM RAM, disk keys), switch the display to a
   fetch-free solid red (only if a display was lit when the payload was staged), wipe the rest of RAM,
   PSCI reset. Measured: kernel running again ~4 s after the panic; Galene back with a new TLS key ~70 s.

## Boot sequence

1. Kernel boots, ashen-tamper connects to MCU; host Noise key from `/var/lib/ashen/host.key`.
2. Unkeyed MCU (after tamper) → pair (trust on first use) → TPM appears.
3. Try TPM unseal of the LUKS volume. Success → reuse. Failure → **uninitialized**: new LUKS volume
   sealed to the new TPM, unpack VM image, VM generates new TLS key.
4. Start Galene VM (tagged memory), print TLS fingerprint on console.

## TPM access

The fwTPM keeps object contexts as handle references (upstream wolfTPM design), so the kernel resource
manager `/dev/tpmrm0` cannot swap objects out. Everything uses `/dev/tpm0` directly, one client at a time:
`systemd-cryptenroll --tpm2-device=/dev/tpm0 --tpm2-pcrs=` to seal, and `systemd-cryptsetup attach … 
tpm2-device=/dev/tpm0` with `SYSTEMD_CRYPTSETUP_USE_TOKEN_MODULE=0` to unseal (libcryptsetup's token plugin
always picks tpmrm0). No PCR binding: the secret is bound to the TPM's seeds, which tamper destroys.

## Trust and keys

| Secret | Lives in | Destroyed by |
|---|---|---|
| TPM seeds / NV | MCU masked RAM | MCU tamper wipe / reset |
| LUKS volume key | Kernel (dm-crypt, secret pool, tagged) | Payload tagged-page wipe |
| TLS private key | VM RAM (tagged) + encrypted volume | Payload wipe + TPM seed loss |
| Host Noise key | Plain rootfs | Not secret for the demo; re-paired by TOFU |
