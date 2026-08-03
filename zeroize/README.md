# Fast tamper-response zeroization

Two-tier secret erase for the UNO Q HSM (QCM2290, 4× Cortex-A53):

1. **In-kernel crash-path zeroize** (patches in `linux/`): on `panic()`, after the
   other CPUs are stopped, wipe the crown jewels first — keyring (`user`/`logon`
   payloads), `memfd_secret` pages, and the QCE crypto-engine key registers —
   before kexec hands off. Lock-free, no timeouts (single CPU, just memory
   writes). Gated by `crash_zeroize.armed` (off by default).
2. **Capture-kernel wipe payload** (this directory): a freestanding aarch64 image
   loaded as the kdump capture image. It parses the DTB, identity-maps RAM
   (wipe-set = Normal **Non-Cacheable** so zeros land in DRAM immediately;
   no-map secure carveouts left unmapped), wipes all RAM single-core (~0.85 s,
   petting the apss watchdog), prints timing over the GENI UART, then
   `PSCI SYSTEM_OFF`. (SMP was tried but the secondary A53s don't come up under
   PSCI on this board in the kdump context — 1/3 at best — so it's single-core.)

The capture payload is the authoritative backstop: it erases all RAM regardless,
so the in-kernel pass only needs to be fast, not perfect.

## Files

| File | Purpose |
|------|---------|
| `start.S` | arm64 Image header, EL2→EL1, MMU enable, fault-skip vectors |
| `payload.c` | DTB parse, page tables, NC wipe, watchdog pet, polled UART, timing |
| `payload.ld`, `Makefile` | link at `PAYLOAD_BASE`, emit raw `Image` |
| `service/zeroize-stage.{sh,service}` | stage payload via `kexec -p` at boot; warn on plaintext swap/hibernate |
| `test/secret-selftest.c` | on-device, non-destructive check of the in-kernel zeroize |

Kernel side lives in `linux/` (vendored): `mm/secretmem.c`, `security/keys/key.c`,
`drivers/crypto/qce/core.c`, `kernel/crash_zeroize.c`,
`arch/arm64/kernel/machine_kexec.c`. Enabled by `qcom-deb-images/kernel-configs/zeroize.config`.

## Build

```sh
# kernel: normal flow (build-kernel.sh / build-image.sh) picks up zeroize.config
# payload:
nix develop .. --command make            # -> zeroize/Image (raw arm64 Image)
```

`PAYLOAD_BASE` (default `0x80000000`) **must** equal the pinned crashkernel base.
The cmdline (`qcom-deb-images/.../qualcomm-linux-debian-image.yaml`) sets
`crashkernel=64M@0x80000000`. If you move it: `make PAYLOAD_BASE=0x...` and update
the cmdline together.

## Deploy (debos / rootfs)

The rootfs needs: `kexec-tools` installed; `zeroize/Image` +
`service/zeroize-stage.sh` at `/usr/lib/zeroize/`; `zeroize-stage.service`
enabled. The HSM arms protection at runtime once secrets are loaded:

```sh
echo 1 > /sys/module/crash_zeroize/parameters/armed
```

Tamper trigger (root-only, bypasses the sysrq mask): `echo c > /proc/sysrq-trigger`
(or an in-kernel tamper source calls `panic()`).

## Verify (staged — on-device steps are destructive; confirm each)

1. **Non-destructive:** boot patched kernel; `cat /proc/iomem | grep -i crash`
   shows the reservation at the pinned base; `kexec -p -s zeroize/Image` loads
   clean; `nproc` == 4.
2. **In-kernel zeroize (no panic):** build & run `test/secret-selftest.c` as root
   → expect `RESULT: PASS` (keyring + memfd_secret zeroed).
3. **Capture jump:** `echo 1 > .../armed; echo c > /proc/sysrq-trigger` →
   payload prints over `ttyMSM0` and powers off.
4. **Full wipe + timing:** confirm no fault on secure carveouts (`skipped=` count),
   read the `done in N us` line, verify clean reboot and prior RAM gone.

## Confirmed on hardware

- `kexec -p -s` accepts the raw Image; it's placed at the crash base `0x80000000`
  (2 MB-aligned, bottom-up) and entered there with `x0` = DTB, MMU off.
- Entry EL: kernel hands off at EL2 (nVHE) via `HVC_SOFT_RESTART`; `start.S`
  drops to EL1. Both paths exercised.
- Full single-core wipe runs in ~0.85 s with `skipped=` 2–3 faults (secure
  carveouts, cleanly skipped) and a controlled `PSCI SYSTEM_OFF`.
- **DTB parse must use byte loads** (`be32` is `ldrb`-based): the parse runs
  MMU-off where memory is Device-nGnRnE, so a merged unaligned `ldr` on the
  4-byte-aligned property data alignment-faults and the fault-skip vector
  silently returns stale data. This was the original "resets through XBL" bug.

## Known open items

- crashkernel base `0x80000000` is free RAM (`/proc/iomem`); adjust base + rebuild
  payload if not.
- Secondary A53s don't start under PSCI in the kdump context on this board
  (1/3 at best), so the wipe is single-core; revisit if a board brings them up.
- 2 MB-rounded no-map exclusion leaves ≤2 MB slack per carveout edge (firmware
  regions, unlikely to hold HSM secrets); tighten to 4 KB pages only if needed.
