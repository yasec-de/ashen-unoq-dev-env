# Freestanding aarch64 wipe payload (kdump capture image). Build with the same
# cross toolchain as the kernel: run via `nix develop ../ --command make`.
#
# PAYLOAD_BASE must match the pinned crashkernel base (crashkernel=SIZE@BASE),
# and SIZE must be >= the reported Image size, rounded up.

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
	$(LD) $(LDFLAGS) -o $@ $(OBJS)

Image: payload.elf
	$(OBJCOPY) -O binary $< $@
	@size=$$($(CROSS_COMPILE)readelf -l payload.elf >/dev/null 2>&1; stat -c %s Image); \
	 echo "Image: $$size bytes loaded at $(PAYLOAD_BASE); reserve crashkernel >= mem footprint (_end)."

clean:
	rm -f $(OBJS) payload.elf Image

.PHONY: all clean
