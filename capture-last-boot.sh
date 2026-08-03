#!/bin/sh

out=${1:-last-boot.log}
tmux capture-pane -t uart:0.0 -S - -p|tac|sed '/Booting Linux on physical CPU 0x0000000000/q'|tac > $out
