# Out-of-tree kbuild for UNO Q modules. Builds against the configured+built
# linux/ tree (branch qcom-v7.0.0-unoq), whose kernelrelease matches the
# running board exactly, so modules load with no vermagic mismatch.
#
# Needs the cross toolchain on PATH: run via `nix develop --command make`
# (flake.nix), same as build-kernel.sh. KDIR must already be built at least
# to Module.symvers (build-kernel.sh's `make Image` does that).

obj-m += hello.o

KDIR ?= $(CURDIR)/../linux
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean

.PHONY: all clean
