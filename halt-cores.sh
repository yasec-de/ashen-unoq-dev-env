#!/bin/sh
# Halt all four A53 cores via openocd's telnet console (port 4444).
printf 'targets auto0.a53.0\nhalt\ntargets auto0.a53.1\nhalt\ntargets auto0.a53.2\nhalt\ntargets auto0.a53.3\nhalt\ntargets\nexit\n' \
	| ncat 127.0.0.1 4444
