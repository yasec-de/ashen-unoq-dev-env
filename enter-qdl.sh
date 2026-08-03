#!/bin/sh

# assert FORCED_USB_BOOT_N
echo 'A6=0' | socat - UNIX-CONNECT:/tmp/gpio 

sleep 0.5

# pulse VBUS_POWER_SWITCH_DISABLE_N
echo -e 'A5=0\nA5=1' | socat - UNIX-CONNECT:/tmp/gpio 

sleep 0.5

# de-assert FORCED_USB_BOOT_N
echo 'A6=Z' | socat - UNIX-CONNECT:/tmp/gpio 

