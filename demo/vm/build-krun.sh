#!/usr/bin/env bash
# Cross-build libkrun (with krun_set_crash_memaction) and the krunwipe launcher for the board,
# from committed HEAD of /workspace/libkrun, in the buildns tmpfs using libkrun's own flake shell.
# Exports /workspace/cache/out/krun/{libkrun.so.2,krunwipe}.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mountpoint -q /dev/shm/ns || exec "$HERE/../buildns" run "$HERE/build-krun.sh" "$@"
REPO=/workspace/libkrun
SRC=/dev/shm/ns/libkrun
EXPORT=/workspace/cache/out/krun
if [[ -z "${IN_NIX_SHELL:-}" ]]; then
	rev=$(git -C "$REPO" rev-parse HEAD)
	if [[ "$(cat "$SRC/.rev" 2>/dev/null)" != "$rev" ]]; then
		rm -rf "$SRC"; mkdir -p "$SRC"
		git -C "$REPO" archive "$rev" | tar -x -C "$SRC"
		echo "$rev" > "$SRC/.rev"
	fi
	# overlay uncommitted changes to tracked files
	git -C "$REPO" diff --name-only HEAD | while read -r f; do cp "$REPO/$f" "$SRC/$f"; done
	cd "$SRC"
	exec "$HERE/../nix" develop "path:$SRC" -c "$HERE/build-krun.sh" "$@"
fi
export CARGO_HOME=/dev/shm/ns/cargo
cd "$SRC"
cargo build --release --target "$CROSS_TARGET" -p libkrun --features net
(cd examples/krunwipe && cargo build --release --target "$CROSS_TARGET")
mkdir -p "$EXPORT"
cp "target/$CROSS_TARGET/release/libkrun.so" "$EXPORT/libkrun.so.2"
cp "examples/target/$CROSS_TARGET/release/krunwipe" "$EXPORT/krunwipe"
for f in "$EXPORT"/*; do
	echo "$f: needs $(readelf -V "$f" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)," \
		"interp $(readelf -l "$f" | sed -n 's/.*interpreter: \(.*\)]/\1/p')"
done
