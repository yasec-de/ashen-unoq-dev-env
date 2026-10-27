/* SPDX-License-Identifier: GPL-2.0 */
ENTRY(_start)

/* Nominal link address only: the code is PC-relative (no absolute
 * relocations, checked by the Makefile), so it runs at whatever 2 MB-aligned
 * address kexec picks in the crashkernel region. */
BASE = DEFINED(PAYLOAD_BASE) ? PAYLOAD_BASE : 0x80000000;

SECTIONS {
	. = BASE;

	.head.text : { KEEP(*(.head.text)) }
	.text	: { *(.text*) }
	.rodata	: { *(.rodata*) }
	.data	: { *(.data*) }
	. = ALIGN(8);
	_edata = .;

	.bss (NOLOAD) : {
		__bss_start = .;
		*(.bss.stacks)
		*(.bss*)
		*(COMMON)
		. = ALIGN(8);
		__bss_end = .;
	}
	_end = .;

	/DISCARD/ : { *(.note*) *(.comment) *(.eh_frame*) }
}
