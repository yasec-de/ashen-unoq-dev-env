#!/bin/sh
# Build ashen-fw (incl. submodules, dirty tree) in the buildns tmpfs; export ELF to cache/out.
set -e
out=$(/workspace/demo/buildns run /workspace/demo/nix build -L --no-link --print-out-paths \
	"git+file:///workspace/ashen-fw?submodules=1")
rm -f /workspace/cache/out/ashen-fw.elf
/workspace/demo/buildns run cp "/dev/shm/ns/.nix-portable$out/bin/ashen-fw" /workspace/cache/out/ashen-fw.elf
echo "built $out -> /workspace/cache/out/ashen-fw.elf"
