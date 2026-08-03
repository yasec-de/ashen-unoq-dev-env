#!/bin/sh

out=${1:-last-boot.log}
tmux capture-pane -t uart:0.0 -S - -p > $out
