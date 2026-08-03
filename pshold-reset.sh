#!/bin/bash
# Warm-reset the target by deasserting PS_HOLD via an AXI-AP MMIO write through
# OpenOCD. PS_HOLD high = "keep me powered"; writing 0 makes the PMIC drop the
# rail, which is a warm reset (DDR survives if SDI is armed -- the path the
# qcom_scm download_mode dump relies on).
#
# Requires: OpenOCD already running with openocd.cfg (tcl port 6666) and at
# least the AXI-AP reachable. Run it via the `openocd` tmux session.
#
# ponytail: PS_HOLD addr is a param, not hardcoded -- qcm2290 has no pshold DT
# node so the address is unverified against this board's /proc/iomem. Default is
# the MSM8953/SDM/qcm2290-family MSM_PSHOLD location. Override if iomem differs:
#   PSHOLD=0x0Cxxxxxx ./pshold-reset.sh
set -eu

PSHOLD=${PSHOLD:-0x0C264000}
TCL_HOST=${TCL_HOST:-localhost}
TCL_PORT=${TCL_PORT:-6666}

# openocd tcl_rpc commands are 0x1a-terminated. Use bash /dev/tcp (no nc needed).
oocd() {
	exec 3<>"/dev/tcp/$TCL_HOST/$TCL_PORT"
	printf '%s\x1a' "$1" >&3
	# Read until the 0x1a reply terminator.
	IFS= read -r -d $'\x1a' -u 3 reply || true
	printf '%s\n' "$reply"
	exec 3<&- 3>&-
}

echo "PS_HOLD reg: $PSHOLD"
echo "Pre-write value:"
oocd "auto0.axi mdw $PSHOLD"

printf 'Deasserting PS_HOLD to warm reset the board now...'

# Write 0 -> PS_HOLD low -> PMIC drops the rail -> warm reset.
oocd "auto0.axi mww $PSHOLD 0x0"
echo "PS_HOLD deasserted; board should warm-reset into PBL now."
