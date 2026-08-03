#!/bin/sh

#[ ! -e /tmp/gpio0 ] && echo "/tmp/gpio0 not found! Is the glasgow driver running?" && exit
#echo '0Z' > /tmp/gpio1
[ ! -e /tmp/gpio ] && echo "/tmp/gpio not found! Is the glasgow driver running?" && exit
echo -e 'A5=0\nA5=Z' | socat - UNIX-CONNECT:/tmp/gpio
