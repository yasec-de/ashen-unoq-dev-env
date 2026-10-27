# Ashen demo work log

One line per change to code or target, ≤120 chars, timestamp first.

2026-10-26T11:40 ws: created demo/ and cache/ (cache/ added to .gitignore)
2026-10-26T11:41 ws: added demo/bssh ssh helper (wired .199 default, BOARD=… override)
2026-10-26T11:50 ws: NOTES.md: appended Phase 0 demo board-state findings
2026-10-26T12:05 ws: installed nix-portable 2.20.6 in cache/bin (store in cache/nix-portable), user-approved
2026-10-26T12:05 ws: added demo/nix wrapper (nix-portable, flakes enabled)
2026-10-26T12:20 ws: demo/nix: use-sqlite-wal=false (virtiofs SQLite WAL disk I/O error)
2026-10-26T13:10 linux: branch ashen-demo-base = ashen-drv-tpm + uncommitted TPM work (user tree untouched)
2026-10-26T13:12 linux: worktree /workspace/linux-demo, branch ashen-demo off crash-memaction-upstream-20260921
2026-10-26T13:14 linux-demo: 71643aac import ashen-tamper+tpm_ashen squashed; recreated ashen-tamper .dtso
2026-10-26T13:25 linux-demo: d157dcea arm hb deadline on arm; fw log lines at NOTICE; overlay no-autostart
2026-10-26T13:30 demo/kernel: ashen-demo.config fragment, build.sh (nix devshell, O=cache/kbuild)
2026-10-26T13:50 ws: demo/nix: limit substitution parallelism (4096 fd limit), TMPDIR=cache/tmp
2026-10-26T14:20 ws: demo/nix: XDG_CACHE_HOME=/dev/shm (fetcher-cache SQLite I/O error on virtiofs)
2026-10-26T15:30 ws: STOP using nix store on virtiofs (exhausted host virtiofsd fds; cache/nix-portable abandoned)
2026-10-26T15:35 ws: demo/buildns: user+mount ns with private exec tmpfs (24G) at /dev/shm/ns for builds
2026-10-26T15:36 ws: demo/nix: store/tmp/xdg in buildns tmpfs, re-exec inside ns
2026-10-26T15:50 demo/kernel/build.sh: build from git archive in buildns tmpfs, export artifacts to cache/out
2026-10-26T16:10 ws: demo/nix: sandbox=false (nix build sandbox can't start inside buildns)
2026-10-26T16:20 zeroize/payload.c: parse elfcorehdr MEMACTION note, wipe tagged pages first, PSCI SYSTEM_RESET
2026-10-26T16:30 ashen-fw: panic_link flush_wipe_and(Fault|Reset); fix wipe storing SHCSR value instead of 0
2026-10-26T16:35 ashen-fw: tamper.rs + main.rs: PB9 (D10) EXTI low>500us -> log TAMPER, wipe SRAM, reset
2026-10-26T16:50 ws: demo/buildns run: nested userns as uid 1000 (tar chown failures as ns-root)
2026-10-26T17:05 demo/rootfs: common.sh (say/wait_for), ashen-pair + ashen-pair.service
2026-10-26T17:20 demo/kernel/deploy.sh: ssh install + BLS default, demo cmdline (tty0, no download_mode)
2026-10-26T17:40 linux-demo: fixup! space-indented CRASH_MEMACTION_DEBUGFS help broke Kconfig parse
2026-10-26T18:10 ws: demo/nix: remove stale /homeless-shelter before each run (sandbox=false side effect)
2026-10-26T18:40 ashen-fw: tamper build OK (TamperPeripherals split); demo/fw-build.sh exports ELF
2026-10-26T18:50 board: disable --now arduino-router{,-serial.path,-serial}, arduino-app-cli, arduino-burn-bootloader
2026-10-26T19:00 board: flashed ashen-fw (tamper build) to MCU via /opt/openocd program+verify+reset
2026-10-26T19:40 demo/vm/build-krun.sh: cross-build libkrun+krunwipe in buildns (libkrun flake)
2026-10-26T19:55 demo/vm: guest/init (TLS keygen on volume, fingerprint), groups/ashen.json, build-guest.sh
2026-10-26T20:20 demo/kernel: DTB = prebuilt base+video_sound (dtb/) + our dtbo via fdtoverlay; dtc in shell
2026-10-26T20:45 demo/build-payload.sh: payload Image 8873 B, _end 0x80012000 (fits crashkernel)
2026-10-26T20:50 board: diag only: MCU LPUART1 RX (PG8) idles LOW, no RX DMA bytes; QRB SE2 TX completes (GENI regs)
2026-10-26T21:00 board: !! deploy.sh 'tar -C / -x' of modules.tar.gz replaced /lib symlink with a dir -> no ld.so
2026-10-26T21:00 board: !! all exec broken (ssh/depmod fail). Needs manual fix: restore /lib -> usr/lib (see report)
2026-10-26T21:05 demo/kernel/deploy.sh: extract modules under /usr with --keep-directory-symlink
2026-10-26T21:40 board: user restored /lib symlink via initramfs; wired adapter detached, using wlan .209
2026-10-26T21:41 demo/bssh: fall back to Wi-Fi when wired is unreachable
2026-10-26T22:10 board: installed 7.3.0-rc4-next-20260922-ashen-demo (BLS default, demo cmdline), NOT rebooted
2026-10-26T22:10 demo/kernel/deploy.sh: printf %q remote args (ssh word-split dropped cmdline options)
2026-10-26T22:30 demo/kernel/deploy.sh: skip ESP space check on reinstall; board entry options fixed
2026-10-26T22:35 NOTES.md: MCU link hardware finding (GPIO_71 -> PG8 open)
2026-10-26T22:35 board: gdb probe toggled MCU PG8 pull-up/down briefly, restored to none
2026-10-26T23:30 board: diag: TLMM gpio71/gpio126 temporarily GPIO-mode via /dev/mem (restored 0x204/0x3, 0x801/0x1)
2026-10-26T23:30 board: diag: MCU GPIO A-I MODER/PUPDR temporarily input+pull via gdb (restored, verified)
2026-10-27T13:40 demo/wiretest.py: board-side SoC<->MCU UART wire test (TLMM + OpenOCD tcl, restores)
2026-10-27T13:40 demo/mcu-gdb-forward.sh: SSH equivalent of ashen-fw/run-openocd.sh (gdb on :3333)
2026-10-27T13:55 demo/wirehold.py: hold GPIO_71/PG8 net at a level for probing (copied to board /var/tmp)
2026-10-27T13:40 board: user replaced R2504 (dodgy) with wire link; Ethernet back (.199)
2026-10-27T13:41 board: wiretest all pass; ashen-tamper handshake completes; MCU keyed to another host key
2026-10-27T14:00 demo/rootfs: ashen-pair arms only if ASHEN_ARM=1 and kexec_crash_loaded; /etc/default/ashen
2026-10-27T14:01 demo/install-rootfs.sh; board: installed demo/rootfs (ashen-pair, common.sh, unit, default=no-arm)
2026-10-27T14:15 board: MCU erased (action=erase; first attempt lost, second ok), keystore empty
2026-10-27T14:40 ashen-fw: IrqSafeAllocator (critical_section around emballoc) fixes IRQ-vs-thread heap deadlock
2026-10-27T14:42 board: flashed ashen-fw (IrqSafeAllocator); demo/mcu-flash.sh, demo/mcu-state.py
2026-10-27T14:50 demo/rootfs: ashen-mcu-lines.service holds GPIO_37 (MCU BOOT0) low; enabled on board
2026-10-27T15:20 wolftpm: branch ashen-upstream = upstream master 3737723c + local 6dffba84, 059234b3 (ported)
2026-10-27T15:21 wolftpm: port: Clear staged SPS via FwSetHierarchySeed, EPS proof v1, Startup ctx-key rotation
2026-10-27T15:22 wolftpm: upstream already fixes TOTAL_COMMANDS vs CAP_COMMANDS (vendor CC); 14d942e kept as branch
2026-10-27T15:25 board: flashed ashen-fw (wolftpm upstream); /dev/tpmrm0 up; installed tpm2-tools (apt)
2026-10-27T15:26 demo/rootfs: ashen-pair re-probes TPM aux device if unbound
2026-10-27T16:10 wolftpm: ca9abf79 release CreatePrimary seed before ticket (masked port); 01bf7ce9 ticket rc
2026-10-27T16:30 ashen-fw: UART_BUF_LEN 256 -> 4096 (RX ring overran on multi-fragment TPM commands)
2026-10-27T16:32 board: flashed ashen-fw (ring 4096); session ContextLoad (780 B, 2 fragments) works
2026-10-27T17:20 wolftpm: 59aa7194: sessions-tagged cmds w/o auth handles get session rsp; StartAuthSession ENC|DEC
2026-10-27T17:25 board: flashed ashen-fw; systemd-cryptenroll --tpm2-device=/dev/tpm0 works; unlock via built-in path
2026-10-27T17:26 board: TPM unlock needs SYSTEMD_CRYPTSETUP_USE_TOKEN_MODULE=0 (token plugin always uses tpmrm0)
2026-10-27T18:00 ashen-fw: committed 6a01880 (leftover refused flag), e23042a, 0be4ef9, 292f453, 3e91409
2026-10-27T18:05 linux-demo: overlay gpio-hog GPIO_37 (MCU BOOT0) low; demo/rootfs: dropped ashen-mcu-lines.service
2026-10-27T18:20 board: zeroize payload staged (install-rootfs.sh); sysrq crash -> reset -> kernel up in ~4 s
2026-10-27T18:30 board: installed libkrun.so.2 + krunwipe in /usr/local/lib/ashen
2026-10-27T19:00 board: NM bridge ashen-br0 (br0, MAC of enx6c1ff7bc45b1) + port; Wired connection 1 autoconnect=no
2026-10-27T19:30 demo/rootfs: ashen-demo (unlock-or-provision), ashen-galene-vm (+units), krunwipe --tap
2026-10-27T19:35 demo/nix: HOME=/dev/shm/ns/home (devshells polluted /homeless-shelter)
2026-10-27T19:50 board: apt install tcpdump
2026-10-27T20:20 board: deployed kernel 65eabab6 (BOOT0 hog DTB), not rebooted; removed ashen-mcu-lines.service
2026-10-27T20:21 board: installed+enabled zeroize-stage, ashen-pair, ashen-demo, ashen-galene-vm; galene image
2026-10-27T20:50 demo/vm: guest /etc/ssl/openssl.cnf + OPENSSL_CONF (static openssl looked in nix store)
2026-10-27T20:51 demo/kernel/deploy.sh: printk.devkmsg=on (kmsg narration was ratelimited); board: sysctl set
2026-10-27T21:00 board: deleted volume.img to re-run provisioning
2026-10-27T21:15 linux-demo: ashen-tamper byte trace behind module param trace (default off); rebuilding
2026-10-27T21:20 libkrun: committed krunwipe --tap (no Signed-off-by: DCO sign-off left to the author)
2026-10-27T21:40 board: deployed kernel 0a07ac66 (trace off); guest image w/o TURN; ASHEN_ARM=1; volume deleted
2026-10-27T21:50 board: first-boot reboot test
2026-10-27T22:10 linux-demo: cherry-picked 34a7417e (pmdomain devlink UAF fix, lost in squash); rebuilding
2026-10-27T22:12 demo/rootfs: ashen-pair After/Wants zeroize-stage; waits /dev/tpm0; zeroize unit 0644
2026-10-27T22:30 board: armed chain OK (pair->arm->provision->VM->Galene in 7 s), fingerprint 5F:9E...
2026-10-27T22:45 board: simulated D10 press (press-button.py): MCU wipe -> panic -> wipe -> reboot -> reprovision
2026-10-27T22:46 board: alarm cycle: ssh +62 s, Galene +68 s with new TLS fingerprint 7F:C5...
2026-10-27T23:00 linux-demo: overlay disables &gpu (a702 init -EINVAL errors on console)
2026-10-27T23:40 linux-demo: d7d9229e drm/msm/dpu drm_panic support; a39af0f7 panic string 'TAMPER ALARM...'
2026-10-27T23:45 zeroize: payload solid-red DPU border (LM0/CTL0) when bootargs ashen_display=1
2026-10-27T23:46 zeroize/service: stage with --append ashen_display=N; udev rule re-stages on DRM hotplug
2026-10-27T23:47 demo/kernel/deploy.sh: + crash_kexec_post_notifiers (drm_panic runs before crash kexec)
2026-10-28T00:00 demo/kernel/build.sh: incremental source update via read-tree with private index
2026-10-28T00:10 demo/kernel/deploy.sh: dropped crash_kexec_post_notifiers again (notifiers can hang for s)
2026-10-28T00:11 zeroize: solid red is the payload's first action (no drm_panic dependency)
2026-10-28T00:15 demo/kernel/build.sh: incremental source update via read-tree with private index
2026-10-28T01:00 board: deployed kernel a39af0f7 (gpu off, msm panic, no post_notifiers), payload red-first, rules+guest
2026-10-28T01:40 linux-demo: reverted GPU-disable and pmdomain cherry-pick (suspected boot hang); rebuilding
2026-10-28T02:00 board: user power-cycled; same demo kernel booted fine (Galene at 23.7 s): pmdomain theory wrong
2026-10-28T02:01 linux-demo: dropped the two reverts; 'disarm heartbeat on shutdown' (.shutdown hook); rebuilding
2026-10-28T02:02 zeroize: payload checks dispcc GDSC + MDP/AHB clocks before touching display (no bus stall)
2026-10-28T02:20 board: default target multi-user, lightdm disabled+stopped (greeter hid the console)
2026-10-28T02:40 board: deployed kernel 3e753305 (shutdown disarm), fbcon TER16x32, payload with dispcc check
2026-10-28T03:00 board: !! hung again on reboot: old kernel (no shutdown hook) + old payload still staged
2026-10-28T03:00 board: needs power cycle; next boot = 3e753305 + dispcc-checking payload
2026-10-28T03:30 board: plain reboot OK (shutdown disarm works), volume+TLS key reused; VM hung at boot on DHCP
2026-10-28T03:31 demo: guest MTU 1500 + bounded visible DHCP retries; launcher waits for br0 lease; narration filter
2026-10-28T03:45 board: installed rootfs; copied new guest /init onto current volume
2026-10-28T04:00 demo/rootfs: ashen-demo retries unlock 3x before provisioning (transient errors)
2026-10-28T04:40 demo/kernel: CONFIG_FONTS=y (TER16x32 silently not built before)
2026-10-28T04:50 board: deployed kernel with TER16x32 font
2026-10-28T05:10 linux-demo: overlay disables ADSP + LPASS audio nodes (deferred-probe noise on console)
2026-10-28T05:11 board: disabled docker/containerd, samba (4), ModemManager, bluetooth/blueman
2026-10-28T05:12 demo/kernel/deploy.sh: systemd.show_status=error (only failures on console)
2026-10-28T05:20 demo/bssh: ssh keepalives (session to a crashing board hung the tests)
2026-10-28T05:40 linux-demo: overlay re-enables ADSP (modem crashed without it), disables venus + PMIC codec
2026-10-28T05:41 demo/rootfs: journald Storage=volatile
2026-10-28T06:00 board: bisect modem crash: re-enabled ModemManager, bluetooth, blueman
2026-10-28T06:10 board: modem crash bisected to disabled ModemManager/bluetooth/blueman; re-enabled, 0 crashes
2026-10-28T06:40 board: apt-get update
2026-10-28T06:45 board: TEST: backports firmware-qcom-dsp adsp* -> /lib/firmware/updates/qcom/qcm2290 (revertable)
2026-10-28T06:50 board: reverted firmware test (identical md5), removed /lib/firmware/updates/qcom
2026-10-28T07:10 board: TEST boot of Oct 7 kernel (next-20260730) for ADSP; ASHEN_ARM=0, loader.conf saved
2026-10-28T07:20 board: Oct 7 kernel also fails ADSP (-22); restored demo default + ASHEN_ARM=1, rebooted
2026-10-28T07:40 demo/kernel/build.sh: KTEST=name test builds (own kernelrelease + export dir)
2026-10-28T08:10 board: TEST qbootctl -s b (stock QHEE+U-Boot) to check ADSP without the QHEE teardown
2026-10-28T08:40 board: !! after failed 'qbootctl -s b' + reboot: no ssh >20 min, HDMI black; needs power cycle
2026-10-28T08:45 NOTES.md: ADSP investigation status
2026-10-28T09:30 linux-demo: overlay: ADSP iommus <&apps_smmu 0x1c0 0> (EL2 PAS path); building
2026-10-28T09:40 demo/test-kexec.sh: one-shot kexec test boots (no ESP changes)
2026-10-28T09:50 NOTES.md: ADSP root-cause evidence (QHEE PIL handlers) + fix candidate
2026-10-28T10:10 demo/test-kexec.sh: kexec -c (kexec_file_load ignored --dtb; first ADSP test invalid)
2026-10-28T10:20 board: kexec from EL2/nVHE ends in a full firmware reboot (user observed) -> both kexec tests invalid
2026-10-28T10:21 demo: removed test-kexec.sh; deploying ADSP-iommus DTB as regular entry
2026-10-28T10:40 board: deployed ADSP-iommus DTB (834483c0) as default entry; rebooting
2026-10-28T11:00 linux-demo: PAS tolerates TZ without GET_RSCTABLE (ADSP now -EIO there); building
2026-10-28T11:20 board: deployed 4715c21e (GET_RSCTABLE fallback), rebooting
2026-10-28T11:50 demo: uart-log.py (TCP 8811), board-reset.sh (TCP 8812 gpio)
2026-10-28T11:55 board: reset via glasgow (hung after 4715c21e deploy)
2026-10-27T01:20 demo/kernel/deploy.sh: K env selects the build dir (for KTEST builds)
2026-10-27T01:20 board: deployed KTEST=assign kernel (PAS carveout hyp-assign test) as default
2026-10-27T01:20 demo/kernel/deploy.sh: ESP free-space floor 90M->70M (a demo kernel install is 61M)
2026-10-27T01:21 board: deployed KTEST=assign kernel (PAS carveout hyp-assign test) as default
2026-10-27T01:23 board: reboot to undo hyp-assign of modem carveout to VMID 6 (test param leaked to modem)
2026-10-27T01:29 board: hard reset via Glasgow A5 (reboot hung after modem-carveout assign test)
2026-10-27T01:31 kernel: ADSP disabled in overlay (5e1d1502); deployed demo kernel as default, rebooting
2026-10-27T01:38 board: hard reset via Glasgow (reboot hung during modem crash recovery)
2026-10-27T01:53 board: hard reset via Glasgow (systemctl reboot hung again after modem crash)
2026-10-27T01:57 NOTES/ARCHITECTURE: ADSP closed (disabled), QHEE pil_lpass_mem_assign RE, modem DOG crash note
2026-10-27T02:08 board: hard reset via Glasgow (reboot cycle 2 ended on red payload screen, no reset)
2026-10-27T02:14 board: payload (UART 1ms timeout, wdt 10s backstop) + ashen-pair ExecStop disarm installed
2026-10-27T02:30 verified: 1 tamper + 3 reboot cycles OK with new payload/ExecStop (reboot 2: no VM DHCP lease)
2026-10-27T02:36 MCU: cleared RCC_CSR reset flags (reboot reset-cause experiment)
2026-10-27T02:47 board: modem stop/start with qrtr tracing (crash investigation)
2026-10-27T02:48 board: removed -assign test kernel from ESP
2026-10-27T02:49 board: deployed KTEST=qrtrdbg kernel (qrtr/pd-mapper logging) as default
2026-10-27T02:56 NOTES: fwTPM loss on reboot root-caused to USB-C dock dropping VBUS (SMPL/BOR)
2026-10-27T03:01 board: redeployed KTEST=qrtrdbg (+ns hello/announce logging)
2026-10-27T03:05 board: deployed KTEST=qrtrdbg with qrtr pending-HELLO fix + debug
2026-10-27T03:13 board: deployed demo kernel dd40cddc (qrtr pending-HELLO fix); removed qrtrdbg test kernel
2026-10-27T03:13 NOTES: modem DOG crash root cause (qrtr HELLO race) + fix
2026-10-27T03:14 verified: demo kernel 45ba3c7f boots with no modem crash, units active, payload staged
2026-10-27T05:06 verified on VIN: reboot keeps MCU powered + TPM; dock w/o PD input dead (HW: no VBUS source)
2026-10-27T05:06 NOTES: VIN power results, dock needs its own PD supply
2026-10-27T05:06 ARCHITECTURE: power row (VIN + PD-powered dock)
