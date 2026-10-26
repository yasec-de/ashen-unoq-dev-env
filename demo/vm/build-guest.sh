#!/usr/bin/env bash
# Build the Galene guest rootfs tarball: static aarch64 galene, busybox and openssl from nixpkgs
# (same pin as demo/kernel/flake.lock), plus guest/ (init, group config) and Galene's static web
# files. Exports /workspace/cache/out/galene-rootfs.tar.gz.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mountpoint -q /dev/shm/ns || exec "$HERE/../buildns" run "$HERE/build-guest.sh" "$@"
NIX="$HERE/../nix"
STORE=/dev/shm/ns/.nix-portable
pkg() { $NIX build --no-link --print-out-paths --inputs-from "path:$HERE/../kernel" \
	"nixpkgs#pkgsCross.aarch64-multiplatform.pkgsStatic.$1" | grep -v -- '-man$\|-doc$' | head -1; }
galene=$(pkg galene); galene_web=$(pkg galene.static); busybox=$(pkg busybox); openssl=$(pkg openssl.bin)
echo "galene=$galene busybox=$busybox openssl=$openssl"

R=/dev/shm/ns/guest-rootfs
rm -rf "$R"; mkdir -p "$R"/{bin,proc,tmp,dev,etc,srv/galene/data}
cp "$STORE$busybox/bin/busybox" "$R/bin/"
for a in sh mount cat cut ls echo chmod mkdir sleep date ip awk grep udhcpc tail; do ln -s busybox "$R/bin/$a"; done
cp "$STORE$galene/bin/galene" "$STORE$openssl/bin/openssl" "$R/bin/"
# Galene's web client is the package's separate "static" output.
gsrc=$(find "$STORE$galene_web" -name index.html -printf '%h\n' | head -1)
[ -n "$gsrc" ] || { echo "ERROR: no web client in $galene_web"; exit 1; }
cp -r "$gsrc" "$R/srv/galene/static"
cp "$HERE/guest/init" "$R/init"
cp -r "$HERE/guest/groups" "$R/srv/galene/groups"
cp -r "$HERE/guest/etc/." "$R/etc/"
chmod -R u+w "$R"
for f in "$R/bin/busybox" "$R/bin/galene" "$R/bin/openssl"; do
	file "$f" 2>/dev/null || readelf -h "$f" | grep -E 'Machine|Type'
	readelf -l "$f" | grep -q interpreter && echo "ERROR: $f is dynamically linked" && exit 1
done
mkdir -p /workspace/cache/out
tar -C "$R" -czf /workspace/cache/out/galene-rootfs.tar.gz .
ls -la /workspace/cache/out/galene-rootfs.tar.gz
