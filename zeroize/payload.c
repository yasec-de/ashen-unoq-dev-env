// SPDX-License-Identifier: GPL-2.0
/*
 * Tamper-response wipe payload (kdump capture image) for the Arduino UNO Q
 * (Qualcomm QCM2290, 4x Cortex-A53). Entered from start.S at EL1 with the DTB.
 *
 * Flow (single core, MMU off until the tables are built so early writes hit
 * DRAM directly):
 *   1. Parse the DTB: RAM (/memory), secure carveouts (/reserved-memory no-map),
 *      our own region (/chosen linux,usable-memory-range).
 *   2. Build a 2 MB-block identity map: wipe-set = Normal Non-Cacheable (writes
 *      go straight to DRAM, no writeback worry, no read-for-ownership); our own
 *      region = Normal-WB (fast code/stack); UART + watchdog = Device; no-map
 *      carveouts left unmapped (writing them from EL1 would fault an xPU).
 *   3. Enable MMU+caches. Stop USB DMA (see usb_stop). Wipe the pages the crashed kernel tagged in its
 *      MEMACTION note (crash_memaction=secret: VM RAM, disk/TLS keys) first,
 *      then all of RAM (petting the watchdog), then PSCI SYSTEM_RESET.
 *
 * DT cell sizes are hardcoded to this board's layout (root/reserved-memory
 * #address-cells=2 #size-cells=2).
 */

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;

/* GENI debug UART (serial@4a90000 = ttyMSM0/serial0), already set up by the
 * bootloader; we only push bytes. ponytail: board-specific base, not parsed. */
#define UART_BASE		0x04a90000UL
#define SE_GENI_M_CMD0		0x600
#define SE_GENI_M_IRQ_STATUS	0x610
#define SE_GENI_M_IRQ_CLEAR	0x618
#define SE_UART_TX_TRANS_LEN	0x270
#define SE_GENI_TX_FIFOn	0x700
#define M_CMD_DONE_EN		(1u << 0)
#define M_OPCODE_SHFT		27
#define UART_START_TX		1

#define PSCI_CPU_ON		0xC4000003UL
#define PSCI_SYSTEM_RESET	0x84000009UL

/* apss/kpss watchdog (sm6115/qcm2290 watchdog@f017000). Writing WDT_RST kicks
 * the bark/bite counter; the full-RAM wipe is long enough to trip it unpetted. */
#define WDT_BASE		0x0f017000UL
#define WDT_RST			0x4	/* qcom,kpss-wdt layout */
#define WDT_EN			0x8
#define WDT_BARK_TIME		0x10
#define WDT_BITE_TIME		0x14
#define WDT_RATE		32768	/* sleep clock */
#define WDT_BACKSTOP_S		10

/* Display controller (qcm2290 DPU 6.5, mdp @ 0x5e01000; offsets from the msm dpu catalog).
 * Staging only the layer mixer's border colour makes the panel show a solid colour without any
 * memory fetches, so it survives the full-RAM wipe. Only touched when
 * the staging script saw an enabled display (ashen_display=1): an unclocked MDSS stalls the bus. */
#define MDP_BASE		0x05e01000UL
#define CTL0			(MDP_BASE + 0x1000)
#define CTL_LAYER0		0x000
#define CTL_LAYER_EXT0		0x040
#define CTL_LAYER_EXT2_0	0x070
#define CTL_LAYER_EXT3_0	0x0a0
#define CTL_LAYER_EXT4_0	0x0b8
#define CTL_FLUSH		0x018
#define CTL_MIXER_BORDER_OUT	(1u << 24)
#define CTL_FLUSH_LM0		(1u << 6)
#define CTL_FLUSH_CTL		(1u << 17)
#define LM0			(MDP_BASE + 0x44000)
#define LM_BORDER_COLOR_0	0x08	/* green | blue << 16, 12 bits each */
#define LM_BORDER_COLOR_1	0x10	/* red | alpha << 16 */
/* Display clock controller: readable at any time (its GCC AHB clock is forced on), so it tells us
 * whether the display controller is powered and clocked before we touch it. ashen_display=1 only
 * says a display was lit at staging time; by the panic (e.g. mid-shutdown) it may be off. */
#define DISPCC_BASE		0x05f00000UL
#define DISPCC_MDSS_GDSCR	0x3000
#define DISPCC_MDSS_AHB_CBCR	0x2044
#define DISPCC_MDSS_MDP_CBCR	0x2008
#define GDSC_PWR_ON		(1u << 31)
#define CBCR_CLK_OFF		(1u << 31)

/* USB (dwc3 in host mode, xHCI at its base). The controller keeps DMAing (the dock's
 * Ethernet always receives) into rings and buffers we are about to zero, and once they
 * are gone it wedges the interconnect: our stores stall until something else resets
 * the SoC. Halt it, then hold the whole block in reset, before wiping anything. */
#define GCC_BASE		0x01400000UL
#define GCC_USB30_PRIM_BCR	0x1a000
#define GCC_USB30_PRIM_GDSCR	0x1a004
#define GCC_USB30_PRIM_MASTER_CBCR 0x1a010
#define GCC_CFG_NOC_USB3_AXI_CBCR 0x1a084
#define XHCI_BASE		0x04e00000UL
#define XHCI_USBCMD_RS		(1u << 0)
#define XHCI_USBSTS_HCH		(1u << 0)

#define SZ_2M			0x200000UL
#define MASK_2M			(SZ_2M - 1)

#define MAX_MEM			8
#define MAX_NOMAP		48
#define MAX_L2			8	/* one per 1 GB region we touch */

struct range { u64 start, end; };

/* Shared with start.S (mmu_enable reads these; set MMU-off so they reach DRAM). */
u64 ttbr0_val, tcr_val, mair_val;
volatile u64 exc_skips;			/* bumped by the fault handler */

/* Parsed DTB. */
static struct range mem[MAX_MEM];	static int n_mem;
static struct range nomap[MAX_NOMAP];	static int n_nomap;
static u64 resv_start, resv_end;	/* our own (usable-memory-range) region */
static u64 elfcorehdr;			/* /chosen linux,elfcorehdr (in our region) */
static int display_active;		/* /chosen bootargs has ashen_display=1 */

/* Computed wipe-set (RAM - no-map(rounded to 2 MB) - our region). */
static struct range wipe[MAX_MEM + MAX_NOMAP]; static int n_wipe;
static u64 wipe_total;

/* Page tables (in our WB region; written MMU-off so they land in DRAM). */
static u64 l1[512]			__attribute__((aligned(4096)));
static u64 l2[MAX_L2][512]		__attribute__((aligned(4096)));
static int n_l2;
static u64 l2_for_gb[512];		/* 1 GB index -> l2 table addr, 0 = none */

extern void mmu_enable(void);

/* --- tiny MMIO + barriers --- */
static inline void writel(u32 v, u64 a) { *(volatile u32 *)a = v; }
static inline u32 readl(u64 a) { return *(volatile u32 *)a; }
static inline void dsb_sy(void) { asm volatile("dsb sy" ::: "memory"); }
static inline u64 rd_cntvct(void) { u64 v; asm volatile("mrs %0, cntvct_el0" : "=r"(v)); return v; }
static inline u64 rd_cntfrq(void) { u64 v; asm volatile("mrs %0, cntfrq_el0" : "=r"(v)); return v; }

/* Kick the apss watchdog. Cheap single MMIO write; safe MMU-off (Device by
 * default) or MMU-on (WDT_BASE mapped Device in build_tables). */
static void wdt_pet(void) { writel(1, WDT_BASE + WDT_RST); }

/* The panicked kernel leaves the watchdog off. Arm it (as qcom_wdt_start does) so that if
 * anything below stalls, or PSCI SYSTEM_RESET never resets, the bite still reboots. */
static void wdt_arm(void)
{
	writel(0, WDT_BASE + WDT_EN);
	writel(1, WDT_BASE + WDT_RST);
	writel(WDT_BACKSTOP_S * WDT_RATE, WDT_BASE + WDT_BARK_TIME);
	writel(WDT_BACKSTOP_S * WDT_RATE, WDT_BASE + WDT_BITE_TIME);
	writel(1, WDT_BASE + WDT_EN);
}

/* --- UART (polled GENI TX, modeled on qcom_geni_serial_poll_put_char) --- */
/* The panicked kernel can leave the GENI TX engine wedged (see GENI-UART-TX-FLUSH-BUG.md):
 * then M_CMD_DONE never comes. Give each char 1 ms (it takes ~87 us) and drop the UART for
 * good on the first timeout, so a dead console can never keep the payload from resetting. */
static int uart_dead;
static void uart_putc(char c)
{
	u64 deadline;

	if (uart_dead)
		return;
	if (c == '\n')
		uart_putc('\r');
	writel(M_CMD_DONE_EN, UART_BASE + SE_GENI_M_IRQ_CLEAR);
	writel(1, UART_BASE + SE_UART_TX_TRANS_LEN);
	writel(UART_START_TX << M_OPCODE_SHFT, UART_BASE + SE_GENI_M_CMD0);
	writel((u32)(u8)c, UART_BASE + SE_GENI_TX_FIFOn);
	deadline = rd_cntvct() + rd_cntfrq() / 1000;
	while (!(readl(UART_BASE + SE_GENI_M_IRQ_STATUS) & M_CMD_DONE_EN))
		if (rd_cntvct() > deadline) {
			uart_dead = 1;
			return;
		}
}

static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

static void uart_putu(u64 v)
{
	char buf[20];
	int i = 0;

	if (!v) { uart_putc('0'); return; }
	while (v) { buf[i++] = '0' + v % 10; v /= 10; }
	while (i--) uart_putc(buf[i]);
}

static void uart_puthex(u64 v)
{
	uart_puts("0x");
	for (int s = 60; s >= 0; s -= 4)
		uart_putc("0123456789abcdef"[(v >> s) & 0xf]);
}

/* --- FDT (read-only, big-endian) --- */
#define FDT_BEGIN_NODE	1
#define FDT_END_NODE	2
#define FDT_PROP	3
#define FDT_NOP		4
#define FDT_END		9

/* The DTB is parsed MMU-off (Device-nGnRnE memory: unaligned loads fault). DTB
 * property data is only 4-byte aligned, so be64 must never become a single
 * unaligned `ldr`. Force byte loads with explicit ldrb inline asm — structural,
 * not dependent on the optimizer not merging plain C byte reads. */
static inline u8 rb(const void *p) { u8 v; asm("ldrb %w0, [%1]" : "=r"(v) : "r"(p)); return v; }
static u32 be32(const void *p) { const u8 *b = p; return (rb(b) << 24) | (rb(b+1) << 16) | (rb(b+2) << 8) | rb(b+3); }
static u64 be64(const void *p) { return ((u64)be32(p) << 32) | be32((const u8 *)p + 4); }
static u32 align4(u32 x) { return (x + 3) & ~3u; }
static int streq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
static int startswith(const char *s, const char *pfx) { while (*pfx) if (*s++ != *pfx++) return 0; return 1; }
/* startswith() for DTB data read MMU-off: byte loads only. */
static int startswith_dev(const char *s, const char *pfx) { while (*pfx) if (rb(s++) != (u8)*pfx++) return 0; return 1; }

static void add_mem(u64 a, u64 n) { if (n && n_mem < MAX_MEM) { mem[n_mem].start = a; mem[n_mem].end = a + n; n_mem++; } }
static void add_nomap(u64 a, u64 n) { if (n && n_nomap < MAX_NOMAP) { nomap[n_nomap].start = a; nomap[n_nomap].end = a + n; n_nomap++; } }

static void fdt_parse(u64 dtb)
{
	const u8 *base = (const u8 *)dtb;
	u32 off_struct = be32(base + 8);
	u32 off_strings = be32(base + 12);
	const char *strings = (const char *)(base + off_strings);
	const u8 *p = base + off_struct;
	int depth = 0;
	const char *name1 = "";
	int d2_nomap = 0, d2_has_reg = 0;
	u64 d2_addr = 0, d2_size = 0;

	for (;;) {
		u32 tok = be32(p); p += 4;

		if (tok == FDT_BEGIN_NODE) {
			const char *nm = (const char *)p;
			u32 len = 0; while (nm[len]) len++;
			p += align4(len + 1);
			depth++;
			/* depth 1 == root ("/"); top-level nodes (memory, chosen,
			 * cpus, reserved-memory) are depth 2, their children depth 3. */
			if (depth == 2) name1 = nm;
			else if (depth == 3) { (void)nm; d2_nomap = 0; d2_has_reg = 0; }
		} else if (tok == FDT_END_NODE) {
			if (depth == 3 && streq(name1, "reserved-memory") && d2_nomap && d2_has_reg)
				add_nomap(d2_addr, d2_size);
			depth--;
			if (depth == 0)
				break;
		} else if (tok == FDT_PROP) {
			u32 len = be32(p); p += 4;
			u32 noff = be32(p); p += 4;
			const char *pn = strings + noff;
			const u8 *data = p;
			p += align4(len);

			if (depth == 2 && startswith(name1, "memory") && streq(pn, "reg")) {
				for (u32 o = 0; o + 16 <= len; o += 16)
					add_mem(be64(data + o), be64(data + o + 8));
			} else if (depth == 2 && streq(name1, "chosen") &&
				   streq(pn, "linux,usable-memory-range") && len >= 16) {
				resv_start = be64(data);
				resv_end = resv_start + be64(data + 8);
			} else if (depth == 2 && streq(name1, "chosen") &&
				   streq(pn, "linux,elfcorehdr") && len >= 16) {
				elfcorehdr = be64(data);
			} else if (depth == 2 && streq(name1, "chosen") && streq(pn, "bootargs")) {
				for (u32 o = 0; o + 15 <= len; o++)
					if (rb(data + o) == 'a' && startswith_dev((const char *)data + o, "ashen_display=1"))
						display_active = 1;
			} else if (depth == 3 && streq(name1, "reserved-memory")) {
				if (streq(pn, "no-map")) d2_nomap = 1;
				else if (streq(pn, "reg") && len >= 16) {
					d2_addr = be64(data); d2_size = be64(data + 8); d2_has_reg = 1;
				}
			}
		} else if (tok == FDT_NOP) {
			/* skip */
		} else {	/* FDT_END or garbage */
			break;
		}
	}
}

/* --- wipe-set computation --- */
static int in_nomap_2m(u64 a, u64 b)	/* does [a,b) touch a no-map block (2 MB-rounded)? */
{
	for (int i = 0; i < n_nomap; i++) {
		u64 ns = nomap[i].start & ~MASK_2M;
		u64 ne = (nomap[i].end + MASK_2M) & ~MASK_2M;
		if (a < ne && ns < b)
			return 1;
	}
	return 0;
}

static void add_wipe(u64 a, u64 b) { if (a < b && n_wipe < (int)(sizeof(wipe) / sizeof(wipe[0]))) { wipe[n_wipe].start = a; wipe[n_wipe].end = b; n_wipe++; } }

/* Split each RAM range into 2 MB-aligned pieces, dropping no-map and our own
 * region. Anything left is mapped Normal-NC and gets wiped. */
static void build_wipe_set(void)
{
	for (int i = 0; i < n_mem; i++) {
		u64 a = (mem[i].start + MASK_2M) & ~MASK_2M;
		u64 e = mem[i].end & ~MASK_2M;

		for (u64 b = a; b < e; b += SZ_2M) {
			if (in_nomap_2m(b, b + SZ_2M))
				continue;
			if (b < resv_end && resv_start < b + SZ_2M)
				continue;	/* our region: mapped WB, never wiped */
			/* coalesce with previous block */
			if (n_wipe && wipe[n_wipe - 1].end == b)
				wipe[n_wipe - 1].end = b + SZ_2M;
			else
				add_wipe(b, b + SZ_2M);
		}
	}
	for (int i = 0; i < n_wipe; i++)
		wipe_total += wipe[i].end - wipe[i].start;
}

/* --- page tables --- */
#define ATTR_NORMAL	(0UL << 2)	/* MAIR idx 0: Normal WB         */
#define ATTR_DEVICE	(1UL << 2)	/* MAIR idx 1: Device-nGnRE      */
#define ATTR_NC		(2UL << 2)	/* MAIR idx 2: Normal NonCacheable */
#define PTE_AF		(1UL << 10)
#define PTE_SH_INNER	(3UL << 8)
#define PTE_BLOCK	0x1UL		/* valid block at L1/L2          */
#define PTE_TABLE	0x3UL
#define PTE_XN		((1UL << 53) | (1UL << 54))	/* PXN | UXN     */

static u64 *l2_table(u64 pa)
{
	u64 gb = pa >> 30;
	u64 *t;

	if (l2_for_gb[gb])
		return (u64 *)l2_for_gb[gb];
	t = l2[n_l2++];
	for (int i = 0; i < 512; i++)
		t[i] = 0;
	l2_for_gb[gb] = (u64)t;
	l1[gb] = (u64)t | PTE_TABLE;
	return t;
}

static void map_2m(u64 pa, u64 attr)
{
	u64 *t = l2_table(pa);
	t[(pa >> 21) & 0x1ff] = pa | attr | PTE_AF | PTE_SH_INNER | PTE_BLOCK;
}

static void build_tables(void)
{
	for (int i = 0; i < 512; i++)
		l1[i] = 0;

	/* UART + watchdog (+ display controller) (Device). */
	map_2m(UART_BASE & ~MASK_2M, ATTR_DEVICE | PTE_XN);
	if (display_active)
		map_2m(MDP_BASE & ~MASK_2M, ATTR_DEVICE | PTE_XN);	/* also covers DISPCC */
	map_2m(WDT_BASE & ~MASK_2M, ATTR_DEVICE | PTE_XN);
	map_2m(GCC_BASE & ~MASK_2M, ATTR_DEVICE | PTE_XN);
	map_2m(XHCI_BASE & ~MASK_2M, ATTR_DEVICE | PTE_XN);

	/* RAM: our region WB+executable, wipe-set NC, no-map left unmapped. */
	for (int i = 0; i < n_mem; i++) {
		u64 a = (mem[i].start + MASK_2M) & ~MASK_2M;
		u64 e = mem[i].end & ~MASK_2M;

		for (u64 b = a; b < e; b += SZ_2M) {
			if (in_nomap_2m(b, b + SZ_2M))
				continue;
			if (b < resv_end && resv_start < b + SZ_2M)
				map_2m(b, ATTR_NORMAL);		/* code/stack/tables */
			else
				map_2m(b, ATTR_NC | PTE_XN);	/* wipe target */
		}
	}

	mair_val = 0xffUL | (0x04UL << 8) | (0x44UL << 16);	/* WB, Device, NC */
	tcr_val = 25UL			/* T0SZ: 39-bit VA */
		| (1UL << 8)		/* IRGN0 WBWA */
		| (1UL << 10)		/* ORGN0 WBWA */
		| (3UL << 12)		/* SH0 inner */
		| (1UL << 23)		/* EPD1: no TTBR1 */
		| (2UL << 32);		/* IPS 40-bit */
	ttbr0_val = (u64)l1;
}

/* --- PSCI --- */
static long smc(u64 fn, u64 a1, u64 a2, u64 a3)
{
	register u64 x0 asm("x0") = fn, x1 asm("x1") = a1;
	register u64 x2 asm("x2") = a2, x3 asm("x3") = a3;

	asm volatile("smc #0" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3) :: "memory");
	return x0;
}

/* --- the wipe --- */
static void wipe_range(u64 p, u64 end)
{
	u64 next_pet = p + 0x1000000;	/* pet the watchdog every 16 MB */

	while (p + 64 <= end) {
		asm volatile(
			"stp xzr, xzr, [%0, #0]\n"
			"stp xzr, xzr, [%0, #16]\n"
			"stp xzr, xzr, [%0, #32]\n"
			"stp xzr, xzr, [%0, #48]\n"
			:: "r"(p) : "memory");
		p += 64;
		if (p >= next_pet) {
			wdt_pet();
			next_pet = p + 0x1000000;
#ifdef WIPE_TRACE
			uart_putc('.');
#endif
		}
	}
	while (p < end) { *(volatile u8 *)p = 0; p++; }
}

static void wipe_all(void)
{
	for (int i = 0; i < n_wipe; i++) {
#ifdef WIPE_TRACE
		uart_puts("\nw ");
		uart_puthex(wipe[i].start);
		uart_putc('-');
		uart_puthex(wipe[i].end);
		uart_putc(' ');
#endif
		wipe_range(wipe[i].start, wipe[i].end);
	}
}

/* --- MEMACTION note (include/linux/crash_memaction.h wire format) --- */
#define PT_NOTE			4
#define CRASH_MEMACTION_SECRET	0x2000

struct elf64_phdr { u32 p_type, p_flags; u64 p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align; };
struct memaction_region { u64 start_pfn, nr_pages, bitmap_paddr; };
struct memaction_note { u32 types, page_shift, nr_regions, _pad; struct memaction_region regions[]; };

static int in_wipe_set(u64 a, u64 b)
{
	for (int i = 0; i < n_wipe; i++)
		if (wipe[i].start <= a && b <= wipe[i].end)
			return 1;
	return 0;
}

/* Find the MEMACTION descriptor among the PT_NOTE segments of the ELF core
 * header. Both live in the crashkernel region, so they are mapped WB. */
static const struct memaction_note *find_memaction(void)
{
	const u8 *eh = (const u8 *)elfcorehdr;
	u64 phoff;
	u32 phnum;

	if (!elfcorehdr || eh[0] != 0x7f || eh[1] != 'E' || eh[2] != 'L' || eh[3] != 'F' || eh[4] != 2)
		return 0;
	phoff = *(const u64 *)(eh + 32);
	phnum = *(const unsigned short *)(eh + 56);

	for (u32 i = 0; i < phnum; i++) {
		const struct elf64_phdr *ph = (const void *)(eh + phoff + i * sizeof(*ph));
		u64 p = ph->p_paddr, end = p + ph->p_filesz;

		if (ph->p_type != PT_NOTE || p < resv_start || end > resv_end)
			continue;
		while (p + 12 <= end) {
			u32 namesz = ((const u32 *)p)[0], descsz = ((const u32 *)p)[1];
			const char *name = (const char *)(p + 12);
			u64 desc = p + 12 + align4(namesz);

			if (!namesz && !descsz)
				break;	/* final_note() terminator */
			if (namesz == sizeof("MEMACTION") && streq(name, "MEMACTION"))
				return (const void *)desc;
			p = desc + align4(descsz);
		}
	}
	return 0;
}

/* Wipe every page whose bit is set. Returns the number of pages wiped; pages
 * outside the wipe-set (no-map carveouts, our own region) are left alone. */
static u64 wipe_tagged(const struct memaction_note *n)
{
	u64 pages = 0, psz;

	if (!n || !(n->types & CRASH_MEMACTION_SECRET) || n->page_shift < 12 || n->page_shift > 16)
		return 0;
	psz = 1UL << n->page_shift;

	for (u32 r = 0; r < n->nr_regions; r++) {
		const struct memaction_region *reg = &n->regions[r];
		const u64 *bm = (const u64 *)reg->bitmap_paddr;
		u64 bm_end = reg->bitmap_paddr + (reg->nr_pages + 63) / 64 * 8;

		/* The bitmap lives in the old kernel's RAM, i.e. in the wipe-set. */
		if (!in_wipe_set(reg->bitmap_paddr & ~MASK_2M, (bm_end + MASK_2M) & ~MASK_2M))
			continue;
		for (u64 w = 0; w < (reg->nr_pages + 63) / 64; w++) {
			u64 bits = bm[w];

			while (bits) {
				u64 bit = __builtin_ctzl(bits);
				u64 pa = (reg->start_pfn + w * 64 + bit) << n->page_shift;

				bits &= bits - 1;
				if (w * 64 + bit >= reg->nr_pages || !in_wipe_set(pa, pa + psz))
					continue;
				wipe_range(pa, pa + psz);
				pages++;
			}
		}
	}
	return pages;
}

static int display_powered(void)
{
	return (readl(DISPCC_BASE + DISPCC_MDSS_GDSCR) & GDSC_PWR_ON) &&
	       !(readl(DISPCC_BASE + DISPCC_MDSS_AHB_CBCR) & CBCR_CLK_OFF) &&
	       !(readl(DISPCC_BASE + DISPCC_MDSS_MDP_CBCR) & CBCR_CLK_OFF);
}

static void usb_stop(void)
{
	u64 g = GCC_BASE, deadline;

	/* Only touch the controller while it is powered and clocked: unclocked MMIO stalls. */
	if ((readl(g + GCC_USB30_PRIM_GDSCR) & GDSC_PWR_ON) &&
	    !(readl(g + GCC_USB30_PRIM_MASTER_CBCR) & CBCR_CLK_OFF) &&
	    !(readl(g + GCC_CFG_NOC_USB3_AXI_CBCR) & CBCR_CLK_OFF)) {
		u64 op = XHCI_BASE + (readl(XHCI_BASE) & 0xff);	/* CAPLENGTH */

		writel(readl(op) & ~XHCI_USBCMD_RS, op);
		/* xHCI halts within 16 ms of clearing R/S */
		deadline = rd_cntvct() + rd_cntfrq() / 50;
		while (!(readl(op + 4) & XHCI_USBSTS_HCH) && rd_cntvct() < deadline)
			;
	}
	writel(1, g + GCC_USB30_PRIM_BCR);
	dsb_sy();
}

/* Solid red on the panel until reset, independent of RAM contents. */
static void display_solid_red(void)
{
	if (!display_powered())
		return;
	writel(0, LM0 + LM_BORDER_COLOR_0);
	writel(0xfff | (0xfff << 16), LM0 + LM_BORDER_COLOR_1);
	writel(CTL_MIXER_BORDER_OUT, CTL0 + CTL_LAYER0);
	writel(0, CTL0 + CTL_LAYER_EXT0);
	writel(0, CTL0 + CTL_LAYER_EXT2_0);
	writel(0, CTL0 + CTL_LAYER_EXT3_0);
	writel(0, CTL0 + CTL_LAYER_EXT4_0);
	dsb_sy();
	writel(CTL_FLUSH_LM0 | CTL_FLUSH_CTL, CTL0 + CTL_FLUSH);
	dsb_sy();
}

static void uart_putms(u64 ticks, u64 freq)
{
	u64 us = ticks * 1000000 / (freq ? freq : 1);

	uart_putu(us / 1000);
	uart_putc('.');
	uart_putc('0' + us / 100 % 10);
	uart_puts(" ms");
}

void payload_main(u64 dtb)
{
	const struct memaction_note *note;
	u64 t_tag, tagged;

	u64 t0, t1, freq;

	wdt_arm();

	/* All of this runs MMU-off: writes hit DRAM directly. */
	fdt_parse(dtb);
	build_wipe_set();
	build_tables();
	dsb_sy();

	mmu_enable();			/* MMU + caches on */
	wdt_pet();			/* fresh kick before the long wipe */

	/* Single-core: PSCI CPU_ON for the other A53s never actually started a
	 * secondary on this board (1/3 at best, usually 0), so SMP was pure
	 * complexity for no speedup. One CPU wipes the whole set, petting the
	 * watchdog every 16 MB (see wipe_range) so the ~0.85 s pass can't trip the
	 * bite. ponytail: re-add SMP only if a board actually brings the cores up. */
	/* A few register writes: the panel turns solid red at once and, needing no memory
	 * fetches, stays red through the whole wipe until the reset. */
	if (display_active)
		display_solid_red();
	usb_stop();

	freq = rd_cntfrq();
	t0 = rd_cntvct();
	note = find_memaction();
	tagged = wipe_tagged(note);
	t_tag = rd_cntvct();

	/* Secrets are gone; spend ~5 ms of UART on telling the console. */
	uart_puts("\nzeroize: TAMPER - wiped ");
	uart_putu(tagged);
	uart_puts(note ? " tagged pages in " : " tagged pages (no MEMACTION note!) in ");
	uart_putms(t_tag - t0, freq);
	uart_puts("\n");

	t0 = rd_cntvct();
	wipe_all();
	t1 = rd_cntvct();

	/* UART is only safe to use now: it's slow polled 115.2 kBd and we keep it
	 * out of the timed wipe. */
	uart_puts("\nzeroize: RAM ranges=");
	uart_putu(n_mem);
	uart_puts(" wipe=");
	uart_puthex(wipe_total);
	uart_puts(" done in ");
	uart_putms(t1 - t0, freq);
	uart_puts(", skipped=");
	uart_putu(exc_skips);
	uart_puts(" faults. reset.\n");

	smc(PSCI_SYSTEM_RESET, 0, 0, 0);
	for (;;)
		asm volatile("wfi");
}
