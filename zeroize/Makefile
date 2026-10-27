# Freestanding aarch64 wipe payload (kdump capture image). Build with the same
# cross toolchain as the kernel: run via `nix develop ../ --command make`.
#
# The code is PC-relative only (ADRP/ADR, no absolute relocations; enforced
# below), so it runs wherever kexec places it in the crashkernel region.
# PAYLOAD_BASE is only the nominal link address.

CROSS_COMPILE ?= aarch64-linux-gnu-
CC      := $(CROSS_COMPILE)gcc
LD      := $(CROSS_COMPILE)ld
OBJCOPY := $(CROSS_COMPILE)objcopy

PAYLOAD_BASE   ?= 0x80000000

CFLAGS := -ffreestanding -nostdinc -fno-pic -fno-stack-protector -fno-common \
	  -mgeneral-regs-only -mno-outline-atomics -march=armv8-a \
	  -O2 -Wall -Wextra
LDFLAGS := -nostdlib -static -T payload.ld --defsym PAYLOAD_BASE=$(PAYLOAD_BASE)

OBJS := start.o payload.o

all: Image

start.o: start.S
	$(CC) $(CFLAGS) -c -o $@ $<

payload.o: payload.c
	$(CC) $(CFLAGS) -c -o $@ $<

payload.elf: $(OBJS) payload.ld
	@if $(CROSS_COMPILE)readelf -rW $(OBJS) | grep -E 'R_AARCH64_(ABS|MOVW_UABS)'; then \
		echo "absolute relocations: the payload must stay position-independent"; exit 1; fi
	$(LD) $(LDFLAGS) -o $@ $(OBJS)

Image: payload.elf
	$(OBJCOPY) -O binary $< $@
	@size=$$($(CROSS_COMPILE)readelf -l payload.elf >/dev/null 2>&1; stat -c %s Image); \
	 echo "Image: $$size bytes; reserve crashkernel >= mem footprint (_end)."

clean:
	rm -f $(OBJS) payload.elf Image

.PHONY: all clean
