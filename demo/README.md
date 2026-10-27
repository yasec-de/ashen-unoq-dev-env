# Ashen demo on the Arduino UNO Q

Galene runs in a krun microVM with tagged memory, on a LUKS volume sealed by the MCU's firmware TPM.
The tamper button (D10/PB9) wipes everything, and the board comes back with new keys. How it works:
[ARCHITECTURE.md](ARCHITECTURE.md). Change log: [WORKLOG.md](WORKLOG.md).

## Setup

- **Power:** 9 V → VIN. The board's 5 V out → USB-A → the dock's PD power input. The board must
  not be powered through USB-C (see Limitations).
- **Dock:** USB-C hub with AX88179B GbE and HDMI, on the board's USB-C port. The HDMI monitor shows
  the kernel console.
- **Network:** the dock's Ethernet goes to the demo switch. Static DHCP mappings:

  | Who | MAC | Address |
  |---|---|---|
  | Board, wired (`br0`) | `6c:1f:f7:bc:45:b1` | 192.168.1.17 |
  | Board, Wi-Fi | `14:b5:cd:ea:b6:db` | 192.168.1.18 |
  | Galene VM | `02:a5:4e:00:00:01` | 192.168.1.21 → `https://192.168.1.21:8443/` |

- **Tamper button:** D10 to GND, external pull-up.

## Tools (run from this directory)

| Script | Does |
|---|---|
| `bssh` | SSH to the board (wired, Wi-Fi fallback) |
| `kernel/build.sh`, `kernel/deploy.sh [--reboot]` | Build the demo kernel and DTB, install them as default boot entry |
| `vm/build-guest.sh`, `vm/build-krun.sh` | Galene guest rootfs tarball; libkrun + launcher |
| `build-payload.sh`, `fw-build.sh`, `mcu-flash.sh` | Wipe payload; MCU firmware |
| `install-rootfs.sh` | Install units, scripts, guest tarball, payload and krun on the board |
| `image/build-image.sh` | Full reproducible board image (see image/README.md) |
| `cycle-test.sh reboot\|tamper` | One reboot/tamper cycle with timings and TLS fingerprints |
| `grab-frame.sh`, `uart-log.py`, `board-reset.sh` | HDMI capture, UART log, hard reset |

## Limitations

- **A full power cycle is a tamper.** The fwTPM's seeds live only in MCU RAM. Losing power
  (rewiring, pulling the plug) destroys them like the button does: the next boot re-provisions,
  and Galene gets a new TLS key. Plain reboots keep the TPM because VIN keeps the MCU powered.
- **USB-C power.** The port can only sink power and cannot supply VBUS. Powered through USB-C,
  every SoC reset makes the source drop VBUS (the CC controller resets with the SoC), so the MCU
  browns out and the TPM is lost. Use VIN.
- **USB-C is host-only.** The self-powered dock never attaches as a Type-C partner, so the DTB runs
  dwc3 host-only (`dr_mode = "host"`, `usb-role-switch` removed). USB device mode (gadget, adb over
  USB-C) is unavailable. HDMI comes up at 1280x720.
- **No audio.** The ADSP doesn't start under the patched hypervisor, so it, GPU, venus and audio are
  disabled.
- **`/dev/tpmrm0` can't be used.** The fwTPM can't swap object contexts, so everything uses
  `/dev/tpm0`, one client at a time.
- **No kexec for normal reboots.** It only works as the crash path into the wipe payload.
- **Don't take the VM's tap down.** libkrun's virtio-net stops for good, even after the tap is back up.
  Restart `ashen-galene-vm` instead.
- **Office DHCP is flaky.** The server sometimes ignores a client for a while. The guest retries in
  the background, and Galene announces its address on the console once it has a lease.
