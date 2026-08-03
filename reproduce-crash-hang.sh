#!/bin/sh

set -euo pipefail

for i in $(seq 1 $(nproc)); do
	for k in $(seq 1 100); do
		( for j in $(seq 1 10); do
			echo "<0>crash-repro flood cpu pid=$$ $(seq -s'' 1 40)" > /dev/kmsg
		done ) &
	done
done

sleep 1

echo c > /proc/sysrq-trigger