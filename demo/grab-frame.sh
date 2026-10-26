#!/bin/sh
# Grab one frame of the board's HDMI output (dock capture, ffmpeg NUT stream on localhost:5000).
# The stream starts with buffered (possibly stale) frames, so skip the first SKIP frames.
#   grab-frame.sh OUT.png
exec /workspace/demo/nix shell --inputs-from path:/workspace/demo/kernel nixpkgs#ffmpeg-headless -c \
	ffmpeg -loglevel error -y -f nut -i tcp://127.0.0.1:5000 -vf "select=gte(n\\,${SKIP:-90})" -frames:v 1 "$1"
