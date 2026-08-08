; uncomment to print out debug info at runtime (dev only)
;#define DEBUG
;#define DEBUGIO
;
; Apple II (ProDOS) Aa-machine frontend.
; Designed for the xa65 assembler.
;
; ProDOS Version (-DPRODOS=1):
;
; The machine is identified at boot from the
; ProDOS global page, and the screen width,
; the character set and the use of auxiliary
; memory follow from that.
;
;  Apple ][ / ][+	40 columns, upper case
;  //e / //c / IIgs	80 columns if an
;			80-column card is
;			present, 40 otherwise
;  128 kB machines	cache/undo in aux RAM
;
; Screen output is delegated to the Monitor
; ROM, and to the //e 80-column firmware when
; that is active.  Keyboard input is NOT
; delegated, because RDKEY and KEYIN increment
; RNDL/RNDH at $4e/$4f, which alias the
; engine's rsim register.
;
; Storage is ProDOS 8 via the MLI.  ProDOS
; lives in the language card; system programs
; run with ROM banked in and trampoline
; through the $bf00 global page, so $fded and
; the MLI are both available at all times.
;
; For standard 143,360 byte floppy disks:
; You can put the entire story file into a single
; file called STORY on the main disk, but this limits
; you to about 100 KB size story files.
; On Apple IIGS you can use 800 KB disk images, and on
; emulators you can typically use up to 32 MB.
;
; ProDOS isn't very memory-efficient, as it takes up the
; entire 16 KB language card and 1 KB of RAM per open file.
; Many games require too much memory to run.
;
; Note -- the volume containing the STORY file should be
; called AA.STORY. The ProDOS version will scan for this
; volume label if it fails to find STORY in the current prefix.
;
; Main memory map (ProDOS)
; =====================================
;  0000 - 001f	frontend zero page
;  0020 - 002b	Monitor text variables
;  002c - 0031	frontend zero page
;  0032 - 0039	Monitor text variables
;  003a - 003f	frontend and disk driver temporaries
;  0040 - 00ff	engine zero page
;  0100 - 01ff	stack
;  0200 - 02ff	frontend buffers and MLI
;		parameter blocks
;  0300 - 037f	aux page cache tags
;  0400 - 07ff	text page 1
;  0800 -~4800	interpreter code
; ~4800 -~4e00	init code, reclaimed as cache
; ~4800 - baff  heap / data
;  bb00 - beff	ProDOS file buffer
;  bf00 - bfff	ProDOS global page
;  d000 - ffff	ProDOS 8 (language card)
;
; Auxiliary memory, when there is any
; =====================================
;  0400 - 07ff	80-column text page
;  0800 - bfff  aux page cache
;  d000 - ffff	aux undo ring, both $d000
;		banks, 16 kB in all
;
; ProRWTS2 Version (-DPRORWTS=1)
;
; This version uses a small-footprint ProDOS library which
; resides at $d000-$dfff and replaces the existing ProDOS.
; It has a separate entry point ($2003) for 0boot which
; stubs out the few ProDOS calls ProRWTS2 needs to init.
;
; Main memory map (ProRWTS2)
; =====================================
;  0800 - 2000	interpreter code
; ~2000 - bfff  heap / data
;  d000 - f800  interpreter code (bank 1)
;  d000 - daff  PRORWTS (bank 2)
;
; See also:
;   https://prodos8.com/docs/techref/memory-use/
;   https://savagetaylor.com/til/TA33130.html
;   https://github.com/peterferrie/prorwts2
;   https://github.com/peterferrie/0boot
;
; TODO
; - io_load flaky (hangs, inserting nop makes it say "Failed to *save* game state")
;   and the savefiles differ at $300
; - SAVEFILE on first disk when running AAM.SYSTEM from Prodos?
; - run STORY file from subdirectory?
; - victim cache (move stale pages to aux)?
; - use the packer instead of boot mover?
; - save/restore filenames or multiple slots?

DEFWIDTH	= 80

PREXTRA		= 2
PRSHIFT		= 0
HAVE_QUIT	= 1
HAVE_STATUS	= 1
HAVE_STYLE	= 0
SAVERESTORE	= 1
UNDO		= 1

TRACE_INST	= 0
TRACE_STORE	= 0

// ProRWTS can't create files, so our SAVEFILE
// must be created with maximum size in advance
// and thus we must reserve that much memory
#if PRORWTS
#define A2_EVICT_MAX 1
#endif

; ---- Monitor entry points ----

COUT		= $fded
COUT1		= $fdf0
HOME		= $fc58
VTAB		= $fc22
SETTXT		= $fb39
PRBYTE		= $fdda

AUXMOVE		= $c311
SLOT3		= $c300

CSW		= $36
A1		= $3c
A2		= $3e
A4		= $42

WNDLFT		= $20
WNDWDTH		= $21
WNDTOP		= $22
WNDBTM		= $23
CH		= $24
OURCH		= 1403
CV		= $25
INVFLG		= $32

KBD		= $c000
KBDSTRB		= $c010
CLR80STORE	= $c000
SET80STORE	= $c001
CLR80COL	= $c00c
TXTPAGE1	= $c054
TXTPAGE2	= $c055
ALTCHRSET_OFF	= $c00e
ALTCHRSET_ON	= $c00f

; ALTZP picks main or auxiliary for the zero
; page, the stack and $d000-$ffff, all three
; together.  The language card switches then
; apply to whichever side ALTZP has selected.

CLRALTZP	= $c008
SETALTZP	= $c009

; RAMRD and RAMWRT pick main or auxiliary for
; everything from $0200 to $bfff, independently
; for reads and writes.  80STORE overrides them
; for the text and hires pages, so it has to be
; off for these to mean anything.

CLRAUXRD	= $c002
SETAUXRD	= $c003
CLRAUXWR	= $c004
SETAUXWR	= $c005

LCRD2		= $c080		; read bank 2
LCROM2		= $c082		; rom, bank 2 latched
LCWR2		= $c083		; read/write bank 2,
				; access twice
LCRD1		= $c088		; read bank 1
LCWR1		= $c08b		; read/write bank 1,
				; access twice

; ---- auxiliary memory ----

AUXCACHESTART	= $800
AUXCACHEEND	= $c000
AUXCACHEPAGES	= (AUXCACHEEND-AUXCACHESTART)>>8

; Slots are indexed by the virtual page
; number modulo AUXCACHEPAGES, computed by
; auxslot with repeated subtraction, so the
; size does not have to be a power of two --
; anything up to 255 pages works.
;
; auxslot hands back the quotient along with
; the remainder, and since
;   page = slot + quotient * AUXCACHEPAGES
; the quotient alone identifies the page
; occupying a slot.  That makes the tag one
; byte instead of two, which both fits the
; table below $03d0 (where the Monitor and
; ProDOS keep their vectors) and lifts the
; 128-slot ceiling that two-byte tags imposed
; on page 3.

AUXCACHETAG	= $300		; AUXCACHEPAGES bytes

; The undo ring lives in the auxiliary
; language card, so the page cache keeps all
; of aux $0800-$bfff.
;
; AUXMOVE is no help up there.  It reaches
; auxiliary memory by flipping RAMRD and
; RAMWRT, and those switches stop at $bfff --
; above that the bank is chosen by ALTZP
; instead, which also swaps the zero page and
; the stack.  undomove drives the banking
; itself, and presents the two $d000 banks as
; one flat 16 kB range
;
;   logical $c000-$cfff = bank 1 $d000-$dfff
;   logical $d000-$ffff = bank 2 $d000-$ffff

AUXUNDOLO	= $c000		; logical
AUXUNDOPAGES	= 256-(AUXUNDOLO>>8)
AUXUNDOBANK2	= $d0		; logical page from
				; which bank 2 serves

; ---- frontend zero page ----

ioparam		= $06	; word, used by the engine
wrappos		= $08
xpos		= $09
pendspc		= $0a
f_temp		= $0b
f_temp2		= $0c
coutx		= $0d
couty		= $0e
tr0		= $0f
tr1		= $10
stxoffs		= $11
statush		= $12
cury		= $13
seed		= $14	; word
rp_page		= $16
savedch		= $17
savedcv		= $18
strptr		= $19	; word
strow		= $1b
scrw		= $1c	; 40 or 80
col80		= $1d	; $80 if the //e 80-column
			; firmware is driving COUT
foldup		= $1e	; $80 to fold output to
			; upper case
auxram		= $1f	; $80 if aux RAM is usable

; ---- frontend buffers ----

; wrapbuf doubles as the buffer for status
; row 0, exactly as on the C64. io_sprepare
; clears it, io_sputc fills it via stxoffs,
; and io_scommit copies it to the screen.
; The two uses never interleave, because
; stflag routes every character to exactly
; one of io_mputc and io_sputc.

wrapbuf		= $0200	; 80 bytes
zpbuf		= $0250	; 32, MLI zero-page save

auxregsbuf	= $0270	; AUXMOVE zero-page save

; Undo ring bookkeeping.  Snapshots are all
; the same size, so the ring is a plain array
; of equal slots starting at AUXUNDOLO.  Each
; slot is rounded up to whole pages, which
; puts every slot on a page boundary and keeps
; the bookkeeping to single bytes -- slots are
; tracked by index, and a slot address is just
; a msb.

u_size		= $0278	; word, snapshot size
u_pages		= $027a	; slot stride, in pages
u_max		= $027b	; slot capacity
u_count		= $027c	; snapshots stored
u_head		= $027d	; index of the next slot
u_ready		= $027e	; nonzero once sized
u_dir		= $027f	; $80 = main to aux
u_page		= $0280	; logical msb of the slot
			; undomove is working on

; undomove state.  It lives here, and not in
; the zero page, because ALTZP swaps the zero
; page out from under the copy loop while the
; language card is banked in.  Page 2 is
; unaffected by ALTZP.

u_cur		= $0281	; logical page in flight
u_auxhi		= $0282	; msb it is banked in at
u_mainhi	= $0283	; msb on the main side
u_full		= $0284	; whole pages still to go
u_tail		= $0285	; bytes in the last page
u_limit		= $0286	; bytes in this page,
			; 0 meaning 256

#if PRODOS || PRORWTS
MACHID		= $bf98
#endif

#if PRODOS

#define ROMCALL(addr)		jsr addr
#define ROMTAILCALL(addr)	jmp addr

; MLI parameter blocks have to survive into
; the run, so they live down here rather than
; in the init segment.

p_open		= $0288	; 6 bytes
p_read		= $028e	; 8 bytes
p_mark		= $0296	; 5 bytes
p_quit		= $029b	; 7 bytes

MLI		= $bf00
DEVADR		= $bf10
DEVCNT		= $bf31
DEVLST		= $bf32
FILEBUF		= $bb00

#endif

#if PRORWTS

; for ProRWTS, some of engine gets put at $d000-$ffff
#define A2_ENGINE_HIMEM		

; Only ProRWTS2's own init calls the MLI, and
; only once.  When 0boot has booted us there is
; no ProDOS at all and mlistub answers it.

MLI		= $bf00

#define ROMCALL(addr)		bit LCROM2:jsr addr:bit LCRD1
#define ROMTAILCALL(addr)	ROMCALL(addr):rts

; ProRWTS2 lives in bank 2 and writes to its own
; buffers up there, so it needs the bank write
; enabled, which takes two reads of the switch.

#define RWTSCALL(addr)		lda LCWR2:lda LCWR2:jsr addr:lda LCRD1

next_rpagelo	= $029e
next_rpagehi	= $029f
rwregsbuf	= $02a0	; PRORWTS zero-page save,
			; rwregs_count bytes

; Arguments for rwts_openfile.  opendir runs the
; transfer as part of the open, so command, size
; and buffer all have to be set before the call.

sv_cmd		= $02cd	; 0 seek, 1 read, 2 write
sv_size		= $02ce	; word, bytes to transfer
sv_addr		= $02d0	; word, main memory buffer
sv_drive	= $02d2	; drive to open on, 0 boot
cur_drive	= $02d3	; drive ProRWTS2 is on now

rwregs_first	= $3b
rwregs_last	= $67
rwregs_count	= rwregs_last - rwregs_first + 1

prorwts_zp = $50
prorwts_status	= prorwts_zp+0
prorwts_auxreq	= prorwts_zp+1
prorwts_sizelo	= prorwts_zp+2
prorwts_sizehi	= prorwts_zp+3
prorwts_reqcmd	= prorwts_zp+4
prorwts_ldrlo	= prorwts_zp+5
prorwts_ldrhi	= prorwts_zp+6
prorwts_namlo	= prorwts_zp+7
prorwts_namhi	= prorwts_zp+8

prorwts_reloc    = $d000
prorwts_rdwrpart = prorwts_reloc + 0
prorwts_opendir	 = prorwts_reloc + 3
#endif

; ProDOS loads a SYS file at $2000,
; but the interpreter has to run at $800.

	* = $2000
#if PRODOS || PRORWTS
; 0boot enters at $2003 which is how we
; know there is no ProDOS underneath us and the
; MLI/global page has to be faked before ProRWTS2
; can initialise.

#if PRORWTS
	jmp	boot_entry
	jmp	raw_entry
#endif

; First, we move the mover to $300...
boot_entry
	.(
#if PRORWTS
	; we have to call prorwts2_init here first,
	; before we copy over ProDOS in the language card
	jsr	prorwts2_init
#endif
	ldx	#moverlen
copy
	lda	moversrc,x
	sta	$0300,x
	dex
	bpl	copy

	jmp	$0300
	.)

#if PRORWTS
; 0boot loads us the way ProDOS would and leaves
; DEVNUM at $bf30, so all that is missing is the
; MLI.  Plant the stub, then join the normal
; path.

raw_entry
	.(
	sei
	cld
	ldx	#mlistublen-1
copy
	lda	mlistubsrc,x
	sta	MLI,x
	dex
	bpl	copy

	jmp	boot_entry
	.)
#endif

; Then we run the mover at $300
	moversrc = *
	* = $300
mover
	.(
	lda	#<bootcode
	sta	$00
	lda	#>bootcode
	sta	$01		; source = bootcode

	lda	#$00
	sta	$02
	lda	#$08
	sta	$03		; dest = $0800

	ldx	#SAFEPG-$8
	jsr	pageloop

; ProRWTS requires we move engine code to $d000-$ffff
; and the init segment
#if PRORWTS
himemsegsec = engine_reloc + $2000 - $800 + boothdrlen
	lda	#<himemsegsec
	sta	$00
	lda	#>himemsegsec
	sta	$01		; source = bootcode

	lda	#$00
	sta	$02
	lda	#$d0
	sta	$03		; dest = $d000

	lda	LCWR1		; write lc_bank = 1
	lda	LCWR1

	; exactly the himem segment, so that
	; whatever is above it -- including the
	; vectors at $fffa -- is left alone

	ldx	#(himem_end-himem_start+$ff)>>8
	jsr	pageloop
	lda	LCRD1		; read lc_bank = 1

initsegsec = initsegment + $2000 - $800 + boothdrlen + himem_end - himem_start
	lda	#<initsegsec
	sta	$00
	lda	#>initsegsec
	sta	$01		; source = bootcode2

	lda	#<initsegment
	sta	$02
	lda	#>initsegment
	sta	$03		; dest = initsegment

	ldx	#SAFEPG-$8
	jsr	pageloop
	jsr	swaprwregs	; load prorwts registers into save bank
#endif
	jmp	coldstart

pageloop
	ldy	#0
byteloop
	lda	($00),y
	sta	($02),y
	iny
	bne	byteloop

	inc	$01
	inc	$03
	dex
	bne	pageloop
	rts
	.)

moverlen = * - $300

#if PRORWTS
; The stub is assembled for $bf00 but lives in
; the boot header, right behind the mover.

	mlistubsrc = moversrc + moverlen
	* = MLI
mlistub
	.(
	; ProRWTS2 asks for the prefix once and
	; takes its "no prefix" path when the
	; answer is empty, so it never makes a
	; second call -- an empty $0200 is the
	; whole of the emulation.  The call number
	; and the parameter pointer sit inline
	; after the jsr, so the return address has
	; to step over three bytes.

	tsx
	lda	$0101,x
	clc
	adc	#3
	sta	$0101,x
	lda	$0102,x
	adc	#0
	sta	$0102,x

	lda	#0
	sta	$0200		; prefix length
	clc			; and no error
	rts
	.)
mlistublen = * - MLI
#else
mlistublen = 0
#endif

boothdrlen = moverlen + mlistublen + moversrc - $2000
bootcode = $2000 + boothdrlen

#endif

; =====================================
; Main code
; =====================================

	* = $0800

do_foldup
	.(
	bit	foldup
	bpl	nofold

	cmp	#'a'
	bcc	nolower

	cmp	#'z'+1
	bcs	nolower

	and	#$df
nolower
nofold
	rts
	.)

io_mputc
	; input a = char

	.(
	cmp	#$20
	beq	space
	bcc	ignore

	cmp	#$80
	bcs	extended
plain
	jsr	do_foldup
	ldx	xpos
	cpx	scrw
	bcs	wrap
postwrap
	ldx	wrappos
	sta	wrapbuf,x
	inc	wrappos
	inc	xpos

	cmp	#'-'
	beq	dash
ignore
	rts
dash
	jmp	io_mflush
space
	jsr	io_mflush
	inc	pendspc
	inc	xpos
	rts
wrap
	pha
	jsr	io_mline_raw
	ldx	wrappos
	stx	xpos
	jsr	io_mflush
	pla
	jmp	postwrap
extended
	jsr	translit

	lda	tr0
	jsr	io_mputc	; always < $80

	lda	tr1
	beq	done

	jmp	io_mputc	; always < $80
done
	rts
	.)

io_mflush
	.(
	ldx	pendspc
	beq	nospc
spcloop
	lda	#$a0
	jsr	cout
	dex
	bne	spcloop

	stx	pendspc
nospc
	ldx	#0
	cpx	wrappos
	beq	done
loop
	lda	wrapbuf,x
	ora	#$80
	jsr	cout
	inx
	cpx	wrappos
	bne	loop
done
	lda	#0
	sta	wrappos
	rts
	.)

io_mline
	jsr	io_mflush
io_mline_raw
	.(
	ldx	xpos
	dex
	cpx	scrw	; signed cmp
	bpl	nocr	; don't CR if we filled entire line
	lda	#$8d
	jsr	cout
nocr
	lda	#0
	sta	xpos
	sta	pendspc

	; wrappos is deliberately preserved --
	; word-wrap path carries a pending word
	; across the line break.

	ldx	cury
	cpx	#23
	bcs	nobump

	inc	cury
nobump
	rts
	.)

io_mclear
	.(
	lda	#0
	sta	xpos
	sta	pendspc
	sta	wrappos

	jsr	clrwin		; clears the window
				; only, so the status
				; area survives
	lda	statush
	sta	cury
	rts
	.)

	; TODO some bugs in 80-column mode
io_mstyle
	rts
	; input a = style bits
	/*
	.(
	pha
	jsr	io_mflush
	pla
	and	#6		; bold and italic
	beq	normal

	jmp	set_inverse
normal
	jmp	set_normal
	.)
	*/

; TODO use MouseText?
io_mprogress
	; input x = progress
	; input y = total
	; where 0 <= x <= y
	; and y =
	; (width << PRSHIFT) - PREXTRA

	.(
	jsr	io_mflush

	stx	f_temp
	sty	f_temp2

	lda	#$db		; '['
	jsr	cout

	ldx	#0
loop
	lda	#$a0
	cpx	f_temp
	bcs	past

	lda	#$bd		; '='
past
	jsr	cout
	inx
	cpx	f_temp2
	bcc	loop

	lda	#$dd		; ']'
	jmp	cout
	.)

; =====================================
; Status bar area
; =====================================

; The status area occupies the top statush
; rows.  It is kept outside the text window
; (WNDTOP = statush) so that every scroll
; performed by COUT leaves it alone.  To
; write into it, the window is opened up
; temporarily and closed again by io_scommit.

io_sprepare
	; input a = height

	.(
	sta	statush

	lda	CH
	bit	col80
	bpl	noourch
	lda	OURCH
noourch
	sta	savedch
	lda	cury
	sta	savedcv

	; clear the status rows by pointing the
	; window at them and homing

	lda	#0
	sta	WNDTOP
	lda	statush
	sta	WNDBTM
	jsr	clrwin

	lda	statush
	sta	WNDTOP
	lda	#24
	sta	WNDBTM

	; blank the row 0 buffer

	ldy	scrw
	dey
	lda	#$20
clr0
	sta	wrapbuf,y
	dey
	bpl	clr0

	; put the cursor back, clamped into the
	; main area

	lda	savedcv
	cmp	statush
	bcs	keep

	lda	statush
	ldx	#0
	stx	savedch
keep
	sta	cury
	tay
	ldx	savedch
	jsr	gotoxy
	rts
	.)

io_slocate
	; input x = column
	; input y = row
	;
	; Row 0 is buffered in wrapbuf and
	; committed by io_scommit.  Rows 1 and up
	; are written straight to the screen.

	.(
	stx	stxoffs

	dey
	bpl	notrow0

	lda	#$ff
	sta	strow
	rts
notrow0
	iny
	sty	strow

	; open the window over the status area so
	; that gotoxy can reach it

	lda	#0
	sta	WNDTOP
	ldx	stxoffs
	jsr	gotoxy
	rts
	.)

io_sputc
	; input a = char

	.(
	jsr	do_foldup
	ldy	strow
	bpl	screen

	ldy	stxoffs
	cpy	scrw
	bcs	skip

	sta	wrapbuf,y
	inc	stxoffs
skip
	rts
screen
	ora	#$80
	jsr	cout
	inc	stxoffs
	rts
	.)

io_sprogress
	; input x = progress
	; input y = total
	; where 0 <= x <= y
	; and y =
	; (width << PRSHIFT) - PREXTRA

	.(
	stx	f_temp
	sty	f_temp2

	lda	#'['
	jsr	io_sputc

	ldx	#0
loop
	lda	#$20
	cpx	f_temp
	bcs	past

	lda	#'='
past
	jsr	io_sputc
	inx
	cpx	f_temp2
	bcc	loop

	lda	#']'
	jmp	io_sputc
	.)

io_scommit
	.(
	lda	#0
	sta	WNDTOP

	ldx	#0
	ldy	#0
	jsr	gotoxy
	jsr	set_inverse

	ldx	#0
loop
	lda	wrapbuf,x
	ora	#$80
	jsr	cout
	inx
	cpx	scrw
	bcc	loop

	lda	statush
	sta	WNDTOP

	ldx	xpos
	ldy	cury
	jsr	gotoxy
	jsr	set_normal	; do we have to restore old value?
	rts
	.)

; =====================================
; Input
; =====================================

io_getc
	; output a = char

	.(
	jsr	io_mflush
	jmp	getkey
	.)

io_gets
	; input ioparam = buffer
	; (room for 64 chars)
	; output y = length

	.(
	jsr	io_mflush

	ldy	#0
loop
	sty	f_temp2
	jsr	getkey
	ldy	f_temp2

	cmp	#13
	beq	done

	cmp	#8
	beq	backspace

	cmp	#$7f
	beq	backspace

	cmp	#$20
	bcc	loop

	cpy	#64
	bcs	loop

	sta	(ioparam),y
	iny

	ora	#$80
	jsr	cout
	inc	xpos
	jmp	loop
backspace
	cpy	#0
	beq	loop

	dey
	lda	#$88
	jsr	cout
	lda	#$a0
	jsr	cout
	lda	#$88
	jsr	cout
	dec	xpos
	jmp	loop
done
	sty	f_temp2
	jsr	io_mline_raw
	ldy	f_temp2
	rts
	.)

getkey
	; output a = key, high bit clear
	;
	; A block cursor is drawn while waiting.
	; The wait loop also stirs the random
	; seed, which is the only entropy source
	; on a machine with no clock.

	.(
	jsr	set_inverse
	lda	#$a0
	jsr	cout
	lda	#$88
	jsr	cout
	jsr	set_normal
wait
	inc	seed+0
	bne	nohi

	inc	seed+1
nohi
	lda	KBD
	bpl	wait

	sta	KBDSTRB
	and	#$7f
	pha

	lda	#$a0
	jsr	cout
	lda	#$88
	jsr	cout

	pla
	rts
	.)

; =====================================
; Character translation
; =====================================

translit
	; input a = char code, >= $80
	; output tr0, tr1
	; tr1 is zero for a single character

	.(
	jsr	lookupchar
	bcs	unknown

	ldy	#2
	lda	(ioparam),y
	bne	unknown		; outside the BMP

	iny
	lda	(ioparam),y
	sta	f_temp
	iny
	lda	(ioparam),y
	sta	f_temp2

	ldx	#NTRANS-1
loop
	lda	trhi,x
	cmp	f_temp
	bne	next

	lda	trlo,x
	cmp	f_temp2
	beq	found
next
	dex
	bpl	loop
unknown
	lda	#'?'
	sta	tr0
	lda	#0
	sta	tr1
	rts
found
	lda	trc0,x
	sta	tr0
	lda	trc1,x
	sta	tr1
	rts
	.)

; =====================================
; Screen primitives
; =====================================

cout
	; input a = char, high bit set
	;
	; COUT and the 80-column firmware both
	; clobber x and y.

	.(
	stx	coutx
	sty	couty
	ROMCALL(COUT)
	ldx	coutx
	ldy	couty
	rts
	.)

#ifdef DEBUG
prbyte
	.(
	stx	coutx
	sty	couty
	ROMCALL(PRBYTE)
	ldx	coutx
	ldy	couty
	rts
	.)
#endif

clrwin
	; clear the text window and home the
	; cursor within it

	.(
	bit	col80
	bmi	firmware

	ROMTAILCALL(HOME)
firmware
	lda	#$8c		; ctrl-L
	jmp	cout
	.)

gotoxy
	; input x = column, y = row

	.(
	stx	CH
; https://www.atarimagazines.com/compute/issue76/Feedback_3.php
	stx	OURCH	; synchronize CH and OURCH
	sty	CV
	ROMTAILCALL(VTAB)
	.)

set_inverse
	.(
	bit	col80
	bmi	firmware

	lda	#$3f
	sta	INVFLG
	rts
firmware
	lda	#$8f		; ctrl-O
	jmp	cout
	.)

set_normal
	.(
	bit	col80
	bmi	firmware

	lda	#$ff
	sta	INVFLG
	rts
firmware
	lda	#$8e		; ctrl-N
	jmp	cout
	.)

; =====================================
; System
; =====================================

;; TODO ProDOS thinks the system is corrupted?
;; "RESTART SYSTEM-$0B"
io_quit
	.(
; ProRWTS2 can't quit, so we reboot
#if PRODOS
	jsr	set_normal
	jsr	io_mline

	lda	#$65		; QUIT
	ldx	#<p_quit
	ldy	#>p_quit
	jsr	mlicall
#endif
	inc	$3f4		; modify pwrup checksum so we reboot
halt
	bit	LCROM2
	jmp	halt		; wait for reset
	.)

io_restart
	; The engine reloads the story itself.
	; All the frontend has to do is throw
	; away the undo history.

	.(
#if UNDO
	lda	#0
	sta	u_count
	sta	u_head
#endif
	rts
	.)

io_random
	; output x = lsb, y = msb
	; range is 0..7fff

	.(
	lsr	seed+1
	ror	seed+0
	bcc	noeor

	lda	seed+1
	eor	#$b4
	sta	seed+1
noeor
	ldx	seed+0
	lda	seed+1
	and	#$7f
	tay
	rts
	.)

; The story file is reopened after every save
; and load, so its name has to outlive the init
; segment that opens it the first time.

#if PRODOS
pathname_full
	.byt	5+8+2
	.asc	"/AA.STORY/STORY"
#endif
pathname_short
	.byt	5
	.asc	"STORY"

; =====================================
; Saved games
; =====================================
;
; ProDOS wants a kilobyte of buffer for
; every open file and main memory has none to
; spare, so STORY is closed for the duration
; and lends SAVEFILE its buffer.  Nothing is
; lost by that, io_readpage sets the mark
; before every read, so the reopened file does
; not have to remember where it was.

#if PRODOS && SAVERESTORE

io_save
	; input x = size lsb
	; input y = size msb
	; data at SAVEADDR
	; output c = success

	.(
	stx	sv_size+0
	sty	sv_size+1

	jsr	closestory

	lda	#$c0		; CREATE
	ldx	#<p_create
	ldy	#>p_create
	jsr	mlicall
	bcc	created

	cmp	#$47		; already there, and
	bne	fail		; about to be rewritten
created
	jsr	opensave
	bcs	fail

	lda	#<SAVEADDR
	sta	p_rw+2
	lda	#>SAVEADDR
	sta	p_rw+3
	lda	sv_size+0
	sta	p_rw+4
	lda	sv_size+1
	sta	p_rw+5

	lda	#$cb		; WRITE
	ldx	#<p_rw
	ldy	#>p_rw
	jsr	mlicall
	bcs	shut

	; a short save must not leave the tail of
	; a longer one behind it

	lda	sv_size+0
	sta	p_eof+2
	lda	sv_size+1
	sta	p_eof+3
	lda	#0
	sta	p_eof+4
	lda	#$d0		; SET_EOF
	ldx	#<p_eof
	ldy	#>p_eof
	jsr	mlicall
	bcs	shut

	jsr	closesave
	jsr	reopenstory
	sec
	rts
shut
	jsr	closesave
fail
	jsr	reopenstory
	clc
	rts
	.)

io_load
	; verify AASV header, 12 bytes
	; if ok, put file at SAVEADDR
	; and set c
	; otherwise, clear c

	.(
	jsr	closestory
	jsr	opensave
	bcs	fail

	; the 12 byte FORM header
	; length inside it says how much is left

	lda	#<SAVEADDR
	sta	p_rw+2
	lda	#>SAVEADDR
	sta	p_rw+3
	lda	#12
	sta	p_rw+4
	lda	#0
	sta	p_rw+5
	jsr	readsave
	bcs	shut

	; bytes 6 and 7 are the length; the rest
	; of the header is a fixed signature

	ldy	#11
check
	cpy	#6
	bcc	compare

	cpy	#8
	bcc	skip
compare
	lda	SAVEADDR,y
	cmp	form0000aasv,y
	bne	shut
skip
	dey
	bpl	check

	; four of those length bytes, the "AASV",
	; arrived with the header

	lda	SAVEADDR+7
	sec
	sbc	#4
	sta	p_rw+4
	lda	SAVEADDR+6
	sbc	#0
	sta	p_rw+5

	lda	#<SAVEADDR+12
	sta	p_rw+2
	lda	#>SAVEADDR+12
	sta	p_rw+3
	jsr	readsave
	bcs	shut

	jsr	closesave
	jsr	reopenstory
	sec
	rts
shut
	jsr	closesave
fail
	jsr	reopenstory
	clc
	rts
	.)

p_open_save
	.byt	3
	.word	sv_name
	.word	FILEBUF
	.byt	0

opensave
	; output c = error
	.(
	lda	#$c8		; OPEN
	ldx	#<p_open_save
	ldy	#>p_open_save
	jsr	mlicall
	bcs	done

	lda	p_open_save+5
	sta	p_rw+1
	sta	p_eof+1
	clc
done
	rts
	.)

readsave
	; ProDOS reports a short read as an error,
	; which is exactly what a truncated
	; savefile deserves

	lda	#$ca		; READ
	ldx	#<p_rw
	ldy	#>p_rw
	jmp	mlicall

closesave
	lda	p_rw+1
	jmp	closefile

closestory
	lda	p_read+1
	;jmp	closefile

closefile
	; input a = ref num

	sta	p_close+1
	lda	#$cc		; CLOSE
	ldx	#<p_close
	ldy	#>p_close
	jmp	mlicall

reopenstory
	; Losing the story file here would leave
	; nothing to go back to, so a failure is
	; as fatal as any other disk error.

	.(
	lda	#$c8		; OPEN
	ldx	#<p_open
	ldy	#>p_open
	jsr	mlicall
	bcs	err

	lda	p_open+5
	sta	p_read+1
	sta	p_mark+1
	rts
err
	jmp	diskerror
	.)

; Parameter blocks and names for the above.
; These outlive the init segment, so unlike
; parmsrc they are assembled where they stand.

sv_size	.word	0

p_create
	.byt	7
	.word	sv_name
	.byt	$c3		; read, write, rename,
				; destroy
	.byt	$06		; BIN
	.word	SAVEADDR	; aux type
	.byt	1		; standard file
	.word	0		; date, 0 = ask ProDOS
	.word	0		; time

p_rw
	.byt	4
	.byt	0		; ref num
	.word	0		; data buffer
	.word	0		; request count
	.word	0		; bytes transferred

p_eof
	.byt	2
	.byt	0		; ref num
	.byt	0,0,0		; new end of file

p_close
	.byt	1
	.byt	0		; ref num

sv_name
	.byt	8
	.asc	"SAVEFILE"

#elseif PRORWTS && SAVERESTORE

; One slot, a file called SAVEFILE alongside
; STORY.  ProRWTS2 can only write to a file that
; is already there and it cannot change the
; length, so the bundler puts a SAVEMAXBYTES long
; SAVEFILE on the disk and a save overwrites it
; in place.  A save that would not fit is
; refused rather than truncated.
;
; Transfers happen in whole 512 byte blocks --
; opendir rounds the size up itself -- so a save
; carries some slack at the end.  Nothing reads
; it, the length inside the AASV header says
; where the image really stops.

io_save
	; input x = size lsb
	; input y = size msb
	; data at SAVEADDR
	; output c = success

	.(
	stx	sv_size+0
	sty	sv_size+1

	; the file on disk cannot grow, so a
	; bigger image than that has nowhere
	; to go

	lda	#<SAVEMAXBYTES
	cmp	sv_size+0
	lda	#>SAVEMAXBYTES
	sbc	sv_size+1
	bcc	fail

	lda	#2		; cmdwrite
	jsr	savexfer
	bne	fail

	sec
	rts
fail
	clc
	rts
	.)

io_load
	; verify AASV header, 12 bytes
	; if ok, put file at SAVEADDR
	; and set c
	; otherwise, clear c

	.(
	; the whole file, since its length is
	; what the bundler wrote and not what
	; the last save happened to be

	lda	#<SAVEMAXBYTES
	sta	sv_size+0
	lda	#>SAVEMAXBYTES
	sta	sv_size+1

	lda	#1		; cmdread
	jsr	savexfer
	bne	fail

	; bytes 6 and 7 are the length; the rest
	; of the header is a fixed signature.  An
	; unwritten SAVEFILE is all zeroes and
	; fails here.

	ldy	#11
check
	cpy	#6
	bcc	compare

	cpy	#8
	bcc	skip
compare
	lda	SAVEADDR,y
	cmp	form0000aasv,y
	bne	fail
skip
	dey
	bpl	check

	sec
	rts
fail
	clc
	rts
	.)

savexfer
	; input a = prorwts command
	; input sv_size = byte count
	; output a = status, z set on success
	;
	; Moves the savefile to or from SAVEADDR
	; and puts STORY back, because ProRWTS2
	; has room for one open file at a time.
	;
	; The bundler puts SAVEFILE on the boot
	; disk, so it is on drive 0 even when the
	; story came off the other drive.

	.(
	sta	sv_cmd
	lda	#<SAVEADDR
	sta	sv_addr+0
	lda	#>SAVEADDR
	sta	sv_addr+1
	lda	#0
	sta	sv_drive

	ldx	#<sv_name
	ldy	#>sv_name
	jsr	rwts_openfile

	pha
	jsr	reopenstory
	pla			; sets z for the caller
	rts
	.)

sv_name
	.byt	8
	.asc	"SAVEFILE"

#endif

#if UNDO

; =====================================
; Undo, in auxiliary memory
; =====================================

; Snapshots go into a ring of equal-sized
; slots starting at AUXUNDOLO.  The engine
; asks for the same size every time, so the
; layout is computed once, on the first save.
; If not even one slot fits, undo just fails.

io_undosupp
	; output c = undo supported

	.(
	lda	auxram
	asl
	rts
	.)

io_saveundo
	; input x = byte size lsb
	; input y = byte size msb
	; input ioparam = start of data
	; output c = success

	.(
	jsr	undoprep
	bcc	no

	lda	u_head
	jsr	undoaddr
	lda	#$80
	sta	u_dir
	jsr	undomove

	; a full ring forgets its oldest entry,
	; which is the one u_head just landed on

	lda	u_count
	cmp	u_max
	bcs	full

	inc	u_count
full
	ldx	u_head
	inx
	cpx	u_max
	bcc	store

	ldx	#0
store
	stx	u_head

	sec
	rts
no
	clc
	rts
	.)

io_loadundo
	; input x = byte size lsb
	; input y = byte size msb
	; input ioparam = dest address
	; output a = status
	;	0 ok
	;	1 no more entries
	;	2 error

	.(
	jsr	undoprep
	bcc	err

	lda	u_count
	beq	empty

	; step back onto the newest snapshot

	ldx	u_head
	bne	back

	ldx	u_max
back
	dex
	stx	u_head
	txa
	jsr	undoaddr

	lda	#0
	sta	u_dir
	jsr	undomove

	dec	u_count
	lda	#0
	rts
empty
	lda	#1
	rts
err
	lda	#2
	rts
	.)

undoprep
	; input x = byte size lsb
	; input y = byte size msb
	; output c = the ring holds at least one
	; snapshot of that size

	.(
	bit	auxram
	bpl	nofit

	lda	u_ready
	beq	init

	cpx	u_size+0
	bne	init

	cpy	u_size+1
	bne	init
check
	lda	u_max
	beq	nofit

	sec
	rts
nofit
	clc
	rts
init
	jsr	undoinit
	jmp	check
	.)

undoinit
	; input x = byte size lsb
	; input y = byte size msb
	;
	; Rounds the snapshot up to whole pages
	; and counts how many of those fit, one
	; subtraction at a time rather than
	; dividing.  It runs once.

	.(
	stx	u_size+0
	sty	u_size+1

	lda	#1
	sta	u_ready

	lda	#0
	sta	u_max
	sta	u_count
	sta	u_head

	txa			; partial page?
	beq	whole

	iny
whole
	tya
	beq	none		; empty, or 64 kB and up

	sta	u_pages

	lda	#AUXUNDOPAGES
loop
	sec
	sbc	u_pages
	bcc	none

	inc	u_max
	bne	loop		; always
none
	rts
	.)

undoaddr
	; input a = slot index
	; output u_page = msb of that slot
	; clobbers a, x

	.(
	tax
	lda	#>AUXUNDOLO
loop
	dex
	bmi	done

	clc
	adc	u_pages
	bne	loop		; always, the last
				; slot ends at $ffff
done
	sta	u_page
	rts
	.)

undomove
	; input u_page = logical msb of the slot
	; input ioparam = address in main memory
	; input u_size = bytes to copy
	; input u_dir bit 7 set = main to aux
	;
	; Copies a page at a time between main
	; memory and the auxiliary language card.
	;
	; ALTZP brings in the auxiliary zero page
	; and stack along with the language card,
	; so between SETALTZP and CLRALTZP there
	; is no zero page addressing, no stack
	; traffic and no jsr.  The addresses ride
	; in the copy loop itself and the counters
	; sit on page 2, which ALTZP leaves alone.
	; Everything else the loop touches is code
	; below $c000, which ALTZP does not reach
	; either.
	;
	; Interrupts stay off for the whole copy,
	; because a ProDOS interrupt handler would
	; come up on the wrong zero page.

	.(
	lda	u_page
	sta	u_cur
	lda	ioparam+1
	sta	u_mainhi

	lda	u_size+1
	sta	u_full
	lda	u_size+0
	sta	u_tail

	; The main side is not page aligned, so
	; the two operands carry different low
	; bytes.  Neither low byte ever changes --
	; only the msbs walk, one page at a time.

	bit	u_dir
	bmi	tolow

	lda	#0		; aux is the source
	sta	srclo
	lda	ioparam+0
	sta	dstlo
	jmp	begin
tolow
	lda	ioparam+0
	sta	srclo
	lda	#0
	sta	dstlo
begin
	php
	sei
	sta	SETALTZP

	; ---- no zero page, no stack ----
nextpg
	lda	u_full
	beq	lastpg

	dec	u_full
	lda	#0
	sta	u_limit		; 0 means 256
	beq	bank		; always
lastpg
	lda	u_tail
	beq	done

	sta	u_limit
	lda	#0
	sta	u_tail		; there is only one
bank
	; Bank in whichever half holds the logical
	; page u_cur, and note the msb it shows up
	; at.  Bank 1 is only reachable at its own
	; $d000, so the low half of the ring is
	; shifted up by the difference.

	lda	u_cur
	cmp	#AUXUNDOBANK2
	bcs	two

	clc
	adc	#AUXUNDOBANK2-(AUXUNDOLO>>8)
	sta	u_auxhi
	bit	u_dir
	bmi	wr1

	lda	LCRD1
	lda	LCRD1
	jmp	operands
wr1
	lda	LCWR1
	lda	LCWR1
	jmp	operands
two
	sta	u_auxhi
	bit	u_dir
	bmi	wr2

	lda	LCRD2
	lda	LCRD2
	jmp	operands
wr2
	lda	LCWR2
	lda	LCWR2
operands
	bit	u_dir
	bmi	frommain

	lda	u_auxhi
	sta	srchi
	lda	u_mainhi
	sta	dsthi
	jmp	copy
frommain
	lda	u_mainhi
	sta	srchi
	lda	u_auxhi
	sta	dsthi
copy
	ldy	#0
byte
srclo	= *+1
srchi	= *+2
	lda	$ffff,y
dstlo	= *+1
dsthi	= *+2
	sta	$ffff,y
	iny
	cpy	u_limit
	bne	byte

	inc	u_cur
	inc	u_mainhi
	jmp	nextpg
done
	sta	CLRALTZP

	; ---- zero page and stack are back ----
#if PRODOS
	lda	LCROM2		; rom in, the way a
				; system program runs
#elseif PRORWTS
	lda	LCRD1		; ram in, for ProRWTS2
#endif
	plp
	rts
	.)

#endif

; =====================================
; Storage
; =====================================

swapauxregs
	.(
	ldx	#7
save
	lda	A1,x
	pha
	lda	auxregsbuf,x
	sta	A1,x
	pla
	sta	auxregsbuf,x
	dex
	bpl	save
	rts
	.)

#if PRORWTS
swaprwregs
	.(
	ldx	#rwregs_count-1
save
	lda	rwregs_first,x
	pha
	lda	rwregsbuf,x
	sta	rwregs_first,x
	pla
	sta	rwregsbuf,x
	dex
	bpl	save
	rts
	.)
#endif


auxslot
	; input f_temp = virtual page, l-e word
	; output y = aux cache slot
	; output a = quotient, i.e. the tag
	; clobbers x, f_temp

	.(
	ldx	#$ff		; quotient
loop
	inx
	lda	f_temp
	sec
	sbc	#AUXCACHEPAGES
	tay
	lda	f_temp+1
	sbc	#0
	bcc	done

	sty	f_temp
	sta	f_temp+1
	bcs	loop		; always
done
	ldy	f_temp
	txa
	rts
	.)

io_readpage
	; input x = physical ram target page
	; input ioparam = virtual address 23..8, l-e
	; output a = physical ram target page

	.(
	stx	rp_page

	; do we have it in aux cache?
	bit	auxram
	bpl	noloadfromaux
	; check aux cache tag for this slot
	lda	ioparam
	sta	f_temp
	lda	ioparam+1
	sta	f_temp+1
	jsr	auxslot
	cmp	AUXCACHETAG,y
	bne	noloadfromaux

	; we have it, transfer page from aux cache
	jsr	swapauxregs
	lda	#0
	sta	A1+0
	sta	A4+0
	tya			; y is preserved
	clc
	adc	#>AUXCACHESTART
	sta	A1+1		; src in aux
	sta	A2+1		; src end in aux
	lda	rp_page
	sta	A4+1		; dest in main
	; A2 = A1 + size - 1, inclusive
	lda	#$ff
	sta	A2+0		; src ending addr
	clc			; aux -> main
	jsr	AUXMOVE
	jsr	swapauxregs
#ifdef DEBUGIO
	lda	#'C'
	jsr	cout
#endif
	jmp	nosaveinaux	; page is loaded

noloadfromaux
	; byte position = virtual page << 8
#if PRODOS
	lda	#0
	sta	p_mark+2
	sta	p_read+2
	lda	ioparam
	sta	p_mark+3
	lda	ioparam+1
	sta	p_mark+4

	lda	rp_page
	sta	p_read+3

	lda	#$ce		; SET_MARK
	ldx	#<p_mark
	ldy	#>p_mark
	jsr	mlicall
	bcs	goterr

	lda	#$ca		; READ
	ldx	#<p_read
	ldy	#>p_read
	jsr	mlicall
	bcs	goterr
#endif

#if PRORWTS
	jsr	swaprwregs
seekoffset = f_temp
; compute desired - next seek offset
redoseek
	lda	ioparam
	sec
	sbc	next_rpagelo
	sta	seekoffset
	lda	ioparam+1
	sbc	next_rpagehi
	sta	seekoffset+1
; are we seeking backwards? if so rewind
	bmi	rewind		; negative, rewind
	ora	seekoffset
	beq	noseek		; equal, no seek
	bne	norewind	; positive, no rewind

; be kind, rewind
rewind
#ifdef DEBUGIO
	lda	#'R'
	jsr	cout
#endif
	jsr	rwts_rewind
	beq	redoseek	; recompute desired - next
norewind
#ifdef DEBUGIO
	lda	#'S'
	jsr	cout
#endif
        lda     #0	; cmdseek
        sta     prorwts_reqcmd
        sta     prorwts_sizelo
	lda	seekoffset+1
	beq	nobigseek
; big seek = $ff00 bytes
#ifdef DEBUGIO
	lda	#'B'
	jsr	cout
#endif
	lda	#$ff
	sta	prorwts_sizehi
	clc
	adc	next_rpagelo
	sta	next_rpagelo
	lda	#0
	adc	next_rpagehi
	sta	next_rpagehi
	RWTSCALL(prorwts_rdwrpart)
	jmp	redoseek	; recompute
nobigseek
	lda	seekoffset
	sta	prorwts_sizehi
#ifdef DEBUGIO
	jsr	prbyte
#endif
	RWTSCALL(prorwts_rdwrpart)
noseek
	lda     rp_page
	sta	prorwts_ldrhi
        lda     #1	;cmdread
        sta     prorwts_reqcmd
        sta     prorwts_sizehi
        lda     #0
        sta     prorwts_sizelo
	sta	prorwts_ldrlo
	RWTSCALL(prorwts_rdwrpart)

	ldy	prorwts_status
	jsr	swaprwregs
	tya
	beq	noerr
noerr
	lda	ioparam
	clc
	adc	#1
	sta	next_rpagelo
	lda	ioparam+1
	adc	#0
	sta	next_rpagehi
#endif

#ifdef DEBUGIO
	lda	ioparam+1
	jsr	prbyte
	lda	ioparam
	jsr	prbyte
	lda	rp_page
	jsr	prbyte
	lda	#$a0
	jsr	cout
#endif
	; store in aux memory
	bit	auxram
	bpl	nosaveinaux

	lda	ioparam
	sta	f_temp
	lda	ioparam+1
	sta	f_temp+1
	jsr	auxslot
	sta	AUXCACHETAG,y	; tag this aux cache slot

	jsr	swapauxregs
	lda	#0
	sta	A1+0
	sta	A4+0
	tya			; y is preserved
	clc
	adc	#>AUXCACHESTART
	sta	A4+1		; dest in aux

	lda	rp_page
	sta	A1+1		; src in main
	sta	A2+1		; src end in main
	; A2 = A1 + size - 1, inclusive
	lda	#$ff
	sta	A2		; src ending addr
	sec			; main -> aux
	jsr	AUXMOVE
	jsr	swapauxregs

nosaveinaux
	lda	rp_page
	rts
goterr
	jmp	diskerror
	.)

#if PRORWTS
rwts_rewind
	.(
	lda     #0
        sta     $5b ; treeidx (TODO set B >> 8)
        sta     $5f ; blkidx
        sta     $63 ; blkofflo
        sta     $64 ; blkoffhi
	; next page read will be 0
	sta	next_rpagelo
	sta	next_rpagehi
	rts
	.)

rwts_openfile
	; input x = pathname lsb
	; input y = pathname msb
	; input sv_cmd = command
	; input sv_size = byte count
	; input sv_addr = main memory buffer
	; input sv_drive = 0 boot drive, 1 the other
	; output a = status, z set on success
	;
	; opendir falls through into the transfer,
	; so one call both opens the file and moves
	; the data.  A command of zero moves
	; nothing and just opens.
	;
	; Bit 7 of the command makes the open swap
	; to the other drive in the slot rather
	; than naming one, so reaching a particular
	; drive means comparing with the one we are
	; on.  ProRWTS2 remembers the choice, hence
	; cur_drive alongside it.  A machine with
	; one drive ignores the swap, and then both
	; drives are the same drive and everything
	; below still works.

	.(
	stx	f_temp
	sty	f_temp2

	jsr	swaprwregs

	lda	f_temp
	sta	prorwts_namlo
	lda	f_temp2
	sta	prorwts_namhi
	lda	sv_cmd
	ldx	sv_drive
	cpx	cur_drive
	beq	samedrive
	stx	cur_drive
	ora	#$80		; swap drives
samedrive
	sta	prorwts_reqcmd
	lda	sv_size+0
	sta	prorwts_sizelo
	lda	sv_size+1
	sta	prorwts_sizehi
	lda	sv_addr+0
	sta	prorwts_ldrlo
	lda	sv_addr+1
	sta	prorwts_ldrhi

	RWTSCALL(prorwts_opendir)

	; opendir leaves the file positioned at
	; the start, so the reader has to agree.
	; This has to happen while the ProRWTS
	; registers are still swapped in.

	jsr	rwts_rewind

	ldy	prorwts_status
	jsr	swaprwregs
	tya
	rts
	.)

reopenstory
	; ProRWTS2 keeps one file open, so STORY
	; has to come back after every save and
	; load.  Losing it would leave nothing to
	; go back to, so a failure is as fatal as
	; any other disk error.

	.(
	jsr	storyparms
	jsr	rwts_openfile
	beq	done

	jmp	diskerror
done
	rts
	.)

storyparms
	; open STORY, transferring nothing

	.(
	lda	#0
	sta	sv_cmd		; cmdseek
	sta	sv_size+0
	sta	sv_size+1
	sta	sv_addr+0
	sta	sv_addr+1
	lda	storydrive
	sta	sv_drive
	ldx	#<pathname_short
	ldy	#>pathname_short
	rts
	.)

storydrive
	; Which drive STORY turned up on, 0 being
	; the one we booted from.  On a two disk
	; set the boot disk holds the interpreter
	; and SAVEFILE and the story disk goes in
	; the other drive, so this is 1 there.

	.byt	0
#endif

#if PRODOS
; =====================================
; ProDOS glue
; =====================================

mlicall
	; input a = command
	; input x/y = parameter block, l/h
	; output c = error, a = error code
	;
	; The engine owns zero page from $40 up
	; and ProDOS is documented to use part of
	; that range, so it is saved across every
	; call.  Every caller is disk-bound, so
	; the copy costs nothing in practice.

	.(
	sta	cmd
	stx	parm+0
	sty	parm+1

	ldx	#31
save
	lda	$40,x
	sta	zpbuf,x
	dex
	bpl	save

	jsr	MLI
cmd	.byt	0
parm	.word	0

	php
	pha

	ldx	#31
restore
	lda	zpbuf,x
	sta	$40,x
	dex
	bpl	restore

	pla
	plp
	rts
	.)

nodev
	; Stands in for the /RAM driver once the
	; RAM disk has been unhooked.  It has to
	; be resident, because ProDOS keeps the
	; pointer.

	lda	#$28		; no device connected
	sec
	rts
#endif

diskerror
	.(
	pha
	jsr	io_mline
	lda	#'E'
	jsr	cout
	pla
	ROMCALL(PRBYTE) ; error code
#ifdef DEBUG
	lda	rp_page
	jsr	prbyte ; error code
	lda	ioparam
	jsr	prbyte ; error code
#if PRODOS
	lda	p_read+3
	jsr	prbyte ; error code
	lda	p_read+2
	jsr	prbyte ; error code
#endif
#endif
halt
	jmp	halt
	.)

; =====================================
; Resident data
; =====================================

; Transliteration table.  Text mode draws
; from the character ROM, so anything outside
; ASCII has to be approximated.  Codepoints
; are BMP only, and the replacement is at
; most two characters wide.

trhi
	.byt	$00,$00,$00,$00,$00,$00,$00,$00
	.byt	$00,$00,$00,$00,$00,$00,$00,$00
	.byt	$00,$00,$00,$00,$00,$00,$00,$00
	.byt	$00,$00,$00,$00,$00,$00
	.byt	$20,$20,$20,$20,$20,$20,$20,$20
trlo
	.byt	$a0,$ab,$bb,$c4,$c5,$c6,$c9,$d6
	.byt	$d8,$dc,$df,$e0,$e1,$e2,$e4,$e5
	.byt	$e6,$e7,$e8,$e9,$ea,$eb,$ee,$ef
	.byt	$f1,$f4,$f6,$f8,$fc,$fd
	.byt	$10,$13,$14,$18,$19,$1c,$1d,$26
trc0
	.byt	' ','"','"','A','A','A','E','O'
	.byt	'O','U','s','a','a','a','a','a'
	.byt	'a','c','e','e','e','e','i','i'
	.byt	'n','o','o','o','u','y'
	.byt	'-','-','-',$27,$27,$22,$22,'.'
trc1
	.byt	0,0,0,0,0,'E',0,0
	.byt	0,0,'s',0,0,0,0,0
	.byt	'e',0,0,0,0,0,0,0
	.byt	0,0,0,0,0,0
	.byt	0,0,'-',0,0,0,0,'.'

NTRANS = trlo-trhi

; =====================================
; Cold start
; =====================================

; This sequence has to be resident.
; initengine5 prefills the page cache
; starting at the init segment, so any
; caller living there would be overwritten
; while it ran.  initengine5 itself is
; resident for the same reason.

coldstart
	.(

	jsr	initsystem

	jsr	initengine0

	; initengine0 has just set screenw from
	; DEFWIDTH; the real width is whatever
	; was detected.

	lda	scrw
	jsr	setwidth

	jsr	initengine1
	jsr	initengine2
	jsr	initengine3
	jsr	initengine4
	jsr	initengine5
#ifdef DEBUG
	jsr	dumpvars
#endif
	jsr	io_mclear
	jmp	startengine
	.)

#ifdef DEBUG
prword	.(
	pha
	txa
	pha
	pla
	tax
	pla
	rts
	.)

dumpvars
	.(
	lda	#$8d
	jsr	cout
	lda	firstpg
	jsr	prbyte
	lda	endpg
	jsr	prbyte
	lda	#$a0
	jsr	cout

	lda	vtmsb
	jsr	prbyte
	lda	vtptr+1
	jsr	prbyte
	lda	vtptr+0
	jsr	prbyte
	lda	#$a0
	jsr	cout

	lda	vtsize+1
	jsr	prbyte
	lda	vtsize+0
	jsr	prbyte
	lda	#$a0
	jsr	cout

	lda	freeptr+1
	jsr	prbyte
	lda	freeptr+0
	jsr	prbyte
	lda	#$a0
	jsr	cout

	lda	#$8d
	jsr	cout

	; heap sizes (b-e words)
	lda	heapsz
	jsr	prbyte
	lda	heapsz+1
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	auxsz
	jsr	prbyte
	lda	auxsz+1
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	ramsz
	jsr	prbyte
	lda	ramsz+1
	jsr	prbyte
	lda	#$8d
	jsr	cout

	; bases (l-e words)
	lda	hpbase+1
	jsr	prbyte
	lda	hpbase+0
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	auxbase+1
	jsr	prbyte
	lda	auxbase+0
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	rambase+1
	jsr	prbyte
	lda	rambase+0
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	inbase+1
	jsr	prbyte
	lda	inbase+0
	jsr	prbyte
	lda	#$8d
	jsr	cout

	lda	codeseg+0
	jsr	prbyte
	lda	codeseg+1
	jsr	prbyte
	lda	codeseg+2
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	lngbase+1
	jsr	prbyte
	lda	lngbase+0
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	mapbase+1
	jsr	prbyte
	lda	mapbase+0
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	decoder+1
	jsr	prbyte
	lda	decoder+0
	jsr	prbyte
	lda	#$8d
	jsr	cout
	rts
;	jmp	verify
	.)

; Read every whole page of the story file
; through io_readpage and Fletcher-8 it, so
; the storage layer can be checked against a
; checksum computed on the host.

fla	= numer
flb	= numer+1

verify
	.(
	lda	#0
	sta	fla
	sta	flb
	sta	ioparam
	sta	ioparam+1
pgloop
	lda	#0
	sta	phydata
	lda	firstpg
	sta	phydata+1

	ldy	#0
	tya
clrloop	
	sta	(phydata),y
	iny
	bne	clrloop

	ldx	firstpg
	jsr	io_readpage

	lda	#0
	sta	phydata
	lda	firstpg
	sta	phydata+1

	ldy	#0
byteloop
	lda	(phydata),y
	clc
	adc	fla
	sta	fla
	clc
	adc	flb
	sta	flb
	iny
	bne	byteloop

	inc	ioparam
	bne	nov
	inc	ioparam+1
nov
	lda	fla
	jsr	prbyte
	lda	flb
	jsr	prbyte
	; loop while ioparam < vtsize-0
	lda	vtsize
	clc
	adc	#1
	sta	f_temp
	lda	vtsize+1
	adc	#0
	sta	f_temp+1

	lda	ioparam
	cmp	f_temp
	lda	ioparam+1
	sbc	f_temp+1
	bcc	pgloop

	lda	#$8d
	jsr	cout
	lda	ioparam+1
	jsr	prbyte
	lda	ioparam
	jsr	prbyte
	lda	#$a0
	jsr	cout
	lda	flb
	jsr	prbyte
	lda	fla
	jsr	prbyte
	lda	#$8d
	jsr	cout
;	rts
halt3	jmp	halt3
	.)

dumpram
	.(
	lda #$8d
	jsr cout
	ldy #$0
loop2
	ldx #8
	tya
	jsr prbyte
	lda #':'+$80
	jsr cout
	jsr cout
loop
	lda $00,y
	jsr prbyte
	lda #$a0
	jsr cout
	iny
	dex
	bne loop
	lda #$8d
	jsr cout
	tya
	bne loop2
	rts	
	.)
#endif

; =====================================
; Aa-machine Interpreter Engine
; =====================================

#include "engine.s"

; =====================================
; Initialization
; =====================================

; Everything from here on is overwritten by
; page buffers once the engine is running.

putline
	; input x/y = string, l/h
	; plain ascii, nul terminated
	.(
	jsr	puts_xy
	lda	#SPC_AUTO
	sta	rspc
	jmp	vio_line
	.)

initsystem
	.(
	; Apple ][ boot doesn't clear engine zero page so we do it here
	lda	#0
	ldx	#$c0
clrlp
	sta	$3f,x
	dex
	bne	clrlp

	; clear the aux cache lookup table
	lda	#$ff		; never a valid quotient
	ldx	#AUXCACHEPAGES
auxclrlp
	sta	AUXCACHETAG-1,x
	dex
	bne	auxclrlp

	lda	#0
	sta	wrappos
	sta	xpos
	sta	pendspc
	sta	statush
	sta	stxoffs
	sta	cury
	sta	strow
#if UNDO
	sta	u_ready
	sta	u_count
#endif

	lda	#$e1
	sta	seed+0
	lda	#$27
	sta	seed+1

#if PRORWTS
	ROMCALL(setmachid)
#endif
	jsr	detect
	jsr	setupvideo
#if PRODOS
	jsr	initparms
	jsr	removeram
#endif
	jsr	banner
	jmp	openstory
	.)

detect
	; ProDOS has already worked out what it
	; is running on, so ask it rather than
	; poking at soft switches.
	;
	; MACHID
	; (Bit 3 off) BITS 7,6- 00=II 01=II+ 10=IIe 11=///
	; (Bit 3 on) BITS 7,6- 00=NA 01=NA 10=//c 11=NA
	; BITS 5,4- 00=NA 01=48K 10=64K 11=128K
	; BIT 3 - Modifier for MACHID Bits 7,6.
	; BIT 1=1- 80 Column card

	.(
	lda	#0
	sta	col80
	sta	auxram
	sta	foldup

	lda	#40
	sta	scrw

	lda	MACHID
	and	#$c0
	cmp	#$80
	beq	notplus

	; The Apple ][ and ][+ character
	; generator has no lower case, and an
	; 80-column card in one of those is not
	; the //e firmware, so it goes unused.

	lda	#$80
	sta	foldup
	rts
notplus
	sta	ALTCHRSET_ON	; display inverse lowercase
	lda	MACHID
	and	#$02
	beq	no80

	lda	#$80
	sta	col80
	lda	#80
	sta	scrw
no80
	lda	MACHID
	and	#$30
	cmp	#$30		; %10 is 64K, not 128K
	bne	done

	lda	#$80
	sta	auxram
done
	rts
	.)

#if PRORWTS
; Work out for ourselves what ProDOS would have
; put in MACHID, since under 0boot there is no
; ProDOS to ask and by this point in a ProDOS
; boot the global page is inside the heap.  Only
; the three fields detect reads are filled in --
; the clock bit and the bits 7,6 modifier stay
; clear.

setmachid
	.(
	lda	#$50		; ][+, 48K, no 80 columns
	ldx	$fbb3
	cpx	#$06		; ][e, ][c and IIgs say 6
	bne	store

	; The Pascal 1.1 firmware signature is the
	; same thing ProDOS looks for, so a card in
	; slot 3 that is not a display -- an
	; accelerator, say -- is rejected here too.

	lda	#$a0		; ][e, 64K, no 80 columns
	ldx	$c305
	cpx	#$38
	bne	no80
	ldx	$c307
	cpx	#$18
	bne	no80
	ldx	$c30b
	cpx	#$01
	bne	no80
	ldx	$c30c
	cpx	#$80		; high nibble 8 is a display
	bcc	no80
	cpx	#$90
	bcs	no80

	ora	#$02		; 80 columns
no80
	sta	MACHID
	jsr	auxtest
	ora	MACHID		; aux RAM
store
	sta	MACHID
	rts
	.)

; Returns $10 in a if there is auxiliary RAM,
; which turns the 64K in bits 5,4 into 128K.
; Only ever reached on a ][e or later, so the
; switches are known to exist.  The main side of
; the scratch byte is left as it was.
;
; RAMRD is no use for this.  It hands reads of
; $0200 to $bfff to the auxiliary side, and that
; includes the opcode fetches of the routine
; doing the testing, so the read-back would come
; out of auxiliary memory as code.  ALTZP moves
; the zero page, the stack and $d000-$ffff
; instead, and this routine sits in none of
; those -- ROMCALL has left rom banked in over
; $d000, and between SETALTZP and CLRALTZP there
; is no zero page addressing, no stack traffic
; and no jsr.
;
; A plain 80-column card carries 1 kB rather
; than 64K, and decodes none of the address
; lines above it, so it answers at every
; auxiliary address -- the sparse mapping the
; Apple II identification routine tests for.
; Zero page $0b and $040b are the same cell on
; such a card and different cells on a real
; one, and 80STORE with PAGE2 reaches the
; second of those without disturbing the fetch
; either, so writing one and reading the other
; tells the two cards apart.
;
; ProDOS starts by reading RDRAMRD and RDALTZP,
; on the grounds that anything already banked
; in must exist.  Nothing has touched either
; switch this early, so that shortcut would
; always fall through to here.

auxscratch = f_temp		; moved by ALTZP
auxmirror = $400 + auxscratch	; moved by PAGE2

auxtest
	.(
	lda	auxscratch
	pha
	php
	sei

	; PAGE2 only picks the bank while 80STORE
	; is on, and gives the display back when
	; it goes off again, so the screen never
	; sees any of this.

	sta	SET80STORE
	sta	TXTPAGE2
	lda	auxmirror
	pha

	lda	#$5a
	sta	auxmirror

	lda	#$a5
	sta	SETALTZP
	sta	auxscratch	; auxiliary zero page
	sta	CLRALTZP
	eor	#$ff
	sta	auxscratch	; main gets $5a

	ldx	#0		; assume there is none

	lda	auxmirror
	cmp	#$5a
	bne	restore		; 1 kB, mirrored

	sta	SETALTZP
	lda	auxscratch
	sta	CLRALTZP
	cmp	#$a5
	bne	restore		; main answered instead

	ldx	#$10
restore
	pla
	sta	auxmirror
	sta	TXTPAGE1
	sta	CLR80STORE
	plp
	pla
	sta	auxscratch
	txa
	rts
	.)
#endif

setupvideo
	.(
	bit	col80
	bmi	firmware

	lda	#<COUT1		; force video output for COUT
	sta	CSW+0
	lda	#>COUT1
	sta	CSW+1
	jmp	window
firmware
	ROMCALL(SETTXT)
	jsr	SLOT3		; hook up the //e
				; 80-column firmware

	lda	#$92		; ctrl-R, 80 columns
	jsr	cout
window
	lda	#0
	sta	WNDLFT
	sta	WNDTOP
	lda	scrw
	sta	WNDWDTH
	lda	#24
	sta	WNDBTM
	jsr	set_normal
	jmp	clrwin
	.)

#if PRODOS

initparms
	.(
	ldx	#nparm-1
loop
	lda	parmsrc,x
	sta	p_open,x
	dex
	bpl	loop
	rts
	.)

removeram
	; ProDOS puts its RAM disk in auxiliary
	; memory, which is where the undo ring / aux page cache
	; goes, so unhook it first, if it's there.
	; TODO restore on quit

	.(
	bit	auxram
	bpl	done

	ldx	DEVCNT
scan
	lda	DEVLST,x
	and	#$f0
	cmp	#$b0		; slot 3, drive 2
	beq	found

	dex
	bpl	scan
done
	rts
found
	cpx	DEVCNT
	bcs	last
shift
	lda	DEVLST+1,x
	sta	DEVLST,x
	inx
	cpx	DEVCNT
	bcc	shift
last
	dec	DEVCNT

	lda	#<nodev
	sta	DEVADR+$16	; unit $bx
	lda	#>nodev
	sta	DEVADR+$17
	rts
	.)
#endif

banner
	.(
	bit	auxram
	bmi	yesauxram
	lda	#0
	sta	txt_128k
yesauxram
	ldx	#<txt_banner
	ldy	#>txt_banner
	jsr	putline
	jsr	io_mline
	jmp	io_mline
	.)

#if PRODOS
openstory
	.(
	jsr	tryopen
	bcc	opened
; retry with full volume name
retry
	lda	#<pathname_full
	sta	p_open+1
	lda	#>pathname_full
	sta	p_open+2

	jsr	tryopen
	bcc	opened

	ldx	#<txt_nostory
	ldy	#>txt_nostory
	jsr	putline
	jsr	io_getc
	jmp	retry
opened
	lda	p_open+5
	sta	p_read+1
	sta	p_mark+1
	rts
tryopen
	lda	#$c8		; OPEN
	ldx	#<p_open
	ldy	#>p_open
	jmp	mlicall
	.)

; Image of the MLI parameter blocks, copied
; down to $0288 at boot.

parmsrc
	; p_open
	.byt	3
	.word	pathname_short
	.word	FILEBUF
	.byt	0
	; p_read
	.byt	4
	.byt	0		; ref num
	.word	0		; data buffer
	.word	$0100		; request count
	.word	0		; bytes read
	; p_mark
	.byt	2
	.byt	0
	.byt	0,0,0
	; p_quit
	.byt	4
	.byt	0
	.word	0
	.byt	0
	.word	0
nparm = *-parmsrc
#endif

#if PRORWTS
openstory
	; A two disk set boots from the disk with
	; the interpreter on it and the story is in
	; the other drive, so a miss on the drive
	; we booted from is not an error until the
	; other one has been tried too.  Each pass
	; looks at both, and storydrive keeps the
	; answer for every later open.

	.(
	lda	#0
	sta	cur_drive
retry
	jsr	storyparms
	jsr	rwts_openfile
	beq	opened

	lda	storydrive
	eor	#1
	sta	storydrive

	jsr	storyparms
	jsr	rwts_openfile
	beq	opened

	ldx	#<txt_nostory
	ldy	#>txt_nostory
	jsr	putline
	jsr	io_getc
	jmp	retry
opened
	rts
	.)
#endif

txt_banner
	.asc	"Aa-machine "
	.asc	VERSION
#if PRODOS
	.asc	" ProDOS"
#elseif PRORWTS
	.asc	" ProRWTS2"
#endif
; previous strings continue w/o null terminator
txt_128k
	.asc	" 128K",0

txt_nostory
	.asc	"Insert story disk and press a key.",10,0

#if PRODOS
RAMEND = $bb00
#endif
#if PRORWTS
RAMEND = $c000
#endif

SAFEPG = (* + $ff) >> 8		; after init routines

; Over the init routines, but rounded up to a
; page boundary. The engine reserves the save
; window by page number -- it keeps the page
; cache above >(SAVEADDR+SAVEMAXBYTES) while an
; image is being built, and drops that same
; range of pages before a restore. Unaligned,
; the last partial page is shared between the
; savefile buffer and a live cache page in both
; places.

SAVEADDR = ((initsegment + $ff) >> 8) << 8

; the ProRWTS2 library is at the end of the file
; but it does not have to be moved, it will
; relocate itself

#if PRORWTS
prorwts2_init = * + $2000 - $800 + boothdrlen + himem_end - himem_start
#endif

; Make sure the engine fits in the language card area
.assert himem_start == $d000, "A2_ENGINE_HIMEM: engine code must start at $d000"
.assert himem_end <= $f800, "A2_ENGINE_HIMEM: engine code exceeds LC RAM"
