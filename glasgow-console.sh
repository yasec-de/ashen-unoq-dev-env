#!/bin/sh
# 1V8 UART console to the UNO Q debug UART via a Glasgow.
#
# Wiring (Glasgow port A, level-shifted to 1.8V):
#   A0 = Glasgow TX -> board RX
#   A1 = Glasgow RX <- board TX   (board sends, Glasgow receives)
#   GND-GND
#
# Qualcomm console default is 115200 8N1; override as arg 1, e.g.:
#   ./glasgow-console.sh 921600
#
# Glasgow isn't installed system-wide; run it straight from nixpkgs.
# If it errors on USB access, you need the Glasgow udev rule (uaccess for
# 20b7:9db1) or run under sudo.
exec nix run nixpkgs#glasgow -- run uart -V A=1.8 --tx A0 --rx A1 -b "${1:-115200}" tty
