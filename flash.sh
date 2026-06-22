#!/usr/bin/env bash
# Flash the built UNO Q image over USB/EDL with qdl.
#
# Put the board in EDL mode first: short the two JCTL pins furthest from the
# USB connector with a jumper, then power on (this board has no boot button,
# and `reboot edl` is a no-op -- see NOTES.md).
#
# Handles the qcserial gotcha: the kernel's qcserial driver auto-binds the EDL
# interface and makes qdl hang silently with zero USB traffic, so we unbind it
# first (needs sudo). --allow-missing matches arduino-flasher-cli's invocation.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)

QDL=${QDL:-$ROOT/qdl/build/qdl}
FLASHDIR=$ROOT/qcom-deb-images/flash_qrb2210-arduino-imola_emmc

[ -x "$QDL" ] || { echo "qdl not built: (cd qdl && meson setup build && meson compile -C build)"; exit 1; }
[ -f "$FLASHDIR/rawprogram0.xml" ] || { echo "no flash dir at $FLASHDIR -- run ./build-image.sh first"; exit 1; }

echo "Waiting for EDL device (05c6:9008) -- put the board in EDL mode..."
until lsusb | grep -q '05c6:9008'; do sleep 1; done

PORT=$(ls /sys/bus/usb/drivers/qcserial/ 2>/dev/null | grep -E '^[0-9]+-[0-9]' || true)
if [ -n "$PORT" ]; then
  echo "Unbinding qcserial from $PORT (sudo)..."
  echo "$PORT" | sudo tee /sys/bus/usb/drivers/qcserial/unbind >/dev/null
fi

cd "$FLASHDIR"
exec "$QDL" --allow-missing --storage emmc prog_firehose_ddr.elf rawprogram0.xml patch0.xml
