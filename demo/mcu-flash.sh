#!/bin/sh
# Flash an ashen-fw ELF onto the UNO Q's MCU through the board's own OpenOCD (bit-banged SWD),
# verify, and reset. The keystore page (top of flash, NOLOAD) is not touched.
#   mcu-flash.sh [elf]   (default: /workspace/cache/out/ashen-fw.elf)
set -e
ELF=${1:-/workspace/cache/out/ashen-fw.elf}
H=$(/workspace/demo/bssh --host)
scp -q -i /workspace/id_ed25519_claude_vm "$ELF" root@"$H":/var/tmp/ashen-fw.elf
/workspace/demo/bssh 'pkill -x openocd; cd /opt/openocd && bin/openocd -s /opt/openocd -f openocd_gpiod.cfg \
	-c "reset_config srst_only srst_push_pull" -c "program /var/tmp/ashen-fw.elf verify reset exit" 2>&1 |
	grep -E "Verified|Error|wrong"'
