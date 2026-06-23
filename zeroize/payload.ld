/* SPDX-License-Identifier: GPL-2.0 */
ENTRY(_start)

/* Link == load address. Pin it with crashkernel=SIZE@PAYLOAD_BASE so the
 * capture image runs where it's linked (no PIC needed). Override with
 * `make PAYLOAD_BASE=0x...`. */
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
