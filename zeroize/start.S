/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Freestanding aarch64 entry for the tamper-response wipe payload.
 *
 * Loaded as the kdump capture image (kexec -p) and entered per the arm64 boot
 * protocol with x0 = DTB phys. Runs at EL1 (drops from EL2 if needed), installs
 * exception vectors, then hands off to payload_main() which parses the DTB,
 * builds an identity map, and wipes RAM.
 *
 * All addressing is PC-relative, so it runs wherever kexec loads it in the
 * crashkernel region (the bottom of it, 2 MB-aligned).
 */

	.section .head.text, "ax"
	.global _start
_head:
	b	_start			/* code0: branch to entry        */
	.long	0			/* code1                         */
	.quad	0			/* text_offset                  */
	.quad	_end - _head		/* image_size (incl. bss)       */
	.quad	0			/* flags (LE, 4K)               */
	.quad	0, 0, 0			/* res2..res4                   */
	.long	0x644d5241		/* magic "ARM\x64"              */
	.long	0			/* res5 (no PE header)          */

_start:
	mov	x19, x0			/* save DTB phys */

	/* If we entered at EL2, drop to EL1h. */
	mrs	x0, CurrentEL
	cmp	x0, #(2 << 2)
	b.ne	1f
	mov	x0, #(1 << 31)		/* HCR_EL2.RW = AArch64 EL1 */
	msr	hcr_el2, x0
	mov	x0, #0x0830		/* SCTLR_EL1 reserved-1 bits */
	movk	x0, #0x30d0, lsl #16
	msr	sctlr_el1, x0
	mov	x0, #0x3c5		/* DAIF masked, EL1h */
	msr	spsr_el2, x0
	adr	x0, 1f
	msr	elr_el2, x0
	eret
1:
	/* EL1: vectors, stack, IRQs masked, then C. */
	adrp	x0, vectors
	add	x0, x0, :lo12:vectors
	msr	vbar_el1, x0
	isb

	adrp	x0, boot_stack_top
	add	x0, x0, :lo12:boot_stack_top
	mov	sp, x0

	msr	daifset, #0xf
	isb

	/* zero .bss (kexec does not; our globals assume zero) */
	adrp	x0, __bss_start
	add	x0, x0, :lo12:__bss_start
	adrp	x1, __bss_end
	add	x1, x1, :lo12:__bss_end
4:	cmp	x0, x1
	b.hs	5f
	str	xzr, [x0], #8
	b	4b
5:
	mov	x0, x19			/* DTB phys */
	bl	payload_main
halt:
	wfi
	b	halt

/*
 * mmu_enable - install MAIR/TCR/TTBR0 and turn on MMU + caches.
 * Reads ttbr0_val/tcr_val/mair_val globals (set by C before the call).
 */
	.global mmu_enable
mmu_enable:
	adrp	x0, mair_val
	ldr	x1, [x0, :lo12:mair_val]
	msr	mair_el1, x1
	adrp	x0, tcr_val
	ldr	x1, [x0, :lo12:tcr_val]
	msr	tcr_el1, x1
	adrp	x0, ttbr0_val
	ldr	x1, [x0, :lo12:ttbr0_val]
	msr	ttbr0_el1, x1
	isb

	dsb	ish
	tlbi	vmalle1
	dsb	ish
	ic	iallu
	dsb	ish
	isb

	mrs	x0, sctlr_el1
	orr	x0, x0, #(1 << 0)	/* M: MMU */
	orr	x0, x0, #(1 << 2)	/* C: data cache */
	orr	x0, x0, #(1 << 12)	/* I: instruction cache */
	msr	sctlr_el1, x0
	isb
	ret

/* Minimal exception vectors: any fault during the wipe is skipped (see
 * exc_skip in payload.c) so a rejected address can't hang or reset us. */
	.macro ventry label
	.balign 128
	b	\label
	.endm

	.balign 2048
	.global vectors
vectors:
	ventry	exc_handler		/* Sync   EL1t */
	ventry	exc_handler		/* IRQ    EL1t */
	ventry	exc_handler		/* FIQ    EL1t */
	ventry	exc_handler		/* SError EL1t */
	ventry	exc_handler		/* Sync   EL1h */
	ventry	exc_handler		/* IRQ    EL1h */
	ventry	exc_handler		/* FIQ    EL1h */
	ventry	exc_handler		/* SError EL1h */
	ventry	exc_handler		/* Sync   EL0  64 */
	ventry	exc_handler		/* IRQ    EL0  64 */
	ventry	exc_handler		/* FIQ    EL0  64 */
	ventry	exc_handler		/* SError EL0  64 */
	ventry	exc_handler		/* Sync   EL0  32 */
	ventry	exc_handler		/* IRQ    EL0  32 */
	ventry	exc_handler		/* FIQ    EL0  32 */
	ventry	exc_handler		/* SError EL0  32 */

/*
 * On any exception, advance ELR past the faulting store and return. The wipe
 * loop is written so that skipping a single instruction simply drops the
 * current store-pair (16 bytes); the next iteration continues. SError is
 * imprecise so we just return and let the loop carry on.
 */
exc_handler:
	mrs	x0, elr_el1
	add	x0, x0, #4
	msr	elr_el1, x0
	/* note that we skipped something, for diagnostics */
	adrp	x1, exc_skips
	ldr	x2, [x1, :lo12:exc_skips]
	add	x2, x2, #1
	str	x2, [x1, :lo12:exc_skips]
	eret

	.section .bss.stacks, "aw", %nobits
	.balign 4096
boot_stack:
	.space	16384
boot_stack_top:
